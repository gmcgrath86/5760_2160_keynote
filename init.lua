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

  -- Screen role matching
  slideSpanWidth = 5760,
  slideSpanHeight = 2160,
  slideSpanTolerance = 20,
  slideDisplayWidth = 2880,
  slideDisplayHeight = 2160,
  notesDisplayWidth = 1920,
  notesDisplayHeight = 1080,
  slideDisplayTolerance = 16,
  notesDisplayTolerance = 20,
  notesWindowRequired = false,

  -- Delays and timing
  activateDelay = 0.20,
  playDelay = 0.35,
  stopDelay = 0.06,
  settleDelay = 0.08,
  seatPoll = 0.10,
  findTimeoutStart = 3.5,
  findTimeoutSeat = 0.7,
  findTimeoutNotes = 1.2,
  forceNotesFullscreen = true,
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

local function absValue(v)
  return (v < 0) and -v or v
end

local function framesClose(a, b, tolerance)
  return absValue(a.x - b.x) <= tolerance
    and absValue(a.y - b.y) <= tolerance
    and absValue(a.w - b.w) <= tolerance
    and absValue(a.h - b.h) <= tolerance
end

local function frameToStringShort(frame)
  return string.format("%.0fx%.0f @ (%.0f,%.0f)", frame.w, frame.h, frame.x, frame.y)
end

local function allScreensLeftToRight()
  local screens = hs.screen.allScreens()
  table.sort(screens, function(a, b)
    return a:fullFrame().x < b:fullFrame().x
  end)
  return screens
end

local function logScreens(screens)
  local seen = {}
  for index, screen in ipairs(screens) do
    if index > CONFIG.screenLogLimit then
      break
    end
    local frame = screen:fullFrame()
    local name = screen:name() or "Unknown"
    table.insert(seen, string.format("%s: %s", name, frameToStringShort(frame)))
  end
  log.i("Detected screens: " .. table.concat(seen, " | "))
  return screens
end

local function frameMatchesTarget(frame, targetW, targetH, tolerance)
  return absValue(frame.w - targetW) <= tolerance and absValue(frame.h - targetH) <= tolerance
end

local function sortScreensByArea(screens)
  local withArea = {}
  for _, screen in ipairs(screens) do
    local frame = screen:fullFrame()
    local area = frame.w * frame.h
    table.insert(withArea, { screen = screen, area = area })
  end
  table.sort(withArea, function(a, b)
    return a.area > b.area
  end)
  local ordered = {}
  for _, entry in ipairs(withArea) do
    table.insert(ordered, entry.screen)
  end
  return ordered
end

local function candidateScreens(screens)
  local fullCanvasCandidates = {}
  local halfCanvasCandidates = {}
  local notesCandidates = {}

  for _, screen in ipairs(screens) do
    local frame = screen:fullFrame()
    if frameMatchesTarget(frame, CONFIG.slideSpanWidth, CONFIG.slideSpanHeight, CONFIG.slideSpanTolerance) then
      table.insert(fullCanvasCandidates, screen)
    end
    if frameMatchesTarget(frame, CONFIG.slideDisplayWidth, CONFIG.slideDisplayHeight, CONFIG.slideDisplayTolerance) then
      table.insert(halfCanvasCandidates, screen)
    end
    if frameMatchesTarget(frame, CONFIG.notesDisplayWidth, CONFIG.notesDisplayHeight, CONFIG.notesDisplayTolerance) then
      table.insert(notesCandidates, screen)
    end
  end

  return fullCanvasCandidates, halfCanvasCandidates, notesCandidates
end

local function screenFingerprint(screen)
  local frame = screen:fullFrame()
  return string.format("x=%.0f y=%.0f w=%.0f h=%.0f", frame.x, frame.y, frame.w, frame.h)
end

