#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$ROOT_DIR/dist"
STAGE_DIR="$OUT_DIR/keynote_dual_canvas_export"
ZIP_PATH="$OUT_DIR/keynote_dual_canvas_export.zip"
ZIP_NAME="$(basename "$ZIP_PATH")"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
mkdir -p "$STAGE_DIR/launchagents"

cp "$ROOT_DIR/keynote_dual_canvas.lua" "$STAGE_DIR/"
cp "$ROOT_DIR/init.lua.export.example" "$STAGE_DIR/"
cp "$ROOT_DIR/INSTALL_ON_ANOTHER_MAC.md" "$STAGE_DIR/"
cp "$ROOT_DIR/README.md" "$STAGE_DIR/"
cp "$ROOT_DIR/launchagents/local.hammerspoon.autostart.plist" "$STAGE_DIR/launchagents/"

rm -f "$ZIP_PATH"
(
  cd "$OUT_DIR"
  rm -f "$ZIP_NAME"
  /usr/bin/zip -rq "$ZIP_NAME" "$(basename "$STAGE_DIR")"
)

printf 'Export bundle created:\n%s\n' "$ZIP_PATH"
