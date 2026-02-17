#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_URL="https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main"
INIT_URL="${REPO_RAW_URL}/init.lua"
HAMMERSPOON_APP="/Applications/Hammerspoon.app"
TARGET_DIR="${HOME}/.hammerspoon"
TMP_DIR="$(mktemp -d)"
INIT_FILE="${TMP_DIR}/init.lua"
trap 'rm -rf "$TMP_DIR"' EXIT

log() {
  printf '[keynote-bootstrap] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

assert_required_cmds() {
  local missing=0
  local cmd
  for cmd in curl open osascript; do
    if ! has_cmd "$cmd"; then
      log "Required command not found: $cmd"
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    log "Install command line tools and rerun."
    exit 1
  fi
}

is_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    log "This installer supports macOS only."
    exit 1
  fi
}

ensure_tmp_dir() {
  if [ ! -d "$TMP_DIR" ]; then
    TMP_DIR="$(mktemp -d)"
    INIT_FILE="${TMP_DIR}/init.lua"
  fi
}

download_init_file() {
  log "Downloading init.lua from repository..."
  curl -fsSL "$INIT_URL" -o "$INIT_FILE"
  if [ ! -s "$INIT_FILE" ]; then
    log "Failed to download init.lua from $INIT_URL"
    exit 1
  fi
}

copy_to_applications() {
  local app_path="$1"

  if [ -d "$HAMMERSPOON_APP" ]; then
    if has_cmd sudo; then
      sudo rm -rf "$HAMMERSPOON_APP"
    else
      rm -rf "$HAMMERSPOON_APP"
    fi
  fi

  if cp -R "$app_path" "/Applications/"; then
    return 0
  fi

  if has_cmd sudo; then
    log "Administrator privileges are required to write /Applications."
    sudo cp -R "$app_path" "/Applications/"
    return 0
  fi

  log "Could not install to /Applications."
  return 1
}

install_by_brew() {
  if ! has_cmd brew; then
    return 1
  fi

  if brew install --cask hammerspoon; then
    return 0
  fi

  log "Homebrew install failed."
  return 1
}

install_by_github_release() {
  log "Installing Hammerspoon from GitHub release..."
  local release_json="${TMP_DIR}/release.json"
  local asset_url
  local zip_file="${TMP_DIR}/hammerspoon.zip"
  local extract_dir="${TMP_DIR}/hammerspoon"
  local app_path
  local release_tag
  local release_link

  if ! curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: keynote-bootstrap" \
    "https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest" \
    -o "$release_json"; then
    log "Could not query GitHub release API."
  else
    asset_url="$( \
      grep -o '"browser_download_url":[[:space:]]*\"[^\"]*\"' "$release_json" \
      | sed -E 's/.*"([^"]+)"/\\1/' \
      | grep -E 'Hammerspoon-.*\.zip' \
      | head -n1
    )"
  fi

  if [ -z "$asset_url" ]; then
    log "Falling back to release tag + canonical asset URL."
    release_link="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/Hammerspoon/hammerspoon/releases/latest)"
    release_tag="${release_link##*/}"

    if [ -n "$release_tag" ]; then
      for candidate in \
        "https://github.com/Hammerspoon/hammerspoon/releases/download/$release_tag/Hammerspoon-$release_tag.zip" \
        "https://github.com/Hammerspoon/hammerspoon/releases/download/$release_tag/Hammerspoon.zip"; do
        if curl -fsSLI -o /dev/null "$candidate"; then
          asset_url="$candidate"
          break
        fi
      done
    fi
  fi

  if [ -z "$asset_url" ]; then
    log "Could not locate Hammerspoon zip asset."
    return 1
  fi

  log "Downloading $asset_url"
  if ! curl -fsSL \
    -H "User-Agent: keynote-bootstrap" \
    -L \
    "$asset_url" \
    -o "$zip_file"; then
    log "Failed to download Hammerspoon archive from $asset_url"
    return 1
  fi

  if [ ! -s "$zip_file" ]; then
    log "Downloaded Hammerspoon archive is empty."
    return 1
  fi

  if has_cmd unzip; then
    unzip -q "$zip_file" -d "$extract_dir"
  elif has_cmd ditto; then
    ditto -xk "$zip_file" "$extract_dir"
  else
    log "Neither unzip nor ditto is available."
    return 1
  fi

  app_path="$(find "$extract_dir" -type d -name 'Hammerspoon.app' -print -quit)"
  if [ -z "$app_path" ]; then
    log "Hammerspoon.app was not found in the release archive."
    return 1
  fi

  copy_to_applications "$app_path"
}

ensure_hammerspoon() {
  if [ -d "$HAMMERSPOON_APP" ]; then
    log "Hammerspoon already present."
    return
  fi

  if install_by_brew; then
    log "Hammerspoon installed via Homebrew."
    return
  fi

  if install_by_github_release; then
    log "Hammerspoon installed from GitHub release."
    return
  fi

  log "Unable to install Hammerspoon automatically."
  log "Install Hammerspoon manually from https://www.hammerspoon.org/ and rerun."
  exit 1
}

install_config() {
  mkdir -p "$TARGET_DIR"
  cp "$INIT_FILE" "$TARGET_DIR/init.lua"
  log "Config installed to $TARGET_DIR/init.lua"
}

restart_hammerspoon() {
  if has_cmd pgrep && pgrep -x Hammerspoon >/dev/null 2>&1; then
    osascript -e 'tell application "Hammerspoon" to quit'
    for _ in {1..50}; do
      if ! pgrep -x Hammerspoon >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
  fi

  if ! open -a Hammerspoon; then
    log "Failed to launch Hammerspoon. Open it manually once and rerun."
    exit 1
  fi
  sleep 2
}

main() {
  is_macos
  assert_required_cmds
  ensure_tmp_dir
  download_init_file
  ensure_hammerspoon

  if [ ! -d "$HAMMERSPOON_APP" ]; then
    log "Hammerspoon installation failed."
    exit 1
  fi

  install_config
  restart_hammerspoon

  log "Hammerspoon is running. Endpoints available on port 8765." 
  local default_ip
  if has_cmd ipconfig; then
    default_ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  fi
  if [ -z "${default_ip:-}" ]; then
    log "Find your Mac IP in System Settings > Network or run: ipconfig getifaddr en0"
  else
    log "Test endpoint: curl http://$default_ip:8765/keynote/health"
  fi

  log "Important: allow Accessibility + Input Monitoring for Hammerspoon in System Settings > Privacy & Security."
}

main "$@"
