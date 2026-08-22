local total = 0
local passed = 0

local function expect(condition, message)
  if not condition then
    error(message or "expectation failed", 2)
  end
end

local function equal(actual, expected, message)
  if actual ~= expected then
    error(
      string.format(
        "%s: expected %s, got %s",
        message or "values differ",
        tostring(expected),
        tostring(actual)
      ),
      2
    )
  end
end

local function test(name, body)
  total = total + 1
  local ok, failure = pcall(body)
  if not ok then
    error(string.format("FAILED: %s\n%s", name, failure), 0)
  end
  passed = passed + 1
  print("PASS: " .. name)
end

local AnimationList = dofile("main.lua")

local function fakeFrame(number)
  return { frameNumber = number }
end

local function fakeTag(name, first, last, sprite)
  return {
    name = name,
    fromFrame = fakeFrame(first),
    toFrame = fakeFrame(last),
    sprite = sprite,
  }
end

local function newHost(sprite)
  local host = {
    dialogs = {},
  }
  local fakeApp = {
    isUIAvailable = true,
    sprite = sprite,
    alertCalls = {},
    refreshCalls = 0,
    range = {
      clearCalls = 0,
    },
  }
  function fakeApp.alert(options)
    fakeApp.alertCalls[#fakeApp.alertCalls + 1] = options
  end
  function fakeApp.refresh()
    fakeApp.refreshCalls = fakeApp.refreshCalls + 1
  end
  function fakeApp.range:clear()
    self.clearCalls = self.clearCalls + 1
  end
  host.app = fakeApp

  function host.createDialog(options)
    local dialog = {
      options = options,
      widgets = {},
      closed = false,
      bounds = { x = 10, y = 20, width = 200, height = 300 },
    }
    local function addWidget(kind, definition)
      definition.kind = kind
      dialog.widgets[#dialog.widgets + 1] = definition
      return dialog
    end
    function dialog:label(definition)
      return addWidget("label", definition)
    end
    function dialog:button(definition)
      return addWidget("button", definition)
    end
    function dialog:separator()
      return addWidget("separator", {})
    end
    function dialog:newrow(definition)
      return addWidget("newrow", definition or {})
    end
    function dialog:show(showOptions)
      self.showOptions = showOptions
      return self
    end
    function dialog:close()
      self.closed = true
      if self.options.onclose ~= nil then
        self.options.onclose()
      end
    end
    host.dialogs[#host.dialogs + 1] = dialog
    return dialog
  end

  return host
end

local function widgetById(dialog, id)
  for _, widget in ipairs(dialog.widgets) do
    if widget.id == id then
      return widget
    end
  end
  return nil
end

test("filters Soupmasters metadata tag prefixes", function()
  expect(AnimationList.isAnimationName("Idle"))
  expect(AnimationList.isAnimationName("@command"))
  expect(not AnimationList.isAnimationName("-disabled"))
  expect(not AnimationList.isAnimationName("*event"))
  expect(not AnimationList.isAnimationName("//comment"))
  expect(not AnimationList.isAnimationName("'keyframe"))
  expect(not AnimationList.isAnimationName(""))
end)

test("collects animation tags in sprite order", function()
  local sprite = { tags = {} }
  sprite.tags = {
    fakeTag("Idle", 1, 4, sprite),
    fakeTag("*hit", 2, 2, sprite),
    fakeTag("Run", 5, 10, sprite),
  }
  local tags = AnimationList.collectTags(sprite)
  equal(#tags, 2, "visible tag count")
  equal(tags[1].name, "Idle", "first visible tag")
  equal(tags[2].name, "Run", "second visible tag")
end)

test("registers a callable and state-aware plugin command", function()
  local registered
  local plugin = {}
  function plugin:newCommand(command)
    registered = command
  end

  local host = newHost({})
  AnimationList._setHostForTests(host)
  init(plugin)
  equal(registered.id, "OpenAnimationList", "command id")
  equal(type(registered.onclick), "function", "onclick type")
  expect(registered.onenabled(), "command should be enabled")
  host.app.sprite = nil
  expect(not registered.onenabled(), "command should be disabled without a sprite")
end)

test("opens one button per animation tag and jumps safely", function()
  local sprite = { tags = {} }
  sprite.tags = {
    fakeTag("Idle", 1, 4, sprite),
    fakeTag("//timing note", 2, 2, sprite),
    fakeTag("Run", 5, 10, sprite),
  }
  local host = newHost(sprite)
  AnimationList._setHostForTests(host)

  expect(AnimationList.open(), "dialog should open")
  equal(#host.dialogs, 1, "dialog count")
  local dialog = host.dialogs[1]
  equal(widgetById(dialog, "tag_1").text, "Idle  (1-4)", "first button text")
  equal(widgetById(dialog, "tag_2").text, "Run  (5-10)", "second button text")
  expect(widgetById(dialog, "tag_3") == nil, "metadata tag should not have a button")

  widgetById(dialog, "tag_2").onclick()
  equal(host.app.frame.frameNumber, 5, "selected frame")
  equal(host.app.range.clearCalls, 1, "range clear count")
  equal(host.app.refreshCalls, 1, "refresh count")
end)

test("rejects stale buttons after the active sprite changes", function()
  local sprite = { tags = {} }
  local tag = fakeTag("Idle", 1, 4, sprite)
  sprite.tags = { tag }
  local host = newHost(sprite)
  AnimationList._setHostForTests(host)
  host.app.sprite = { tags = {} }

  expect(not AnimationList.jumpToTag(sprite, tag), "jump should be rejected")
  equal(#host.app.alertCalls, 1, "alert count")
  expect(host.app.frame == nil, "frame should remain unchanged")
end)

test("refresh replaces the existing modeless dialog", function()
  local sprite = { tags = {} }
  sprite.tags = { fakeTag("Idle", 1, 4, sprite) }
  local host = newHost(sprite)
  AnimationList._setHostForTests(host)

  AnimationList.open()
  local first = host.dialogs[1]
  widgetById(first, "refresh").onclick()

  equal(#host.dialogs, 2, "dialog count after refresh")
  expect(first.closed, "first dialog should close")
  expect(host.dialogs[2].showOptions.bounds == nil, "refresh should not reuse dialog bounds")
end)

test("handles missing sprites and extension shutdown", function()
  local host = newHost(nil)
  AnimationList._setHostForTests(host)
  expect(not AnimationList.open(), "dialog should not open")
  equal(#host.app.alertCalls, 1, "missing-sprite alert count")

  local sprite = { tags = {} }
  host.app.sprite = sprite
  AnimationList.open()
  local dialog = host.dialogs[1]
  exit(nil)
  expect(dialog.closed, "dialog should close on exit")
end)

AnimationList._setHostForTests(nil)
print(string.format("%d/%d tests passed", passed, total))
