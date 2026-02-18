#!/usr/bin/env bash
set -euo pipefail

set +H
RAW_BASE="https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote"
REPO_URL="https://github.com/gmcgrath86/5760_2160_keynote.git"
COMMITS_API="https://api.github.com/repos/gmcgrath86/5760_2160_keynote/commits/main"
COMMIT_SHA=""
SCRIPT_URL=""

if ! command -v curl >/dev/null 2>&1; then
  echo "[keynote-bootstrap] curl is required on the target machine." >&2
  exit 1
fi

if command -v git >/dev/null 2>&1; then
  COMMIT_SHA="$(git ls-remote "$REPO_URL" HEAD 2>/dev/null | awk '{print $1}')"
fi

if ! printf '%s' "${COMMIT_SHA:-}" | grep -Eq '^[0-9a-f]{40}$'; then
  COMMIT_SHA=""
fi

if [ -z "$COMMIT_SHA" ]; then
  COMMIT_SHA="$(
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "User-Agent: keynote-bootstrap-installer" \
      "$COMMITS_API" \
      | grep -oE '"sha":"[0-9a-f]{40}"' \
      | head -n1 \
      | cut -d'"' -f4
  )" || true
fi

if [ -n "${COMMIT_SHA:-}" ]; then
  SCRIPT_URL="${RAW_BASE}/${COMMIT_SHA}/scripts/bootstrap.sh"
else
  SCRIPT_URL="${RAW_BASE}/main/scripts/bootstrap.sh"
fi

curl -fsSL "$SCRIPT_URL" | bash
