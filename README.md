# Keynote Hammerspoon Show Control

Production-ready Hammerspoon control for one-button Keynote presentation control on a 5760×2160 stitched output with separate 1920×1080 notes output.

## Files

- `init.lua` — Hammerspoon configuration loaded from `~/.hammerspoon/init.lua`
- `scripts/bootstrap.sh` — one-shot installer for dependencies, config, and Hammerspoon restart
- `install.sh` — optional entrypoint that resolves a pinned bootstrap commit

## What it does

- Starts an HTTP server on port `8765` with:
  - `GET /keynote/left` → launch/activate Keynote, start Play in Window, seat slideshow
  - `GET /keynote/right` → launch/activate Keynote, start Play in Window, seat slideshow
  - `GET /keynote/seat?side=left|right` → idempotent seat on existing playback
  - `GET /keynote/stop` → stop playback with Escape
  - `GET /keynote/health` → returns `OK` when controller responds
- Uses `hs.screen` full-frame geometry and automatic layout detection:
  - Detects a 5760×2160 full canvas when present
  - Detects stitched 2880×2160 side-by-side outputs and uses the full span for slideshow
  - Falls back to leftmost/rightmost 2880×2160 panel selection
- Includes fixed-name preference for known displays:
  - `OG-US-5000` is treated as notes output
  - `SwitchResX4 - E2-01 (2)` is treated as the far-left 2880×2160 slide output
  - `SwitchResX4 - E2-01 (1)` is treated as the far-right 2880×2160 slide output
- Places slideshow window to 5760×2160 target span and notes to 1920×1080 target
- Adds hotkey `⌘⌥⌃K` (defaults to the left/start flow)
- Hotkey feedback is enabled by default to confirm execution in-cockpit.
- Sends structured plain-text HTTP responses with logs for endpoint hit, screen roles, and frame placement

## One-shot install (blank machine ready)

Pick one:

```bash
curl -fsSL https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main/install.sh | bash
```

Direct latest `main` bootstrap (no commit lookup):

```bash
curl -fsSL https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main/scripts/bootstrap.sh | bash
```

The installer performs:

- Homebrew check/install if missing
- Hammerspoon install/update (`brew` first, then GitHub release fallback)
- `~/.hammerspoon/init.lua` deployment
- Hammerspoon restart
- Post-install health check against `http://127.0.0.1:8765/keynote/health`
- Final console summary with endpoint + hotkey reminder

If you prefer a fixed SHA URL:

```bash
LATEST_SHA="$(git ls-remote https://github.com/gmcgrath86/5760_2160_keynote.git HEAD | awk '{print $1}')"
curl -fsSL "https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/$LATEST_SHA/scripts/bootstrap.sh" | bash
```

## Operator quick start

1. Ensure Hammerspoon has `Accessibility` + `Input Monitoring` in
   `System Settings → Privacy & Security`.
2. Run one of the one-shot commands.
3. Find the controller IP:

```bash
ipconfig getifaddr en0
ipconfig getifaddr en1
```

### Temporary troubleshooting snippet (until final flip fix)

Run this command on the operator Mac to capture the exact role-assignment logs during playback/tests:

```bash
LOG_FILE="$(find ~/Library/Logs -maxdepth 4 -type f -iname 'Hammerspoon.log' | head -n 1)"
if [ -z "$LOG_FILE" ]; then
  LOG_FILE="$(find ~/Library -maxdepth 4 -type f -iname '*Hammerspoon*.log' | head -n 1)"
fi

if [ -z "$LOG_FILE" ]; then
  echo "Could not locate Hammerspoon log file; ensure Hammerspoon has launched at least once."
else
  echo "Reading: $LOG_FILE"
  if command -v rg >/dev/null 2>&1; then
    tail -n 220 "$LOG_FILE" \
      | rg -E "Detected screens|Using configured canvas|Screen roles|Using stitched|Selected slide window|Selected notes window|Could not resolve|Could not|Window after seat"
  else
    tail -n 220 "$LOG_FILE" \
      | grep -E "Detected screens|Using configured canvas|Screen roles|Using stitched|Selected slide window|Selected notes window|Could not resolve|Could not|Window after seat"
  fi
fi
```

4. Smoke-test endpoints:

```bash
curl http://MAC_IP:8765/keynote/health
curl http://MAC_IP:8765/keynote/left
curl http://MAC_IP:8765/keynote/right
curl "http://MAC_IP:8765/keynote/seat?side=left"
curl http://MAC_IP:8765/keynote/stop
```

5. Configure Companion HTTP GET actions:

- `http://MAC_IP:8765/keynote/left`
- `http://MAC_IP:8765/keynote/right`
- `http://MAC_IP:8765/keynote/stop`
- Optional: `http://MAC_IP:8765/keynote/seat?side=left`
- Optional: `http://MAC_IP:8765/keynote/seat?side=right`

## Notes

- `notesWindowRequired = true` by default in `init.lua`.
- `/keynote/seat?side=...` reuses existing playback and only repositions windows.
- If your workflow intentionally skips notes window handling, set `notesWindowRequired = false`.
- Set `hotkeyFeedback = false` in `init.lua` to suppress hotkey on-screen messages.
