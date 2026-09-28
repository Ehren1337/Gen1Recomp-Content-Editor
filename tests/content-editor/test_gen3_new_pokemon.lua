-- New Pokemon evolve from the start (Gen3NewPokemon.lua): what main.lua is
-- given. Plain LuaJIT, no LOVE. Run from the repository root:
--   luajit tests/content-editor/test_gen3_new_pokemon.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local N = require("Gen3NewPokemon")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

local function project()
  return { gen3 = { pokemon = {
    BLASTYKE = { index = 440, evolutions = {
      { method = "EVO_LEVEL", level = 5, species = "TOTARTLE" },
      { method = "EVO_ITEM", item = "WATER_STONE", species = "BLASTOISE" },
      { method = "EVO_ITEM", item = "FIRE_STONE", species = "TOTARTLE" } } },
    TOTARTLE = { index = 441, evolutions = {} },
    SQUIRTLE = { index = 7, evolutions = { { method = "EVO_LEVEL", level = 16, species = "BLASTYKE" } } },
  } }, gen3Modes = { pokemon = { BLASTYKE = "register", TOTARTLE = "register", SQUIRTLE = "patch" } } }
end

run("no new species, nothing to add", function()
  assert(N.compile({ gen3 = { pokemon = { SQUIRTLE = { index = 7 } } }, gen3Modes = { pokemon = { SQUIRTLE = "patch" } } }) == nil)
  local out = {}
  N.emit({}, tostring, out)
  assert(#out == 0)
end)

run("new species and the evolutions into them", function()
  local d = N.compile(project())
  assert(d.new[440] and d.new[441] and not d.new[7])
  assert(d.fixes.BLASTYKE[1] == 441 and d.fixes.BLASTYKE[2] == nil and d.fixes.BLASTYKE[3] == 441)
  assert(d.fixes.SQUIRTLE[1] == 440, "the game's own species evolving into a new one")
  assert(d.indices.BLASTYKE == 440 and d.indices.SQUIRTLE == nil, "the game's own species are looked up in game")
end)

run("main.lua code loads", function()
  local out = {}
  N.emit(project(), function(v)
    local function enc(x)
      if type(x) == "table" then
        local parts = {}
        for k, y in pairs(x) do parts[#parts + 1] = "[" .. enc(k) .. "]=" .. enc(y) end
        return "{" .. table.concat(parts, ",") .. "}"
      end
      return type(x) == "string" and ("%q"):format(x) or tostring(x)
    end
    return enc(v)
  end, out)
  assert(#out == 1 and out[1]:find("nationalAllows", 1, true))
  assert(loadstring("local mod; return function() " .. out[1] .. " end"))
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
