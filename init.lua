require("hs.ipc")

local home = os.getenv("HOME")

package.path = package.path .. ";" .. home .. "/.hammerspoon/?.lua"

if hs.accessibilityState and hs.accessibilityState() then
  require("keynote_dual_canvas").bind({
    hotkeyMods = { "ctrl", "alt", "cmd" },
    hotkeyKey = "k",

    -- Match the known SwitchResX display names for the production machine.
    playScreenNames = {
      "SwitchResX4 - Desktop (1)",
      "SwitchResX4 - Desktop (2)",
    },
    notesScreenName = "SwitchResX4 - Desktop (3)",

    http = {
      enabled = true,
      bindAddress = "10.2.130.108",
      port = 8765,
      token = nil,
    },

    -- Optional: uncomment to always reopen a specific deck before refresh.
    -- deckPath = "/absolute/path/to/your/deck.key",
    -- openDeckOnHotkey = true,
    -- If you want auth on the AV VLAN, set a shared token:
    -- http = {
    --   enabled = true,
    --   bindAddress = "10.2.130.108",
    --   port = 8765,
    --   token = "replace-with-a-secret",
    -- },
  })
else
  hs.printf("Accessibility permission not granted yet; skipping Keynote hotkey bind. Reload after granting access.")
end
