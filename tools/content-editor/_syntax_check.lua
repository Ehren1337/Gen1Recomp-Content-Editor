local ok, err = pcall(function()
  package.path = "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;" .. package.path
  -- stub love for Preview
  love = love or {}
  love.filesystem = love.filesystem or {
    getInfo = function() return nil end,
    getSource = function() return "." end,
    newFileData = function() error("no") end,
  }
  love.graphics = love.graphics or {
    newImage = function() end,
    setColor = function() end,
    rectangle = function() end,
    draw = function() end,
  }
  local Preview = require("Preview")
  local Trainers = require("Trainers")
  local Pokemon = require("Pokemon")
  local Manifest = require("Manifest")
  local Code = require("Code")
  local MoveEffects = require("MoveEffects")
  local Audio = require("Audio")
  local Gfx = require("Gfx")
  local AiClasses = require("AiClasses")
  local Project = require("Project")
  local ModWriter = require("ModWriter")
  assert(Preview.draw)
  assert(Trainers.draw)
  assert(Pokemon.draw)
  assert(Manifest.draw)
  assert(Code.draw)
  assert(MoveEffects.draw)
  assert(Audio.draw)
  assert(Gfx.draw)
  assert(AiClasses.draw)
  assert(Project.draw)
  assert(ModWriter.emitMain)
  local sample = ModWriter.emitMain({
    id = "t", palettes = { P = { colors = { {1,2,3},{4,5,6},{7,8,9},{0,0,0} }, _isNew = true } },
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
  assert(sample:find("mod.content.palettes:register"), sample)
  assert(sample:find("mod.content.music:"), sample)
  assert(sample:find("mod.content.ai_classes:"), sample)
  assert(sample:find('field:patch%("boot"'), sample)
  assert(sample:find("move_effects:register"), sample)
  print("OK modules load")
end)
if not ok then print("FAIL", err); os.exit(1) end
