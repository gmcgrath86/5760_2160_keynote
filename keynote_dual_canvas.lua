local M = {}

local log = hs.logger.new("keynote_dual_canvas", "info")

local defaults = {
  hotkeyMods = { "ctrl", "alt", "cmd" },
  hotkeyKey = "k",
  keynoteAppName = "Keynote",
  deckPath = nil,
  openDeckOnHotkey = false,
  playScreenNames = {
    "SwitchResX4 - Desktop (1)",
    "SwitchResX4 - Desktop (2)",
  },
  notesScreenName = "SwitchResX4 - Desktop (3)",
  playMenuPaths = {
    { "Play", "Play Slideshow in Window" },
    { "Play", "Play in Window" },
  },
  presenterMenuPaths = {
    { "Play", "Show Presenter Display in Window" },
    { "Play", "Show Presenter Display" },
    { "Play", "Show Presenter Notes in Window" },
    { "View", "Show Presenter Display" },
  },
  delays = {
    afterActivate = 0.35,
    afterStop = 0.5,
    afterPlay = 0.9,
    retry = 0.35,
  },
  maxPlacementRetries = 20,
  showAlerts = true,
}

M.config = nil
M._hotkey = nil

local function deepcopy(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[k] = deepcopy(v)
  end
  return out
end

local function merge(dst, src)
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

local function notify(cfg, msg)
  log.i(msg)
  if cfg.showAlerts then
    hs.alert.show(msg)
  end
end

local function screenName(screen)
  local ok, name = pcall(function()
    return screen:name()
  end)
  if ok and name then
    return name
  end
  return "(unknown)"
end

local function normalize(s)
  return (s or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function findScreenByName(name)
  if not name then
    return nil
  end

  local needle = normalize(name)
  local containsMatch = nil

  for _, screen in ipairs(hs.screen.allScreens()) do
    local sname = screenName(screen)
    local norm = normalize(sname)
    if norm == needle then
      return screen
    end
    if not containsMatch and norm:find(needle, 1, true) then
      containsMatch = screen
    end
  end

  return containsMatch
end

local function autoFindWideScreens()
  local wides = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    if math.abs(f.w - 2880) <= 2 and math.abs(f.h - 2160) <= 2 then
      table.insert(wides, screen)
    end
  end
  table.sort(wides, function(a, b)
    return a:fullFrame().x < b:fullFrame().x
  end)
  if #wides >= 2 then
    return wides[1], wides[2]
  end
  return nil, nil
end

local function autoFindPortraitScreen()
  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:fullFrame()
    if f.h > f.w and (math.abs(f.w - 1080) <= 2 or math.abs(f.h - 1920) <= 2) then
      return screen
    end
  end
  return nil
end

local function unionFrame(a, b)
  return {
    x = math.min(a.x, b.x),
    y = math.min(a.y, b.y),
    w = math.max(a.x + a.w, b.x + b.w) - math.min(a.x, b.x),
    h = math.max(a.y + a.h, b.y + b.h) - math.min(a.y, b.y),
  }
end

local function resolveTargetFrames(cfg)
  local left = findScreenByName(cfg.playScreenNames[1])
  local right = findScreenByName(cfg.playScreenNames[2])
  local notes = findScreenByName(cfg.notesScreenName)

  if not left or not right then
    local a, b = autoFindWideScreens()
    left = left or a
    right = right or b
  end
  if not notes then
    notes = autoFindPortraitScreen()
  end

  if not left or not right or not notes then
    return nil, nil, {
      left = left and screenName(left) or nil,
      right = right and screenName(right) or nil,
      notes = notes and screenName(notes) or nil,
    }
  end

  local lf = left:fullFrame()
  local rf = right:fullFrame()
  local nf = notes:fullFrame()
  local playFrame = unionFrame(lf, rf)

  return playFrame, nf, {
    left = screenName(left),
    right = screenName(right),
    notes = screenName(notes),
  }
end

local function openDeckIfConfigured(cfg)
  if not (cfg.openDeckOnHotkey and cfg.deckPath and cfg.deckPath ~= "") then
    return
  end

  local quoted = string.format("%q", cfg.deckPath)
  hs.execute("/usr/bin/open -a Keynote " .. quoted, true)
end

local function keynoteApp(cfg)
  return hs.appfinder.appFromName(cfg.keynoteAppName)
end

local function activateKeynote(cfg)
  hs.application.launchOrFocus(cfg.keynoteAppName)
  local app = keynoteApp(cfg)
  if app then
    app:activate(true)
  end
  return app
end

local function sendEscape(app)
  if not app then
    return
  end
  hs.eventtap.keyStroke({}, "escape", 0, app)
end

local function tryMenuPaths(app, paths)
  if not app then
    return false, nil
  end

  for _, path in ipairs(paths or {}) do
    local ok = false
    local success, result = pcall(function()
      ok = app:selectMenuItem(path)
      return ok
    end)
    if success and result then
      return true, path
    end
  end
  return false, nil
end

local function tryPlayUsingWindowToggle(app)
  if not app then
    return false, nil
  end

  -- Some Keynote versions use a mode toggle ("In Window") plus a generic
  -- "Play Slideshow" action instead of a single "Play in Window" item.
  pcall(function()
    app:selectMenuItem({ "Play", "In Window" })
  end)

  local success = false
  pcall(function()
    success = app:selectMenuItem({ "Play", "Play Slideshow" }) or false
  end)

  if success then
    return true, "Play > In Window + Play > Play Slideshow"
  end

  return false, nil
end

local function windowArea(win)
  local f = win:frame()
  return (f.w or 0) * (f.h or 0)
end

local function visibleKeynoteWindows(app)
  local out = {}
  if not app then
    return out
  end

  for _, win in ipairs(app:allWindows() or {}) do
    local okVisible, isVisible = pcall(function()
      return win:isVisible()
    end)
    if okVisible and isVisible then
      local okStandard, isStandard = pcall(function()
        return win:isStandard()
      end)
      if (not okStandard) or isStandard then
        table.insert(out, win)
      end
    end
  end
  return out
end

local function classifyWindows(app)
  local wins = visibleKeynoteWindows(app)
  local slidesWin = nil
  local notesWin = nil

  for _, win in ipairs(wins) do
    local title = normalize(win:title() or "")
    if not notesWin and (title:find("presenter", 1, true) or title:find("notes", 1, true)) then
      notesWin = win
    elseif not slidesWin and (title:find("slide show", 1, true) or title:find("slideshow", 1, true)) then
      slidesWin = win
    end
  end

  if (not slidesWin or not notesWin) and #wins >= 2 then
    table.sort(wins, function(a, b)
      return windowArea(a) > windowArea(b)
    end)

    if not slidesWin then
      for i = 1, #wins do
        if wins[i] ~= notesWin then
          slidesWin = wins[i]
          break
        end
      end
    end

    if not notesWin then
      for i = 1, #wins do
        if wins[i] ~= slidesWin then
          notesWin = wins[i]
          break
        end
      end
    end
  elseif not slidesWin and #wins == 1 then
    slidesWin = wins[1]
  end

  if slidesWin and notesWin and slidesWin == notesWin then
    for i = 1, #wins do
      if wins[i] ~= notesWin then
        slidesWin = wins[i]
        break
      end
    end
  end

  return slidesWin, notesWin, wins
end

local function titlesForDebug(wins)
  local out = {}
  for _, win in ipairs(wins or {}) do
    table.insert(out, string.format("%q", win:title() or ""))
  end
  return table.concat(out, ", ")
end

local function setWindowFrame(win, frame)
  if not win or not frame then
    return
  end
  win:setFrame(frame, 0)
end

local function ensurePresenterWindow(app, cfg)
  local ok, path = tryMenuPaths(app, cfg.presenterMenuPaths)
  if ok then
    log.i("Presenter window menu selected: " .. table.concat(path, " > "))
  else
    log.w("Could not find a presenter display menu item; continuing with available windows")
  end
end

local function placeWindowsWhenReady(app, cfg, playFrame, notesFrame, attempt, presenterRequested)
  local slidesWin, notesWin, wins = classifyWindows(app)

  if slidesWin and notesWin then
    setWindowFrame(slidesWin, playFrame)
    setWindowFrame(notesWin, notesFrame)
    slidesWin:raise()
    notesWin:raise()
    slidesWin:focus()
    notify(cfg, "Keynote windows placed")
    return
  end

  if not presenterRequested and attempt >= 2 then
    ensurePresenterWindow(app, cfg)
    presenterRequested = true
  end

  if slidesWin and not notesWin then
    setWindowFrame(slidesWin, playFrame)
  end

  if attempt >= cfg.maxPlacementRetries then
    local msg = "Keynote window placement timed out"
    log.e(msg .. "; windows seen: " .. titlesForDebug(wins))
    notify(cfg, msg)
    return
  end

  hs.timer.doAfter(cfg.delays.retry, function()
    local currentApp = keynoteApp(cfg) or app
    placeWindowsWhenReady(currentApp, cfg, playFrame, notesFrame, attempt + 1, presenterRequested)
  end)
end

function M.run()
  local cfg = M.config or deepcopy(defaults)
  pcall(function()
    hs.window.animationDuration = 0
  end)
  local playFrame, notesFrame, targets = resolveTargetFrames(cfg)

  if not playFrame or not notesFrame then
    local seen = {}
    for _, s in ipairs(hs.screen.allScreens()) do
      local f = s:fullFrame()
      table.insert(seen, string.format("%s (%dx%d @ %d,%d)", screenName(s), f.w, f.h, f.x, f.y))
    end
    notify(cfg, "Display mapping failed; check screen names")
    log.e("Resolved screens: left=" .. tostring(targets.left) .. " right=" .. tostring(targets.right) .. " notes=" .. tostring(targets.notes))
    log.e("Available screens: " .. table.concat(seen, " | "))
    return
  end

  log.i(string.format(
    "Targets: slides=%s + %s => %dx%d, notes=%s => %dx%d",
    targets.left,
    targets.right,
    playFrame.w,
    playFrame.h,
    targets.notes,
    notesFrame.w,
    notesFrame.h
  ))

  openDeckIfConfigured(cfg)
  local app = activateKeynote(cfg)

  hs.timer.doAfter(cfg.delays.afterActivate, function()
    app = keynoteApp(cfg) or app
    if not app then
      notify(cfg, "Keynote is not running")
      return
    end

    app:activate(true)

    -- Exit slideshow/presenter mode if active, then restart so content/layout refreshes.
    sendEscape(app)
    hs.timer.doAfter(0.12, function()
      sendEscape(app)
    end)

    hs.timer.doAfter(cfg.delays.afterStop, function()
      app = keynoteApp(cfg) or app
      if not app then
        notify(cfg, "Keynote disappeared before relaunch")
        return
      end

      local played, playPath = tryMenuPaths(app, cfg.playMenuPaths)
      if not played then
        played, playPath = tryPlayUsingWindowToggle(app)
      end
      if not played then
        notify(cfg, "Could not start Keynote with 'Play in Window'")
        log.e("Checked menu paths did not match; update playMenuPaths for your Keynote version")
        return
      end
      if type(playPath) == "table" then
        log.i("Play menu selected: " .. table.concat(playPath, " > "))
      else
        log.i("Play menu selected: " .. tostring(playPath))
      end

      hs.timer.doAfter(cfg.delays.afterPlay, function()
        local currentApp = keynoteApp(cfg) or app
        placeWindowsWhenReady(currentApp, cfg, playFrame, notesFrame, 1, false)
      end)
    end)
  end)
end

function M.bind(userConfig)
  M.config = merge(deepcopy(defaults), userConfig or {})
  pcall(function()
    hs.window.animationDuration = 0
  end)

  if M._hotkey then
    M._hotkey:delete()
    M._hotkey = nil
  end

  M._hotkey = hs.hotkey.bind(M.config.hotkeyMods, M.config.hotkeyKey, M.run)
  log.i("Bound hotkey " .. table.concat(M.config.hotkeyMods, "+") .. "+" .. M.config.hotkeyKey)
  return M
end

return M
