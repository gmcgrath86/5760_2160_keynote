-- Keynote show-control for Hammerspoon.
-- API:
--   GET /keynote/left
--   GET /keynote/right
--   GET /keynote/seat?side=left|right
--   GET /keynote/stop

local CONFIG = {
  httpPort = 8765,
  keynoteBundleId = "com.apple.iWork.Keynote",
  keynoteName = "Keynote",
  hotkeySide = "left",
  playShortcut = { mods = { "alt", "cmd" }, key = "p" },
  showAlerts = false,
  logLevel = "info",
  activateDelay = 0.20,
  playDelay = 0.35,
  stopDelay = 0.06,
  settleDelay = 0.08,
  seatPoll = 0.10,
  findTimeoutStart = 3.5,
  findTimeoutSeat = 0.7,
  frameTolerance = 2,
  fullFrameTolerance = 8,
  screenLogLimit = 4,
}

local log = hs.logger.new("keynote-http", CONFIG.logLevel)

local function ms(value)
  return math.floor(value * 1000000)
end

local function maybeAlert(message)
  if CONFIG.showAlerts then
    hs.alert.show(message, 0.8)
  end
end

local function frameToString(frame)
  return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", frame.x, frame.y, frame.w, frame.h)
end

local function plainText(status, body)
  return body .. "\n", status, { ["Content-Type"] = "text/plain; charset=utf-8" }
end

local function parseQueryString(queryString)
  local query = {}
  if not queryString or queryString == "" then
    return query
  end
  for pair in string.gmatch(queryString, "([^&]+)") do
    local key, value = pair:match("^([^=]+)=?(.*)$")
    if key then
      query[key] = value or ""
    end
  end
  return query
end

local function parsePath(rawPath)
  local path, queryString = rawPath:match("^([^?]*)%??(.*)$")
  if path and #path > 1 and path:sub(-1) == "/" then
    path = path:sub(1, -2)
  end
  return path or rawPath, parseQueryString(queryString or "")
end

local function normalizeSide(side)
  side = (side or ""):lower()
  if side == "left" or side == "right" then
    return side
  end
  return nil
end

local function allScreensLeftToRight()
  local screens = hs.screen.allScreens()
  table.sort(screens, function(a, b)
    return a:fullFrame().x < b:fullFrame().x
  end)
  return screens
end

local function logScreens()
  local screens = allScreensLeftToRight()
  local seen = {}
  for index, screen in ipairs(screens) do
    if index > CONFIG.screenLogLimit then
      break
    end
    local frame = screen:fullFrame()
    local name = screen:name() or "Unknown"
    table.insert(seen, string.format("%s: %s", name, frameToString(frame)))
  end
  log.i("Detected screen order: " .. table.concat(seen, " | "))
  return screens
end

local function screensBySide()
  local screens = logScreens()
  if #screens < 2 then
    return nil, nil, "Need at least two displays"
  end
  return screens[1], screens[#screens], nil
end

local function targetScreenForSide(side)
  local left, right, err = screensBySide()
  if err then
    return nil, err
  end
  if side == "left" then
    return left, nil
  end
  if side == "right" then
    return right, nil
  end
  return nil, "Invalid side (expected left or right)"
end

local function findKeynoteApp()
  return hs.application.get(CONFIG.keynoteBundleId) or hs.application.find(CONFIG.keynoteName)
end

local function launchAndActivateKeynote()
  if hs.application.launchOrFocusByBundleID then
    hs.application.launchOrFocusByBundleID(CONFIG.keynoteBundleId)
  else
    hs.application.launchOrFocus(CONFIG.keynoteName)
  end

  local deadline = hs.timer.secondsSinceEpoch() + 6
  while hs.timer.secondsSinceEpoch() < deadline do
    local app = findKeynoteApp()
    if app then
      app:activate(true)
      hs.timer.usleep(ms(CONFIG.activateDelay))
      return app, nil
    end
    hs.timer.usleep(ms(0.1))
  end
  return nil, "Keynote not found"
end

local function getRunningKeynote()
  local app = findKeynoteApp()
  if not app then
    return nil, "Keynote not found"
  end
  app:activate(true)
  hs.timer.usleep(ms(0.12))
  return app, nil
end

local function keyWindowIds(windows)
  local idMap = {}
  for _, win in ipairs(windows or {}) do
    local id = win:id()
    if id then
      idMap[id] = true
    end
  end
  return idMap
end

local function isKeynoteWindow(win)
  if not win then
    return false
  end
  local app = win:application()
  return app and app:bundleID() == CONFIG.keynoteBundleId
end

local function frameDelta(a, b)
  return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.w - b.w) + math.abs(a.h - b.h)
