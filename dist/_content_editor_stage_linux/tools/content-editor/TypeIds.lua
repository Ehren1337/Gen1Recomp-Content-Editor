-- Resolve the live list of type ids (vanilla TypeChart + project types).

local TypeIds = {}

local FALLBACK = {
  "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON",
}

function TypeIds.list(S)
  local seen, ids = {}, {}
  local function add(id)
    if id and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and TypeChart.TYPES then
    for id in pairs(TypeChart.TYPES) do add(id) end
  end
  if S and S.data and S.data.type_chart then
    local tc = S.data.type_chart
    if tc.types then
      for id in pairs(tc.types) do add(id) end
    end
    for _, name in ipairs(tc.names or {}) do
      -- generated names use PSYCHIC; live ids use PSYCHIC_TYPE
      if name == "PSYCHIC" then add("PSYCHIC_TYPE") else add(name) end
    end
  end
  if S and S.project and S.project.types then
    for id in pairs(S.project.types) do add(id) end
  end
  if #ids == 0 then
    for _, id in ipairs(FALLBACK) do add(id) end
  end
  table.sort(ids)
  return ids
end

function TypeIds.cycle(S, cur, allowNone)
  local list = TypeIds.list(S)
  if allowNone then
    -- append sentinel after last
    local idx = 0
    for i, t in ipairs(list) do
      if t == cur then idx = i; break end
    end
    if cur == nil or cur == "" then return list[1] end
    if idx == 0 then return list[1] end
    if idx >= #list then return nil end
    return list[idx + 1]
  end
  local idx = 0
  for i, t in ipairs(list) do
    if t == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

return TypeIds
