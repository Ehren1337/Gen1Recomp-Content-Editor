package.path = "tools/content-editor/?.lua;" .. package.path

local Adapter = require("WorldPaletteOverrides")

local vanilla = {}
for i = 1, 8 do vanilla[i] = { { i, 0, 0 }, { i, 1, 0 }, { i, 2, 0 }, { i, 3, 0 } } end
local PaletteFX = {
  worldGroupColors = function() return vanilla end,
  darkWorld = function() return false end,
}

local state = Adapter.install(PaletteFX)
assert(state == Adapter.install(PaletteFX), "adapter must install only once")
assert(PaletteFX.vanillaWorldGroupColors("OVERWORLD")[2][1][1] == 2)

local red = { { 255, 0, 0 }, { 200, 0, 0 }, { 100, 0, 0 }, { 0, 0, 0 } }
PaletteFX.setWorldGroupOverrides({ OVERWORLD = { [2] = red, [7] = red } })
local generic = PaletteFX.worldGroupColors({}, "OVERWORLD", nil, nil)
assert(generic[2] == red, "tileset override must replace its palette group")
local mapped = PaletteFX.worldGroupColors({}, "OVERWORLD", "PALLET_TOWN", nil)
assert(mapped[2] == red, "ordinary override must survive map resolution")
assert(mapped[7] == vanilla[7], "resolved town roof palette must win")

PaletteFX.setWorldGroupOverrides(nil)
assert(PaletteFX.worldGroupColors({}, "OVERWORLD", nil, nil) == vanilla)

print("ok world palette overrides")
