#!/usr/bin/env bash
set -euo pipefail

set +H
RAW_BASE="https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote"
COMMITS_API="https://api.github.com/repos/gmcgrath86/5760_2160_keynote/commits/main"
COMMIT_SHA=""
SCRIPT_URL=""

if command -v curl >/dev/null 2>&1; then
  COMMIT_SHA="$(
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "User-Agent: keynote-bootstrap-installer" \
      "$COMMITS_API" \
      | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' \
      | head -n 1
  )" || true
fi

if [ -n "${COMMIT_SHA:-}" ]; then
  SCRIPT_URL="${RAW_BASE}/${COMMIT_SHA}/scripts/bootstrap.sh"
else
  SCRIPT_URL="${RAW_BASE}/main/scripts/bootstrap.sh"
fi

curl -fsSL "$SCRIPT_URL" | bash
