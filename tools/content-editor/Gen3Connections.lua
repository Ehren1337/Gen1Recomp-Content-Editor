-- A direction accepts a legacy connection or an ordered list of connections.
local M={directions={"north","south","east","west"}}
M.opposite={north="south",south="north",east="west",west="east"}
M.alias={up="north",down="south",left="west",right="east"}
local cache=setmetatable({},{__mode="k"})
local empty={}
local function cached(connections)
  if not connections then connections=empty end
  local result=cache[connections]
  if result then return result end
  result={rows={}};cache[connections]=result
  for _,dir in ipairs(M.directions) do
    local value=connections[dir];local rows={}
    if value then
      if type(value)~="table" then rows[1]={map=value,offset=0}
      elseif value.map or value.mapId then rows[1]=value
      else rows=value end
    else
      for _,c in ipairs(connections) do
        if (M.alias[c.dir] or c.dir)==dir then rows[#rows+1]=c end
      end
    end
    result[dir]=rows
    for i,c in ipairs(rows) do
      local row={dir,c,i};result.rows[#result.rows+1]=row
    end
  end
  return result
end
-- Cached arrays can be traversed with ipairs, including nested/early-exit loops.
function M.list(connections,dir) return cached(connections)[dir] or empty end
function M.each(connections) return cached(connections).rows end
function M.invalidate(connections) if connections then cache[connections]=nil end end
function M.put(connections,dir,rows)
  M.invalidate(connections)
  connections[dir]=#rows==0 and nil or #rows==1 and rows[1] or rows
end
function M.copy(value)
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value) do out[k]=M.copy(v) end;return out
end
-- New ROM caches use ordered {dir,map,offset} records. Authoring and export
-- use direction buckets, including a list when a side has several exits.
function M.normalize(connections)
  local out={}
  for _,dir in ipairs(M.directions) do
    local rows=M.copy(M.list(connections,dir))
    for _,c in ipairs(rows) do c.dir=nil end
    if #rows>0 then M.put(out,dir,rows) end
  end
  return out
end
function M.validate(connections)
  for dir,value in pairs(connections or {}) do
    assert(M.opposite[dir],"Unknown connection direction: "..tostring(dir))
    assert(type(value)=="table","Connection must contain a destination and offset")
    for _,c in ipairs(M.list(connections,dir)) do
      assert(type(c)=="table" and type(c.map or c.mapId)=="string","Choose a connection destination")
      local n=c.offset or 0;assert(type(n)=="number" and n==n and n%1==0,"Connection offset must be a whole number")
    end
  end
end
-- Repair the verified stock cache overwrite, never authored replacements.
-- Source: pret/pokefirered data/maps/SixIsland_WaterPath/map.json.
function M.recover(maps,skip)
  local id="FR_SIX_ISLAND_WATER_PATH";local map=maps[id]
  if not map or (skip or {})[id] then return end
  local old=M.list(map.connections,"west")
  if #old~=1 or old[1].map~="FR_SIX_ISLAND_RUIN_VALLEY" or old[1].offset~=80 then return end
  local rows={{map="FR_SIX_ISLAND_GREEN_PATH",offset=0},{map="FR_SIX_ISLAND",offset=40},{map="FR_SIX_ISLAND_RUIN_VALLEY",offset=80}}
  for _,c in ipairs(rows) do
    local dest=maps[c.map];local found=false
    for _,back in ipairs(M.list(dest and dest.connections,"east")) do if back.map==id and back.offset==-c.offset then found=true end end
    if not found then return end
  end
  M.put(map.connections,"west",rows)
end
function M.landing(def,conn,dir,x,y)
  dir=M.alias[dir] or dir
  local l=def and def.midLayout or def or {};local w,h=l.width or 0,l.height or 0
  local off=conn.offset or 0
  if dir=="west" then x,y=w-1,y-off
  elseif dir=="east" then x,y=0,y-off
  elseif dir=="north" then x,y=x-off,h-1
  elseif dir=="south" then x,y=x-off,0 else return end
  if x>=0 and y>=0 and x<w and y<h then return x,y end
end
return M
