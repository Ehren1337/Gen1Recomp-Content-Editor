-- Outside the map (FireRed / LeafGreen): what shows past a map's edge where
-- no connected map is.
--  * Game border: the game's repeating border pattern (Border > Pattern).
--  * Extrude: the map's last 2 rows / columns carried on outward, so 2x2
--    things like trees stay whole.
-- Any cell in a map's margin can also be painted by hand, from any tileset;
-- painted cells win over the fill. They are only for looks: nobody can walk
-- outside a map. The mod default covers outdoor maps (Town, City, Route,
-- Ocean route); any map can choose its own.
-- Map aware: a cell outside every map belongs to the NEAREST map (this one or
-- a connected one), which decides its fill and holds its painted tile, so the
-- space around connected maps joins up the same from either side.
-- In the game this is drawn from main.lua by wrapping Map.worldMidAt, which
-- the field view asks for every cell (the engine isn't changed).
--
-- project.gen3VoidDefault = "border" | "extrude"
-- project.gen3VoidMaps[id] = { fill = nil | "border" | "extrude",
--   margin = 0-64 (16 when unset), pair = paint tileset, cells = { [key] = { m = mid, p = pair } } }

local M = {}

M.FILLS = { "border", "extrude" }
M.LABELS = { border = "Game border", extrude = "Extrude" }
M.OFF, M.ROW = 128, 1024
M.MAX_MARGIN, M.DEFAULT_MARGIN = 64, 16
M.OUTDOOR = { [1] = true, [2] = true, [3] = true, [6] = true }

function M.key(x, y) return (y + M.OFF) * M.ROW + x + M.OFF end
function M.unkey(k) return k % M.ROW - M.OFF, math.floor(k / M.ROW) - M.OFF end

local function valid(fill) return fill == "border" or fill == "extrude" end

--- The mod default ("border" unless set).
function M.default(project)
  return (project or {}).gen3VoidDefault == "extrude" and "extrude" or "border"
end

function M.setDefault(project, fill)
  assert(valid(fill), "Choose Game border or Extrude")
  if M.default(project) == fill then return false end
  project.gen3VoidDefault = fill ~= "border" and fill or nil
  return true
end

function M.record(project, id)
  return ((project or {}).gen3VoidMaps or {})[id]
end

local function ensure(project, id)
  project.gen3VoidMaps = project.gen3VoidMaps or {}
  local rec = project.gen3VoidMaps[id]
  if not rec then rec = {}; project.gen3VoidMaps[id] = rec end
  return rec
end

local function tidy(project, id)
  local rec = M.record(project, id)
  if not rec then return end
  if rec.cells and not next(rec.cells) then rec.cells = nil end
  if rec.fill == nil and rec.cells == nil and rec.margin == nil and rec.pair == nil then
    project.gen3VoidMaps[id] = nil
    if not next(project.gen3VoidMaps) then project.gen3VoidMaps = nil end
  end
end

--- The map's own choice, or nil when it follows the mod default.
function M.mapFill(project, id)
  local rec = M.record(project, id)
  return rec and valid(rec.fill) and rec.fill or nil
end

function M.setMapFill(project, id, fill)
  assert(fill == nil or valid(fill), "Choose Mod default, Game border or Extrude")
  if M.mapFill(project, id) == fill then return false end
  ensure(project, id).fill = fill
  tidy(project, id)
  return true
end

--- What the game shows past this map's edge. outdoor: is it an outdoor map.
function M.fillFor(project, id, outdoor)
  return M.mapFill(project, id) or (outdoor and M.default(project)) or "border"
end

function M.margin(project, id)
  local rec = M.record(project, id)
  return rec and tonumber(rec.margin) or M.DEFAULT_MARGIN
end

--- Change how far out tiles can be painted. Painted tiles past a smaller
-- margin are removed; returns changed, removed count (or false, message).
function M.setMargin(project, id, width, height, n)
  n = tonumber(n)
  if not n or n % 1 ~= 0 or n < 0 or n > M.MAX_MARGIN then
    return false, "Margin must be a whole number from 0 to " .. M.MAX_MARGIN
  end
  if M.margin(project, id) == n then return false end
  local rec = ensure(project, id)
  rec.margin = n ~= M.DEFAULT_MARGIN and n or nil
  local removed = 0
  for k in pairs(rec.cells or {}) do
    local x, y = M.unkey(k)
    if x < -n or y < -n or x >= width + n or y >= height + n then
      rec.cells[k] = nil; removed = removed + 1
    end
  end
  tidy(project, id)
  return true, removed
end

--- The tileset hand-painted tiles come from (the map's own unless changed).
function M.paintPair(project, id, fallback)
  local rec = M.record(project, id)
  return rec and rec.pair or fallback
end

function M.setPaintPair(project, id, pair, fallback)
  assert(type(pair) == "string" and pair ~= "", "Choose a tileset")
  if M.paintPair(project, id, fallback) == pair then return false end
  ensure(project, id).pair = pair ~= fallback and pair or nil
  tidy(project, id)
  return true
end

--- A painted cell { m = mid, p = pair }, or nil.
function M.cell(project, id, x, y)
  local rec = M.record(project, id)
  return rec and rec.cells and rec.cells[M.key(x, y)] or nil
end

--- Paint (mid, pair) outside the map, or clear the cell when mid is nil.
function M.paint(project, id, width, height, x, y, mid, pair)
  if x >= 0 and y >= 0 and x < width and y < height then return false, "inside" end
  local n = M.margin(project, id)
  if x < -n or y < -n or x >= width + n or y >= height + n then return false, "margin" end
  local current = M.cell(project, id, x, y)
  if mid == nil then
    if not current then return false end
    M.record(project, id).cells[M.key(x, y)] = nil
    tidy(project, id)
    return true
  end
  assert(type(mid) == "number" and mid % 1 == 0 and mid >= 0 and mid <= 1023, "Invalid metatile")
  assert(type(pair) == "string" and pair ~= "", "Choose a tileset")
  if current and current.m == mid and current.p == pair then return false end
  local rec = ensure(project, id)
  rec.cells = rec.cells or {}
  rec.cells[M.key(x, y)] = { m = mid, p = pair }
  return true
end

--- Clear every painted tile of a map.
function M.clear(project, id)
  local rec = M.record(project, id)
  if not (rec and rec.cells) then return false end
  rec.cells = nil
  tidy(project, id)
  return true
end

--- Extrude: coordinate c past an edge of length n, repeating the last 2.
function M.edge(c, n)
  if c >= 0 and c < n then return c end
  if n < 2 then return 0 end
  if c < 0 then return c % 2 end
  return n - 2 + (c - n + 2) % 2
end

--- The map a cell outside every map belongs to: the nearest (Chebyshev
-- distance to its rectangle, then the smaller dx + dy, then list order, so
-- the open map wins ties). rects: { {ox=,oy=,w=,h=}, ... } in one space.
function M.owner(rects, x, y)
  local best, bd, bs
  for i, r in ipairs(rects) do
    local dx = x < r.ox and r.ox - x or (x >= r.ox + r.w and x - (r.ox + r.w - 1) or 0)
    local dy = y < r.oy and r.oy - y or (y >= r.oy + r.h and y - (r.oy + r.h - 1) or 0)
    local d, sum = math.max(dx, dy), dx + dy
    if not best or d < bd or (d == bd and sum < bs) then best, bd, bs = i, d, sum end
  end
  return best
end

--- Editor preview of a cell outside the map: mid, pair, kind
-- ("painted" | "extrude" | "border"). opts: width, height, pair (the map's),
-- outdoor, cell(x, y) -> mid inside the map, border (a Gen3Map.borderLayout).
function M.preview(project, id, x, y, opts)
  local painted = M.cell(project, id, x, y)
  if painted then return painted.m, painted.p, "painted" end
  if M.fillFor(project, id, opts.outdoor) == "extrude" and opts.width > 0 and opts.height > 0 then
    return opts.cell(M.edge(x, opts.width), M.edge(y, opts.height)), opts.pair, "extrude"
  end
  local b = opts.border
  local bx, by = x % b.width, y % b.height
  return b:cellAt(bx, by).mid, b.pair, "border"
end

--- Does the mod change anything outside maps?
function M.used(project)
  if M.default(project) ~= "border" then return true end
  for _, rec in pairs((project or {}).gen3VoidMaps or {}) do
    if valid(rec.fill) or (rec.cells and next(rec.cells)) then return true end
  end
  return false
end

function M.validate(project)
  local d = (project or {}).gen3VoidDefault
  assert(d == nil or valid(d), "Outside the map: unknown mod default")
  for id, rec in pairs((project or {}).gen3VoidMaps or {}) do
    assert(type(id) == "string" and type(rec) == "table", "Outside the map: bad map entry")
    assert(rec.fill == nil or valid(rec.fill), "Outside the map: unknown fill for " .. id)
    local n = rec.margin
    assert(n == nil or (type(n) == "number" and n % 1 == 0 and n >= 0 and n <= M.MAX_MARGIN),
      "Outside the map: margin must be 0-" .. M.MAX_MARGIN .. " for " .. id)
    for k, c in pairs(rec.cells or {}) do
      assert(type(k) == "number" and k % 1 == 0 and k >= 0 and k < M.ROW * M.ROW,
        "Outside the map: bad painted cell in " .. id)
      assert(type(c) == "table" and type(c.m) == "number" and c.m % 1 == 0 and c.m >= 0 and c.m <= 1023
        and type(c.p) == "string" and c.p ~= "", "Outside the map: bad painted tile in " .. id)
    end
  end
end

--- What main.lua needs, or nil when nothing changes.
function M.compile(project)
  if not M.used(project) then return nil end
  local maps = {}
  for id, rec in pairs(project.gen3VoidMaps or {}) do
    local cells
    for k, c in pairs(rec.cells or {}) do
      cells = cells or {}
      cells[k] = { m = c.m, p = c.p }
    end
    if valid(rec.fill) or cells then maps[id] = { fill = rec.fill, cells = cells } end
  end
  return { default = M.default(project), maps = maps }
end

function M.emit(project, encode, out)
  M.validate(project)
  local data = M.compile(project)
  if not data then return end
  out[#out + 1] = "  local outsideMaps=" .. encode(data) .. "\n" .. [=[
  -- Outside the map: extrude / hand-painted tiles past a map's edge where no
  -- connected map is (Gen3Void.lua). The field view asks Map.worldMidAt for
  -- every cell; void cells come back with a third value, true.
  mod.events:on("game.ready",function()
    local okM,Map=pcall(require,"src.core.game3.map")
    if not okM or type(Map)~="table" or type(Map.worldMidAt)~="function" then return end
    local OUTDOOR={[1]=true,[2]=true,[3]=true,[6]=true}
    -- Wrap once; a reload swaps in this mod's current tiles.
    local base=Map.worldMidAt
    if base==Map._editorOutsideWrapper then base=Map._editorOutsideBase end
    local function edge(c,n)
      if c>=0 and c<n then return c end
      if n<2 then return 0 end
      if c<0 then return c%2 end
      return n-2+(c-n+2)%2
    end
    -- The open map, its connected maps and the loaded world, relative to it.
    local rects,rectsFor,nFor,wFor={},nil,nil,nil
    local function around(def)
      if rectsFor==def and nFor==Map.neighborList and wFor==Map.world then return rects end
      rects={};rectsFor,nFor,wFor=def,Map.neighborList,Map.world
      local seen={}
      local function add(d,ox,oy)
        local l=d and d.midLayout
        if not l or seen[d] then return end
        seen[d]=true
        local w,h=l.trueWidth or l.width or 0,l.trueHeight or l.height or 0
        if w>0 and h>0 then rects[#rects+1]={def=d,l=l,id=l.mapId or d.id,ox=ox,oy=oy,w=w,h=h} end
      end
      add(def,0,0)
      for _,n in ipairs(Map.neighborList or {}) do add(n.def,n.ox or 0,n.oy or 0) end
      for _,n in ipairs(Map.world or {}) do add(n.def,n.ox or 0,n.oy or 0) end
      return rects
    end
    local function fillOf(r)
      local rec=r.id and outsideMaps.maps[r.id]
      local fill=rec and rec.fill
      if fill then return fill end
      local d=r.def
      if outsideMaps.default~="border" and (OUTDOOR[tonumber(d.mapType)] or (d.mapType==nil and d.outdoor==true)) then
        return outsideMaps.default
      end
      return "border"
    end
    local function wrapper(x,y,def)
      local mid,pair,void=base(x,y,def)
      if not void then return mid,pair,void end
      local list=around(def)
      if #list==0 then return mid,pair,void end
      -- a painted tile of any of these maps
      for i=1,#list do
        local r=list[i]
        local rec=r.id and outsideMaps.maps[r.id]
        local cell=rec and rec.cells and rec.cells[(y-r.oy+128)*1024+x-r.ox+128]
        if cell then return cell.m,cell.p end
      end
      -- otherwise the nearest map's fill
      local best,bd,bs
      for i=1,#list do
        local r=list[i]
        local dx=x<r.ox and r.ox-x or (x>=r.ox+r.w and x-(r.ox+r.w-1) or 0)
        local dy=y<r.oy and r.oy-y or (y>=r.oy+r.h and y-(r.oy+r.h-1) or 0)
        local d,sum=math.max(dx,dy),dx+dy
        if not best or d<bd or (d==bd and sum<bs) then best,bd,bs=r,d,sum end
      end
      local lx,ly=x-best.ox,y-best.oy
      if fillOf(best)=="extrude" then
        return best.l:midAt(edge(lx,best.w),edge(ly,best.h)),best.l.pair or best.def.pair
      end
      if best.def==def then return mid,pair,void end
      -- that map's own border pattern (still void: the VOID FILL option applies)
      return best.l:midAt(lx,ly),best.l.pair or best.def.pair,true
    end
    Map.worldMidAt=wrapper;Map._editorOutsideWrapper=wrapper;Map._editorOutsideBase=base
    local okF,FieldView=pcall(require,"src.core.game3.field_view")
    if okF and type(FieldView)=="table" then FieldView._nativeDirty=true end
  end,-200)
]=]
end

return M
