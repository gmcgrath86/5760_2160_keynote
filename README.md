# Keynote Hammerspoon Show Control

Production-ready Hammerspoon config for automating Keynote "Play in Window" and snapping the slideshow window to either 2880x2160 half of a 5760x2160 dual-screen setup.

## Files

- `init.lua` — Hammerspoon config to run on the target Mac
- `scripts/bootstrap.sh` — one-shot setup script (copy + launch)
- `install.sh` — launcher that runs the latest one-shot script from GitHub

## What it does

- Runs an HTTP server on port `8765` with endpoints:
  - `GET /keynote/left` -> launch/activate Keynote, start Play in Window (⌥⌘P), seat on left 2880×2160 area
  - `GET /keynote/right` -> same, seat on right 2880×2160 area
  - `GET /keynote/seat?side=left|right` -> idempotent seat only if a slideshow window is already running
  - `GET /keynote/stop` -> send Escape twice
  - `GET /keynote/health` -> health check
- Chooses target display via `hs.screen` leftmost/rightmost by `fullFrame().x`
- Uses `screen:fullFrame()` for full-screen sizing on each target display
- Logs endpoint hits, screen layout, and seat attempt details
- Adds hotkey `⌘⌥⌃K` to start and seat on the configured default side (`left` in `init.lua`)

## One-shot terminal install/run

From this folder:

```bash
./scripts/bootstrap.sh
```

If you are deploying to another Mac, use this one-shot command directly:

```bash
curl -fsSL https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main/scripts/bootstrap.sh | bash
```

Or use the canonical launcher:

```bash
curl -fsSL https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main/install.sh | bash
```

If you still hit stale cached versions, use this cache-busting command:

```bash
COMMIT_SHA="$(curl -fsSL -H \"Accept: application/vnd.github+json\" -H \"User-Agent: keynote-bootstrap-installer\" https://api.github.com/repos/gmcgrath86/5760_2160_keynote/commits/main | perl -ne 'if ( /\"sha\":\"([0-9a-f]{40})\"/ ) { print $1; exit }')"
curl -fsSL \"https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/${COMMIT_SHA}/scripts/bootstrap.sh\" | bash
```

Both are equivalent. They now install all dependencies automatically, including:

- Hammerspoon via Homebrew when available
- fallback install from latest Hammerspoon GitHub release zip when Homebrew is unavailable
- `~/.hammerspoon/init.lua`
- Hammerspoon restart and endpoint logging

You can also run the script directly from this repository folder:

```bash
./scripts/bootstrap.sh
```

To get the controller machine IP:

```bash
ipconfig getifaddr en0
ipconfig getifaddr en1
```

## Operator quick start

1. Enable Accessibility and Input Monitoring for Hammerspoon in System Settings.
2. Install/run the one-shot command.
3. Confirm endpoint from an operator laptop or the same Mac:

```bash
curl http://MAC_IP:8765/keynote/health
curl http://MAC_IP:8765/keynote/left
curl http://MAC_IP:8765/keynote/right
curl "http://MAC_IP:8765/keynote/seat?side=left"
curl http://MAC_IP:8765/keynote/stop
```

`MAC_IP` is the IP of the Mac running Hammerspoon.

4. In Bitfocus Companion, create HTTP GET actions:
- `http://MAC_IP:8765/keynote/left`
- `http://MAC_IP:8765/keynote/right`
- `http://MAC_IP:8765/keynote/stop`

Optional: add one for `/keynote/seat?side=left` and `/keynote/seat?side=right`.

## GitHub backup workflow

After creating a new GitHub repo:

1. From this folder run:

```bash
git init
git add init.lua scripts/bootstrap.sh README.md
git commit -m "Add production-ready Keynote Hammerspoon controller"
git remote add origin https://github.com/<ORG>/<REPO>.git
git branch -M main
git push -u origin main
```

Then send me the repo URL and I can review the final remote link workflow.
