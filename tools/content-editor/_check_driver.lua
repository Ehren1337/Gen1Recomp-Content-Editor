-- Headless driver: require content-editor modules and exercise ModWriter.
package.path = "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;"
  .. "tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
  .. package.path

local function fail(msg)
  print("FAIL " .. tostring(msg))
  love.event.quit(1)
end

local ok, err = pcall(function()
  local Preview = require("Preview")
  local Audio = require("Audio")
  local Gfx = require("Gfx")
  local AiClasses = require("AiClasses")
  local Project = require("Project")
  local Code = require("Code")
  local MoveEffects = require("MoveEffects")
  local ModWriter = require("ModWriter")
  assert(Preview.draw and Audio.draw and Gfx.draw and AiClasses.draw)
  assert(Project.draw and Code.draw and MoveEffects.draw and ModWriter.emitMain)
  local sample = ModWriter.emitMain({
    id = "t",
    palettes = {
      P = {
        colors = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 0, 0, 0 } },
        _isNew = true,
      },
    },
    audio = { songs = { Music_X = { file = "assets/x.ogg" } } },
    aiClasses = { OPP_X = { kind = "class", uses = 1, _isNew = true } },
    boot = { startMap = "PALLET_TOWN" },
    constants = { levelCap = 80 },
    hiddenItems = { PALLET_TOWN = { { x = 1, y = 2, item = "POTION" } } },
    badgeGates = {},
    moveEffects = {
      FX_RECOIL = { id = "FX_RECOIL", template = "recoil", recoilDiv = 4 },
    },
  })
  assert(sample:find("mod.content.palettes:register", 1, true), sample:sub(1, 400))
  assert(sample:find("mod.content.music:", 1, true), sample)
  assert(sample:find("mod.content.ai_classes:", 1, true), sample)
  assert(sample:find('field:patch("boot"', 1, true), sample)
  assert(sample:find("move_effects:register", 1, true), sample)
  print("OK content-editor modules + ModWriter emit")
end)

if not ok then
  fail(err)
else
  love.event.quit(0)
end
