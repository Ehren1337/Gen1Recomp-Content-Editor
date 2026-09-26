-- Native map headers govern field moves independently of map dimensions/art.
local M = {}
M.ids = {"1", "2", "3", "4", "5", "6", "8", "9", "0", "7"}
M.labels = { ["0"]="None", ["1"]="Town", ["2"]="City", ["3"]="Route",
  ["4"]="Cave / underground", ["5"]="Underwater", ["6"]="Ocean route",
  ["7"]="Unknown", ["8"]="Indoor", ["9"]="Secret base" }
local kinds = {[0]="indoor", "town", "city", "route", "cave", "underwater",
  "route", "indoor", "indoor", "indoor"}

-- Older map caches/project copies omit header fields. Resolve missing values
-- from the extracted ROM header without changing the project while viewing.
function M.resolve(S, map)
  local data = S.data or {}
  local id = map.id or S.mapId
  local native = (data.maps or {})[id] or {}
  local header = {}
  if id and data._gen3Read then
    data._g3MapHeaders = data._g3MapHeaders or {}
    header = data._g3MapHeaders[id]
    if not header then
      header = {}
      local ok, catalog = pcall(require,"src.import.gba.map_catalog")
      local slot = ok and catalog.slotKeyFor and catalog.slotKeyFor(id)
      if slot then
        local raw = data._gen3Read("data/generated/gba/map_tree/maps/"..slot.."/header.json")
        if raw then
          local decoded, value = pcall(require("src.link.Json").decode,raw)
          if decoded and type(value)=="table" then header=value end
        end
      end
      data._g3MapHeaders[id] = header
    end
  end
  local result = {}
  for _,key in ipairs({"mapType","cave","allowEscaping"}) do
    result[key] = map[key]
    if result[key]==nil then result[key]=native[key] end
    if result[key]==nil then result[key]=header[key] end
  end
  return result
end

function M.apply(map, value)
  local n = tonumber(value)
  if not n or not M.labels[tostring(n)] then return false end
  map.mapType = n
  map.kind = kinds[n]
  map.outdoor = n == 1 or n == 2 or n == 3 or n == 6
  map.environment = map.outdoor and (n == 1 or n == 2) and "TOWN"
    or map.outdoor and "ROUTE" or n == 4 and "CAVE" or "INDOOR"
  map.cave = n == 4 and 1 or 0
  map.allowEscaping = n == 4 and 1 or 0
  return true
end

function M.picker(S, map, x, y, w, onPick)
  map = M.resolve(S,map)
  require("ChoicePicker").field(S, {x=x,y=y,w=w,h=27*require("Kit").scale,
    ids=M.ids,labels=M.labels,current=map.mapType ~= nil and tostring(map.mapType) or "",
    emptyLabel="Choose map type",title="MAP TYPE",onPick=onPick,
    tooltip="Gameplay type, independent of size and tiles. Cave enables Dig / Escape Rope; outdoor types allow Fly."})
end

function M.draw(S, map, x, y, w, App)
  local Kit = require("Kit")
  local s = Kit.scale
  Kit.caption(x,y,"Map type")
  local function edit(change)
    local source, err = require("Gen3Workspace").convert(S,S.mapId)
    if not source then S.status=tostring(err);return end
    change(S.project.maps[S.mapId]);App.markDirty()
  end
  M.picker(S,map,x,y+21*s,w,function(id)
    edit(function(target) M.apply(target,id) end)
  end)
  local allowed = (tonumber(M.resolve(S,map).allowEscaping) or 0) ~= 0
  if Kit.button(x,y+54*s,w,27*s,"Dig / Escape Rope: "..(allowed and "Allowed" or "Blocked"),{
      kind=allowed and "good" or "ghost",
      tooltip="Escape permission. Dig also requires a cave type. Enter through a warp from outdoors to establish an escape destination."}) then
    edit(function(target) target.allowEscaping=allowed and 0 or 1 end)
  end
  return y+91*s
end
return M
