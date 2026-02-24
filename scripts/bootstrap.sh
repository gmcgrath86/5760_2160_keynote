#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_REF="${KEYNOTE_BOOTSTRAP_REF:-main}"
REPO_RAW_URL="https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/${BOOTSTRAP_REF}"
INIT_URL="${REPO_RAW_URL}/init.lua"
MODULE_URL="${REPO_RAW_URL}/keynote_dual_canvas.lua"
TARGET_DIR="${HOME}/.hammerspoon"
SYSTEM_HAMMERSPOON_APP="/Applications/Hammerspoon.app"
USER_HAMMERSPOON_APP="${HOME}/Applications/Hammerspoon.app"
USER_HOMEBREW_PREFIX="${HOME}/homebrew"
TMP_DIR="$(mktemp -d)"
INIT_FILE="${TMP_DIR}/init.lua"
MODULE_FILE="${TMP_DIR}/keynote_dual_canvas.lua"
trap 'rm -rf "$TMP_DIR"' EXIT

log() {
  printf '[keynote-bootstrap] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

refresh_brew_cmd() {
  if [ -x "/opt/homebrew/bin/brew" ]; then
    PATH="/opt/homebrew/bin:$PATH"
    export PATH
  elif [ -x "/usr/local/bin/brew" ]; then
    PATH="/usr/local/bin:$PATH"
    export PATH
  elif [ -x "${USER_HOMEBREW_PREFIX}/bin/brew" ]; then
    PATH="${USER_HOMEBREW_PREFIX}/bin:$PATH"
    export PATH
  fi
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
    MODULE_FILE="${TMP_DIR}/keynote_dual_canvas.lua"
  fi
}

download_repo_files() {
  log "Downloading init.lua from repository..."
  curl -fsSL "$INIT_URL" -o "$INIT_FILE"
  if [ ! -s "$INIT_FILE" ]; then
    log "Failed to download init.lua from $INIT_URL"
    exit 1
  fi

  log "Downloading keynote_dual_canvas.lua from repository..."
  curl -fsSL "$MODULE_URL" -o "$MODULE_FILE"
  if [ ! -s "$MODULE_FILE" ]; then
    log "Failed to download keynote_dual_canvas.lua from $MODULE_URL"
    exit 1
  fi
}

install_homebrew() {
  refresh_brew_cmd
  if has_cmd brew; then
    return 0
  fi

  if [ ! -d "${USER_HOMEBREW_PREFIX}" ] && ! has_cmd git; then
    log "git is required to install Homebrew into ${USER_HOMEBREW_PREFIX}."
    return 1
  fi

  log "Homebrew not found. Installing a user-local Homebrew copy to ${USER_HOMEBREW_PREFIX}..."
  if [ ! -d "${USER_HOMEBREW_PREFIX}" ]; then
    git clone --depth 1 https://github.com/Homebrew/brew "${USER_HOMEBREW_PREFIX}"
  fi

  refresh_brew_cmd
  if has_cmd brew; then
    log "Homebrew installed."
    return 0
  fi

  log "Homebrew installation did not produce a usable brew command."
  return 1
}

hammerspoon_installed() {
  [ -d "$USER_HAMMERSPOON_APP" ] || [ -d "$SYSTEM_HAMMERSPOON_APP" ]
}

ensure_hammerspoon() {
  refresh_brew_cmd

  if hammerspoon_installed; then
    log "Hammerspoon already present."
    return
  fi

  if ! install_homebrew; then
    log "Homebrew installation or validation did not complete."
    exit 1
  fi

  mkdir -p "${HOME}/Applications"
  log "Installing Hammerspoon via Homebrew to ${HOME}/Applications..."
  brew install --cask --appdir="${HOME}/Applications" hammerspoon
}

install_config() {
  mkdir -p "$TARGET_DIR"
  cp "$INIT_FILE" "$TARGET_DIR/init.lua"
  cp "$MODULE_FILE" "$TARGET_DIR/keynote_dual_canvas.lua"
  log "Config installed to $TARGET_DIR/init.lua"
  log "Module installed to $TARGET_DIR/keynote_dual_canvas.lua"
}

launch_hammerspoon() {
  if [ -d "$USER_HAMMERSPOON_APP" ]; then
    open -a "$USER_HAMMERSPOON_APP"
    return 0
  fi
  if [ -d "$SYSTEM_HAMMERSPOON_APP" ]; then
    open -a "$SYSTEM_HAMMERSPOON_APP"
    return 0
  fi
  open -a Hammerspoon
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

  if ! launch_hammerspoon; then
    log "Failed to launch Hammerspoon. Open it manually once and rerun."
    exit 1
  fi
  sleep 2
}

main() {
  is_macos
  assert_required_cmds
  ensure_tmp_dir
  download_repo_files
  ensure_hammerspoon

  if ! hammerspoon_installed; then
    log "Hammerspoon installation failed."
    exit 1
  fi

  install_config
  restart_hammerspoon

  log "Hotkey installed: Ctrl+Option+Command+K"
  log "Important: allow Accessibility, Automation (Keynote), and Screen Recording for Hammerspoon if prompted."
  log "If the presenter window stops at 1920x1050 instead of 1920x1080, enable auto-hide for the menu bar on the notes display."
  log "Installation complete."
}

main "$@"