end

local function titleScore(title)
  local lower = string.lower(title or "")
  if lower == "" then
    return 2
  end
  local score = 0
  if lower:find("slideshow", 1, true) then
    score = score + 90
  end
  if lower:find("presentation", 1, true) then
    score = score + 60
  end
  if lower:find("play", 1, true) then
    score = score + 30
  end
  return score
end

local function chooseWindowByScore(app, preWindowIds, targetFrame, includeExisting)
  local windows = app:allWindows() or {}
  local frontmost = hs.window.frontmostWindow()
  local bestWindow, bestScore

  local function scoreWindow(win)
    if not isKeynoteWindow(win) or not win:isStandard() then
      return nil
    end
    if preWindowIds and not includeExisting then
      local id = win:id()
      if id and preWindowIds[id] then
        return nil
      end
    end
    local score = 0
    local frame = win:frame()
    score = score + titleScore(win:title())
    score = score - frameDelta(frame, targetFrame)
    if math.abs(frame.w - targetFrame.w) <= CONFIG.fullFrameTolerance then
      score = score + 80
    end
    if math.abs(frame.h - targetFrame.h) <= CONFIG.fullFrameTolerance then
      score = score + 80
    end
    if win == frontmost then
      score = score + 45
    end
    local area = frame.w * frame.h
    if targetFrame.w * targetFrame.h > 0 then
      local ratio = area / (targetFrame.w * targetFrame.h)
      score = score + math.floor((1000 - math.abs(ratio - 1) * 400))
    end
    return score
  end

  if preWindowIds then
    local frontId = frontmost and frontmost:id()
    if frontmost and frontmost ~= nil and isKeynoteWindow(frontmost) and not (frontId and preWindowIds[frontId]) then
      return frontmost, "frontmost-new"
    end
  end

  for _, win in ipairs(windows) do
    local score = scoreWindow(win)
    if score then
      if not bestWindow or score > bestScore then
        bestWindow = win
        bestScore = score
      end
    end
  end

  if bestWindow then
    return bestWindow, "scored"
  end
  return nil, "none"
end
local function waitForWindow(app, preWindowIds, targetFrame, timeoutSeconds, includeExisting)
  local deadline = hs.timer.secondsSinceEpoch() + timeoutSeconds
  while hs.timer.secondsSinceEpoch() < deadline do
    local win, reason = chooseWindowByScore(app, preWindowIds, targetFrame, includeExisting)
    if win then
      return win, reason
    end
    hs.timer.usleep(ms(CONFIG.seatPoll))
  end
  return nil, "timeout"
end

local function framesMatch(actual, expected, tolerance)
  return math.abs(actual.x - expected.x) <= tolerance
    and math.abs(actual.y - expected.y) <= tolerance
    and math.abs(actual.w - expected.w) <= tolerance
    and math.abs(actual.h - expected.h) <= tolerance
end

local function seatWindow(win, side, screen, reason)
  local target = screen:fullFrame()
  log.i(string.format("Seating (%s) to %s screen: %s", reason or "unknown", side, frameToString(target)))

  win:raise()
  win:focus()
  win:setFrame(target, 0)
  hs.timer.usleep(ms(CONFIG.settleDelay))

  local current = win:frame()
  if not framesMatch(current, target, CONFIG.frameTolerance) then
    win:setTopLeft({ x = target.x, y = target.y })
    win:setSize({ w = target.w, h = target.h })
    hs.timer.usleep(ms(CONFIG.settleDelay))
    current = win:frame()
  end

  log.i("Window after seat: " .. frameToString(current))
  if not framesMatch(current, target, CONFIG.frameTolerance) then
    maybeAlert("Keynote seat failed")
    return false, "Failed to set slideshow window frame"
  end

  return true, nil
