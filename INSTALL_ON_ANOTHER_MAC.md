# Install On Another Mac

## What to copy

From the export bundle, copy these files to the destination Mac:

- `keynote_dual_canvas.lua`
- `init.lua.export.example`

## Install steps

1. Install Hammerspoon on the destination Mac.
2. Open Hammerspoon once and grant:
- Accessibility
- Automation (Keynote), if prompted
- Screen Recording (recommended)
3. Create `~/.hammerspoon` if it does not exist.
4. Copy `keynote_dual_canvas.lua` to `~/.hammerspoon/keynote_dual_canvas.lua`.
5. Merge the contents of `init.lua.export.example` into `~/.hammerspoon/init.lua`.
6. Update display names in the config if the target machine uses different monitor names.
7. Reload Hammerspoon config.
8. Press `ctrl` + `option` + `cmd` + `k`.

## Keynote menu compatibility

This module supports both Keynote menu styles:

- `Play > Play in Window`
- `Play > In Window` + `Play > Play Slideshow`

If the target Keynote version still differs, edit `playMenuPaths` or `presenterMenuPaths` in `keynote_dual_canvas.lua`.
