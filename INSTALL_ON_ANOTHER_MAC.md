# Install On Another Mac

## What to copy

From the export bundle, copy these files to the destination Mac:

- `keynote_dual_canvas.lua`
- `init.lua.export.example`
- `launchagents/local.hammerspoon.autostart.plist`

## Install steps

1. Install Hammerspoon on the destination Mac.
2. Open Hammerspoon once and grant:
- Accessibility
- Automation (Keynote), if prompted
- Screen Recording (recommended)
3. Create `~/.hammerspoon` if it does not exist.
4. Copy `keynote_dual_canvas.lua` to `~/.hammerspoon/keynote_dual_canvas.lua`.
5. Merge the contents of `init.lua.export.example` into `~/.hammerspoon/init.lua`.
6. Update display names and `http.bindAddress` in the config if the target machine differs.
7. Install the LaunchAgent by replacing placeholders in `launchagents/local.hammerspoon.autostart.plist`:
- replace `__HOME__` with the local home directory
- replace `__HAMMERSPOON_APP__` with the local Hammerspoon app path
8. Copy the rendered plist to `~/Library/LaunchAgents/local.hammerspoon.autostart.plist`.
9. Load it:
- `launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/local.hammerspoon.autostart.plist`
- `launchctl enable "gui/$(id -u)/local.hammerspoon.autostart"`
- `launchctl kickstart -k "gui/$(id -u)/local.hammerspoon.autostart"`
10. Reload Hammerspoon config.
11. Press `ctrl` + `option` + `cmd` + `k`.

## Keynote menu compatibility

This module supports both Keynote menu styles:

- `Play > Play in Window`
- `Play > In Window` + `Play > Play Slideshow`

If the target Keynote version still differs, edit `playMenuPaths` or `presenterMenuPaths` in `keynote_dual_canvas.lua`.

## Reboot Behavior

The LaunchAgent is the supported autostart path for this setup.

- It starts Hammerspoon automatically after login.
- The Hammerspoon module retries HTTP server startup if the AV VLAN IP is not ready yet.
