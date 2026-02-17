#!/usr/bin/env bash
set -euo pipefail

RAW_BASE_URL="https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required and was not found."
  exit 1
fi

INIT_FILE="$TMP_DIR/init.lua"
curl -fsSL "$RAW_BASE_URL/init.lua" -o "$INIT_FILE"

if [ ! -f "$INIT_FILE" ]; then
  echo "Missing init.lua file."
  exit 1
fi

HAMMERSPOON_APP="/Applications/Hammerspoon.app"
TARGET_DIR="$HOME/.hammerspoon"

if [ ! -d "$HAMMERSPOON_APP" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing Hammerspoon..."
    brew install --cask hammerspoon
  else
    echo "Hammerspoon is not installed and Homebrew is not available."
    echo "Install Hammerspoon manually from hammerspoon.org, then re-run this script."
    exit 1
  fi
fi

mkdir -p "$TARGET_DIR"
cp "$INIT_FILE" "$TARGET_DIR/init.lua"
echo "Installed Hammerspoon config: $TARGET_DIR/init.lua"

if pgrep -x Hammerspoon >/dev/null 2>&1; then
  osascript -e 'tell application "Hammerspoon" to quit'
  for _ in {1..50}; do
    if ! pgrep -x Hammerspoon >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

open -a Hammerspoon
sleep 2
echo "Hammerspoon started and config loaded."
echo "Endpoints will be available on port 8765."
