#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="gmcgrath86"
REPO_NAME="5760_2160_keynote"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
COMMITS_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/commits/main"
BOOTSTRAP_PATH="scripts/bootstrap.sh"

log() {
  printf '[keynote-bootstrap] %s\n' "$*"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_valid_sha() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

resolve_bootstrap_url() {
  local sha=""

  if has_cmd git; then
    sha="$(git ls-remote "$REPO_URL" HEAD 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  fi

  if ! is_valid_sha "${sha:-}"; then
    local api_body
    if api_body="$(curl -fsSL -H "Accept: application/vnd.github+json" -H "User-Agent: keynote-bootstrap-installer" "$COMMITS_API" || true)"; then
      sha="$(printf '%s\n' "$api_body" | grep -oE '\"sha\":\"[0-9a-f]{40}\"' | head -n1 | cut -d'"' -f4 || true)"
    fi
  fi

  if is_valid_sha "${sha:-}"; then
    printf '%s %s\n' "$sha" "${RAW_BASE}/${sha}/${BOOTSTRAP_PATH}"
    return 0
  fi

  printf 'main %s\n' "${RAW_BASE}/main/${BOOTSTRAP_PATH}"
  return 0
}

main() {
  if ! has_cmd curl; then
    log "curl is required on the target machine."
    exit 1
  fi

  local selected_ref script_url
  read -r selected_ref script_url <<<"$(resolve_bootstrap_url)"
  log "Fetching bootstrap from: $script_url"
  if ! curl -fsSL "$script_url" | KEYNOTE_BOOTSTRAP_REF="$selected_ref" bash; then
    log "Bootstrap download or execution failed."
    exit 1
  fi
}

main "$@"
