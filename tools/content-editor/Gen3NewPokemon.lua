-- New Pokemon (FireRed / LeafGreen): evolutions into the mod's own species.
--
-- The editor numbers new species from 440 up (after the game's own list).
-- Two things stop evolutions into them in the game, fixed from main.lua (the
-- engine isn't changed):
--  * FireRed only lets a Pokemon evolve into a species above #151 once the
--    National Pokedex is on (pokefirered party_menu.c / evolution_scene.c).
--    The mod's new species skip that rule; the game's own keep it.
--  * The game fills in each species' evolutions one species at a time, so an
--    evolution into a new species that isn't filled in yet ends up with no
--    target (nothing happens). The right species numbers are put back.

local M = {}

--- What the game needs, or nil when the mod adds no species:
-- new = { [index] = true }, fixes = { [species id] = { [row] = target index } }.
function M.compile(project)
  local records = ((project.gen3 or {}).pokemon) or {}
  local modes = ((project.gen3Modes or {}).pokemon) or {}
  local new, byId = {}, {}
  for id, rec in pairs(records) do
    if modes[id] == "register" and type(rec) == "table" and tonumber(rec.index) then
      new[tonumber(rec.index)] = true
      byId[id] = tonumber(rec.index)
    end
  end
  if not next(new) then return nil end
  local fixes, indices = {}, {}
  for id, rec in pairs(records) do
    for i, row in ipairs(type(rec) == "table" and rec.evolutions or {}) do
      local target = type(row) == "table" and byId[row.species]
      if target then
        fixes[id] = fixes[id] or {}
        fixes[id][i] = target
      end
    end
    if fixes[id] and byId[id] then indices[id] = byId[id] end
  end
  return { new = new, fixes = fixes, indices = indices }
end

function M.emit(project, encode, out)
  local data = M.compile(project)
  if not data then return end
  out[#out + 1] = "  local newPokemon=" .. encode(data) .. "\n" .. [=[
  -- New Pokemon evolve without the National Pokedex, and evolutions into
  -- them keep their target (Gen3NewPokemon.lua).
  mod.events:on("game.ready",function()
    local okE,Evolution=pcall(require,"src.core.game3.evolution")
    if okE and type(Evolution)=="table" and type(Evolution.nationalAllows)=="function" and not Evolution._newPokemonPatched then
      local allows=Evolution.nationalAllows
      Evolution.nationalAllows=function(target,session)
        if newPokemon.new[tonumber(target) or -1] then return true end
        return allows(target,session)
      end
      Evolution._newPokemonPatched=true
    end
    local okP,Pokemon=pcall(require,"src.core.game3.pokemon")
    if not okP or type(Pokemon)~="table" or type(Pokemon.evolutions)~="function" then return end
    local byNum
    local function fixesFor(num)
      if not byNum then
        byNum={}
        for id,rows in pairs(newPokemon.fixes) do
          local n=newPokemon.indices[id] or (Pokemon.speciesFromName and Pokemon.speciesFromName(id))
          if tonumber(n) then byNum[tonumber(n)]=rows end
        end
      end
      return byNum[num]
    end
    local function mend(num,rows)
      local fix=type(rows)=="table" and fixesFor(num)
      if not fix then return end
      for i,target in pairs(fix) do
        local row=rows[i]
        if type(row)=="table" and (tonumber(row.target or row[3]) or 0)~=target then
          if row.target~=nil or row[3]==nil then row.target=target else row[3]=target end
        end
      end
    end
    if not Pokemon._newPokemonPatched then
      local evolutions=Pokemon.evolutions
      Pokemon.evolutions=function(species)
        local rows=evolutions(species)
        local num=species
        if type(num)=="table" then num=Pokemon.speciesOf(num) end
        if type(num)=="string" then num=(Pokemon.speciesFromName and Pokemon.speciesFromName(num)) or tonumber(num) end
        if tonumber(num) then mend(tonumber(num),rows) end
        return rows
      end
      Pokemon._newPokemonPatched=true
    end
    -- breeding reads the table directly
    for id in pairs(newPokemon.fixes) do
      local n=newPokemon.indices[id] or (Pokemon.speciesFromName and Pokemon.speciesFromName(id))
      if tonumber(n) then pcall(Pokemon.evolutions,tonumber(n)) end
    end
  end)
]=]
end

return M
