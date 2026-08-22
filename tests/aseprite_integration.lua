local AnimationList = dofile("main.lua")

local sprite = Sprite(8, 8)
for frameNumber = 2, 8 do
  sprite:newEmptyFrame(frameNumber)
end

local idle = sprite:newTag(1, 4)
idle.name = "Idle"
local event = sprite:newTag(5, 5)
event.name = "*hit"
local run = sprite:newTag(6, 8)
run.name = "Run"

local tags = AnimationList.collectTags(sprite)
assert(#tags == 2, "expected two visible animation tags")
assert(tags[1].name == "Idle", "expected Idle first")
assert(tags[2].name == "Run", "expected Run second")

AnimationList._setHostForTests {
  app = app,
  createDialog = function()
    error("dialog should not be created")
  end,
}
assert(AnimationList.jumpToTag(sprite, run), "expected jump to succeed")
assert(app.frame.frameNumber == 6, "expected frame 6")

sprite:deleteTag(run)
assert(not AnimationList.jumpToTag(sprite, run), "expected deleted tag to be rejected")

AnimationList._setHostForTests(nil)
print("Aseprite userdata integration passed")