end

local function startSlideshowAndSeat(side, mode)
  local targetScreen, screenErr = targetScreenForSide(side)
  if not targetScreen then
    return 503, screenErr
  end
  local targetFrame = targetScreen:fullFrame()
  local app, appErr
  local includeExisting = (mode == "seat")

  if includeExisting then
    app, appErr = getRunningKeynote()
    if not app then
      return 404, appErr
    end
  else
    app, appErr = launchAndActivateKeynote()
    if not app then
      return 404, appErr
    end
  end

  local preWindowIds
  if not includeExisting then
    preWindowIds = keyWindowIds(app:allWindows())
    hs.eventtap.keyStroke(CONFIG.playShortcut.mods, CONFIG.playShortcut.key, 0, app)
    log.i("Sent Option+Command+P to start Play in Window")
    hs.timer.usleep(ms(CONFIG.playDelay))
  else
    hs.timer.usleep(ms(0.12))
  end

  local timeout = includeExisting and CONFIG.findTimeoutSeat or CONFIG.findTimeoutStart
  local window, reason = waitForWindow(app, preWindowIds, targetFrame, timeout, includeExisting)
  if not window then
    log.e("Keynote slideshow window not found")
    maybeAlert("No Keynote slideshow window")
    return 500, "Slideshow window not found"
  end

  local ok, seatErr = seatWindow(window, side, targetScreen, reason)
  if not ok then
    return 500, seatErr
  end

  local label = includeExisting and "seated" or "started+seated"
  maybeAlert("Keynote " .. label .. " on " .. side)
  return 200, "OK"
end

local function stopSlideshow()
  local app = findKeynoteApp()
  if not app then
    return 404, "Keynote not found"
  end

  app:activate(true)
  hs.timer.usleep(ms(CONFIG.activateDelay))
  hs.eventtap.keyStroke({}, "escape", 0, app)
  hs.timer.usleep(ms(CONFIG.stopDelay))
  hs.eventtap.keyStroke({}, "escape", 0, app)
  log.i("Sent Escape to stop Keynote playback")
  maybeAlert("Keynote stop")
  return 200, "OK"
end

local function handleRequest(method, rawPath, _headers, _body)
  local path, query = parsePath(rawPath or "/")
  log.i(string.format("HTTP %s %s", method, rawPath or "/"))

  if method ~= "GET" then
    return plainText(405, "Method Not Allowed")
  end

  if path == "/keynote/left" then
    local status, body = startSlideshowAndSeat("left", "start")
    return plainText(status, body)
  end

  if path == "/keynote/right" then
    local status, body = startSlideshowAndSeat("right", "start")
    return plainText(status, body)
  end

  if path == "/keynote/seat" then
    local side = normalizeSide(query.side)
    if not side then
      return plainText(400, "Invalid side (use ?side=left or ?side=right)")
    end
    local status, body = startSlideshowAndSeat(side, "seat")
    return plainText(status, body)
  end

  if path == "/keynote/stop" then
    local status, body = stopSlideshow()
    return plainText(status, body)
  end

  if path == "/keynote/health" then
    local app, _ = findKeynoteApp()
    if app then
      return plainText(200, "OK")
    end
    return plainText(503, "Keynote not running")
  end

  return plainText(404, "Not Found")
end

local function startHTTPServer()
  if _G.keynoteControlServer then
    _G.keynoteControlServer:stop()
    _G.keynoteControlServer = nil
  end
  local server = hs.httpserver.new()
  server:setPort(CONFIG.httpPort)
  server:setCallback(handleRequest)
  if server.setInterface then
    server:setInterface("0.0.0.0")
  end
  server:start()
  _G.keynoteControlServer = server
  log.i(string.format("Keynote HTTP control listening on port %d", CONFIG.httpPort))
end

startHTTPServer()

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "k", function()
  local status, body = startSlideshowAndSeat(CONFIG.hotkeySide, "start")
  if status ~= 200 then
    maybeAlert("Keynote control: " .. body)
  end
end)