local function resolveSlideScreens(side, screens, halfCanvasCandidates, fullCanvasCandidates)
  if #fullCanvasCandidates >= 1 then
    if #halfCanvasCandidates >= 2 then
      log.i("Detected unified canvas output (5760x2160) plus 2880x2160 outputs; using unified output for slideshow")
    else
      log.i("Detected unified canvas output (5760x2160); using that for slideshow")
    end
    return fullCanvasCandidates[1], fullCanvasCandidates[1]
  end

  if #halfCanvasCandidates >= 2 then
    local leftSlide = halfCanvasCandidates[1]
    local rightSlide = halfCanvasCandidates[#halfCanvasCandidates]
    if side == "left" then
      return leftSlide, rightSlide
    end
    return rightSlide, leftSlide
  end

  if #halfCanvasCandidates == 1 then
    log.w("Only one 2880x2160 screen detected; using it for both sides")
    local single = halfCanvasCandidates[1]
    return single, single
  end

  local byArea = sortScreensByArea(screens)
  if #byArea >= 1 then
    log.w("Falling back to largest screen for slideshow")
    return byArea[1], byArea[1]
  end

  return nil, nil
end

local function resolveNotesScreen(screens, notesCandidates, slideScreen)
  if #notesCandidates >= 1 then
    return notesCandidates[1]
  end

  for _, screen in ipairs(screens) do
    if screen ~= slideScreen then
      return screen
    end
  end

  return slideScreen
end

local function screensByRole(side)
  local screens = logScreens(allScreensLeftToRight())
  if #screens < 2 then
    return nil, nil, nil, "Need at least two displays"
  end

  local fullCanvasCandidates, halfCanvasCandidates, notesCandidates = candidateScreens(screens)
  local slideScreen, alternateSlide = resolveSlideScreens(side, screens, halfCanvasCandidates, fullCanvasCandidates)
  if not slideScreen then
    return nil, nil, nil, "Could not resolve slide output"
  end

  local notesScreen = resolveNotesScreen(screens, notesCandidates, alternateSlide)

  local targetFrames = {
    side = side,
    slide = screenFingerprint(slideScreen),
    notes = notesScreen and screenFingerprint(notesScreen) or "n/a",
    fullCanvasCount = #fullCanvasCandidates,
    halfCanvasCount = #halfCanvasCandidates,
    notesCandidates = #notesCandidates,
  }
  log.i(string.format("Screen roles: side=%s slide=%s notes=%s | candidates full=%d half=%d notes=%d", targetFrames.side, targetFrames.slide, targetFrames.notes, targetFrames.fullCanvasCount, targetFrames.halfCanvasCount, targetFrames.notesCandidates))

  return slideScreen, notesScreen, nil, nil
end

local function targetScreens(side)
  local slideScreen, notesScreen, _, err = screensByRole(side)
  if not slideScreen then
    return nil, nil, nil, err or "Need two screens"
  end
  return slideScreen, notesScreen, side, nil
end

local function describeRoleFrames(side, slideScreen, notesScreen)
  local slideFrame = slideScreen and slideScreen:fullFrame()
  local notesFrame = notesScreen and notesScreen:fullFrame()
  log.i(string.format(
    "Resolved role: side=%s slide=%s notes=%s",
    side,
    slideFrame and frameToStringShort(slideFrame) or "n/a",
    notesFrame and frameToStringShort(notesFrame) or "n/a"
  ))
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
  return absValue(a.x - b.x) + absValue(a.y - b.y) + absValue(a.w - b.w) + absValue(a.h - b.h)
end

local function titleContains(lowerTitle, token)
  return lowerTitle:find(token, 1, true) ~= nil
end

local function titleScoreForRole(title, role)
  local lower = string.lower(title or "")
  local score = 0

  if role == "notes" then
    if titleContains(lower, "notes") or titleContains(lower, "speaker") or titleContains(lower, "presenter") then
      score = score + 180
    end
    if titleContains(lower, "slideshow") then
      score = score + 40
    end
    return score
  end

  if titleContains(lower, "slideshow") then
    score = score + 90
  end
  if titleContains(lower, "keynote") then
    score = score + 15
  end
  if titleContains(lower, "presentation") then
    score = score + 60
  end
  if titleContains(lower, "play") then
    score = score + 30
  end
  return score
end

local function isLikelyNotesWindow(title)
  local lower = string.lower(title or "")
  return lower:find("notes", 1, true) or lower:find("speaker", 1, true) or lower:find("presenter", 1, true) or false
end

local function isLikelySlideWindow(title)
  local lower = string.lower(title or "")
  if lower == "" then
    return false
  end
  return lower:find("slideshow", 1, true) or lower:find("slide", 1, true) or lower:find("keynote", 1, true) or false
end

local function chooseWindowByScore(app, excludeIds, targetFrame, role, preferredWindowId)
  local windows = app:allWindows() or {}
  local frontmost = hs.window.frontmostWindow()
  local preferredTitleMatch = preferredWindowId
  local bestWindow, bestScore

  local function scoreWindow(win)
    if not isKeynoteWindow(win) or not win:isStandard() then
      return nil
    end

    local id = win:id()
    if id and excludeIds[id] then
      return nil
    end

    local winTitle = win:title()
    local score = titleScoreForRole(winTitle, role)

    local id = win:id()
    if preferredTitleMatch and id == preferredTitleMatch then
      score = score + 260
    end

    if role == "notes" then
      if isLikelyNotesWindow(winTitle) then
        score = score + 170
      end
    elseif isLikelySlideWindow(winTitle) then
      score = score + 120
    end

    local frame = win:frame()
    local delta = frameDelta(frame, targetFrame)
    score = score - delta

    local targetArea = targetFrame.w * targetFrame.h
    if targetArea > 0 then
      local area = frame.w * frame.h
      local ratio = area / targetArea
      score = score + math.floor(700 - absValue(ratio - 1) * 800)
    end

    if math.abs(frame.w - targetFrame.w) <= CONFIG.fullFrameTolerance then
      score = score + 90
    end

    if math.abs(frame.h - targetFrame.h) <= CONFIG.fullFrameTolerance then
      score = score + 90
    end

    if win == frontmost then
      score = score + 45
    end

    return score
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

local function chooseWindowByScoreFallback(app, excludeIds, role)
  local frontmost = hs.window.frontmostWindow()
  if frontmost then
    local id = frontmost:id()
    local title = (frontmost:title() or "")
    if isKeynoteWindow(frontmost) and frontmost:isStandard() then
      if not (id and excludeIds[id]) then
        if role == "notes" then
          if isLikelyNotesWindow(title) then
            return frontmost, "frontmost-notes-title"
          end
        else
          return frontmost, "frontmost"
        end
      end
    end
  end
  return nil, "none"
end

local function waitForWindow(app, excludeIds, targetFrame, timeoutSeconds, role, preferredWindowId)
  local deadline = hs.timer.secondsSinceEpoch() + timeoutSeconds
  while hs.timer.secondsSinceEpoch() < deadline do
    local win, reason = chooseWindowByScore(app, excludeIds, targetFrame, role, preferredWindowId)
    if win then
      return win, reason
    end

    local fallbackWindow, fallbackReason = chooseWindowByScoreFallback(app, excludeIds, role)
    if fallbackWindow then
      return fallbackWindow, fallbackReason
    end

    hs.timer.usleep(ms(CONFIG.seatPoll))
  end
  return nil, "timeout"
end

local function applyFrame(win, target)
  win:setFrame(target, 0)
  hs.timer.usleep(ms(CONFIG.settleDelay))

  local current = win:frame()
  if not framesClose(current, target, CONFIG.frameTolerance) then
    win:setTopLeft({ x = target.x, y = target.y })
    win:setSize({ w = target.w, h = target.h })
    hs.timer.usleep(ms(CONFIG.settleDelay))
    current = win:frame()
  end
  return current
end

local function seatWindow(win, role, screen, reason)
  local target = screen:fullFrame()
  local roleLabel = (role == "notes") and "notes" or "slides"
  log.i(string.format("Seating (%s) %s window to %s", reason or "unknown", roleLabel, frameToString(target)))

  win:raise()
  win:focus()

  local current = applyFrame(win, target)
  if not framesClose(current, target, CONFIG.frameTolerance) then
    return false, string.format("Failed to set %s window position", roleLabel)
  end

  if role == "notes" and CONFIG.forceNotesFullscreen and win.setFullScreen then
    local canFullscreen = win.isFullScreen ~= nil and win.setFullScreen ~= nil
    if canFullscreen and not win:isFullScreen() then
      local ok = pcall(function()
        win:setFullScreen(true)
      end)
      if ok then
        hs.timer.usleep(ms(CONFIG.settleDelay * 2))
      end
    end
    if canFullscreen and win:isFullScreen() then
      log.i(string.format("Notes window entered fullscreen"))
      return true, nil
    end
    log.w("Could not force notes window fullscreen; leaving it windowed on target notes display")
  end

  log.i(string.format("Window after seat (%s): %s", roleLabel, frameToString(current)))
  return true, nil
end

local function startSlideshowAndSeat(side, mode)
  local slideScreen, notesScreen, targetSide, err = targetScreens(side)
  if not slideScreen then
    return 503, err
  end
  describeRoleFrames(targetSide, slideScreen, notesScreen)

  local targetFrame = slideScreen:fullFrame()
  local notesFrame = notesScreen and notesScreen:fullFrame()
  local app, appErr
  local includeExisting = (mode == "seat")
  local preferredWindowId = nil

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

  local preWindowIds = includeExisting and {} or keyWindowIds(app:allWindows())
  if not includeExisting then
    hs.eventtap.keyStroke(CONFIG.playShortcut.mods, CONFIG.playShortcut.key, 0, app)
    log.i("Sent Option+Command+P to start Play in Window")
    hs.timer.usleep(ms(CONFIG.playDelay))
    local frontmost = hs.window.frontmostWindow()
    if frontmost then
      local id = frontmost:id()
      if id then
        preferredWindowId = id
      end
    end
  else
    hs.timer.usleep(ms(0.12))
  end

  local slideTimeout = includeExisting and CONFIG.findTimeoutSeat or CONFIG.findTimeoutStart
  local slideWindow, slideReason = waitForWindow(app, preWindowIds, targetFrame, slideTimeout, "slides", preferredWindowId)
  if not slideWindow then
    log.e("Keynote slideshow window not found")
    maybeAlert("No Keynote slideshow window")
    return 500, "Slideshow window not found"
  end

  local ok, seatErr = seatWindow(slideWindow, "slides", slideScreen, slideReason)
  if not ok then
    return 500, seatErr
  end

  local excludeForNotes = keyWindowIds({ slideWindow })
  if notesScreen and notesFrame then
    local notesWindow, notesReason = waitForWindow(app, excludeForNotes, notesFrame, CONFIG.findTimeoutNotes, "notes")
    if not notesWindow then
      log.w("No separate notes window detected")
      if CONFIG.notesWindowRequired then
        return 500, "Notes window not found"
      end
      return 200, "OK (notes not found)"
    end

    local notesOk, notesSeatErr = seatWindow(notesWindow, "notes", notesScreen, notesReason)
    if not notesOk then
      log.w(string.format("Notes window could not be positioned: %s", notesSeatErr))
      if CONFIG.notesWindowRequired then
        return 500, notesSeatErr
      end
    end
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
