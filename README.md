# Keynote Hammerspoon Show Control

Production-ready Hammerspoon config for:

- Playing Keynote in Window (`⌥⌘P`)
- Placing the slideshow window on the configured 2880×2160 side of the 5760×2160 output
- Moving notes to the 1920×1080 notes output and filling that display
- Driving `/keynote` control endpoints for Bitfocus Companion

## Files

- `init.lua` — Hammerspoon configuration loaded from `~/.hammerspoon/init.lua`
- `scripts/bootstrap.sh` — one-shot installer for Hammerspoon + config copy + restart
- `install.sh` — remote launcher that resolves the latest repo commit and runs bootstrap

## What it does

- Starts an HTTP server on port `8765` with:
  - `GET /keynote/left` → launch/activate Keynote, start Play in Window, seat on left half
  - `GET /keynote/right` → same, seat on right half
  - `GET /keynote/seat?side=left|right` → idempotent seat on existing playback
  - `GET /keynote/stop` → send Escape to stop playback
  - `GET /keynote/health` → returns `OK` when Keynote is present
- Uses `hs.screen` full-frame geometry, left/right by `fullFrame().x` for standard dual-layouts
- Handles stitched-layout machines:
  - Uses a 5760×2160 canvas when present.
  - Falls back to leftmost/rightmost 2880×2160 outputs when needed.
- Targets 1920×1080 for notes when available.
- Logs endpoint hits, screen-role resolution, and final frame placement.
- Adds hotkey `⌘⌥⌃K` (defaults to left side) to start and seat quickly.

## One-shot install (blank machine ready)

Run this once on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main/install.sh | bash
```

The installer now:

- Resolves the latest commit SHA (when possible) for cache-safe bootstrap delivery
- Falls back to `main` branch if commit resolution fails
- Checks for Homebrew and installs it if missing
- Checks/installs Hammerspoon (`brew` first, then GitHub release fallback)
- Installs `~/.hammerspoon/init.lua` and restarts Hammerspoon

If you prefer to keep a fixed versioned URL (for air-gapped workflows):

```bash
LATEST_SHA="$(git ls-remote https://github.com/gmcgrath86/5760_2160_keynote.git HEAD | awk '{print $1}')"
curl -fsSL "https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/$LATEST_SHA/scripts/bootstrap.sh" | bash
```

To find the controller IP:

```bash
ipconfig getifaddr en0
ipconfig getifaddr en1
```

## Operator quick start

1. Enable Accessibility + Input Monitoring for Hammerspoon in System Settings → Privacy & Security.
2. Run the one-shot command above.
3. Verify endpoints:

```bash
curl http://MAC_IP:8765/keynote/health
curl http://MAC_IP:8765/keynote/left
curl http://MAC_IP:8765/keynote/right
curl "http://MAC_IP:8765/keynote/seat?side=left"
curl http://MAC_IP:8765/keynote/stop
```

4. Configure Companion HTTP GET actions:

- `http://MAC_IP:8765/keynote/left`
- `http://MAC_IP:8765/keynote/right`
- `http://MAC_IP:8765/keynote/stop`
- Optional: `http://MAC_IP:8765/keynote/seat?side=left`
- Optional: `http://MAC_IP:8765/keynote/seat?side=right`

## Notes

- `notesWindowRequired = false` is configured by default so notes-window anomalies do not fail the slide start.
- Set to `true` in `init.lua` if you want `/keynote/left|right` to return a failure when notes window is missing.
