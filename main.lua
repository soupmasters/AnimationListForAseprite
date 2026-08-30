local AnimationList = {}

local hiddenPrefixes = {
  "-",
  "*",
  "//",
  "'",
}

local DEFAULT_DIALOG_WIDTH = 260
local activeDialog = nil
local dialogSessionActive = false
local suppressDialogClose = false
local rebuildingDialog = false
local displayedSprite = nil
local displayedTagSnapshot = {}
local observedSprite = nil
local spriteListener = nil
local appEventSource = nil
local appListeners = {}
local refreshTimer = nil
local lastDialogBounds = nil
local testHost = nil

local function currentApp()
  if testHost ~= nil then
    return testHost.app
  end
  return app
end

local function createDialog(options)
  if testHost ~= nil then
    return testHost.createDialog(options)
  end
  return Dialog(options)
end

local function startsWith(value, prefix)
  return value:sub(1, #prefix) == prefix
end

function AnimationList.isAnimationName(name)
  if type(name) ~= "string" or name == "" then
    return false
  end

  for _, prefix in ipairs(hiddenPrefixes) do
    if startsWith(name, prefix) then
      return false
    end
  end

  return true
end

function AnimationList.collectTags(sprite)
  local result = {}
  if sprite == nil or sprite.tags == nil then
    return result
  end

  for _, tag in ipairs(sprite.tags) do
    if AnimationList.isAnimationName(tag.name) then
      result[#result + 1] = tag
    end
  end
  return result
end

local function snapshotTags(tags)
  local snapshot = {}
  for index, tag in ipairs(tags) do
    snapshot[index] = {
      tag = tag,
      name = tag.name,
    }
  end
  return snapshot
end

local function snapshotsEqual(left, right)
  if #left ~= #right then
    return false
  end
  for index = 1, #left do
    if left[index].tag ~= right[index].tag or left[index].name ~= right[index].name then
      return false
    end
  end
  return true
end

local function sameTagStructure(left, right)
  if #left ~= #right then
    return false
  end
  for index = 1, #left do
    if left[index].tag ~= right[index].tag then
      return false
    end
  end
  return true
end

local function readDialogBounds(dialog)
  if dialog == nil then
    return nil
  end

  local ok, bounds = pcall(function()
    return dialog.bounds
  end)
  if not ok or bounds == nil then
    return nil
  end

  local x = tonumber(bounds.x)
  local y = tonumber(bounds.y)
  local width = tonumber(bounds.width)
  local height = tonumber(bounds.height)
  if x == nil or y == nil or width == nil or height == nil then
    return nil
  end

  return {
    x = x,
    y = y,
    width = width,
    height = height,
  }
end

local function rectangle(bounds)
  if testHost ~= nil then
    return {
      x = bounds.x,
      y = bounds.y,
      width = bounds.width,
      height = bounds.height,
    }
  end
  return Rectangle(bounds.x, bounds.y, bounds.width, bounds.height)
end

local function showDialog(dialog, previousBounds)
  dialog:show {
    wait = false,
    autoscrollbars = true,
  }

  local currentBounds = readDialogBounds(dialog)
  if currentBounds == nil then
    return
  end

  local targetBounds = previousBounds or currentBounds
  if previousBounds == nil then
    local width = math.max(targetBounds.width + 48, DEFAULT_DIALOG_WIDTH)
    targetBounds.x = targetBounds.x - math.floor((width - targetBounds.width) / 2)
    targetBounds.width = width
  end

  pcall(function()
    dialog.bounds = rectangle(targetBounds)
  end)
end

local refreshIfChanged

local function createTimer(options)
  if testHost ~= nil and testHost.createTimer ~= nil then
    return testHost.createTimer(options)
  end
  return Timer(options)
end

local function stopRefreshTimer()
  local timer = refreshTimer
  refreshTimer = nil
  if timer ~= nil then
    pcall(function()
      timer:stop()
    end)
  end
end

local function detachSpriteListener()
  if observedSprite ~= nil and spriteListener ~= nil then
    local sprite = observedSprite
    local listener = spriteListener
    pcall(function()
      if sprite.events ~= nil then
        sprite.events:off(listener)
      end
    end)
  end
  observedSprite = nil
  spriteListener = nil
end

local function scheduleRefresh()
  if not dialogSessionActive or rebuildingDialog or refreshTimer ~= nil then
    return
  end

  local timer
  timer = createTimer {
    interval = 0.05,
    ontick = function()
      if refreshTimer ~= timer then
        return
      end
      timer:stop()
      refreshTimer = nil
      refreshIfChanged()
    end,
  }
  refreshTimer = timer
  timer:start()
end

local function onSpriteChange()
  scheduleRefresh()
end

local function observeSprite(sprite)
  if observedSprite == sprite then
    return
  end

  detachSpriteListener()
  observedSprite = sprite
  if observedSprite == nil then
    return
  end

  local ok, listener = pcall(function()
    if observedSprite.events == nil then
      return nil
    end
    return observedSprite.events:on("change", onSpriteChange)
  end)
  if ok and listener ~= nil then
    spriteListener = listener
  end
end

local function onBeforeSiteChange()
  detachSpriteListener()
  scheduleRefresh()
end

local function onSiteChange()
  observeSprite(currentApp().sprite)
  scheduleRefresh()
end

local function detachAppListeners()
  for _, listener in ipairs(appListeners) do
    pcall(function()
      listener.events:off(listener.code)
    end)
  end
  appListeners = {}
  appEventSource = nil
end

local function attachAppListeners()
  local aseprite = currentApp()
  if appEventSource == aseprite and #appListeners > 0 then
    return
  end

  detachAppListeners()
  appEventSource = aseprite
  if aseprite.events == nil then
    return
  end

  for _, event in ipairs({
    { name = "beforesitechange", callback = onBeforeSiteChange },
    { name = "sitechange", callback = onSiteChange },
  }) do
    local ok, listener = pcall(function()
      return aseprite.events:on(event.name, event.callback)
    end)
    if ok and listener ~= nil then
      appListeners[#appListeners + 1] = {
        events = aseprite.events,
        code = listener,
      }
    end
  end
end

local function deactivateSession()
  dialogSessionActive = false
  stopRefreshTimer()
  detachSpriteListener()
  detachAppListeners()
  displayedSprite = nil
  displayedTagSnapshot = {}
  lastDialogBounds = nil
end

local function closeActiveDialog()
  local dialog = activeDialog
  activeDialog = nil
  if dialog == nil then
    return
  end

  suppressDialogClose = true
  pcall(function()
    dialog:close()
  end)
  suppressDialogClose = false
end

local function rebuildDialog(sprite, tags, snapshot)
  if rebuildingDialog then
    return false
  end

  rebuildingDialog = true
  local previousBounds = readDialogBounds(activeDialog) or lastDialogBounds
  if previousBounds ~= nil then
    lastDialogBounds = previousBounds
  end
  closeActiveDialog()
  displayedSprite = sprite
  displayedTagSnapshot = snapshot

  if sprite == nil or #tags == 0 then
    rebuildingDialog = false
    return false
  end

  local dialog
  dialog = createDialog {
    title = "Animation List",
    resizeable = true,
    onclose = function()
      if activeDialog == dialog then
        activeDialog = nil
      end
      if not suppressDialogClose then
        deactivateSession()
      end
    end,
  }
  if dialog == nil then
    displayedSprite = nil
    displayedTagSnapshot = {}
    rebuildingDialog = false
    return false
  end

  for index, tag in ipairs(tags) do
    if index > 1 then
      dialog:newrow()
    end
    dialog:button {
      id = "tag_" .. index,
      text = tag.name,
      hexpand = true,
      onclick = function()
        AnimationList.jumpToTag(sprite, tag)
      end,
    }
  end

  activeDialog = dialog
  showDialog(dialog, previousBounds)
  lastDialogBounds = readDialogBounds(dialog) or previousBounds
  rebuildingDialog = false
  return true
end

local function updateButtonNames(snapshot)
  if activeDialog == nil or type(activeDialog.modify) ~= "function" then
    return false
  end

  local previousBounds = readDialogBounds(activeDialog)
  for index, entry in ipairs(snapshot) do
    if displayedTagSnapshot[index].name ~= entry.name then
      local ok = pcall(function()
        activeDialog:modify {
          id = "tag_" .. index,
          text = entry.name,
        }
      end)
      if not ok then
        return false
      end
    end
  end

  displayedTagSnapshot = snapshot
  if previousBounds ~= nil then
    pcall(function()
      activeDialog.bounds = rectangle(previousBounds)
    end)
    lastDialogBounds = readDialogBounds(activeDialog) or previousBounds
  end
  return true
end

refreshIfChanged = function()
  if not dialogSessionActive or rebuildingDialog then
    return false
  end

  local aseprite = currentApp()
  local sprite = aseprite.sprite
  observeSprite(sprite)
  local tags = AnimationList.collectTags(sprite)
  local snapshot = snapshotTags(tags)
  if sprite == displayedSprite and snapshotsEqual(snapshot, displayedTagSnapshot) then
    return false
  end

  if sprite == displayedSprite and sameTagStructure(snapshot, displayedTagSnapshot) then
    if updateButtonNames(snapshot) then
      return true
    end
  end

  return rebuildDialog(sprite, tags, snapshot)
end

function AnimationList.jumpToTag(sprite, tag)
  local aseprite = currentApp()
  if aseprite.sprite ~= sprite then
    aseprite.alert {
      title = "Animation List",
      text = "The active sprite changed. Reopen the Animation List and try again.",
    }
    return false
  end

  local ok, target = pcall(function()
    if tag.sprite ~= nil and tag.sprite ~= sprite then
      return nil
    end
    return tag.fromFrame
  end)

  if not ok or target == nil then
    aseprite.alert {
      title = "Animation List",
      text = "That tag no longer exists. Reopen the Animation List and try again.",
    }
    return false
  end

  if aseprite.range ~= nil and aseprite.range.clear ~= nil then
    aseprite.range:clear()
  end
  aseprite.frame = target
  aseprite.refresh()
  return true
end

function AnimationList.close()
  deactivateSession()
  closeActiveDialog()
end

function AnimationList.open()
  local aseprite = currentApp()
  if not aseprite.isUIAvailable then
    return false
  end

  local sprite = aseprite.sprite
  if sprite == nil then
    aseprite.alert {
      title = "Animation List",
      text = "Open a sprite before opening the Animation List.",
    }
    return false
  end

  local tags = AnimationList.collectTags(sprite)
  if not dialogSessionActive then
    lastDialogBounds = nil
  end
  dialogSessionActive = true
  stopRefreshTimer()
  attachAppListeners()
  observeSprite(sprite)
  return rebuildDialog(sprite, tags, snapshotTags(tags))
end

function AnimationList._setHostForTests(host)
  AnimationList.close()
  testHost = host
end

function init(plugin)
  plugin:newCommand {
    id = "OpenAnimationList",
    title = "Animation List...",
    group = "file_scripts",
    onclick = function()
      AnimationList.open()
    end,
    onenabled = function()
      local aseprite = currentApp()
      return aseprite.isUIAvailable and aseprite.sprite ~= nil
    end,
  }
end

function exit(_plugin)
  AnimationList.close()
end

return AnimationList
