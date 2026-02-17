#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
INIT_FILE="$PROJECT_DIR/init.lua"
HAMMERSPOON_APP="/Applications/Hammerspoon.app"
TARGET_DIR="$HOME/.hammerspoon"

if [ ! -f "$INIT_FILE" ]; then
  echo "Missing init.lua at $INIT_FILE"
  exit 1
fi

if [ ! -d "$HAMMERSPOON_APP" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing Hammerspoon..."
    brew install --cask hammerspoon
  else
    echo "Hammerspoon is not installed and Homebrew is not available."
    echo "Install Hammerspoon manually from https://www.hammerspoon.org, then re-run this script."
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
