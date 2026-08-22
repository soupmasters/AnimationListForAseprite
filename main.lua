local AnimationList = {}

local hiddenPrefixes = {
  "-",
  "*",
  "//",
  "'",
}

local activeDialog = nil
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

local function frameNumber(frame)
  if type(frame) == "number" then
    return frame
  end
  if frame ~= nil then
    return frame.frameNumber
  end
  return nil
end

local function tagButtonText(tag)
  local first = frameNumber(tag.fromFrame)
  local last = frameNumber(tag.toFrame)
  if first ~= nil and last ~= nil then
    return string.format("%s  (%d-%d)", tag.name, first, last)
  end
  return tag.name
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

function AnimationList.jumpToTag(sprite, tag)
  local aseprite = currentApp()
  if aseprite.sprite ~= sprite then
    aseprite.alert {
      title = "Animation List",
      text = "The active sprite changed. Refresh the Animation List and try again.",
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
      text = "That tag no longer exists. Refresh the Animation List and try again.",
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
  local dialog = activeDialog
  activeDialog = nil
  if dialog ~= nil then
    pcall(function()
      dialog:close()
    end)
  end
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

  AnimationList.close()

  local dialog
  dialog = createDialog {
    title = "Animation List",
    resizeable = true,
    onclose = function()
      if activeDialog == dialog then
        activeDialog = nil
      end
    end,
  }
  if dialog == nil then
    return false
  end

  local tags = AnimationList.collectTags(sprite)
  if #tags == 0 then
    dialog:label {
      id = "empty",
      text = "No animation tags found.",
    }
    dialog:newrow()
  else
    for index, tag in ipairs(tags) do
      dialog:button {
        id = "tag_" .. index,
        text = tagButtonText(tag),
        hexpand = true,
        onclick = function()
          AnimationList.jumpToTag(sprite, tag)
        end,
      }
      dialog:newrow()
    end
  end

  dialog:separator()
  dialog:button {
    id = "refresh",
    text = "Refresh",
    onclick = function()
      AnimationList.open()
    end,
  }
  dialog:button {
    id = "close",
    text = "Close",
  }

  activeDialog = dialog
  local showOptions = {
    wait = false,
    autoscrollbars = true,
  }
  dialog:show(showOptions)
  return true
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
