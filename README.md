# Keynote Dual-Canvas Hammerspoon Hotkey

This repository packages a working Hammerspoon setup for one-button Keynote control on:

- two `2880x2160` displays used as one `5760x2160` slide canvas
- one `1920x1080` notes display

The default hotkey is:

- `ctrl` + `option` + `cmd` + `k`

## What It Does

When the hotkey runs, it:

1. Focuses Keynote.
2. Sends `Escape` twice to exit any active play or presenter state.
3. Restarts playback in windowed mode.
4. Ensures the presenter display window is shown.
5. Seats the slide window across the full `5760x2160` stitched canvas.
6. Seats the presenter window on the separate notes display.

It can also expose a small HTTP trigger for remote control from another machine on the AV VLAN.

The module supports both Keynote menu layouts:

- `Play > Play in Window`
- `Play > In Window`, then `Play > Play Slideshow`

## Repository Files

- `init.lua`: installable `~/.hammerspoon/init.lua`
- `keynote_dual_canvas.lua`: reusable window-placement module
- `install.sh`: one-line bootstrap entrypoint
- `scripts/bootstrap.sh`: installer that downloads the config and module
- `launchagents/local.hammerspoon.autostart.plist`: LaunchAgent template for reboot-safe autostart
- `INSTALL_ON_ANOTHER_MAC.md`: manual setup checklist
- `init.lua.export.example`: alternate config example for handoff bundles
- `export_keynote_dual_canvas.sh`: creates a zip bundle for offline transfer

## Quick Install On Another Mac

Use the repository bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/gmcgrath86/5760_2160_keynote/main/install.sh | bash
```

The bootstrap will:

- install a user-local Homebrew copy if `brew` is missing
- install Hammerspoon into `~/Applications`
- copy `init.lua` and `keynote_dual_canvas.lua` into `~/.hammerspoon`
- install a LaunchAgent so Hammerspoon starts automatically after login
- launch or restart Hammerspoon

## Manual Install

1. Install Hammerspoon.
2. Copy `init.lua` to `~/.hammerspoon/init.lua`.
3. Copy `keynote_dual_canvas.lua` to `~/.hammerspoon/keynote_dual_canvas.lua`.
4. Open Hammerspoon and grant permissions.
5. Reload Hammerspoon config.
6. Press `ctrl` + `option` + `cmd` + `k`.

## Autostart After Reboot

The supported autostart path is a per-user LaunchAgent:

- `~/Library/LaunchAgents/local.hammerspoon.autostart.plist`

That LaunchAgent launches Hammerspoon automatically after login.

The module also retries HTTP server startup every 5 seconds if the AV VLAN IP is not ready when Hammerspoon first launches.

## Remote Trigger

The default `init.lua` also enables an HTTP trigger on:

- `http://10.2.130.108:8765`

Available endpoints:

- `GET /keynote/health`
- `GET /keynote/run`
- `GET /keynote/stop`

Example:

```bash
curl http://10.2.130.108:8765/keynote/health
curl http://10.2.130.108:8765/keynote/run
```

The bind address is set to the AV control VLAN IP in `init.lua`, so the trigger does not need to listen on every interface.
The module will retry binding after login if that interface appears slightly later than Hammerspoon.

If you want a shared-secret token, set `http.token` in `init.lua` and call:

```bash
curl "http://10.2.130.108:8765/keynote/run?token=YOUR_SECRET"
```

## Required macOS Permissions

Grant these to Hammerspoon:

- Accessibility
- Automation (Keynote), if prompted
- Screen Recording

Without Accessibility, the hotkey bind is intentionally skipped so Hammerspoon can still start cleanly.
If macOS asks whether Hammerspoon can accept incoming network connections, allow it.

## Machine-Specific Configuration

The default config in `init.lua` assumes these display names:

- `SwitchResX4 - Desktop (1)`
- `SwitchResX4 - Desktop (2)`
- `SwitchResX4 - Desktop (3)`

If another machine uses different names, edit:

- `playScreenNames`
- `notesScreenName`

If another machine uses a different AV VLAN IP, edit:

- `http.bindAddress`

You can also set a fixed deck path by uncommenting:

- `deckPath`
- `openDeckOnHotkey`

## Known Behavior

- The slide window is placed using each display's `fullFrame()`, so it can span the exact `5760x2160` canvas.
- The presenter window is still a normal macOS window in Keynote's "Presenter Display in Window" mode.
- If the menu bar is visible on the notes display, macOS may clamp that window to the visible frame, for example `1920x1050` instead of `1920x1080`.
- If you need full-height notes, enable menu bar auto-hide on the notes display.

## If Keynote Menu Labels Differ

If a future Keynote build changes the menu labels again, update:

- `playMenuPaths`
- `presenterMenuPaths`

in `keynote_dual_canvas.lua`.

## Offline Export

To build a zip bundle for a machine without direct GitHub access:

```bash
./export_keynote_dual_canvas.sh
```

The bundle is written to:

- `dist/keynote_dual_canvas_export.zip`
