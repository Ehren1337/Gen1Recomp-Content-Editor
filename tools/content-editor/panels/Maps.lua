-- Maps tab: block paint (palette + drag), collision overlay, object sprites,
-- warps/signs/encounters, TMX import. Gen1: one tileset + one block layer per map
-- (Tiled tile = Gen1 block). No multi-tileset bake/absorb.

local Kit = require("Kit")
local Theme = require("Theme")
local ModIO = require("ModIO")
local Search = require("Search")
local State = require("State")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local ColorWheel = require("ColorWheel")
local SpeciesPicker = require("SpeciesPicker")
local FormPane = require("FormPane")
local SpriteUtil = require("SpriteUtil")
local EncounterEdit = require("EncounterEdit")
local RegList = require("RegList")
local Autocomplete = require("Autocomplete")
local MapLoader = require("src.world.MapLoader")
local Map = require("src.world.Map")
local SpriteRenderer = require("src.render.SpriteRenderer")
local PAL = Theme.PAL

local Maps = {}
local acS -- session for RegList.suggestField (set in Maps.draw)

local CELL = 16  -- walk cell; a block is 2x2 cells
local BLOCK_PX = 32  -- one Gen1 block = 4x4 of 8x8 tiles
local SECTIONS = {
  { id = "basics", label = "Basics" },
  { id = "warps", label = "Warps" },
  { id = "objects", label = "Objects" },
  { id = "signs", label = "Signs" },
  { id = "encounters", label = "Encounters" },
  { id = "hidden", label = "Hidden" },
  { id = "gates", label = "Gates" },
}

-- RPG Maker XP–style edit modes (Map = tiles / Passage; Events = NPCs & transfers).
local MAP_MODE_SECTIONS = {
  basics = true, encounters = true, hidden = true, gates = true,
}
local EVENT_MODE_SECTIONS = {
  objects = true, warps = true, signs = true,
}
local EVENT_TOOLS = {
  object = true, warp = true, sign = true, trainer = true, wild = true,
}

local function syncMapEditMode(S, mode)
  S.mapEditMode = mode or S.mapEditMode or "map"
  local tool = S.mapTool or "paint"
  if S.mapEditMode == "events" then
    if not EVENT_TOOLS[tool] then S.mapTool = "object" end
    if not EVENT_MODE_SECTIONS[S.mapSection or ""] then
      S.mapSection = "objects"
    end
  else
    if EVENT_TOOLS[tool] then S.mapTool = "paint" end
    if not MAP_MODE_SECTIONS[S.mapSection or ""] then
      S.mapSection = "basics"
    end
  end
end
local MOVEMENTS = { "STAY", "WALK" }
local RANGES = {
  "NONE", "DOWN", "UP", "LEFT", "RIGHT", "UP_DOWN", "LEFT_RIGHT", "ANY_DIR",
}

local spriteCache = {}  -- spriteId -> SpriteRenderer

local function sortedIds(t)
  local ids = {}
  for id in pairs(t or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- Renaming used to leave the live table aliased under every intermediate id
-- in S.data.maps (prepareLiveMap). Drop those stale keys so the list only
-- shows real project / vanilla ids.
local function scrubStaleLiveMapAliases(S)
  if not (S and S.data and S.data.maps and S.project and S.project.maps) then
    return
  end
  local liveId = {}
  for id, def in pairs(S.project.maps) do
    if type(def) == "table" then liveId[def] = id end
  end
  local drop = {}
  for id, def in pairs(S.data.maps) do
    local real = liveId[def]
    if real and real ~= id then
      drop[#drop + 1] = id
    end
  end
  for _, id in ipairs(drop) do
    if S._vanillaMapBackup and S._vanillaMapBackup[id] then
      S.data.maps[id] = S._vanillaMapBackup[id]
    else
      S.data.maps[id] = nil
    end
  end
end

local function allMapIds(S)
  scrubStaleLiveMapAliases(S)
  local seen, ids = {}, {}
  for id in pairs((S.project and S.project.maps) or {}) do
    seen[id] = true
    ids[#ids + 1] = id
  end
  if S.data and S.data.maps then
    for id in pairs(S.data.maps) do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

-- Move a project map to a new id. Also rebinds the live data.maps alias so
-- the old key cannot linger in the sidebar list.
local function renameMapId(S, map, newId, App)
  local oldId = map.id
  if not newId or newId == oldId then return false end
  if not newId:match("^[%w_]+$") then return false end
  if S.project.maps[newId] then return false end
  if S.data and S.data.maps and S.data.maps[newId]
      and S.data.maps[newId] ~= map then
    return false
  end

  S.project.maps[oldId] = nil
  map.id = newId
  S.project.maps[newId] = map
  S.mapId = newId
  if S.data and S.data.maps then
    if S.data.maps[oldId] == map then
      S.data.maps[oldId] = nil
    end
    if S._vanillaMapBackup and S._vanillaMapBackup[oldId] then
      S.data.maps[oldId] = S._vanillaMapBackup[oldId]
    end
    S.data.maps[newId] = map
  end
  if S._vanillaMapBackup then
    S._vanillaMapBackup[newId] = S._vanillaMapBackup[oldId]
    S._vanillaMapBackup[oldId] = nil
  end
  for _, bag in ipairs({ "hiddenItems", "badgeGates" }) do
    local t = S.project[bag]
    if t and t[oldId] ~= nil and t[newId] == nil then
      t[newId] = t[oldId]
      t[oldId] = nil
    end
  end
  local songs = S.project.audio and S.project.audio.mapSongs
  if songs and songs[oldId] ~= nil and songs[newId] == nil then
    songs[newId] = songs[oldId]
    songs[oldId] = nil
  end
  S._mapCenteredFor = nil
  S._mapIdDraft = nil
  if App then App.markDirty() end
  return true
end

local function resolveMapDef(S, mapId)
  if not mapId then return nil, false end
  if S.project and S.project.maps and S.project.maps[mapId] then
    return S.project.maps[mapId], true
  end
  if S.data and S.data.maps and S.data.maps[mapId] then
    return S.data.maps[mapId], false
  end
  return nil, false
end

local function cloneArrayOfTables(arr)
  local out = {}
  for i, item in ipairs(arr or {}) do
    local c = {}
    for k, v in pairs(item) do c[k] = v end
    out[i] = c
  end
  return out
end

local function cloneSlots(slots)
  return EncounterEdit.cloneSlots(slots)
end

local function cloneEncounters(enc)
  return EncounterEdit.cloneEncounters(enc)
end

local function deepCloneMap(def)
  local copy = {}
  for k, v in pairs(def) do
    if k == "blocks" then
      local b = {}
      for i = 1, #v do b[i] = v[i] end
      copy.blocks = b
    elseif k == "warps" or k == "objects" or k == "signs" then
      copy[k] = cloneArrayOfTables(v)
    elseif k == "connections" then
      local c = {}
      for dir, conn in pairs(v or {}) do
        if type(conn) == "table" then
          local cc = {}
          for ck, cv in pairs(conn) do cc[ck] = cv end
          c[dir] = cc
        else
          c[dir] = conn
        end
      end
      copy.connections = c
    elseif k == "encounters" then
      copy.encounters = cloneEncounters(v)
    elseif k == "superRod" then
      copy.superRod = cloneSlots(v)
    elseif k ~= "source" then
      copy[k] = v
    end
  end
  copy._isNew = false
  return copy
end

local function ensureOwned(S, mapId)
  local def, owned = resolveMapDef(S, mapId)
  if not def then return nil end
  if owned then return def end
  S._vanillaMapBackup = S._vanillaMapBackup or {}
  if S.data and S.data.maps and S.data.maps[mapId] and not S._vanillaMapBackup[mapId] then
    S._vanillaMapBackup[mapId] = S.data.maps[mapId]
  end
  local copy = deepCloneMap(def)
  if not copy.encounters and S.data and S.data.encounters and S.data.encounters[mapId] then
    copy.encounters = cloneEncounters(S.data.encounters[mapId])
  end
  if not copy.superRod and S.data and S.data.field and S.data.field.superRod
      and S.data.field.superRod[mapId] then
    copy.superRod = cloneSlots(S.data.field.superRod[mapId])
  end
  S.project.maps[mapId] = copy
  return copy
end

local function oppositeDir(dir)
  if dir == "north" then return "south" end
  if dir == "south" then return "north" end
  if dir == "east" then return "west" end
  if dir == "west" then return "east" end
  return nil
end

-- Wire A[dir] → B and B[opposite] → A with negated block offset (Tiled/vanilla).
local function applyConnectionEdit(S, fromId, dir, wantMap, wantOff, App, opts)
  opts = opts or {}
  local from = ensureOwned(S, fromId)
  if not from then return nil end
  from.connections = from.connections or {}
  local opp = oppositeDir(dir)
  local prev = from.connections[dir]
  local prevMap = prev and prev.map

  local function clearBack(destId)
    if not destId or not opp then return end
    local backMap = ensureOwned(S, destId)
    if not backMap then return end
    backMap.connections = backMap.connections or {}
    local back = backMap.connections[opp]
    if back and back.map == fromId then
      backMap.connections[opp] = nil
      if S.data and S.data.maps then S.data.maps[destId] = backMap end
      MapLoader.invalidate(destId)
    end
  end

  wantOff = math.floor(tonumber(wantOff) or 0)
  if not wantMap or wantMap == "" then
    if prevMap then clearBack(prevMap) end
    from.connections[dir] = nil
  else
    if prevMap and prevMap ~= wantMap then clearBack(prevMap) end
    from.connections[dir] = { map = wantMap, offset = wantOff }
    local dest = ensureOwned(S, wantMap)
    if dest and opp then
      dest.connections = dest.connections or {}
      dest.connections[opp] = { map = fromId, offset = -wantOff }
      if S.data and S.data.maps then S.data.maps[wantMap] = dest end
      MapLoader.invalidate(wantMap)
    end
  end
  if S.data and S.data.maps then S.data.maps[fromId] = from end
  MapLoader.invalidate(fromId)
  if opts.world then S._worldFitKey = nil end
  if App and App.markDirty then App.markDirty() end
  return from
end

local function cloneNumList(v)
  local a = {}
  for i = 1, #(v or {}) do a[i] = v[i] end
  return a
end

local function listIndex(list, n)
  for i, v in ipairs(list or {}) do
    if v == n then return i end
  end
  return nil
end

local function listSet(list, n, on)
  local i = listIndex(list, n)
  if on and not i then
    list[#list + 1] = n
    table.sort(list)
  elseif not on and i then
    table.remove(list, i)
  end
end

-- Ledge hops: standing tile + ledge tile in front + direction (field.ledges).
local LEDGE_BEHIND = {
  down = { 0, -1 }, up = { 0, 1 }, left = { 1, 0 }, right = { -1, 0 },
}

local function ensureLedgeBackup(S)
  if S._vanillaLedgesBackup then return end
  local cur = (S.data and S.data.field and S.data.field.ledges) or {}
  local copy = {}
  for i, row in ipairs(cur) do
    if type(row) == "table" then
      local r = {}
      for k, v in pairs(row) do r[k] = v end
      copy[i] = r
    end
  end
  S._vanillaLedgesBackup = copy
end

local function rebuildLiveLedges(S)
  if not (S.data and S.data.field) then return end
  ensureLedgeBackup(S)
  local out = {}
  for _, row in ipairs(S._vanillaLedgesBackup or {}) do
    out[#out + 1] = row
  end
  for _, row in ipairs((S.project and S.project.ledges) or {}) do
    out[#out + 1] = row
  end
  S.data.field.ledges = out
end

local function ledgeRuleMatches(rule, tilesetId, ledgeTile, standingTile, dir)
  if type(rule) ~= "table" then return false end
  local ruleTs = rule.tileset or "OVERWORLD"
  if ruleTs ~= (tilesetId or "OVERWORLD") then return false end
  if dir and rule.facing ~= dir then return false end
  if ledgeTile ~= nil and rule.ledgeTile ~= ledgeTile then return false end
  if standingTile ~= nil and rule.standingTile ~= standingTile then return false end
  return true
end

local function cloneTilesetRecord(rec)
  if type(rec) ~= "table" then return nil end
  local copy = {}
  for k, v in pairs(rec) do
    if k == "walkable" or k == "doorTiles" or k == "warpTiles"
        or k == "counterTiles" or k == "waterTiles" or k == "shoreTiles" then
      copy[k] = cloneNumList(v)
    elseif k == "blocks" and type(v) == "table" then
      local b = {}
      for i, row in ipairs(v) do
        local r = {}
        for j = 1, #row do r[j] = row[j] end
        b[i] = r
      end
      copy.blocks = b
    else
      copy[k] = v
    end
  end
  copy.waterTiles = copy.waterTiles or {}
  copy.shoreTiles = copy.shoreTiles or {}
  return copy
end

-- Clone vanilla tileset into the mod so collision / terrain flag edits persist.
-- Prefer cloneTilesetForMap / ensureTerrainTileset for RPG Maker–style local
-- Passage slots; this keeps patching a shared id (GFX tab / advanced).
local function ensureOwnedTileset(S, tilesetId, App)
  if not tilesetId or tilesetId == "" then return nil end
  S.project.tilesets = S.project.tilesets or {}
  if S.project.tilesets[tilesetId] then return S.project.tilesets[tilesetId] end
  local rec = S.data and S.data.tilesets and S.data.tilesets[tilesetId]
  if not rec then return nil end
  -- Keep a pristine copy so Undo can put vanilla back into S.data.tilesets.
  S._vanillaTilesetBackup = S._vanillaTilesetBackup or {}
  if not S._vanillaTilesetBackup[tilesetId] then
    S._vanillaTilesetBackup[tilesetId] = cloneTilesetRecord(rec)
  end
  local copy = cloneTilesetRecord(rec)
  copy._isNew = false
  S.project.tilesets[tilesetId] = copy
  if S.data and S.data.tilesets then S.data.tilesets[tilesetId] = copy end
  S._liveTilesets = nil
  MapLoader.invalidateAll()
  if App and App.markDirty then App.markDirty() end
  return copy
end

local function uniqueTilesetId(S, base)
  local id = base
  local n = 1
  while (S.project.tilesets and S.project.tilesets[id])
      or (S.data and S.data.tilesets and S.data.tilesets[id]) do
    n = n + 1
    id = base .. "_" .. n
  end
  return id
end

-- RPG Maker XP style: duplicate a tileset into a new slot (same graphics,
-- independent Passage / walkable / grass / water). Assign to this map.
local function cloneTilesetForMap(S, map, App)
  if not (S and map) then return nil, nil, "no map" end
  State.ensureProjectFields(S.project)
  local srcId = map.tileset or "OVERWORLD"
  local src = (S.project.tilesets and S.project.tilesets[srcId])
    or (S.data and S.data.tilesets and S.data.tilesets[srcId])
  if type(src) ~= "table" then
    return nil, nil, "no tileset " .. tostring(srcId)
  end
  local mapKey = tostring(map.id or S.mapId or "MAP"):upper():gsub("%W+", "_")
  if mapKey == "" then mapKey = "MAP" end
  local newId = uniqueTilesetId(S, mapKey .. "_TILESET")
  local copy = cloneTilesetRecord(src)
  copy.id = newId
  copy._isNew = true
  copy._mapLocal = true
  copy._clonedFrom = srcId
  S.project.tilesets[newId] = copy
  if S.data and S.data.tilesets then S.data.tilesets[newId] = copy end
  map.tileset = newId
  S.mapPaletteTileset = newId
  S._liveTilesets = nil
  MapLoader.invalidate(map.id)
  MapLoader.invalidateAll()
  if App and App.markDirty then App.markDirty() end
  return copy, newId, nil
end

-- TERRAIN / Passage: use a map-local tileset slot so edits don't rewrite
-- shared OVERWORLD for every outdoor map (RPG Maker mental model).
local function ensureTerrainTileset(S, map, App)
  if not map then return nil end
  local tid = map.tileset or "OVERWORLD"
  local owned = S.project.tilesets and S.project.tilesets[tid]
  -- New / already-cloned slots are map-safe. Re-stamp _mapLocal after reload.
  if owned and (owned._mapLocal or owned._isNew) then
    owned._mapLocal = true
    return owned
  end
  local copy, newId, err = cloneTilesetForMap(S, map, App)
  if copy then
    S.status = string.format(
      "Tileset slot %s (from %s) — Passage edits affect this map only",
      tostring(newId), tostring(copy._clonedFrom or tid))
    return copy
  end
  if err then S.status = "Tileset clone failed: " .. tostring(err) end
  return ensureOwnedTileset(S, tid, App)
end

-- ---- block selection / shift ------------------------------------------------

local function normalizeBlockSel(sel)
  if type(sel) ~= "table" then return nil end
  local x0 = math.min(sel.x0 or 0, sel.x1 or 0)
  local x1 = math.max(sel.x0 or 0, sel.x1 or 0)
  local y0 = math.min(sel.y0 or 0, sel.y1 or 0)
  local y1 = math.max(sel.y0 or 0, sel.y1 or 0)
  return x0, y0, x1, y1
end

local function clampBlockSel(map, x0, y0, x1, y1)
  local mw = math.max(1, map.width or 1)
  local mh = math.max(1, map.height or 1)
  x0 = math.max(0, math.min(mw - 1, x0))
  x1 = math.max(0, math.min(mw - 1, x1))
  y0 = math.max(0, math.min(mh - 1, y0))
  y1 = math.max(0, math.min(mh - 1, y1))
  if x0 > x1 then x0, x1 = x1, x0 end
  if y0 > y1 then y0, y1 = y1, y0 end
  return x0, y0, x1, y1
end

local function selectAllBlocks(map)
  if not map then return nil end
  local mw = math.max(1, map.width or 1)
  local mh = math.max(1, map.height or 1)
  return { x0 = 0, y0 = 0, x1 = mw - 1, y1 = mh - 1 }
end

local function cellInBlockSel(cx, cy, x0, y0, x1, y1)
  return cx >= x0 * 2 and cx <= x1 * 2 + 1
     and cy >= y0 * 2 and cy <= y1 * 2 + 1
end

-- Block clipboard: RMB / Ctrl+C copy, Shift+RMB / Ctrl+V paste.
local function copyBlocksToClip(S, map, x0, y0, x1, y1)
  if not (S and map and map.blocks) then return nil end
  x0, y0, x1, y1 = clampBlockSel(map, x0, y0, x1, y1)
  local bw, bh = x1 - x0 + 1, y1 - y0 + 1
  local blocks = {}
  local w = map.width
  for by = y0, y1 do
    for bx = x0, x1 do
      blocks[#blocks + 1] = map.blocks[by * w + bx + 1] or 0
    end
  end
  S.mapClip = {
    w = bw, h = bh, blocks = blocks,
    tileset = map.tileset,
  }
  if bw == 1 and bh == 1 then
    S.paintBlock = blocks[1]
    S.mapPaletteTileset = map.tileset
  end
  return bw, bh
end

local function pasteClipAt(S, mapId, destX, destY, App)
  local clip = S and S.mapClip
  if not (clip and type(clip.blocks) == "table" and clip.w and clip.h) then
    return false, "clipboard empty — RMB or Ctrl+C to copy"
  end
  local map = ensureOwned(S, mapId)
  if not map or type(map.blocks) ~= "table" then
    return false, "no map"
  end
  destX = math.floor(tonumber(destX) or 0)
  destY = math.floor(tonumber(destY) or 0)
  local w, h = map.width, map.height
  local n = 0
  for row = 0, clip.h - 1 do
    for col = 0, clip.w - 1 do
      local nx, ny = destX + col, destY + row
      if nx >= 0 and ny >= 0 and nx < w and ny < h then
        map.blocks[ny * w + nx + 1] = clip.blocks[row * clip.w + col + 1] or 0
        n = n + 1
      end
    end
  end
  if n == 0 then return false, "paste off-map" end
  S._mapNeedsRebuild = map.id or mapId
  if S.data and S.data.maps then S.data.maps[map.id or mapId] = map end
  MapLoader.invalidate(map.id or mapId)
  if App and App.markDirty then App.markDirty() end
  local note = ""
  if clip.tileset and map.tileset and clip.tileset ~= map.tileset then
    note = " (from tileset " .. tostring(clip.tileset) .. ")"
  end
  return true, string.format("Pasted %dx%d at (%d,%d)%s",
    clip.w, clip.h, destX, destY, note)
end

local function pasteDestBlock(S, map)
  if S._mapHoverBx ~= nil and S._mapHoverBy ~= nil then
    return S._mapHoverBx, S._mapHoverBy
  end
  local x0, y0 = normalizeBlockSel(S.mapSel)
  if x0 then return x0, y0 end
  return 0, 0
end

-- Shift blocks (+ warps/objects/signs in the region) by dx/dy blocks.
-- Vacated source cells that are not covered by the destination get borderBlock.
local function shiftMapRegion(S, mapId, x0, y0, x1, y1, dx, dy, App)
  dx = math.floor(tonumber(dx) or 0)
  dy = math.floor(tonumber(dy) or 0)
  if dx == 0 and dy == 0 then return false, "offset is 0" end
  local map = ensureOwned(S, mapId)
  if not map or type(map.blocks) ~= "table" then
    return false, "no map"
  end
  x0, y0, x1, y1 = clampBlockSel(map, x0, y0, x1, y1)
  local w, h = map.width, map.height
  local fill = map.borderBlock or 0
  local buf = {}
  for by = y0, y1 do
    for bx = x0, x1 do
      buf[#buf + 1] = {
        bx, by, map.blocks[by * w + bx + 1] or 0,
      }
    end
  end
  for by = y0, y1 do
    for bx = x0, x1 do
      map.blocks[by * w + bx + 1] = fill
    end
  end
  for _, e in ipairs(buf) do
    local nx, ny = e[1] + dx, e[2] + dy
    if nx >= 0 and ny >= 0 and nx < w and ny < h then
      map.blocks[ny * w + nx + 1] = e[3]
    end
  end

  local cellDx, cellDy = dx * 2, dy * 2
  local maxCx, maxCy = w * 2, h * 2
  local function shiftList(list)
    local out = {}
    for _, ent in ipairs(list or {}) do
      local ex, ey = ent.x or 0, ent.y or 0
      if cellInBlockSel(ex, ey, x0, y0, x1, y1) then
        local nx, ny = ex + cellDx, ey + cellDy
        if nx >= 0 and ny >= 0 and nx < maxCx and ny < maxCy then
          ent.x, ent.y = nx, ny
          out[#out + 1] = ent
        end
      else
        out[#out + 1] = ent
      end
    end
    return out
  end
  map.warps = shiftList(map.warps)
  map.objects = shiftList(map.objects)
  for i, obj in ipairs(map.objects or {}) do
    obj.index = i
  end
  map.signs = shiftList(map.signs)

  local sx0, sy0 = x0 + dx, y0 + dy
  local sx1, sy1 = x1 + dx, y1 + dy
  sx0, sy0, sx1, sy1 = clampBlockSel(map, sx0, sy0, sx1, sy1)
  S.mapSel = { x0 = sx0, y0 = sy0, x1 = sx1, y1 = sy1 }
  S._mapSelFor = map.id or mapId

  if S.data and S.data.maps then
    S.data.maps[map.id or mapId] = map
  end
  MapLoader.invalidate(map.id or mapId)
  App.markDirty()
  S.status = string.format("Shifted selection by (%d, %d) blocks", dx, dy)
  return true
end

local function drawSelectionOverlay(S, mapDef)
  local draft = S._mapSelDraft
  local sel = draft or S.mapSel
  local x0, y0, x1, y1 = normalizeBlockSel(sel)
  if not x0 then return end
  x0, y0, x1, y1 = clampBlockSel(mapDef, x0, y0, x1, y1)
  local camX, camY = S.mapCamX or 0, S.mapCamY or 0
  local px = x0 * BLOCK_PX - camX
  local py = y0 * BLOCK_PX - camY
  local pw = (x1 - x0 + 1) * BLOCK_PX
  local ph = (y1 - y0 + 1) * BLOCK_PX
  love.graphics.setColor(0.27, 0.85, 0.55, 0.18)
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(0.27, 0.85, 0.55, 0.85)
  love.graphics.rectangle("line", px, py, pw, ph)
  love.graphics.setColor(1, 1, 1, 1)
end

local function cloneHiddenList(list)
  local out = {}
  for i, h in ipairs(list or {}) do
    out[i] = { x = h.x or 0, y = h.y or 0, item = h.item or "POTION" }
  end
  return out
end

local function cloneGateCoords(list)
  local out = {}
  for i, c in ipairs(list or {}) do
    out[i] = { x = c.x or 0, y = c.y or 0 }
  end
  return out
end

local function cloneGate(g)
  if not g then return { coords = {} } end
  local out = { coords = cloneGateCoords(g.coords) }
  for _, key in ipairs({ "badge", "text", "failText", "passText", "passedFlag" }) do
    if g[key] ~= nil then out[key] = g[key] end
  end
  return out
end

local function resolveHiddenItems(S, mapId)
  State.ensureProjectFields(S.project)
  if S.project.hiddenItems[mapId] then
    return S.project.hiddenItems[mapId], true
  end
  local base = S.data and S.data.field and S.data.field.hiddenItems
      and S.data.field.hiddenItems[mapId]
  return base, false
end

local function ensureHiddenItems(S, mapId)
  State.ensureProjectFields(S.project)
  if not S.project.hiddenItems[mapId] then
    local base = S.data and S.data.field and S.data.field.hiddenItems
        and S.data.field.hiddenItems[mapId]
    S.project.hiddenItems[mapId] = cloneHiddenList(base)
  end
  return S.project.hiddenItems[mapId]
end

-- project.badgeGates[mapId] = false means "suppress / delete this gate"
-- (Save emits mod.DELETE so deep-merge actually removes it).
local function resolveBadgeGate(S, mapId)
  State.ensureProjectFields(S.project)
  local proj = S.project.badgeGates[mapId]
  if proj == false then
    return nil, true, true
  end
  if type(proj) == "table" then
    return proj, true, false
  end
  local base = S.data and S.data.field and S.data.field.badgeGates
      and S.data.field.badgeGates[mapId]
  return base, false, false
end

local function syncLiveBadgeGate(S, mapId, gateOrNil)
  if not (S.data and S.data.field) then return end
  S.data.field.badgeGates = S.data.field.badgeGates or {}
  S.data.field.badgeGates[mapId] = gateOrNil
end

local function ensureBadgeGate(S, mapId)
  State.ensureProjectFields(S.project)
  local cur = S.project.badgeGates[mapId]
  if type(cur) == "table" then return cur end
  local base = S.data and S.data.field and S.data.field.badgeGates
      and S.data.field.badgeGates[mapId]
  -- After a delete (false), start a fresh gate rather than resurrecting nil.
  if cur == false then base = nil end
  local gate = cloneGate(base)
  S.project.badgeGates[mapId] = gate
  syncLiveBadgeGate(S, mapId, gate)
  return gate
end

local function removeBadgeGate(S, mapId)
  State.ensureProjectFields(S.project)
  -- false = explicit suppress (needed so vanilla FieldDefaults / prior
  -- deep-merge patches do not come back on Save).
  S.project.badgeGates[mapId] = false
  syncLiveBadgeGate(S, mapId, nil)
end

-- Map locale for door SFX / wild rules / LAST_MAP (Outside / Inside / Cave).
local function inferMapEnvironment(map)
  if type(map) ~= "table" then return "outside" end
  local env = map.environment
  if env == "outside" or env == "inside" or env == "cave" then return env end
  if map.outdoor == true then return "outside" end
  if map.outdoor == false then
    if map.tileset == "CAVERN" then return "cave" end
    return "inside"
  end
  if map.tileset == "CAVERN" then return "cave" end
  if map.tileset == "OVERWORLD" or map.tileset == "PLATEAU" then
    return "outside"
  end
  return "inside"
end

local function setMapEnvironment(map, env)
  if env ~= "outside" and env ~= "inside" and env ~= "cave" then return end
  map.environment = env
  map.outdoor = (env == "outside")
end

local function defaultMap(id, index, tileset)
  local w, h = 10, 9
  local blocks = {}
  for i = 1, w * h do blocks[i] = 1 end
  local ts = tileset or "OVERWORLD"
  local env = "outside"
  if ts == "CAVERN" then env = "cave"
  elseif ts ~= "OVERWORLD" and ts ~= "PLATEAU" then env = "inside" end
  return {
    id = id,
    label = id,
    index = index,
    tileset = ts,
    environment = env,
    outdoor = env == "outside",
    width = w,
    height = h,
    blocks = blocks,
    borderBlock = 0,
    warps = {},
    objects = {},
    signs = {},
    connections = {},
    encounters = nil,
    _isNew = true,
  }
end

-- Optional 9th arg `suggest`: id list or function() -> list for autocomplete.
local function field(App, id, x, y, w, h, value, ph, suggest)
  if acS and suggest then
    return RegList.suggestField(App, acS, id, x, y, w, h, value, ph, suggest)
  end
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function cycle(list, cur, dir)
  if not list or #list == 0 then return cur end
  dir = dir or 1
  local idx = 1
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  local n = idx + dir
  if n < 1 then
    n = #list
  elseif n > #list then
    n = 1
  end
  return list[n]
end

-- Songs available for map_songs overrides (AUDIO tab + this Maps field).
local function songIds(S)
  local ids, seen = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.data and S.data.audio and type(S.data.audio.songs) == "table" then
    for id in pairs(S.data.audio.songs) do add(id) end
  end
  if S.project and S.project.audio and type(S.project.audio.songs) == "table" then
    for id in pairs(S.project.audio.songs) do add(id) end
  end
  if #ids == 0 then
    for _, id in ipairs({
      "Music_PalletTown", "Music_Cities1", "Music_Cities2",
      "Music_Routes1", "Music_Routes2", "Music_Routes3", "Music_Routes4",
      "Music_IndigoPlateau", "Music_Gym", "Music_Pokecenter",
      "Music_Dungeon1", "Music_Dungeon2", "Music_Dungeon3",
      "Music_Cinnabar", "Music_Lavender", "Music_Celadon",
      "Music_ViridianForest", "Music_SSAnne",
    }) do add(id) end
  end
  table.sort(ids)
  return ids
end

local function mapSongFor(S, mapId)
  if not mapId then return "", false end
  local proj = S.project and S.project.audio and S.project.audio.mapSongs
  if proj and proj[mapId] ~= nil then
    return tostring(proj[mapId]), true
  end
  local data = S.data and S.data.audio and S.data.audio.mapSongs
  if data and data[mapId] ~= nil then
    return tostring(data[mapId]), false
  end
  return "", false
end

local function setMapSong(S, mapId, songId, App)
  if not (S and S.project and mapId) then return end
  State.ensureProjectFields(S.project)
  S.project.audio = S.project.audio or {}
  S.project.audio.mapSongs = S.project.audio.mapSongs or {}
  if songId == nil or songId == "" then
    S.project.audio.mapSongs[mapId] = nil
  else
    S.project.audio.mapSongs[mapId] = songId
  end
  if App then App.markDirty() end
end

local DEFAULT_MART = {
  "POKE_BALL", "POTION", "ANTIDOTE", "PARLYZ_HEAL",
  "BURN_HEAL", "ICE_HEAL", "AWAKENING", "REPEL",
}

local function spriteDef(S, spriteId)
  if not spriteId then return nil end
  local proj = S.project and S.project.sprites and S.project.sprites[spriteId]
  if proj then return proj end
  return S.data and S.data.sprites and S.data.sprites[spriteId]
end

-- nil = draw raw (trueColor); otherwise SGB palette id for Preview.draw.
local function spritePreviewPal(S, def)
  if not def or def.trueColor then return nil end
  local src = def.paletteSource
  if type(src) == "string" and src ~= "" and Preview.paletteColors(S, src) then
    return src
  end
  return "MEWMON"
end

local function spriteListCacheKey(S)
  local nProj, nData = 0, 0
  local h = 0
  for id in pairs((S.project and S.project.sprites) or {}) do
    nProj = nProj + 1
    h = h + #id
  end
  for id in pairs((S.data and S.data.sprites) or {}) do
    nData = nData + 1
    h = h + #id
  end
  return nProj .. ":" .. nData .. ":" .. h
end

local function spriteIds(S, customOnly)
  local proj = S.project and S.project.sprites
  if customOnly then
    local ids = {}
    for id in pairs(proj or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
  end
  local key = spriteListCacheKey(S)
  if S._spriteIdList and S._spriteIdListKey == key then return S._spriteIdList end
  local seen, ids = {}, {}
  for id in pairs(proj or {}) do
    seen[id] = true; ids[#ids + 1] = id
  end
  if S.data and S.data.sprites then
    for id in pairs(S.data.sprites) do
      if not seen[id] then ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  S._spriteIdList = ids
  S._spriteIdListKey = key
  return ids
end

local function allItemIds(S)
  local seen, ids = {}, {}
  for id in pairs((S.project and S.project.items) or {}) do
    seen[id] = true
    ids[#ids + 1] = id
  end
  if S.data and S.data.items then
    for id in pairs(S.data.items) do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

-- text_pointers entry for an object's TEXT_* (project override, then vanilla).
local function resolveTextPtr(S, mapId, textId)
  if not textId or textId == "" then return nil, nil, false end
  local label = State.mapLabel(S, mapId)
  if not label then return nil, nil, false end
  local proj = S.project and S.project.text_pointers and S.project.text_pointers[label]
  if proj and proj[textId] then return proj[textId], label, true end
  local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
  return base and base[textId], label, false
end

local function cloneTextPtr(src)
  local e = {}
  if not src then return e end
  for k, v in pairs(src) do
    if k == "mart" and type(v) == "table" then
      local m = {}
      for i, id in ipairs(v) do m[i] = id end
      e.mart = m
    else
      e[k] = v
    end
  end
  return e
end

-- Clone pointer into the mod on first shop/role edit.
local function ensureTextPtr(S, mapId, textId)
  State.ensureProjectFields(S.project)
  local entry, label, owned = resolveTextPtr(S, mapId, textId)
  if not label or not textId or textId == "" then return nil, label end
  if not owned then
    S.project.text_pointers[label] = S.project.text_pointers[label] or {}
    S.project.text_pointers[label][textId] = cloneTextPtr(entry)
  end
  return S.project.text_pointers[label][textId], label
end

-- Drop trainer headers / beat flags / dialog / talk scripts for a removed object,
-- then reindex remaining trainer_headers to match new object indices.
local function cleanupRemovedMapObject(S, map, removedIndex, removed)
  if not S or not S.project or not map or not removed then return end
  State.ensureProjectFields(S.project)
  local mapId = map.id
  local label = State.mapLabel(S, mapId)
  local textId = removed.text

  local bucket = label and S.project.trainer_headers
    and S.project.trainer_headers[label]
  if type(bucket) == "table" then
    local hdr = bucket[removedIndex]
    if type(hdr) == "table" then
      for _, key in ipairs({ "battle", "won", "after" }) do
        local tid = hdr[key]
        if type(tid) == "string" and tid ~= "" then
          S.project.text[tid] = nil
        end
      end
      if type(hdr.event) == "string" and hdr.event ~= "" then
        S.project.eventFlags[hdr.event] = nil
      end
    end
    local newBucket = {}
    for j, o in ipairs(map.objects or {}) do
      if type(o) == "table" and o.trainerClass and o.trainerClass ~= "" then
        local prevIdx = (j < removedIndex) and j or (j + 1)
        if type(bucket[prevIdx]) == "table" then
          newBucket[j] = bucket[prevIdx]
        end
      end
    end
    S.project.trainer_headers[label] = newBucket
  end

  if type(textId) == "string" and textId ~= "" and mapId then
    local talkKey = mapId .. "/" .. textId
    if S.project.talkScripts then
      S.project.talkScripts[talkKey] = nil
    end
    if label and S.project.text_pointers and S.project.text_pointers[label] then
      local ptr = S.project.text_pointers[label][textId]
      if type(ptr) == "table" and type(ptr.text) == "string" then
        -- Only drop invented mod bodies (not shared vanilla string ids).
        local invented = "_" .. textId:gsub("^TEXT_", "")
        if ptr.text == invented then
          S.project.text[ptr.text] = nil
        end
      end
      S.project.text_pointers[label][textId] = nil
      if not next(S.project.text_pointers[label]) then
        S.project.text_pointers[label] = nil
      end
    end
  end
end

local function ptrRole(entry)
  if not entry then return "talk" end
  if entry.mart then return "shop" end
  if entry.nurse then return "nurse" end
  if entry.pc then return "pc" end
  if entry.cableClub then return "cable" end
  return "talk"
end

local function setPtrRole(entry, role, keepMart)
  entry.mart = nil
  entry.nurse = nil
  entry.pc = nil
  entry.cableClub = nil
  if role == "shop" then
    entry.mart = {}
    local src = (keepMart and #keepMart > 0) and keepMart or DEFAULT_MART
    for i, id in ipairs(src) do entry.mart[i] = id end
  elseif role == "nurse" then
    entry.nurse = true
  elseif role == "pc" then
    entry.pc = true
  elseif role == "cable" then
    entry.cableClub = true
  end
end

local function tilesetIds(S)
  local seen, ids = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  if S.project and S.project.tilesets then
    for id in pairs(S.project.tilesets) do add(id) end
  end
  if S.data and S.data.tilesets then
    for id in pairs(S.data.tilesets) do add(id) end
  end
  table.sort(ids)
  return ids
end

local function openTilesetPicker(S)
  S.mapTilesetPicker = { query = "", offset = 0, opened = true }
  S._mapDrag = nil
  S._mapViewHit = false
  S._worldViewHit = false
end

local function tilesetDef(S, tilesetId)
  return (S.project.tilesets and S.project.tilesets[tilesetId])
    or (S.data and S.data.tilesets and S.data.tilesets[tilesetId])
end

local function blockCount(S, tilesetId)
  local ts = tilesetDef(S, tilesetId)
  if ts and ts.blocks then return #ts.blocks end
  return 32
end

local function applyMapTileset(S, map, tilesetId, App, mutate)
  if not tilesetId then return map end
  S.mapPaletteTileset = tilesetId
  if not map or map.tileset == tilesetId then return map end
  map = mutate()
  map.tileset = tilesetId
  local maxB = math.max(0, blockCount(S, tilesetId) - 1)
  if (S.paintBlock or 0) > maxB then
    S.paintBlock = math.min(1, maxB)
  end
  S.mapBlockOffset = 0
  MapLoader.invalidate(map.id)
  S._mapNeedsRebuild = map.id
  S._mapCenteredFor = nil
  App.markDirty()
  S.status = "Tileset → " .. tilesetId
  return map
end

-- Draw one tileset block (32x32 source) into a square of `size` pixels.
local quadCache = {}  -- "path#tid" -> Quad
local function mapPaletteName(S, mapDef)
  return Preview.mapPaletteName(S, mapDef or resolveMapDef(S, S.mapId))
end

-- TrueColor: map flag or the tileset's own trueColor (GFX / stock engine).
local function mapUsesTrueColor(S, mapDef)
  mapDef = mapDef or resolveMapDef(S, S.mapId)
  if not mapDef then return false end
  if mapDef.trueColor then return true end
  local ts = tilesetDef(S, mapDef.tileset)
  return ts and ts.trueColor and true or false
end

-- Palette id for SGB remap, or nil when TrueColor (skip remap).
local function mapPreviewPalette(S, mapDef)
  mapDef = mapDef or resolveMapDef(S, S.mapId)
  if mapUsesTrueColor(S, mapDef) then return nil end
  return mapPaletteName(S, mapDef)
end

-- Stamp tileset.trueColor so stock Gen1Recomp (tileset-only) matches the map flag.
local function syncTilesetTrueColor(S, map, on, App)
  if not map then return end
  local ts
  if on then
    -- Prefer a map-local slot so enabling TrueColor does not recolor every
    -- outdoor map that still shares OVERWORLD.
    ts = ensureTerrainTileset(S, map, App)
  else
    local tid = map.tileset or ""
    ts = S.project.tilesets and S.project.tilesets[tid]
    if not ts then return end
  end
  if not ts then return end
  ts.trueColor = on and true or nil
  S._liveTilesets = nil
  MapLoader.invalidateAll()
end

local function drawBlockThumb(S, tilesetId, blockId, x, y, size, mapDef)
  local ts = tilesetDef(S, tilesetId)
  love.graphics.setColor(1, 1, 1, 1)
  if not (ts and ts.blocks and ts.image) then
    Theme.col(PAL.rowBg, 1)
    love.graphics.rectangle("fill", x, y, size, size, 3, 3)
    return
  end
  local block = ts.blocks[(blockId or 0) + 1]
  local img = Preview.image(S, ts.image)
  -- Mod / import tilesets sometimes store a bare tile id instead of a
  -- 16-entry block row; treat that as missing art rather than crashing.
  if not (type(block) == "table" and img) then
    Theme.col(PAL.rowBg, 1)
    love.graphics.rectangle("fill", x, y, size, size, 3, 3)
    Kit.text("micro", tostring(blockId or 0), x + 2, y + size / 2 - 5, PAL.faint)
    return
  end
  local perRow = ts.tilesPerRow or 16
  local iw, ih = img:getDimensions()
  local tileDraw = size / 4
  local scale = tileDraw / 8
  local pal = mapPreviewPalette(S, mapDef)
  local shaded = pal and Preview.pushPaletteShader(S, pal)
  for row = 0, 3 do
    for col = 0, 3 do
      local tid = block[row * 4 + col + 1] or 0
      if type(tid) ~= "number" then tid = 0 end
      local key = ts.image .. "#" .. tid
      local q = quadCache[key]
      if not q then
        q = love.graphics.newQuad(
          (tid % perRow) * 8, math.floor(tid / perRow) * 8, 8, 8, iw, ih)
        quadCache[key] = q
      end
      love.graphics.draw(img, q, x + col * tileDraw, y + row * tileDraw, 0, scale, scale)
    end
  end
  Preview.popPaletteShader(shaded)
end

-- Tileset sheet + first-block strip for the picker / Basics panel.
local function drawTilesetPreview(S, tilesetId, x, y, w, h)
  local s = Kit.scale
  Theme.col(PAL.bgBot or PAL.card, 1)
  love.graphics.rectangle("fill", x, y, w, h, 6 * s, 6 * s)
  local ts = tilesetDef(S, tilesetId)
  if not ts then
    Kit.text("micro", "no tileset", x + 8 * s, y + h / 2 - 6 * s, PAL.faint)
    return
  end
  local pad = 6 * s
  local metaH = 12 * s
  local stripH = math.min(36 * s, math.max(20 * s, h * 0.22))
  local sheetH = math.max(24 * s, h - stripH - metaH - pad * 3)
  local sheetW = w - pad * 2
  local sx, sy = x + pad, y + pad

  local blankAtlas = false
  if ts.image then
    Preview.draw(S, ts.image, sx, sy, sheetW, sheetH, mapPreviewPalette(S))
    -- Old TMX imports wrote a fully transparent atlas (~hundreds of bytes for
    -- a large sheet). Hint that Replace PNG / re-Import TMX is needed.
    local resolved = select(1, Preview.resolve(S, ts.image))
    if resolved then
      local f = io.open(resolved, "rb")
      if f then
        local nbytes = f:seek("end")
        f:close()
        local iw = ts.imageWidth or 0
        local ih = ts.imageHeight or 0
        if type(nbytes) == "number" and nbytes > 0 and nbytes < 1200
            and (iw * ih >= 64 * 64 or nbytes < 600) then
          blankAtlas = true
        end
      end
    end
    if blankAtlas then
      Kit.text("micro", "blank atlas — Replace PNG or re-Import TMX",
        sx + 6 * s, sy + sheetH / 2 - 6 * s, PAL.red or PAL.heading)
    end
  else
    Theme.col(PAL.rowBg, 1)
    love.graphics.rectangle("fill", sx, sy, sheetW, sheetH, 4 * s, 4 * s)
    Kit.text("micro", "no image", sx + 8 * s, sy + sheetH / 2 - 6 * s, PAL.faint)
  end

  local n = blockCount(S, tilesetId)
  local thumb = math.max(12 * s, stripH - 2)
  local gap = 2 * s
  local cols = math.max(1, math.floor((w - pad * 2) / (thumb + gap)))
  local by = sy + sheetH + pad
  Kit.pushClip(x + pad, by, w - pad * 2, stripH)
  for i = 0, math.min(n, cols) - 1 do
    drawBlockThumb(S, tilesetId, i, x + pad + i * (thumb + gap), by, thumb)
  end
  Kit.popClip()
  local meta = string.format("%d blocks", n)
  if ts.tilesPerRow then meta = meta .. " · " .. ts.tilesPerRow .. "/row" end
  if blankAtlas then meta = meta .. " · blank image" end
  Kit.text("micro", meta, x + pad, y + h - metaH, PAL.faint)
end

local function clampZoom(z)
  if z < 0.5 then return 0.5 end
  if z > 8 then return 8 end
  return z
end

local function clampWorldZoom(z)
  if z < 0.04 then return 0.04 end
  if z > 2 then return 2 end
  return z
end

-- Camera bounds in world px. When the map fits the view, lock to centered
-- offsets (same as Fit); when zoomed in, clamp to [0, map - view].
local function mapCamLimits(S, mapDef)
  local z = math.max(0.25, S.mapZoom or 2)
  local vw = (S._mapViewW or 480) / z
  local vh = (S._mapViewH or 432) / z
  local mw = (tonumber(mapDef and mapDef.width) or 0) * BLOCK_PX
  local mh = (tonumber(mapDef and mapDef.height) or 0) * BLOCK_PX
  local minX, maxX, minY, maxY
  if mw <= vw then
    minX = (mw - vw) / 2
    maxX = minX
  else
    minX, maxX = 0, mw - vw
  end
  if mh <= vh then
    minY = (mh - vh) / 2
    maxY = minY
  else
    minY, maxY = 0, mh - vh
  end
  return minX, minY, maxX, maxY, mw, mh, vw, vh
end

local function clampMapCam(S, mapDef)
  if not (S and mapDef) then return end
  local minX, minY, maxX, maxY = mapCamLimits(S, mapDef)
  local x = tonumber(S.mapCamX) or 0
  local y = tonumber(S.mapCamY) or 0
  if x < minX then x = minX elseif x > maxX then x = maxX end
  if y < minY then y = minY elseif y > maxY then y = maxY end
  S.mapCamX, S.mapCamY = x, y
end

-- H/V scrollbars on the map canvas (drag thumbs to pan while zoomed in).
-- Sets S._mapSbBlocking when the pointer is on a bar / drag so paint/pan skip.
local function drawMapScrollbars(S, mapDef, vx, vy, vw, vh)
  S._mapSbBlocking = false
  if not mapDef then return end
  clampMapCam(S, mapDef)
  local minX, minY, maxX, maxY, mw, mh, viewW, viewH = mapCamLimits(S, mapDef)
  local s = Kit.scale
  local sb = math.max(8, 10 * s)
  local needH = maxX > minX + 0.5
  local needV = maxY > minY + 0.5
  if not needH and not needV then
    S._mapSbDrag = nil
    return
  end

  local trackW = math.max(0, needV and (vw - sb) or vw)
  local trackH = math.max(0, needH and (vh - sb) or vh)
  if trackW < 8 * s and trackH < 8 * s then
    S._mapSbDrag = nil
    return
  end

  local drag = S._mapSbDrag
  if drag and not (Kit.mouseDown or Kit.mouseClicked) then
    S._mapSbDrag = nil
    drag = nil
  end
  if drag then
    S._mapSbBlocking = true
    if drag.axis == "x" and needH then
      local travel = math.max(1, drag.trackLen - drag.thumbLen)
      local t = (Kit.mouseX - drag.origin) / travel
      S.mapCamX = minX + Theme.clamp(t, 0, 1) * (maxX - minX)
    elseif drag.axis == "y" and needV then
      local travel = math.max(1, drag.trackLen - drag.thumbLen)
      local t = (Kit.mouseY - drag.origin) / travel
      S.mapCamY = minY + Theme.clamp(t, 0, 1) * (maxY - minY)
    end
    clampMapCam(S, mapDef)
  end

  if needV and trackH >= 8 * s then
    local range = math.max(1, maxY - minY)
    local th = math.max(24 * s, trackH * (viewH / math.max(viewH, mh)))
    th = math.min(th, trackH)
    local travel = math.max(1, trackH - th)
    local ty = vy + travel * (((S.mapCamY or 0) - minY) / range)
    local bx = vx + math.max(0, vw - sb)
    if Kit.hit(bx, vy, sb, trackH) then S._mapSbBlocking = true end
    Theme.col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", bx, vy, sb, trackH, sb / 2, sb / 2)
    local hot = Kit.hover(bx, ty, sb, th)
      or (S._mapSbDrag and S._mapSbDrag.axis == "y")
    Theme.col(PAL.blue, hot and 0.9 or 0.65)
    love.graphics.rectangle("fill", bx, ty, sb, th, sb / 2, sb / 2)
    if Kit.press(bx, vy, sb, trackH) then
      local clickT = Theme.clamp((Kit.mouseY - vy - th / 2) / travel, 0, 1)
      S.mapCamY = minY + clickT * range
      S._mapSbDrag = {
        axis = "y",
        origin = Kit.mouseY - travel * clickT,
        trackLen = trackH,
        thumbLen = th,
      }
      S._mapSbBlocking = true
      clampMapCam(S, mapDef)
    end
  end

  if needH and trackW >= 8 * s then
    local range = math.max(1, maxX - minX)
    local tw = math.max(24 * s, trackW * (viewW / math.max(viewW, mw)))
    tw = math.min(tw, trackW)
    local travel = math.max(1, trackW - tw)
    local tx = vx + travel * (((S.mapCamX or 0) - minX) / range)
    local by = vy + math.max(0, vh - sb)
    if Kit.hit(vx, by, trackW, sb) then S._mapSbBlocking = true end
    Theme.col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", vx, by, trackW, sb, sb / 2, sb / 2)
    local hot = Kit.hover(tx, by, tw, sb)
      or (S._mapSbDrag and S._mapSbDrag.axis == "x")
    Theme.col(PAL.blue, hot and 0.9 or 0.65)
    love.graphics.rectangle("fill", tx, by, tw, sb, sb / 2, sb / 2)
    if Kit.press(vx, by, trackW, sb) then
      local clickT = Theme.clamp((Kit.mouseX - vx - tw / 2) / travel, 0, 1)
      S.mapCamX = minX + clickT * range
      S._mapSbDrag = {
        axis = "x",
        origin = Kit.mouseX - travel * clickT,
        trackLen = trackW,
        thumbLen = tw,
      }
      S._mapSbBlocking = true
      clampMapCam(S, mapDef)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Forward declare: World view draws live tiles before this is assigned.
local prepareLiveMap

-- World view: current map + its direct N/S/E/W neighbors only
-- (same strip math as OverworldState.computeNeighbors).
local WORLD_BLOCK = 32

local function worldConnDelta(dir, offset, curDef, destDef)
  local off = (offset or 0) * WORLD_BLOCK
  if dir == "north" then
    return off, -destDef.height * WORLD_BLOCK
  elseif dir == "south" then
    return off, curDef.height * WORLD_BLOCK
  elseif dir == "west" then
    return -destDef.width * WORLD_BLOCK, off
  end
  return curDef.width * WORLD_BLOCK, off
end

-- Place `other` when `other.connections[dir]` points at `cur`.
local function worldReverseDelta(dir, offset, curDef, otherDef)
  local off = (offset or 0) * WORLD_BLOCK
  if dir == "north" then
    return -off, curDef.height * WORLD_BLOCK
  elseif dir == "south" then
    return -off, -otherDef.height * WORLD_BLOCK
  elseif dir == "west" then
    return curDef.width * WORLD_BLOCK, -off
  end
  return -otherDef.width * WORLD_BLOCK, -off
end

local function buildWorldLayout(S)
  local rootId = S.mapId
  local rootDef = rootId and resolveMapDef(S, rootId) or nil
  local maps, positions, edges = {}, {}, {}
  if not (rootDef and type(rootDef.width) == "number"
      and type(rootDef.height) == "number") then
    return {
      positions = positions, edges = edges, maps = maps,
      bounds = { x = 0, y = 0, w = WORLD_BLOCK, h = WORLD_BLOCK },
      rootId = rootId,
    }
  end

  maps[rootId] = rootDef
  local placed = { [rootId] = { ox = 0, oy = 0 } }

  -- Outgoing neighbors from the current map.
  for dir, conn in pairs(rootDef.connections or {}) do
    local dest = conn and conn.map
    if dest then
      local destDef = resolveMapDef(S, dest)
      edges[#edges + 1] = {
        from = rootId, to = dest, dir = dir,
        offset = conn.offset or 0,
        ok = destDef ~= nil,
      }
      if destDef and type(destDef.width) == "number"
          and type(destDef.height) == "number" and not placed[dest] then
        maps[dest] = destDef
        local dx, dy = worldConnDelta(dir, conn.offset, rootDef, destDef)
        placed[dest] = { ox = dx, oy = dy }
      end
    end
  end

  -- Inbound: other maps that connect into the current map (show if not
  -- already placed via an outbound link).
  for _, id in ipairs(allMapIds(S)) do
    if id ~= rootId then
      local def = resolveMapDef(S, id)
      if def then
        for dir, conn in pairs(def.connections or {}) do
          if conn and conn.map == rootId then
            edges[#edges + 1] = {
              from = id, to = rootId, dir = dir,
              offset = conn.offset or 0, ok = true,
            }
            if type(def.width) == "number" and type(def.height) == "number"
                and not placed[id] then
              maps[id] = def
              local dx, dy = worldReverseDelta(dir, conn.offset, rootDef, def)
              placed[id] = { ox = dx, oy = dy }
            end
          end
        end
      end
    end
  end

  local minX, minY = math.huge, math.huge
  local maxX, maxY = -math.huge, -math.huge
  for id, p in pairs(placed) do
    local def = maps[id]
    local w = def.width * WORLD_BLOCK
    local h = def.height * WORLD_BLOCK
    if p.ox < minX then minX = p.ox end
    if p.oy < minY then minY = p.oy end
    if p.ox + w > maxX then maxX = p.ox + w end
    if p.oy + h > maxY then maxY = p.oy + h end
  end
  if minX == math.huge then
    minX, minY = 0, 0
    maxX = rootDef.width * WORLD_BLOCK
    maxY = rootDef.height * WORLD_BLOCK
  end

  for id, p in pairs(placed) do
    local def = maps[id]
    positions[id] = {
      x = p.ox - minX,
      y = p.oy - minY,
      w = def.width * WORLD_BLOCK,
      h = def.height * WORLD_BLOCK,
    }
  end

  return {
    positions = positions,
    edges = edges,
    maps = maps,
    bounds = { x = 0, y = 0, w = maxX - minX, h = maxY - minY },
    rootId = rootId,
  }
end

local function worldFitKey(S, layout)
  return tostring(layout.rootId or "") .. ":"
    .. tostring(layout.bounds.w) .. "x" .. tostring(layout.bounds.h)
end

local function fitWorldCamera(S, layout, vw, vh)
  local b = layout.bounds
  local pad = 40
  local zx = vw / math.max(1, b.w + pad * 2)
  local zy = vh / math.max(1, b.h + pad * 2)
  S.worldZoom = clampWorldZoom(math.min(zx, zy, 1.5))
  local z = S.worldZoom
  S.worldCamX = b.x + b.w * 0.5 - vw / (2 * z)
  S.worldCamY = b.y + b.h * 0.5 - vh / (2 * z)
  S._worldFitKey = worldFitKey(S, layout)
end

local function drawWorldView(S, App, vx, vy, vw, vh, propW)
  local s = Kit.scale
  local layout = buildWorldLayout(S)
  local canvasW = math.max(40 * s, vw - propW - 12 * s)
  local canvasH = vh
  Kit.card(vx, vy, canvasW, canvasH, 12 * s)

  local pad = 8 * s
  local viewX = vx + pad
  local viewY = vy + pad
  local viewW = canvasW - 2 * pad
  local viewH = canvasH - 2 * pad
  S._worldViewHit = Kit.hit(viewX, viewY, viewW, viewH)
  S._worldViewW, S._worldViewH = viewW, viewH

  local fitKey = worldFitKey(S, layout)
  if S._worldFitKey ~= fitKey or S.worldCamX == nil then
    fitWorldCamera(S, layout, viewW, viewH)
  end
  S.worldZoom = clampWorldZoom(S.worldZoom or 0.25)
  S._worldFocusId = nil

  -- Pan / select (clicking a neighbor recenters World on that map)
  if Kit.mouseDown and not Kit.blockClicks and not Kit._suppressMouse
      and (S._worldDrag or S._worldViewHit) then
    if not S._worldDrag and Kit.mouseClicked and S._worldViewHit then
      local z = S.worldZoom
      local wx = S.worldCamX + (Kit.mouseX - viewX) / z
      local wy = S.worldCamY + (Kit.mouseY - viewY) / z
      local hitId = nil
      for id, p in pairs(layout.positions) do
        if wx >= p.x and wx <= p.x + p.w and wy >= p.y and wy <= p.y + p.h then
          hitId = id
          break
        end
      end
      if hitId then
        if hitId ~= S.mapId then
          S.mapId = hitId
          S._mapIdDraft = nil
          S._mapCenteredFor = nil
          S._worldFitKey = nil
        end
        S._worldDrag = { kind = "select", id = hitId }
      else
        S._worldDrag = {
          kind = "pan", mx = Kit.mouseX, my = Kit.mouseY,
          camX = S.worldCamX, camY = S.worldCamY,
        }
      end
    elseif S._worldDrag and S._worldDrag.kind == "pan" then
      local d = S._worldDrag
      local z = S.worldZoom
      S.worldCamX = d.camX - (Kit.mouseX - d.mx) / z
      S.worldCamY = d.camY - (Kit.mouseY - d.my) / z
    end
  else
    S._worldDrag = nil
  end

  Kit.pushClip(viewX, viewY, viewW, viewH)
  Theme.col(PAL.bgBot, 1)
  love.graphics.rectangle("fill", viewX, viewY, viewW, viewH)

  local z = S.worldZoom
  love.graphics.push()
  love.graphics.translate(viewX, viewY)
  love.graphics.scale(z, z)
  love.graphics.translate(-S.worldCamX, -S.worldCamY)

  -- Draw real map tile bodies (not placeholder boxes).
  for id, p in pairs(layout.positions) do
    local def = layout.maps[id] or resolveMapDef(S, id)
    local sel = S.mapId == id
    if def then
      prepareLiveMap(S, id, def)
      local ok, loaded = pcall(MapLoader.load, S.data, id)
      if ok and loaded and loaded.renderer and loaded.renderer.drawMapOnly then
        love.graphics.push()
        love.graphics.translate(p.x, p.y)
        local pal = mapPreviewPalette(S, def)
        local shaded = pal and Preview.pushPaletteShader(S, pal)
        love.graphics.setColor(1, 1, 1, sel and 1 or 0.92)
        -- Full map body in local space; cam 0,0 shows the whole sheet.
        loaded.renderer:drawMapOnly(0, 0, p.w, p.h)
        Preview.popPaletteShader(shaded)
        love.graphics.pop()
      else
        Theme.col(PAL.rowBg, 0.9)
        love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
      end
    else
      Theme.col(PAL.rowBg, 0.9)
      love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
    end
    Theme.stroke(p.x, p.y, p.w, p.h, 2,
      sel and PAL.green or PAL.cardBorder,
      sel and 0.95 or 0.4, sel and 3 or 1.5)
  end

  -- Connection lines on top of maps.
  if love.graphics.setLineWidth then love.graphics.setLineWidth(2) end
  for _, e in ipairs(layout.edges) do
    local a = layout.positions[e.from]
    local b = layout.positions[e.to]
    if a then
      local x1 = a.x + a.w * 0.5
      local y1 = a.y + a.h * 0.5
      local x2, y2
      if b then
        x2 = b.x + b.w * 0.5
        y2 = b.y + b.h * 0.5
        Theme.col(e.ok and PAL.blue or PAL.red, e.ok and 0.65 or 0.85)
      else
        local stub = 48
        x2, y2 = x1, y1
        if e.dir == "north" then y2 = a.y - stub
        elseif e.dir == "south" then y2 = a.y + a.h + stub
        elseif e.dir == "west" then x2 = a.x - stub
        else x2 = a.x + a.w + stub end
        Theme.col(PAL.red, 0.85)
      end
      if love.graphics.line then
        love.graphics.line(x1, y1, x2, y2)
      end
    end
  end

  love.graphics.pop()

  -- Screen-space labels along the top edge of each map.
  for id, p in pairs(layout.positions) do
    local sx = viewX + (p.x - S.worldCamX) * z
    local sy = viewY + (p.y - S.worldCamY) * z
    local sw = p.w * z
    local sh = p.h * z
    local sel = S.mapId == id
    if sel or (sw >= 40 * s and sh >= 16 * s) then
      local label = id
      local maxW = math.max(12 * s, sw - 6 * s)
      if Kit.textWidth("micro", label) > maxW then
        label = Kit.ellipsize("micro", label, maxW)
      end
      local tw = Kit.textWidth("micro", label)
      local tx = sx + (sw - tw) * 0.5
      local ty = sy + 3 * s
      Theme.col(PAL.bgBot, sel and 0.85 or 0.65)
      love.graphics.rectangle("fill", tx - 3 * s, ty - 1 * s,
        tw + 6 * s, 12 * s, 3, 3)
      Kit.text("micro", label, tx, ty, sel and PAL.green or PAL.text)
    end
  end

  Kit.popClip()

  Kit.text("micro", "drag empty / MMB / hold WASD to pan · click map · wheel zoom",
    viewX + 6 * s, viewY + viewH - 16 * s, PAL.faint)

  -- Side panel: connections for the selected map
  local px = vx + canvasW + 12 * s
  local py = vy
  local map, owned = resolveMapDef(S, S.mapId)
  local title = (S.mapId or "?") .. (owned and "" or " (vanilla)")
  Kit.caption(px, py - 18 * s, Kit.ellipsize("caption", title, propW))
  Kit.card(px, py, propW, canvasH, 12 * s)

  local fh = 26 * s
  local y = py + 10 * s
  Kit.text("micro", "MAP CONNECTIONS", px + 10 * s, y, PAL.caption)
  y = y + 18 * s
  Kit.text("micro", "Current map and its N/S/E/W neighbors.",
    px + 10 * s, y, PAL.faint)
  y = y + 22 * s

  if Kit.button(px + 10 * s, y, propW - 20 * s, 28 * s, "Fit", {
      kind = "ghost", tooltip = "Zoom to this map and its neighbors",
    }) then
    fitWorldCamera(S, layout, viewW, viewH)
  end
  y = y + 34 * s
  if Kit.button(px + 10 * s, y, propW - 20 * s, 28 * s, "Open in Editor", {
      kind = "accent", tooltip = "Edit blocks / warps for the selected map",
    }) then
    S.mapViewMode = "editor"
    S._mapCenteredFor = nil
  end
  y = y + 40 * s

  if not map then
    Kit.text("micro", "Select a map in the list or graph.",
      px + 10 * s, y, PAL.muted)
    return
  end

  local function mutate()
    map = ensureOwned(S, S.mapId)
    owned = true
    return map
  end

  Kit.text("micro", "Connections (auto two-way)", px + 10 * s, y, PAL.caption)
  y = y + 16 * s
  map.connections = map.connections or {}
  local fromId = map.id or S.mapId
  local listBottom = py + canvasH - 16 * s
  for _, dir in ipairs({ "north", "south", "east", "west" }) do
    if y + fh > listBottom then break end
    local cur = map.connections[dir]
    local val = cur and cur.map or ""
    local v = field(App, "mp_wc_" .. dir, px + 10 * s, y, propW - 20 * s, fh,
      val, dir)
    local wantMap = (v == "") and nil or v:upper():gsub("%s+", "_")
    local curMap = cur and cur.map or ""
    local curOff = cur and (cur.offset or 0) or 0
    if (curMap or "") ~= (wantMap or "") then
      map = applyConnectionEdit(S, fromId, dir, wantMap, curOff, App,
        { world = true }) or mutate()
      owned = true
    end
    if wantMap and map.connections and map.connections[dir] then
      local off = tonumber(field(App, "mp_wco_" .. dir,
        px + 10 * s, y + fh + 2 * s, 60 * s, fh - 4 * s,
        tostring(map.connections[dir].offset or 0), "0")) or 0
      if off ~= (map.connections[dir].offset or 0) then
        map = applyConnectionEdit(S, fromId, dir, wantMap, off, App,
          { world = true }) or mutate()
        owned = true
      end
      Kit.text("micro", "offset", px + 78 * s, y + fh + 6 * s, PAL.faint)
      local destDef = resolveMapDef(S, wantMap)
      local back = destDef and destDef.connections
        and destDef.connections[oppositeDir(dir)]
      local ok = back and back.map == fromId
        and (back.offset or 0) == -(map.connections[dir].offset or 0)
      local known = layout.positions[wantMap] ~= nil or destDef ~= nil
      local label = ok and "<-> linked"
        or (known and "<-> pending" or "missing")
      Kit.text("micro", label,
        px + 120 * s, y + fh + 6 * s, ok and PAL.green or PAL.red)
      y = y + fh + 2 * s
    end
    y = y + fh + 4 * s
  end
end

local function centerOn(S, cx, cy)
  local vw = S._mapViewW or 480
  local vh = S._mapViewH or 432
  local z = S.mapZoom or 2
  S.mapCamX = cx * CELL - vw / (2 * z)
  S.mapCamY = cy * CELL - vh / (2 * z)
end

local function fitMap(S, map)
  local vw = math.max(1, S._mapViewW or 480)
  local vh = math.max(1, S._mapViewH or 432)
  local mapW = math.max(1, map.widthCells * CELL)
  local mapH = math.max(1, map.heightCells * CELL)
  local pad = 24
  local z = math.min((vw - pad) / mapW, (vh - pad) / mapH)
  S.mapZoom = clampZoom(z)
  centerOn(S, map.widthCells / 2, map.heightCells / 2)
  S._mapCenteredFor = S.mapId
end

-- Project stores mod-relative paths (assets/…). MapLoader/Assets load via
-- love.filesystem, so the live copy must use mods/<id>/assets/… (or the
-- equivalent under getSource()). Never mutate the project record — Save
-- must keep emitting assets/… + rewriteModPaths.
-- Vanilla ROM-cache paths (assets/generated/…) stay at the game/save root;
-- prefixing them with mods/<id>/ looks for a file that was never copied.
local function lovePathForModAsset(S, rel)
  if type(rel) ~= "string" or rel == "" then return rel end
  if rel:match("^mods/") or rel:match("^save/") then return rel end
  if rel:sub(1, #"assets/generated/") == "assets/generated/" then
    return rel
  end
  if not (S and S.path) then return rel end
  if not (rel:sub(1, 7) == "assets/" or rel:sub(1, 9) == "tilesets/") then
    return rel
  end
  local function norm(p)
    return (p or ""):gsub("\\", "/"):gsub("/+$", "")
  end
  local root = love and love.filesystem and love.filesystem.getSource
    and love.filesystem.getSource()
  local modN, rootN = norm(S.path), norm(root)
  local prefix
  if rootN ~= "" and modN:lower():sub(1, #rootN) == rootN:lower()
      and (modN == rootN or modN:sub(#rootN + 1, #rootN + 1) == "/") then
    prefix = modN:sub(#rootN + 2)
  else
    prefix = "mods/" .. (modN:match("([^/]+)$") or "mod")
  end
  if prefix == "" then prefix = "mods/mod" end
  return (prefix .. "/" .. rel):gsub("/+", "/")
end

local function liveTilesetForEditor(S, ts)
  if type(ts) ~= "table" then return ts end
  local lovePath = lovePathForModAsset(S, ts.image)
  if lovePath == ts.image then return ts end
  -- Stable per-project-tileset wrapper so we do not rebuild every frame.
  S._liveTilesets = S._liveTilesets or {}
  local live = S._liveTilesets[ts]
  if not live then
    live = {}
    S._liveTilesets[ts] = live
  end
  for k, v in pairs(ts) do
    if k ~= "image" then live[k] = v end
  end
  live.image = lovePath
  return live
end

local function clearTilesetThumbCache()
  for k in pairs(quadCache) do quadCache[k] = nil end
end

-- Import a PNG into assets/tilesets/.  opts.createNew registers a new tileset;
-- otherwise replaces the image on tilesetId.
local function importTilesetPng(S, App, tilesetId, opts)
  opts = opts or {}
  App.pickFile("Tileset PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
    function(picked)
      State.ensureProjectFields(S.project)
      local base = App.assetBaseName(picked, "tiles.png")
      if not base:lower():match("%.png$") then
        base = base .. ".png"
      end
      local dest = "assets/tilesets/" .. base
      App.importToMod(picked, dest, function(rel)
        local id = tilesetId
        if opts.createNew or not id or id == "" then
          local stem = base:gsub("%.[Pp][Nn][Gg]$", ""):gsub("[^%w_]", "_"):upper()
          if stem == "" then stem = "MOD_TILES" end
          id = stem
          local n = 1
          while (S.project.tilesets and S.project.tilesets[id])
              or (S.data and S.data.tilesets and S.data.tilesets[id]) do
            n = n + 1
            id = stem .. "_" .. n
          end
        end
        local e = S.project.tilesets[id]
        if not e then
          e = {
            id = id,
            image = rel,
            tilesPerRow = 16,
            blocks = {},
            walkable = {},
            doorTiles = {},
            warpTiles = {},
            counterTiles = {},
            animation = "TILEANIM_NONE",
            _isNew = true,
          }
          S.project.tilesets[id] = e
        else
          e.image = rel
          if e._isNew == nil then e._isNew = true end
        end
        Preview.invalidatePath(rel)
        local img = Preview.image(S, rel)
        if img then
          e.imageWidth = img:getWidth()
          e.imageHeight = img:getHeight()
          local needBlocks = opts.createNew or opts.rebuildBlocks
            or not e.blocks or #e.blocks == 0
          if needBlocks then
            local tw = math.max(1, math.floor(e.imageWidth / 8))
            local th = math.max(1, math.floor(e.imageHeight / 8))
            local tileCount = tw * th
            local nBlocks = math.max(1, math.floor(tileCount / 16))
            local blocks = {}
            for b = 0, nBlocks - 1 do
              local row = {}
              for i = 0, 15 do row[i + 1] = b * 16 + i end
              blocks[b + 1] = row
            end
            e.blocks = blocks
            e.tilesPerRow = 16
          end
        end
        S._liveTilesets = nil
        if S.data and S.data.tilesets then
          S.data.tilesets[id] = liveTilesetForEditor(S, e)
        end
        clearTilesetThumbCache()
        S.tilesetEditId = id
        if S.mapTilesetPicker then S.mapTilesetPicker.focus = id end
        if S.mapId then
          MapLoader.invalidate(S.mapId)
          S._mapNeedsRebuild = S.mapId
        end
        App.markDirty()
        S.status = (opts.createNew and "Imported tileset " or "Tileset image → ")
          .. id .. " (" .. rel .. ")"
      end)
    end)
end

prepareLiveMap = function(S, mapId, def)
  if not (S.data and mapId and def) then return end
  for tid, ts in pairs(S.project.tilesets or {}) do
    -- Keep a pristine ROM copy before project tilesets overwrite live data
    -- (needed so Save can diff terrain flags without dumping water anims).
    S._vanillaTilesetBackup = S._vanillaTilesetBackup or {}
    local cur = S.data.tilesets and S.data.tilesets[tid]
    if not S._vanillaTilesetBackup[tid] and type(cur) == "table" and cur ~= ts then
      S._vanillaTilesetBackup[tid] = cloneTilesetRecord(cur)
    end
    local live = liveTilesetForEditor(S, ts)
    local prev = S.data.tilesets[tid]
    if prev ~= live or (prev and prev.image ~= live.image) then
      MapLoader.invalidate(mapId)
    end
    S.data.tilesets[tid] = live
  end
  if S.data.maps[mapId] ~= def then
    if S.project.maps[mapId] == def then
      S._vanillaMapBackup = S._vanillaMapBackup or {}
      if S.data.maps[mapId] and not S._vanillaMapBackup[mapId] then
        S._vanillaMapBackup[mapId] = S.data.maps[mapId]
      end
    end
    S.data.maps[mapId] = def
    MapLoader.invalidate(mapId)
  end
  if S._mapNeedsRebuild == mapId then
    MapLoader.invalidate(mapId)
    S._mapNeedsRebuild = nil
  end
end

-- Direct N/S/E/W neighbors for the map preview (same offsets as the game).
local function editorNeighbors(S, rootDef)
  local out = {}
  if not rootDef then return out end
  for dir, conn in pairs(rootDef.connections or {}) do
    local dest = conn and conn.map
    local destDef = dest and resolveMapDef(S, dest)
    if destDef and type(destDef.width) == "number"
        and type(destDef.height) == "number" then
      local ox, oy = worldConnDelta(dir, conn.offset, rootDef, destDef)
      out[#out + 1] = { id = dest, def = destDef, ox = ox, oy = oy, dir = dir }
    end
  end
  return out
end

local function facingFromRange(range)
  if range == "UP" then return "up" end
  if range == "LEFT" then return "left" end
  if range == "RIGHT" then return "right" end
  return "down"
end

local function getSpriteRenderer(S, spriteId)
  if type(spriteId) ~= "string" or spriteId == "" then return nil end
  if spriteCache[spriteId] ~= nil then
    return spriteCache[spriteId] or nil
  end
  local def = spriteDef(S, spriteId)
  if not def then
    spriteCache[spriteId] = false
    return nil
  end
  local ok, sr = pcall(SpriteRenderer.new, def, spriteId)
  spriteCache[spriteId] = (ok and sr) or false
  return ok and sr or nil
end

local function clearWarpDestPick(S, status)
  if not S.warpDestPick then return end
  S.warpDestPick = nil
  if status then S.status = status end
end

local function armWarpDestPick(S, mapId, warpIndex)
  if not mapId or not warpIndex then return end
  S.warpDestPick = { sourceMapId = mapId, sourceWarpIndex = warpIndex }
  S.status = string.format(
    "Set dest for %s#%d — switch maps, click cell (Esc cancel)",
    tostring(mapId), warpIndex)
end

-- Nearest warp within manhattan threshold; nil if none.
local function nearestWarpIndex(warps, cx, cy, maxD)
  maxD = maxD or 1
  local best, bestD = nil, maxD + 0.01
  for i, w in ipairs(warps or {}) do
    local d = math.abs((w.x or 0) - cx) + math.abs((w.y or 0) - cy)
    if d < bestD then best, bestD = i, d end
  end
  return best
end

local function applyWarpDestPick(S, mapDef, cx, cy, App)
  local pick = S.warpDestPick
  if not pick then return false end
  local srcId = pick.sourceMapId
  local srcIdx = pick.sourceWarpIndex
  local destId = mapDef.id or S.mapId
  local destMap = ensureOwned(S, destId)
  if not destMap then
    clearWarpDestPick(S, "Set destination failed: no destination map")
    return true
  end
  local srcMap = ensureOwned(S, srcId)
  if not srcMap or not srcMap.warps or not srcMap.warps[srcIdx] then
    clearWarpDestPick(S, "Set destination cancelled: source warp missing")
    return true
  end

  destMap.warps = destMap.warps or {}
  local destIdx = nearestWarpIndex(destMap.warps, cx, cy, 1)
  if not destIdx then
    destIdx = #destMap.warps + 1
    destMap.warps[destIdx] = {
      x = cx, y = cy, destMap = "LAST_MAP", destWarp = 1,
    }
  end

  srcMap.warps[srcIdx].destMap = destId
  srcMap.warps[srcIdx].destWarp = destIdx
  S.data.maps[srcId] = srcMap
  S.data.maps[destId] = destMap
  MapLoader.invalidate(srcId)
  MapLoader.invalidate(destId)

  S.mapSection = "warps"
  S.mapWarpIndex = destIdx
  clearWarpDestPick(S, string.format("Linked %s#%d → %s#%d",
    tostring(srcId), srcIdx, tostring(destId), destIdx))
  App.markDirty()
  return true
end

local function applyToolAtCell(S, mapDef, cx, cy, App)
  if cx < 0 or cy < 0 or cx >= mapDef.width * 2 or cy >= mapDef.height * 2 then
    return
  end
  if S.warpDestPick then
    applyWarpDestPick(S, mapDef, cx, cy, App)
    return
  end
  local owned = ensureOwned(S, mapDef.id or S.mapId)
  if not owned then return end
  mapDef = owned
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local idx = by * mapDef.width + bx + 1
  local tool = S.mapTool or "paint"

  if tool == "pick" then
    S.mapEditMode = "map"
    S.paintBlock = mapDef.blocks[idx] or 0
    S.mapTool = "paint"
    S.mapPaletteTileset = mapDef.tileset
    S.status = string.format("Picked block %s (tileset=%s) -- Pencil armed",
      tostring(S.paintBlock), tostring(mapDef.tileset))
    return
  elseif tool == "paint" then
    S.mapEditMode = "map"
    local bid = S.paintBlock or 1
    if mapDef.blocks[idx] ~= bid then
      mapDef.blocks[idx] = bid
      S._mapNeedsRebuild = mapDef.id
    else
      return
    end
  elseif tool == "erase" then
    S.mapEditMode = "map"
    if mapDef.blocks[idx] ~= 0 then
      mapDef.blocks[idx] = 0
      S._mapNeedsRebuild = mapDef.id
    else
      return
    end
  elseif tool == "collision" then
    S.mapEditMode = "map"
    -- Passage flags on this map's tileset slot (auto-clones shared stock).
    local ts = ensureTerrainTileset(S, mapDef, App)
    local tid = mapDef.tileset
    if not ts then
      S.status = "No tileset for Passage paint (Import ROM / Link Recomp?)"
      return
    end
    local tile = Map.defCellTile(mapDef, ts, cx, cy)
    if tile == nil then
      S.status = "No tile at cell"
      return
    end
    ts.walkable = ts.walkable or {}
    ts.waterTiles = ts.waterTiles or {}
    ts.shoreTiles = ts.shoreTiles or {}
    -- Set modes (not toggle): brush-drag must not flip while dragging.
    -- "none" clears grass/water/shore on this feet tile.
    local mode = S.mapCollisionMode or "solid"
    local label = mode
    if mode == "walk" or mode == "solid" or mode == "toggle" then
      local was = listIndex(ts.walkable, tile) ~= nil
      local want = (mode == "walk") or (mode == "toggle" and not was)
      if mode == "solid" then want = false end
      if want == was then return end
      listSet(ts.walkable, tile, want)
      label = want and "walk" or "solid"
    elseif mode == "water" then
      if listIndex(ts.waterTiles, tile) then return end
      listSet(ts.waterTiles, tile, true)
      listSet(ts.walkable, tile, false)
      label = "water"
    elseif mode == "shore" then
      if listIndex(ts.shoreTiles, tile) then return end
      listSet(ts.shoreTiles, tile, true)
      label = "shore"
    elseif mode == "grass" then
      if ts.grassTile == tile then return end
      ts.grassTile = tile
      listSet(ts.walkable, tile, true)
      label = "grass"
    elseif mode == "ledge" then
      -- Click the ledge cell; standing tile is the neighbor behind the hop.
      local dir = S.mapLedgeDir or "down"
      local off = LEDGE_BEHIND[dir] or LEDGE_BEHIND.down
      local sx, sy = cx + off[1], cy + off[2]
      local standing = Map.defCellTile(mapDef, ts, sx, sy)
      if standing == nil then
        S.status = "Ledge needs a standing tile behind the hop (off-map?)"
        return
      end
      State.ensureProjectFields(S.project)
      ensureLedgeBackup(S)
      S.project.ledges = S.project.ledges or {}
      for _, row in ipairs(S.project.ledges) do
        if ledgeRuleMatches(row, tid, tile, standing, dir) then
          S.status = string.format("Ledge already set (stand %d → %s → %d)",
            standing, dir, tile)
          return
        end
      end
      local rule = {
        facing = dir, input = dir,
        standingTile = standing, ledgeTile = tile,
      }
      if tid and tid ~= "OVERWORLD" then rule.tileset = tid end
      S.project.ledges[#S.project.ledges + 1] = rule
      rebuildLiveLedges(S)
      App.markDirty()
      S.mapShowCollision = true
      S.status = string.format("Ledge %s: stand tile %d → ledge %d (%s)",
        dir, standing, tile, tostring(tid))
      return
    elseif mode == "none" then
      local changed = false
      if ts.grassTile == tile then
        ts.grassTile = nil
        changed = true
      end
      if listIndex(ts.waterTiles, tile) then
        listSet(ts.waterTiles, tile, false)
        changed = true
      end
      if listIndex(ts.shoreTiles, tile) then
        listSet(ts.shoreTiles, tile, false)
        changed = true
      end
      State.ensureProjectFields(S.project)
      local kept = {}
      for _, row in ipairs(S.project.ledges or {}) do
        local hit = ledgeRuleMatches(row, tid, tile, nil, nil)
          or ledgeRuleMatches(row, tid, nil, tile, nil)
        if hit then
          changed = true
        else
          kept[#kept + 1] = row
        end
      end
      if #kept ~= #(S.project.ledges or {}) then
        S.project.ledges = kept
        rebuildLiveLedges(S)
      end
      if not changed then return end
      label = "none"
    else
      return
    end
    if S.data and S.data.tilesets then S.data.tilesets[tid] = ts end
    S._liveTilesets = nil
    MapLoader.invalidateAll()
    App.markDirty()
    S.mapShowCollision = true
    -- Passage is per tileset slot (RPG Maker style), not per map cell.
    S.status = string.format(
      "Tile %d → %s (tileset %s)",
      tile, label, tostring(tid))
    return
  elseif tool == "warp" then
    S.mapEditMode = "events"
    clearWarpDestPick(S)
    mapDef.warps = mapDef.warps or {}
    mapDef.warps[#mapDef.warps + 1] = {
      x = cx, y = cy, destMap = "PALLET_TOWN", destWarp = 1,
    }
    S.mapSection = "warps"
    S.mapWarpIndex = #mapDef.warps
    local ts = tilesetDef(S, mapDef.tileset)
    local tile = ts and Map.defCellTile(mapDef, ts, cx, cy)
    local onWarpTile = false
    if tile ~= nil and ts then
      onWarpTile = listIndex(ts.doorTiles or {}, tile) ~= nil
        or listIndex(ts.warpTiles or {}, tile) ~= nil
    end
    if onWarpTile then
      S.status = string.format("Warp at cell (%d,%d)", cx, cy)
    else
      S.status = string.format(
        "Warp at (%d,%d) — not a door/warp tile; Gen1 only fires at map edge / carpet",
        cx, cy)
    end
  elseif tool == "sign" then
    S.mapEditMode = "events"
    mapDef.signs = mapDef.signs or {}
    local n = #mapDef.signs + 1
    local textId = "TEXT_" .. (mapDef.id or "MAP") .. "_SIGN" .. n
    mapDef.signs[n] = { x = cx, y = cy, text = textId }
    S.mapSection = "signs"
    S.mapSignIndex = n
    S.dialogMapId = mapDef.id
    S.dialogTextId = textId
  elseif tool == "object" then
    S.mapEditMode = "events"
    mapDef.objects = mapDef.objects or {}
    local n = #mapDef.objects + 1
    local textId = "TEXT_" .. (mapDef.id or "MAP") .. "_OBJ" .. n
    local spr = S.placeSprite or "SPRITE_RED"
    mapDef.objects[n] = {
      index = n, x = cx, y = cy,
      sprite = spr, movement = "STAY", range = "DOWN", text = textId,
    }
    S.mapSection = "objects"
    S.mapObjectIndex = n
    S.dialogMapId = mapDef.id
    S.dialogTextId = textId
    S.status = "Placed " .. spr
  elseif tool == "trainer" then
    S.mapEditMode = "events"
    mapDef.objects = mapDef.objects or {}
    local n = #mapDef.objects + 1
    local class = (S.trainerId and S.trainerId ~= "" and S.trainerId)
      or "OPP_YOUNGSTER"
    local party = math.max(1, tonumber(S.placeTrainerParty) or 1)
    local textId = "TEXT_" .. (mapDef.id or "MAP") .. "_TRAINER" .. n
    local spr = S.placeSprite or "SPRITE_YOUNGSTER"
    mapDef.objects[n] = {
      index = n, x = cx, y = cy,
      sprite = spr, movement = "STAY", range = "DOWN",
      text = textId,
      trainerClass = class, trainerParty = party,
    }
    State.ensureProjectFields(S.project)
    local label = State.mapLabel(S, mapDef.id)
    S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
    local beat = State.modFlag(S.project,
      "BEAT_" .. (mapDef.id or "MAP") .. "_" .. n)
    S.project.eventFlags = S.project.eventFlags or {}
    S.project.eventFlags[beat] = true
    S.project.trainer_headers[label][n] = {
      range = 2,
      battle = "_" .. (mapDef.id or "MAP") .. "Trainer" .. n .. "Battle",
      won = "_" .. (mapDef.id or "MAP") .. "Trainer" .. n .. "Won",
      after = "_" .. (mapDef.id or "MAP") .. "Trainer" .. n .. "After",
      event = beat,
      opponent = class,
      party = party,
    }
    for _, key in ipairs({ "battle", "won", "after" }) do
      local tid = S.project.trainer_headers[label][n][key]
      S.project.text[tid] = S.project.text[tid]
        or (key == "battle" and "Let's fight!")
        or (key == "won" and "I lost...")
        or "You're strong."
    end
    S.mapSection = "objects"
    S.mapObjectIndex = n
    S.status = string.format("Placed %s party %d as object #%d",
      class, party, n)
  elseif tool == "wild" then
    S.mapEditMode = "events"
    -- Fixed wild (object.pokemon + level): Articuno, Power Plant Voltorb, …
    mapDef.objects = mapDef.objects or {}
    local n = #mapDef.objects + 1
    local species = (S.placeWildSpecies and S.placeWildSpecies ~= ""
      and S.placeWildSpecies) or "ARTICUNO"
    local level = math.max(1, math.min(100, tonumber(S.placeWildLevel) or 50))
    local textId = "TEXT_" .. (mapDef.id or "MAP") .. "_WILD" .. n
    local spr = S.placeSprite or "SPRITE_BIRD"
    mapDef.objects[n] = {
      index = n, x = cx, y = cy,
      sprite = spr, movement = "STAY", range = "DOWN",
      text = textId,
      pokemon = species, level = level,
    }
    State.ensureProjectFields(S.project)
    local cry = "_" .. (mapDef.id or "MAP") .. "Wild" .. n
    local entry = ensureTextPtr(S, mapDef.id, textId)
    if entry then entry.text = cry end
    S.project.text[cry] = S.project.text[cry] or "Gyaoo!"
    S.mapSection = "objects"
    S.mapObjectIndex = n
    S.status = string.format("Placed wild %s Lv%d as object #%d",
      species, level, n)
  elseif tool == "select" then
    -- pick nearest object / warp / sign
    local best, bestD, kind = nil, 2.5, nil
    for i, obj in ipairs(mapDef.objects or {}) do
      local d = math.abs(obj.x - cx) + math.abs(obj.y - cy)
      if d < bestD then best, bestD, kind = i, d, "object" end
    end
    for i, w in ipairs(mapDef.warps or {}) do
      local d = math.abs(w.x - cx) + math.abs(w.y - cy)
      if d < bestD then best, bestD, kind = i, d, "warp" end
    end
    for i, sign in ipairs(mapDef.signs or {}) do
      local d = math.abs(sign.x - cx) + math.abs(sign.y - cy)
      if d < bestD then best, bestD, kind = i, d, "sign" end
    end
    if kind == "object" then
      S.mapEditMode = "events"
      S.mapSection = "objects"; S.mapObjectIndex = best
    elseif kind == "warp" then
      S.mapEditMode = "events"
      S.mapSection = "warps"; S.mapWarpIndex = best
    elseif kind == "sign" then
      S.mapEditMode = "events"
      S.mapSection = "signs"; S.mapSignIndex = best
    end
  end

  S.data.maps[mapDef.id] = mapDef
  MapLoader.invalidate(mapDef.id)
  App.markDirty()
end

local function drawObjectSprites(S, mapDef)
  local camX, camY = S.mapCamX or 0, S.mapCamY or 0
  love.graphics.setColor(1, 1, 1, 1)
  for i, obj in ipairs(mapDef.objects or {}) do
    if not obj.hidden then
      local sr = getSpriteRenderer(S, obj.sprite)
      local px, py = (obj.x or 0) * CELL, (obj.y or 0) * CELL
      if sr then
        local ok = pcall(sr.draw, sr, px, py, camX, camY,
          facingFromRange(obj.range), 0, false)
        if not ok then
          local def = spriteDef(S, obj.sprite)
          if def and def.image then
            Preview.draw(S, def.image, px - camX, py - camY - 4, CELL, CELL,
              spritePreviewPal(S, def))
          end
        end
      else
        love.graphics.setColor(0.3, 0.9, 0.45, 0.85)
        love.graphics.rectangle("fill",
          px - camX + 2, py - camY + 2, CELL - 4, CELL - 4)
        love.graphics.setColor(1, 1, 1, 1)
      end
      if obj.pokemon and obj.pokemon ~= "" then
        -- Fixed wild marker (distinct from NPC / trainer outlines).
        love.graphics.setColor(0.95, 0.45, 0.2, 0.9)
        love.graphics.rectangle("line",
          px - camX, py - camY - 4, CELL, CELL)
        love.graphics.setColor(1, 1, 1, 1)
      elseif obj.trainerClass and obj.trainerClass ~= "" then
        love.graphics.setColor(0.95, 0.25, 0.3, 0.9)
        love.graphics.rectangle("line",
          px - camX, py - camY - 4, CELL, CELL)
        love.graphics.setColor(1, 1, 1, 1)
      end
      if S.mapObjectIndex == i and S.mapSection == "objects" then
        love.graphics.setColor(1, 0.85, 0.15, 0.9)
        love.graphics.rectangle("line",
          px - camX - 1, py - camY - 5, CELL + 2, CELL + 2)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end
end

-- Screen-space (x,y) labels for objects / warps / signs (drawn after map zoom pop).
local function drawMapCoordLabels(S, mapDef, vx, vy, vw, vh)
  local z = S.mapZoom or 2
  local camX, camY = S.mapCamX or 0, S.mapCamY or 0
  local s = Kit.scale
  local function inView(sx, sy)
    return sx > vx - 40 * s and sy > vy - 20 * s
      and sx < vx + vw + 8 * s and sy < vy + vh + 8 * s
  end
  local function labelAt(cx, cy, text, col)
    local sx = vx + ((cx or 0) * CELL - camX) * z
    local sy = vy + ((cy or 0) * CELL - camY) * z - 11 * s
    if not inView(sx, sy) then return end
    Kit.text("micro", text, sx, sy, col or PAL.heading)
  end
  for i, obj in ipairs(mapDef.objects or {}) do
    if not obj.hidden then
      local selected = S.mapObjectIndex == i and S.mapSection == "objects"
      labelAt(obj.x, obj.y,
        string.format("%d,%d", obj.x or 0, obj.y or 0),
        selected and PAL.yellow or PAL.heading)
    end
  end
  for i, w in ipairs(mapDef.warps or {}) do
    local selected = S.mapWarpIndex == i and S.mapSection == "warps"
    labelAt(w.x, w.y,
      string.format("%d,%d", w.x or 0, w.y or 0),
      selected and PAL.blue or PAL.muted)
  end
  for i, sign in ipairs(mapDef.signs or {}) do
    local selected = S.mapSignIndex == i and S.mapSection == "signs"
    labelAt(sign.x, sign.y,
      string.format("%d,%d", sign.x or 0, sign.y or 0),
      selected and PAL.yellow or PAL.muted)
  end
end

local function drawMarkerOverlays(S, mapDef)
  local camX, camY = S.mapCamX or 0, S.mapCamY or 0
  local function cellRect(cx, cy)
    return cx * CELL - camX, cy * CELL - camY, CELL, CELL
  end
  love.graphics.setColor(0.27, 0.59, 1, 0.55)
  for i, w in ipairs(mapDef.warps or {}) do
    love.graphics.rectangle("line", cellRect(w.x, w.y))
    if S.mapWarpIndex == i and S.mapSection == "warps" then
      love.graphics.setColor(0.27, 0.59, 1, 0.9)
      love.graphics.rectangle("fill", cellRect(w.x, w.y))
      love.graphics.setColor(0.27, 0.59, 1, 0.55)
    end
  end
  love.graphics.setColor(1, 0.85, 0.15, 0.7)
  for i, sign in ipairs(mapDef.signs or {}) do
    love.graphics.rectangle("line", cellRect(sign.x, sign.y))
    if S.mapSignIndex == i and S.mapSection == "signs" then
      love.graphics.setColor(1, 0.85, 0.15, 0.35)
      love.graphics.rectangle("fill", cellRect(sign.x, sign.y))
      love.graphics.setColor(1, 0.85, 0.15, 0.7)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  drawObjectSprites(S, mapDef)
end

local function drawGridOverlay(S, mapDef)
  if not S.mapShowGrid then return end
  local camX, camY = S.mapCamX or 0, S.mapCamY or 0
  local vw = (S._mapViewW or 480) / (S.mapZoom or 2)
  local vh = (S._mapViewH or 432) / (S.mapZoom or 2)
  local mw = (tonumber(mapDef.width) or 0) * BLOCK_PX
  local mh = (tonumber(mapDef.height) or 0) * BLOCK_PX
  if mw <= 0 or mh <= 0 then return end

  -- One line per paint block (32px) — not per walk cell (16px).
  local x0 = math.max(0, math.floor(camX / BLOCK_PX) * BLOCK_PX)
  local y0 = math.max(0, math.floor(camY / BLOCK_PX) * BLOCK_PX)
  local x1 = math.min(mw, math.ceil((camX + vw) / BLOCK_PX) * BLOCK_PX)
  local y1 = math.min(mh, math.ceil((camY + vh) / BLOCK_PX) * BLOCK_PX)

  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.9)
  for x = x0, x1, BLOCK_PX do
    love.graphics.line(x - camX, y0 - camY, x - camX, y1 - camY)
  end
  for y = y0, y1, BLOCK_PX do
    love.graphics.line(x0 - camX, y - camY, x1 - camX, y - camY)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawCollisionOverlay(S, mapDef)
  if not S.mapShowCollision then return end
  local ts = tilesetDef(S, mapDef.tileset)
  if not ts then return end
  local camX, camY = S.mapCamX or 0, S.mapCamY or 0
  local vw = (S._mapViewW or 480) / (S.mapZoom or 2)
  local vh = (S._mapViewH or 432) / (S.mapZoom or 2)
  local x0 = math.max(0, math.floor(camX / CELL) - 1)
  local y0 = math.max(0, math.floor(camY / CELL) - 1)
  local x1 = math.min(mapDef.width * 2 - 1, math.ceil((camX + vw) / CELL) + 1)
  local y1 = math.min(mapDef.height * 2 - 1, math.ceil((camY + vh) / CELL) + 1)
  local shore = {}
  for _, t in ipairs(ts.shoreTiles or {}) do shore[t] = true end
  local grass = ts.grassTile
  -- Orange = ledge tile only. Vanilla standingTile values are often common
  -- walkable ground (paths/floors) — outlining them looked like "wild" zones.
  local ledgeTiles = {}
  local tsId = mapDef.tileset or "OVERWORLD"
  local ledges = (S.data and S.data.field and S.data.field.ledges) or {}
  for _, row in ipairs(ledges) do
    if type(row) == "table" and (row.tileset or "OVERWORLD") == tsId then
      if row.ledgeTile ~= nil then ledgeTiles[row.ledgeTile] = true end
    end
  end
  for cy = y0, y1 do
    for cx = x0, x1 do
      local tile = Map.defCellTile(mapDef, ts, cx, cy)
      local water = Map.defIsWaterCell(mapDef, ts, cx, cy)
      local walk = Map.defIsWalkableCell(mapDef, ts, cx, cy)
      if water then
        if tile ~= nil and shore[tile] then
          love.graphics.setColor(0.2, 0.85, 0.9, 0.32)
        else
          love.graphics.setColor(0.15, 0.45, 1, 0.32)
        end
        love.graphics.rectangle("fill",
          cx * CELL - camX, cy * CELL - camY, CELL, CELL)
      elseif not walk then
        love.graphics.setColor(1, 0.2, 0.2, 0.32)
        love.graphics.rectangle("fill",
          cx * CELL - camX, cy * CELL - camY, CELL, CELL)
      end
      if grass ~= nil and tile == grass then
        -- Magenta (not yellow/green) so tall grass reads on green tiles.
        love.graphics.setColor(0.95, 0.2, 0.85, 0.4)
        love.graphics.rectangle("fill",
          cx * CELL - camX, cy * CELL - camY, CELL, CELL)
        love.graphics.setColor(1, 0.35, 0.95, 1)
        love.graphics.rectangle("line",
          cx * CELL - camX + 1, cy * CELL - camY + 1, CELL - 2, CELL - 2)
      end
      if tile ~= nil and ledgeTiles[tile] then
        love.graphics.setColor(1, 0.55, 0.1, 0.4)
        love.graphics.rectangle("fill",
          cx * CELL - camX, cy * CELL - camY, CELL, CELL)
        love.graphics.setColor(1, 0.65, 0.15, 1)
        love.graphics.rectangle("line",
          cx * CELL - camX + 1, cy * CELL - camY + 1, CELL - 2, CELL - 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawMapPreview(S, mapDef, x, y, w, h, App)
  local s = Kit.scale
  S.mapZoom = clampZoom(S.mapZoom or 2)
  local pad = 8 * s
  local vx = x + pad
  local vy = y + pad
  local vw = math.max(0, w - 2 * pad)
  local vh = math.max(0, h - 2 * pad)
  S._mapViewW, S._mapViewH = vw, vh

  Theme.col(PAL.bgBot or PAL.card, 1)
  if vw > 0 and vh > 0 then
    local rr = math.min(8 * s, vw * 0.5, vh * 0.5)
    love.graphics.rectangle("fill", vx, vy, vw, vh, rr, rr)
  end
  if vw < 16 or vh < 16 then
    Kit.text("micro", "Widen map view", vx + 4 * s, vy + 4 * s, PAL.faint)
    return
  end

  prepareLiveMap(S, S.mapId, mapDef)
  local ok, map = pcall(MapLoader.load, S.data, S.mapId)
  if not ok then
    Kit.text("mono", "Failed to load map: " .. tostring(map),
      vx + 8 * s, vy + 8 * s, PAL.red)
    Kit.text("micro",
      "Project → Import ROM or Link Recomp so tilesets (e.g. OVERWORLD) load",
      vx + 8 * s, vy + 28 * s, PAL.faint)
    return
  end

  if S._mapCenteredFor ~= S.mapId then
    fitMap(S, map)
  end

  if love.graphics.push and vw > 0 and vh > 0 then
    love.graphics.setScissor(math.floor(vx), math.floor(vy),
      math.ceil(vw), math.ceil(vh))
    love.graphics.push()
    love.graphics.translate(vx, vy)
    love.graphics.scale(S.mapZoom, S.mapZoom)
    love.graphics.setColor(1, 1, 1, 1)
    local worldW = vw / S.mapZoom
    local worldH = vh / S.mapZoom
    local camX = S.mapCamX or 0
    local camY = S.mapCamY or 0

    -- Connected neighbors behind the current map (engine drawMapOnly path).
    if S.mapShowNeighbors ~= false then
      for _, nb in ipairs(editorNeighbors(S, mapDef)) do
        prepareLiveMap(S, nb.id, nb.def)
        local nok, nmap = pcall(MapLoader.load, S.data, nb.id)
        if nok and nmap and nmap.renderer and nmap.renderer.drawMapOnly then
          local nPal = mapPreviewPalette(S, nb.def)
          local nShaded = nPal and Preview.pushPaletteShader(S, nPal)
          love.graphics.setColor(1, 1, 1, 0.75)
          nmap.renderer:drawMapOnly(camX - nb.ox, camY - nb.oy, worldW, worldH)
          Preview.popPaletteShader(nShaded)
          love.graphics.setColor(0.27, 0.59, 1, 0.35)
          love.graphics.rectangle("line",
            nb.ox - camX, nb.oy - camY,
            (nmap.widthCells or nb.def.width * 2) * CELL,
            (nmap.heightCells or nb.def.height * 2) * CELL)
        end
      end
    end

    local palName = mapPreviewPalette(S, mapDef)
    local shaded = palName and Preview.pushPaletteShader(S, palName)
    love.graphics.setColor(1, 1, 1, 1)
    map.renderer:draw(camX, camY, worldW, worldH)
    Preview.popPaletteShader(shaded)
    love.graphics.setColor(1, 1, 1, 0.22)
    love.graphics.rectangle("line",
      - camX, - camY,
      map.widthCells * CELL, map.heightCells * CELL)
    drawGridOverlay(S, mapDef)
    drawCollisionOverlay(S, mapDef)
    drawMarkerOverlays(S, mapDef)
    drawSelectionOverlay(S, mapDef)
    love.graphics.pop()
    drawMapCoordLabels(S, mapDef, vx, vy, vw, vh)
    love.graphics.setScissor()
  end

  clampMapCam(S, mapDef)
  drawMapScrollbars(S, mapDef, vx, vy, vw, vh)

  local tool = S.mapTool or "paint"
  -- Dest pick is a single click; do not brush-drag while armed.
  local brush = (tool == "paint" or tool == "erase" or tool == "pick"
      or tool == "collision")
    and not S.warpDestPick
  local selecting = (tool == "select") and not S.warpDestPick
  local over = Kit.hit(vx, vy, vw, vh)
  -- Middle button / Space / Alt pan. Right-click copies the block (eyedropper).
  local rmb, mmb = false, false
  if love and love.mouse and love.mouse.isDown then
    rmb = love.mouse.isDown(2)
    mmb = love.mouse.isDown(3)
  end
  local spacePan = (not Kit.focus) and (
    love.keyboard.isDown("space")
    or love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt"))
  local auxPan = mmb
  local panHeld = (auxPan or spacePan)
    and not Kit.blockClicks
    and not Kit._suppressMouse
    and (over or (S._mapDrag and S._mapDrag.pan))

  local function mouseWorld()
    local z = S.mapZoom or 2
    local wx = (Kit.mouseX - vx) / z + (S.mapCamX or 0)
    local wy = (Kit.mouseY - vy) / z + (S.mapCamY or 0)
    return wx, wy
  end

  local function mouseBlock()
    local wx, wy = mouseWorld()
    return math.floor(wx / BLOCK_PX), math.floor(wy / BLOCK_PX)
  end

  local function mouseCell()
    local wx, wy = mouseWorld()
    return math.floor(wx / CELL), math.floor(wy / CELL)
  end

  -- Track hover for Ctrl+V paste destination + coord readout.
  if over then
    local hbx, hby = mouseBlock()
    local hcx, hcy = mouseCell()
    S._mapHoverBx, S._mapHoverBy = hbx, hby
    S._mapHoverCx, S._mapHoverCy = hcx, hcy
  else
    S._mapHoverCx, S._mapHoverCy = nil, nil
  end

  if over and rmb and not S._mapRmbWasDown and not Kit.blockClicks
      and not spacePan and not S.warpDestPick then
    local bx, by = mouseBlock()
    if bx >= 0 and by >= 0 and bx < (mapDef.width or 0)
        and by < (mapDef.height or 0) then
      local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
      if shift then
        local ok, msg = pasteClipAt(S, mapDef.id or S.mapId, bx, by, App)
        S.status = msg or (ok and "Pasted" or "Paste failed")
      else
        local bw, bh = copyBlocksToClip(S, mapDef, bx, by, bx, by)
        if tool == "pick" then S.mapTool = "paint" end
        if bw then
          S.status = string.format(
            "Copied block %s — Shift+RMB or Ctrl+V to paste",
            tostring(S.paintBlock))
        end
      end
    end
  end
  S._mapRmbWasDown = rmb

  if S._mapSbBlocking then
    -- Scrollbar owns this pointer; do not paint or free-pan underneath.
  elseif panHeld then
    S._mapSelDraft = nil
    local d = S._mapDrag
    if not d or not d.pan then
      S._mapDrag = {
        mx = Kit.mouseX, my = Kit.mouseY,
        camX = S.mapCamX or 0, camY = S.mapCamY or 0,
        pan = true,
      }
    else
      S.mapCamX = d.camX - (Kit.mouseX - d.mx) / S.mapZoom
      S.mapCamY = d.camY - (Kit.mouseY - d.my) / S.mapZoom
      clampMapCam(S, mapDef)
    end
  elseif Kit.mouseDown and not Kit.blockClicks and not Kit._suppressMouse
      and (S._mapDrag or over) then
    if brush and over then
      S._mapDrag = { brush = true }
      local z = S.mapZoom or 2
      local wx = (Kit.mouseX - vx) / z + (S.mapCamX or 0)
      local wy = (Kit.mouseY - vy) / z + (S.mapCamY or 0)
      local cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
      local key = cx .. "," .. cy
      if S._lastPaintCell ~= key then
        S._lastPaintCell = key
        applyToolAtCell(S, mapDef, cx, cy, App)
      end
    elseif selecting and over then
      local bx, by = mouseBlock()
      local d = S._mapDrag
      if not d or not d.marquee then
        S._mapDrag = {
          mx = Kit.mouseX, my = Kit.mouseY,
          camX = S.mapCamX or 0, camY = S.mapCamY or 0,
          marquee = true, moved = false,
          bx0 = bx, by0 = by,
        }
        S._mapSelDraft = { x0 = bx, y0 = by, x1 = bx, y1 = by }
      else
        local mdx = Kit.mouseX - d.mx
        local mdy = Kit.mouseY - d.my
        if math.abs(mdx) > 3 or math.abs(mdy) > 3 then
          d.moved = true
        end
        S._mapSelDraft = {
          x0 = d.bx0, y0 = d.by0, x1 = bx, y1 = by,
        }
      end
    else
      local d = S._mapDrag
      if not d then
        S._mapDrag = {
          mx = Kit.mouseX, my = Kit.mouseY,
          camX = S.mapCamX or 0, camY = S.mapCamY or 0,
          moved = false,
        }
      else
        local dx = Kit.mouseX - d.mx
        local dy = Kit.mouseY - d.my
        if math.abs(dx) > 3 or math.abs(dy) > 3 then
          d.moved = true
          S.mapCamX = d.camX - dx / S.mapZoom
          S.mapCamY = d.camY - dy / S.mapZoom
          clampMapCam(S, mapDef)
        end
      end
    end
  elseif S._mapDrag then
    if S._mapDrag.marquee then
      if S._mapDrag.moved and S._mapSelDraft then
        local x0, y0, x1, y1 = normalizeBlockSel(S._mapSelDraft)
        x0, y0, x1, y1 = clampBlockSel(mapDef, x0, y0, x1, y1)
        S.mapSel = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
        S._mapSelFor = mapDef.id or S.mapId
        S.status = string.format("Selected blocks (%d,%d)–(%d,%d)",
          x0, y0, x1, y1)
      else
        local z = S.mapZoom or 2
        local wx = (S._mapDrag.mx - vx) / z + S._mapDrag.camX
        local wy = (S._mapDrag.my - vy) / z + S._mapDrag.camY
        local cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
        applyToolAtCell(S, mapDef, cx, cy, App)
      end
      S._mapSelDraft = nil
    elseif not S._mapDrag.brush and not S._mapDrag.pan and not S._mapDrag.moved then
      local z = S.mapZoom or 2
      local wx = (S._mapDrag.mx - vx) / z + S._mapDrag.camX
      local wy = (S._mapDrag.my - vy) / z + S._mapDrag.camY
      local cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
      applyToolAtCell(S, mapDef, cx, cy, App)
    end
    S._mapDrag = nil
    S._lastPaintCell = nil
  end

  local swH = 12 * s
  local swX, swY = vx + 6 * s, vy + vh - 34 * s
  if mapUsesTrueColor(S, mapDef) then
    Kit.text("micro", "true color", swX, swY + 1 * s, PAL.yellow)
  elseif Preview.useGbcPalettes(S)
      and Preview.hasTilesetGbcGroups(S, mapDef.tileset) then
    local groups = Preview.tilesetGbcGroups(S, mapDef.tileset)
    local cell = 8 * s
    if groups then
      for gi = 1, 8 do
        local g = groups[gi]
        local c = (g and g[2]) or { 128, 128, 128 }
        love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
          (c[3] or 0) / 255, 1)
        love.graphics.rectangle("fill", swX + (gi - 1) * (cell + 2 * s),
          swY, cell, swH, 2 * s, 2 * s)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    Kit.text("micro", "GBC ×8 " .. tostring(mapDef.tileset or ""),
      swX + 8 * (cell + 2 * s) + 4 * s, swY + 1 * s, PAL.faint)
  else
    local palName = mapPaletteName(S, mapDef)
    Preview.drawNamedSwatches(S, palName, swX, swY, 72 * s, swH)
    Kit.text("micro", palName, vx + 84 * s, swY + 1 * s, PAL.faint)
    if Kit.press(swX, swY, 160 * s, swH + 2 * s) then
      local mid = mapDef.id or S.mapId
      PalettePicker.open(S, {
        current = mapDef.palette,
        allowClear = true,
        clearLabel = "(inherit FieldDefaults)",
        title = "MAP PALETTE (SGB)",
        onPick = function(id)
          local owned = ensureOwned(S, mid)
          if owned then
            owned.palette = id
            App.markDirty()
          end
        end,
        owner = {
          kind = "map",
          entityId = mid,
          entityLabel = mid,
          assign = function(id)
            local owned = ensureOwned(S, mid)
            if owned then
              owned.palette = id
              App.markDirty()
            end
          end,
        },
      })
    end
  end
  local hint
  local ts = tostring(mapDef.tileset or "?")
  local coord = ""
  if S._mapHoverCx ~= nil and S._mapHoverCy ~= nil then
    local cx, cy = S._mapHoverCx, S._mapHoverCy
    local bx, by = S._mapHoverBx, S._mapHoverBy
    local blk = nil
    if bx and by and bx >= 0 and by >= 0
        and bx < (mapDef.width or 0) and by < (mapDef.height or 0)
        and type(mapDef.blocks) == "table" then
      blk = mapDef.blocks[by * mapDef.width + bx + 1]
    end
    if blk ~= nil then
      coord = string.format("  cell %d,%d  block %d,%d  id=%s",
        cx, cy, bx, by, tostring(blk))
    else
      coord = string.format("  cell %d,%d  block %d,%d",
        cx, cy, bx or 0, by or 0)
    end
  end
  if S.warpDestPick then
    hint = string.format(
      "%.1fx  %s%s  click=set warp dest  Esc=cancel  MMB/Space=pan",
      S.mapZoom, ts, coord)
  elseif tool == "collision" then
    hint = string.format(
      "%.1fx  %s%s  paint=%s%s  red=solid blue=water magenta=grass orange=ledge",
      S.mapZoom, ts, coord, tostring(S.mapCollisionMode or "solid"),
      (S.mapCollisionMode == "ledge"
        and (" dir=" .. tostring(S.mapLedgeDir or "down")) or ""))
  elseif brush then
    hint = string.format(
      "%.1fx  %s%s  blk=%s  drag=paint  RMB=copy Shift+RMB=paste",
      S.mapZoom, ts, coord, tostring(S.paintBlock or 1))
  elseif selecting then
    hint = string.format(
      "%.1fx  %s%s  drag=marquee  Ctrl+C/V  Apply shift",
      S.mapZoom, ts, coord)
  else
    hint = string.format(
      "%.1fx  %s%s  scrollbars · Shift+wheel=V Ctrl+wheel=H · WASD/MMB pan",
      S.mapZoom, ts, coord)
  end
  Kit.text("micro", hint, vx + 6 * s, vy + vh - 16 * s, PAL.faint)
end

-- Hold WASD to pan continuously (Shift = faster).
-- Arrow keys navigate the map list (RegList), not the camera.
-- Drop renderer + id-list caches after undo/redo restores the project.
function Maps.invalidateCaches(S)
  spriteCache = {}
  if S then
    S._spriteIdList = nil
    S._spriteIdListKey = nil
  end
end

function Maps.update(S, dt)
  if not S or S.mapTilesetPicker then return end
  if Kit.focus or Kit._suppressMouse then return end
  if Kit.blockClicks then return end
  -- Modals set blockClicks only during draw; update runs earlier.
  if S.speciesPicker or S.itemPicker or S.palettePicker then return end
  if not (love and love.keyboard and love.keyboard.isDown) then return end
  local dx, dy = 0, 0
  if love.keyboard.isDown("a") then dx = dx - 1 end
  if love.keyboard.isDown("d") then dx = dx + 1 end
  if love.keyboard.isDown("w") then dy = dy - 1 end
  if love.keyboard.isDown("s") then dy = dy + 1 end
  if dx == 0 and dy == 0 then return end
  local len = math.sqrt(dx * dx + dy * dy)
  dx, dy = dx / len, dy / len
  local speed = 320 -- screen px / sec
  if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
    speed = speed * 2.5
  end
  dt = tonumber(dt) or 0
  if S.mapViewMode == "world" then
    local z = math.max(0.04, S.worldZoom or 0.25)
    local step = (speed * dt) / z
    S.worldCamX = (S.worldCamX or 0) + dx * step
    S.worldCamY = (S.worldCamY or 0) + dy * step
  else
    local z = math.max(0.25, S.mapZoom or 2)
    local step = (speed * dt) / z
    S.mapCamX = (S.mapCamX or 0) + dx * step
    S.mapCamY = (S.mapCamY or 0) + dy * step
    local map = resolveMapDef(S, S.mapId)
    if map then clampMapCam(S, map) end
  end
end

function Maps.wheelmoved(S, dy, dx)
  if not S then return false end
  dy = tonumber(dy) or 0
  dx = tonumber(dx) or 0
  -- Modal owns the wheel (Kit.scroll on the list). Do not zoom the map.
  if S.mapTilesetPicker then return false end
  if S.mapViewMode == "world" and S._worldViewHit then
    if dy ~= 0 then
      S.worldZoom = clampWorldZoom(
        (S.worldZoom or 0.25) + (dy > 0 and 0.05 or -0.05))
    end
    return dy ~= 0 or dx ~= 0
  end
  if not S._mapViewW then return false end
  if not S._mapViewHit then return false end

  local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
  local map = resolveMapDef(S, S.mapId)
  local z = math.max(0.25, S.mapZoom or 2)
  local step = (48 * (Kit.scale or 1)) / z

  -- Trackpad horizontal / Ctrl+wheel → pan X; Shift+wheel → pan Y.
  local panX, panY = 0, 0
  if dx ~= 0 then panX = panX - dx * step end
  if shift and dy ~= 0 then
    panY = panY - dy * step
    dy = 0
  elseif ctrl and dy ~= 0 then
    panX = panX - dy * step
    dy = 0
  end
  if panX ~= 0 or panY ~= 0 then
    S.mapCamX = (S.mapCamX or 0) + panX
    S.mapCamY = (S.mapCamY or 0) + panY
    if map then clampMapCam(S, map) end
    return true
  end
  if dy ~= 0 then
    S.mapZoom = clampZoom((S.mapZoom or 2) + (dy > 0 and 0.25 or -0.25))
    if map then clampMapCam(S, map) end
    return true
  end
  return false
end

function Maps.keypressed(S, key, App)
  -- Escape / typing handled at App while the tileset modal is up.
  if S.mapTilesetPicker then return true end
  -- Never steal keys while a parameters field is focused (zoom +/- etc.).
  if Kit.focus then return true end
  if key == "escape" and S.warpDestPick then
    clearWarpDestPick(S, "Set destination cancelled")
    return true
  end
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
  if ctrl and (key == "c" or key == "v") and S.mapViewMode ~= "world" then
    local map = resolveMapDef(S, S.mapId)
    if not map then return true end
    if key == "c" then
      local x0, y0, x1, y1 = normalizeBlockSel(S.mapSel)
      if not x0 and S._mapHoverBx ~= nil then
        x0 = S._mapHoverBx; y0 = S._mapHoverBy
        x1, y1 = x0, y0
      end
      if not x0 then
        S.status = "Nothing to copy — select a region or hover a block"
        return true
      end
      local bw, bh = copyBlocksToClip(S, map, x0, y0, x1, y1)
      if bw then
        S.status = string.format("Copied %dx%d — Ctrl+V or Shift+RMB to paste",
          bw, bh)
      end
      return true
    end
    -- Ctrl+V
    local dx, dy = pasteDestBlock(S, map)
    local ok, msg = pasteClipAt(S, S.mapId, dx, dy, App)
    S.status = msg or (ok and "Pasted" or "Paste failed")
    return true
  end
  -- WASD pans in Maps.update; arrows are reserved for the map list.
  if key == "w" or key == "a" or key == "s" or key == "d" then
    return true
  end
  if S.mapViewMode == "world" then
    if key == "=" or key == "+" then
      S.worldZoom = clampWorldZoom((S.worldZoom or 0.25) + 0.05)
    elseif key == "-" then
      S.worldZoom = clampWorldZoom((S.worldZoom or 0.25) - 0.05)
    end
    return
  end
  if key == "=" or key == "+" then
    S.mapZoom = clampZoom((S.mapZoom or 2) + 0.25)
  elseif key == "-" then
    S.mapZoom = clampZoom((S.mapZoom or 2) - 0.25)
  end
end

-- Full-window modal (same contract as PalettePicker): App draws this over
-- (0,0,W,H) after the Maps panel so hit tests match the painted rects.
function Maps.drawTilesetPicker(S, x, y, w, h, App)
  local p = S and S.mapTilesetPicker
  if not p or not App then return end
  local map = resolveMapDef(S, S.mapId)
  if not map then
    S.mapTilesetPicker = nil
    Kit.suppressMouseUntilUp()
    return
  end
  local function mutate()
    return ensureOwned(S, S.mapId)
  end
  local function closeTilesetPicker()
    S.mapTilesetPicker = nil
    Kit.blur()
    Kit.suppressMouseUntilUp()
  end

  local s = Kit.scale
  -- Swallow the click that opened the modal so it does not also hit a row.
  if p.opened then
    p.opened = nil
    Kit.mouseClicked = false
    p.focus = map.tileset
  end

  Theme.col(PAL.bgBot or PAL.card, 0.72)
  love.graphics.rectangle("fill", x, y, w, h)

  local pw = math.min(w - 24 * s, 640 * s)
  local ph = math.min(h - 24 * s, 520 * s)
  local px = x + (w - pw) / 2
  local py = y + (h - ph) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(px, py, pw, ph) then
    closeTilesetPicker()
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, "CHOOSE TILESET")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    closeTilesetPicker()
    return
  end
  cy = cy + 22 * s

  local listW = math.min(240 * s, inner * 0.42)
  local prevX = cx + listW + 10 * s
  local prevW = inner - listW - 10 * s

  local qh = 28 * s
  local q = Kit.textfield("map_ts_pick", cx, cy, listW, qh, p.query or "",
    "search tilesets...")
  if q ~= (p.query or "") then
    p.query = q
    p.offset = 0
  end

  local list = tilesetIds(S)
  if #list == 0 then list = { "OVERWORLD" } end
  if (p.query or "") ~= "" then
    local filtered, ql = {}, p.query:lower()
    for _, id in ipairs(list) do
      if id:lower():find(ql, 1, true) then filtered[#filtered + 1] = id end
    end
    list = filtered
  end

  local btnH = 24 * s
  local btnGap = 3 * s
  local footerH = btnH * 4 + btnGap * 3 + 6 * s
  local listY = cy + qh + 8 * s
  local listH = py + ph - pad - listY - footerH
  local rowH = 32 * s
  local thumb = 24 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(listW)
  p.offset = Kit.scroll(cx, listY, listW, listH, p.offset or 0, #list, perPage,
    nil, "mapTilesetPickerOffset")

  if #list == 0 then
    Kit.emptyBox(cx, listY, listW, listH, "No tilesets match")
  else
    local focusOk = false
    for _, id in ipairs(list) do
      if id == p.focus then focusOk = true; break end
    end
    if not focusOk then
      p.focus = list[(p.offset or 0) + 1] or list[1]
    end
    Kit.pushClip(cx, listY, innerW, listH)
    local ry = listY
    for i = (p.offset or 0) + 1, math.min(#list, (p.offset or 0) + perPage) do
      local id = list[i]
      local on = map.tileset == id
      local focused = p.focus == id
      local modded = S.project.tilesets and S.project.tilesets[id] ~= nil
      local localSlot = modded and S.project.tilesets[id]._mapLocal
      if Kit.hover(cx, ry, innerW, rowH) then p.focus = id end
      if Kit.row(cx, ry, innerW, rowH, on or focused, PAL.blue) then
        applyMapTileset(S, map, id, App, mutate)
        closeTilesetPicker()
        Kit.popClip()
        return
      end
      drawBlockThumb(S, id, 1, cx + 4 * s, ry + (rowH - thumb) / 2, thumb)
      local label = Kit.ellipsize("mono", id, math.max(8, innerW - thumb - 16 * s))
      Kit.text("mono", label, cx + 4 * s + thumb + 6 * s, ry + 8 * s,
        on and PAL.heading
          or (localSlot and PAL.green)
          or (modded and PAL.text or PAL.muted))
      ry = ry + rowH + 3 * s
    end
    Kit.popClip()
  end
  p.offset = Kit.scrollbar(cx, listY, listW, listH, p.offset or 0, #list, perPage,
    "mapTilesetPickerOffset")

  local focusId = p.focus or map.tileset or list[1]
  local by = listY + listH + 6 * s
  -- Footer: Clone / Replace / New from PNG / Edit in GFX.
  local row1 = btnH
  if Kit.button(cx, by, listW, row1, "Clone for this map", {
      kind = "good",
      tooltip = "RPG Maker style: new tileset slot from the selected one, assigned here",
    }) then
    local m = mutate()
    if focusId and m.tileset ~= focusId then
      applyMapTileset(S, m, focusId, App, mutate)
      m = resolveMapDef(S, S.mapId) or m
    end
    local _, newId, err = cloneTilesetForMap(S, m, App)
    if newId then
      S.status = "Tileset slot " .. newId .. " (Passage local to this map)"
      closeTilesetPicker()
      return
    end
    S.status = "Clone failed: " .. tostring(err)
  end
  if Kit.button(cx, by + row1 + btnGap, listW, row1, "Replace PNG", {
      kind = "accent",
      tooltip = "Import a PNG over this tileset's image (assets/tilesets/)",
    }) then
    importTilesetPng(S, App, focusId, { rebuildBlocks = false })
  end
  if Kit.button(cx, by + (row1 + btnGap) * 2, listW, row1, "+ New from PNG", {
      kind = "ghost",
      tooltip = "Register a new tileset from a PNG sheet",
    }) then
    importTilesetPng(S, App, nil, { createNew = true, rebuildBlocks = true })
  end
  if Kit.button(cx, by + (row1 + btnGap) * 3, listW, row1, "Edit in GFX", {
      kind = "ghost",
      tooltip = "Open flags + block editor for this tileset",
    }) and focusId then
    S.tab = "gfx"
    S.gfxMode = "tilesets"
    S.tilesetEditId = focusId
    S.gfxTilesetPane = "flags"
    closeTilesetPicker()
    return
  end

  Kit.text("micro", Kit.ellipsize("micro", tostring(focusId or ""), prevW - 8 * s),
    prevX, cy + 6 * s, PAL.caption)
  local prevH = listH + footerH
  drawTilesetPreview(S, focusId, prevX, listY, prevW, prevH)
end

local function loadImportResult(path)
  -- Prefer io.open + load: loadfile can fail for absolute paths outside the
  -- LÖVE source tree on some platforms.
  local f = io.open(path, "rb")
  if f then
    local src = f:read("*a")
    f:close()
    if src and src ~= "" then
      local chunk, err = load(src, "@" .. path)
      if chunk then return true, chunk end
      return false, err or "load failed"
    end
  end
  local chunk, err = loadfile(path)
  if not chunk then
    return false, err or "missing tmx_import_result.lua"
  end
  return true, chunk
end

local function mergeImportResult(S, App)
  State.ensureProjectFields(S.project)
  local sep = package.config:sub(1, 1)
  local path = S.path .. sep .. "tmx_import_result.lua"
  local okLoad, chunkOrErr = loadImportResult(path)
  if not okLoad then
    return false, chunkOrErr
  end
  local ok, result = pcall(chunkOrErr)
  if not ok or type(result) ~= "table" then
    return false, tostring(result)
  end

  local function adoptTileset(tid, ts)
    if type(tid) ~= "string" or tid == "" or type(ts) ~= "table" then return end
    ts.id = tid
    ts._isNew = true
    ts.tilesPerRow = ts.tilesPerRow or 16
    ts.animation = ts.animation or "TILEANIM_NONE"
    ts.doorTiles = ts.doorTiles or {}
    ts.warpTiles = ts.warpTiles or {}
    ts.counterTiles = ts.counterTiles or {}
    ts.blocks = ts.blocks or {}
    ts.walkable = ts.walkable or {}
    ts.waterTiles = ts.waterTiles or {}
    if not ts.image or ts.image == "" then
      ts.image = "assets/tilesets/" .. tid:lower() .. ".png"
    end
    S.project.tilesets[tid] = ts
    if S.data and S.data.tilesets then
      S.data.tilesets[tid] = liveTilesetForEditor(S, ts)
    end
  end

  local tilesetId = result.tilesetId
  if result.tileset and tilesetId then
    adoptTileset(tilesetId, result.tileset)
    S.tilesetEditId = tilesetId
  end

  -- Every Tiled tileset tab becomes a browsable editor tileset.
  if type(result.tilesets) == "table" then
    for tid, ts in pairs(result.tilesets) do
      adoptTileset(tid, ts)
    end
  end

  -- Remember source Tiled art paths (copied under assets/tilesets/source/).
  if type(result.sourceTilesets) == "table" and #result.sourceTilesets > 0 then
    S.project.tmxSourceTilesets = S.project.tmxSourceTilesets or {}
    for _, src in ipairs(result.sourceTilesets) do
      if type(src) == "table" and src.name then
        S.project.tmxSourceTilesets[src.name] = src
      end
    end
  end

  local first
  local mapCount = 0
  for id, map in pairs(result.maps or {}) do
    mapCount = mapCount + 1
    if map.index and (not S.project.nextMapIndex or map.index >= S.project.nextMapIndex) then
      S.project.nextMapIndex = map.index + 1
    end
    map.id = map.id or id
    map._isNew = true
    if tilesetId and (not map.tileset or map.tileset == "") then
      map.tileset = tilesetId
    end
    S.project.maps[id] = map
    if S.data and S.data.maps then
      S.data.maps[id] = map
    end
    MapLoader.invalidate(id)
    first = first or id
  end
  if first then
    S.mapId = first
    S._mapCenteredFor = nil
    S._mapNeedsRebuild = first
  end
  if tilesetId then
    S.mapPaletteTileset = tilesetId
    S.tilesetEditId = tilesetId
    if first then S._mapPaletteFor = first end
  end

  local lines = result.report or {}
  S.importReport = table.concat(lines, "\n")
  App.markDirty()
  local summary
  if tilesetId and mapCount > 0 then
    summary = string.format("%d map(s) + tileset %s", mapCount, tilesetId)
  elseif tilesetId then
    summary = "tileset " .. tilesetId
  else
    summary = (#lines > 0 and lines[1]) or "merged"
  end
  return true, summary
end

function Maps.importTmx(S, tmxPath, App)
  if not S.project or not S.path then
    S.status = "Open a mod before importing TMX"
    return
  end
  local root = ModIO.repoRoot()
  local sep = package.config:sub(1, 1)
  local script = root .. sep .. "tools" .. sep .. "tmx_import.py"
  local outMod = S.path
  local cmd
  if sep == "\\" then
    cmd = string.format('python "%s" "%s" --mod "%s" 2>&1', script, tmxPath, outMod)
  else
    cmd = string.format('python3 "%s" "%s" --mod "%s" 2>&1', script, tmxPath, outMod)
  end
  S.status = "Importing TMX..."
  local pipe = io.popen(cmd, "r")
  if not pipe then
    S.status = "Could not run tmx_import.py (is Python on PATH?)"
    return
  end
  local report = pipe:read("*a") or ""
  pipe:close()
  local ok, msg = mergeImportResult(S, App)
  S.importReport = (S.importReport or "") .. "\n" .. report
  if ok then
    S.status = "TMX import: " .. tostring(msg)
      .. " (Save to write main.lua + tileset register)"
  else
    S.status = "Import finished but merge failed: " .. tostring(msg)
  end
end

-- ---- property panel sections ------------------------------------------------

local function drawBasics(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  local function prow(label, body)
    if py + fh + 22 * s > listBottom then return true end
    Kit.text("micro", label, px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    body(px + 10 * s, py, propW - 20 * s, fh)
    py = py + fh + 8 * s
  end

  if prow("ID", function(fx, fy, fw, fh_)
    -- Draft while typing; commit on Enter / focus loss so each keystroke
    -- does not create a sidebar entry (and a live data.maps alias).
    local shown = S._mapIdDraft
    if shown == nil then shown = map.id end
    local v = field(App, "mp_id", fx, fy, fw, fh_, shown, "MAP_ID")
    if Kit.focus == "mp_id" then
      S._mapIdDraft = v
    elseif S._mapIdDraft ~= nil then
      local newId = v
      S._mapIdDraft = nil
      if newId ~= map.id then
        map = mutate()
        if not renameMapId(S, map, newId, App) then
          S.status = "Map id unavailable or invalid: " .. tostring(newId)
        end
      end
    end
  end) then return py end

  if prow("Label", function(fx, fy, fw, fh_)
    local v = field(App, "mp_label", fx, fy, fw, fh_, map.label or "", "Label")
    if v ~= (map.label or "") then map = mutate(); map.label = v end
  end) then return py end

  if prow("Locale", function(fx, fy, fw, fh_)
    local cur = inferMapEnvironment(map)
    local mx = fx
    for _, opt in ipairs({
      { id = "outside", label = "Outside", tip = "Towns / routes — grass & water wilds, Go Outside SFX" },
      { id = "inside", label = "Inside", tip = "Buildings — indoor wilds (if any), Go Inside SFX" },
      { id = "cave", label = "Cave", tip = "Caves / dungeons — indoor wilds on every tile when indexed indoor" },
    }) do
      local on = cur == opt.id
      local bw = Kit.textWidth("micro", opt.label) + 16 * s
      if Kit.chip(mx, fy, bw, fh_, opt.label, on, PAL.blue, nil, opt.tip) then
        if cur ~= opt.id then
          map = mutate()
          setMapEnvironment(map, opt.id)
          MapLoader.invalidate(map.id)
          App.markDirty()
          S.status = "Map locale → " .. opt.label
        end
      end
      mx = mx + bw + 4 * s
    end
  end) then return py end
  do
    local cur = inferMapEnvironment(map)
    local hint = (cur == "outside" and "wilds in grass / water only")
      or (cur == "cave" and "treated as indoors for wilds & exits")
      or "interior (not an outside map)"
    Kit.text("micro", hint, px + 10 * s, py, PAL.faint)
    py = py + 14 * s
  end

  if prow("Dark map", function(fx, fy, fw, fh_)
    -- field.darkMaps: needs FLASH until lit (Rock Tunnel, etc.)
    local function darkList()
      if type(S.project.darkMaps) == "table"
          and type(S.project.darkMaps.maps) == "table" then
        return S.project.darkMaps.maps
      end
      local base = S.data and S.data.field and S.data.field.darkMaps
      return (base and base.maps) or {}
    end
    local function isDark()
      for _, mid in ipairs(darkList()) do
        if mid == map.id then return true end
      end
      return false
    end
    local on = isDark()
    if Kit.chip(fx, fy, 120 * s, fh_, on and "Dark (FLASH)" or "Lit",
        on, PAL.blue,
        nil, "When on, this map is listed in field.darkMaps (needs FLASH)") then
      State.ensureProjectFields(S.project)
      if type(S.project.darkMaps) ~= "table"
          or type(S.project.darkMaps.maps) ~= "table" then
        local base = S.data and S.data.field and S.data.field.darkMaps
        local maps = {}
        if base and type(base.maps) == "table" then
          for i, mid in ipairs(base.maps) do maps[i] = mid end
        end
        S.project.darkMaps = { maps = maps }
        if base and base.palOffset ~= nil then
          S.project.darkMaps.palOffset = base.palOffset
        end
      end
      local list = S.project.darkMaps.maps
      if on then
        for i = #list, 1, -1 do
          if list[i] == map.id then table.remove(list, i) end
        end
      else
        list[#list + 1] = map.id
      end
      App.markDirty()
      S.status = on and (map.id .. " removed from darkMaps")
        or (map.id .. " added to darkMaps")
    end
  end) then return py end

  if prow("Index", function(fx, fy, fw, fh_)
    local cur = map.index or 0
    local v = tonumber(field(App, "mp_idx", fx, fy, 80 * s, fh_, tostring(cur), "0")) or 0
    if v ~= cur then map = mutate(); map.index = v end
    -- Gen1: index >= 37 + non-outside = encounters on every tile.
    local firstIndoor = 37
    local indoor = S.data and S.data.field and S.data.field.indoorEncounters
    if indoor and indoor.firstIndoorMap then firstIndoor = indoor.firstIndoorMap end
    if (map.index or 0) >= firstIndoor and Map.isOutside(map) then
      Kit.text("micro", "outside: grass/water (mod hook on Save)",
        fx + 88 * s, fy + 6 * s, PAL.faint)
    elseif (map.index or 0) >= firstIndoor then
      Kit.text("micro", "indoor index: wilds on EVERY tile",
        fx + 88 * s, fy + 6 * s, PAL.yellow)
    end
  end) then return py end

  if prow("Size W x H (blocks)", function(fx, fy, fw, fh_)
    -- Draft while typing; commit on Enter / focus leaving both fields.
    -- Live apply on "1" of "12" would crop the map to width 1.
    local draft = S._mapSizeDraft
    if draft == nil or draft.forId ~= map.id then
      draft = {
        forId = map.id,
        w = tostring(map.width),
        h = tostring(map.height),
      }
      S._mapSizeDraft = draft
    end
    local ww = Kit.textfield("mp_w", fx, fy, 60 * s, fh_, draft.w, "10")
    local hh = Kit.textfield("mp_h", fx + 70 * s, fy, 60 * s, fh_, draft.h, "9")
    local sizing = (Kit.focus == "mp_w" or Kit.focus == "mp_h")
    if sizing then
      draft.w, draft.h = ww, hh
    else
      local nw = math.max(1, tonumber(ww) or map.width)
      local nh = math.max(1, tonumber(hh) or map.height)
      S._mapSizeDraft = nil
      if nw ~= map.width or nh ~= map.height then
        map = mutate()
        local nb = {}
        for yb = 0, nh - 1 do
          for xb = 0, nw - 1 do
            local old = (yb < map.height and xb < map.width)
              and map.blocks[yb * map.width + xb + 1] or 1
            nb[yb * nw + xb + 1] = old
          end
        end
        map.width, map.height, map.blocks = nw, nh, nb
        MapLoader.invalidate(map.id)
        S._mapCenteredFor = nil
        App.markDirty()
      end
    end
  end) then return py end

  if py + 16 * s <= listBottom then
    Kit.text("micro", "Size applies on Enter / click away",
      px + 10 * s, py, PAL.faint)
    py = py + 16 * s
  end

  if prow("Tileset", function(fx, fy, fw, fh_)
    local cloneW = 70 * s
    local assignW = 70 * s
    local gap = 4 * s
    local labelW = math.max(40 * s, fw - cloneW - assignW - gap * 2)
    local label = Kit.ellipsize("mono", map.tileset or "?", labelW - 4 * s)
    local ownedTs = S.project.tilesets and S.project.tilesets[map.tileset or ""]
    local localSlot = ownedTs and ownedTs._mapLocal
    Kit.text("mono", label, fx, fy + 6 * s, localSlot and PAL.green or PAL.heading)
    if Kit.button(fx + labelW + gap, fy, cloneW, fh_, "Clone", {
        kind = "good",
        tooltip = "RPG Maker style: copy tileset for THIS map (Passage edits stay local)",
      }) then
      map = mutate()
      local _, newId, err = cloneTilesetForMap(S, map, App)
      if newId then
        S.status = "Tileset slot " .. newId .. " — Passage edits affect this map only"
      else
        S.status = "Clone failed: " .. tostring(err)
      end
    end
    if Kit.button(fx + labelW + gap + cloneW + gap, fy, assignW, fh_, "Assign", {
        kind = "accent",
        tooltip = "Choose which tileset slot this map uses (like RPG Maker)",
      }) then
      openTilesetPicker(S)
    end
  end) then return py end
  do
    local ownedTs = S.project.tilesets and S.project.tilesets[map.tileset or ""]
    if ownedTs and ownedTs._mapLocal then
      Kit.text("micro", "local slot (Passage safe)", px + 10 * s, py, PAL.green)
    else
      Kit.text("micro", "shared tileset — Clone or TERRAIN will make a local slot",
        px + 10 * s, py, PAL.yellow)
    end
    py = py + 14 * s
  end

  if prow("Border block", function(fx, fy, fw, fh_)
    local bid = map.borderBlock or 0
    local thumb = fh_
    drawBlockThumb(S, map.tileset, bid, fx, fy, thumb)
    local fieldX = fx + thumb + 6 * s
    local v = tonumber(field(App, "mp_border", fieldX, fy, 50 * s, fh_,
      tostring(bid), "0")) or 0
    if v ~= bid then
      map = mutate()
      map.borderBlock = v
      MapLoader.invalidate(map.id)
      App.markDirty()
    end
    local btnX = fieldX + 56 * s
    local btnW = math.max(0, fw - (btnX - fx))
    if btnW >= 56 * s and Kit.button(btnX, fy, btnW, fh_, "Use brush", {
        kind = "accent",
        tooltip = "Set border to paint block "
          .. tostring(S.paintBlock or 0),
      }) then
      map = mutate()
      map.borderBlock = S.paintBlock or 0
      MapLoader.invalidate(map.id)
      App.markDirty()
      S.status = "Border block → " .. tostring(map.borderBlock)
    end
  end) then return py end

  if prow("TrueColor", function(fx, fy, fw, fh_)
    local on = mapUsesTrueColor(S, map)
    if Kit.chip(fx, fy, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
      map = mutate()
      local newOn = not on
      map.trueColor = newOn and true or nil
      syncTilesetTrueColor(S, map, newOn, App)
      Preview.invalidate()
      App.markDirty()
      S.status = newOn
        and "TrueColor ON — raw tileset PNG (map palette ignored)"
        or "TrueColor OFF — palette remap"
    end
  end) then return py end
  do
    local on = mapUsesTrueColor(S, map)
    Kit.text("micro",
      on and "full-color tileset — skips 4-shade palette remap"
        or "OFF = grayscale tiles remapped through map palette colors",
      px + 10 * s, py, PAL.faint)
    py = py + 14 * s
  end

  if prow("GBC palettes", function(fx, fy, fw, fh_)
    local on = Preview.useGbcPalettes(S)
    if Kit.chip(fx, fy, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow,
        nil, on
          and "YES = ADVANCED per-tile GBC (8 BG groups)"
          or "NO = ROM/cache SGB single palette") then
      Preview.setUseGbcPalettes(S, not on)
      MapLoader.invalidateAll()
      S.status = (not on)
        and "GBC ON — ADVANCED tileset groups + named pack"
        or "GBC OFF — SGB map palette remap"
    end
  end) then return py end
  do
    local on = Preview.useGbcPalettes(S)
    Kit.text("micro",
      on and "preview = COLORS ADVANCED (8 BG palettes / tileset)"
        or "preview = SGB single map palette",
      px + 10 * s, py, PAL.faint)
    py = py + 14 * s
  end

  -- GBC tileset BG groups (GRAY…TEXT): 8×4 editable when pack has world data.
  local tsId = map.tileset
  local gbcOn = Preview.useGbcPalettes(S)
  if gbcOn and Preview.hasTilesetGbcGroups(S, tsId) then
    local names = Preview.GBC_GROUP_NAMES
    local groups = Preview.tilesetGbcGroups(S, tsId)
    local owned = Preview.tilesetGbcGroupsOwned(S, tsId)
    Kit.text("micro", "GBC BG groups · " .. tostring(tsId)
        .. (owned and " (mod)" or " (vanilla)"),
      px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local sw = 22 * s
    local gap = 4 * s
    local rowH = 24 * s
    for gi = 1, 8 do
      if py + rowH + 4 * s > listBottom then return true end
      local label = names[gi] or ("G" .. (gi - 1))
      Kit.text("micro", label, px + 10 * s, py + 6 * s, PAL.muted)
      local g = groups and groups[gi]
      local bx = px + 10 * s + 52 * s
      for ci = 1, 4 do
        local c = (g and g[ci]) or { 40, 40, 40 }
        local sx = bx + (ci - 1) * (sw + gap)
        love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
          (c[3] or 0) / 255, 1)
        love.graphics.rectangle("fill", sx, py + 2 * s, sw, rowH - 4 * s,
          3 * s, 3 * s)
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.rectangle("line", sx, py + 2 * s, sw, rowH - 4 * s,
          3 * s, 3 * s)
        love.graphics.setColor(1, 1, 1, 1)
        if Kit.press(sx, py + 2 * s, sw, rowH - 4 * s) then
          local groupI, colorI = gi, ci
          ColorWheel.open(S, {
            title = label .. " C" .. colorI .. " · " .. tostring(tsId),
            color = c,
            onChange = function(rgb)
              Preview.ensureTilesetGbcGroups(S, tsId)
              local ow = S.project.gbcWorld.groupColors[tsId]
              if ow and ow[groupI] then
                ow[groupI][colorI] = {
                  math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
                  math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
                }
              end
              App.markDirty()
            end,
            onApply = function(rgb)
              Preview.setTilesetGbcGroupColor(S, tsId, groupI, colorI, rgb)
              App.markDirty()
              MapLoader.invalidateAll()
              S.status = "GBC " .. label .. " C" .. colorI .. " updated"
            end,
          })
        end
      end
      py = py + rowH + 2 * s
    end
    if owned then
      if py + fh + 8 * s > listBottom then return true end
      if Kit.button(px + 10 * s, py, 100 * s, fh, "Revert GBC", {
          kind = "danger",
          tooltip = "Clear mod overrides for this tileset's 8 BG groups",
        }) then
        Preview.clearTilesetGbcGroups(S, tsId)
        App.markDirty()
        MapLoader.invalidateAll()
        S.status = "Reverted GBC groups for " .. tostring(tsId)
      end
      py = py + fh + 8 * s
    else
      Kit.text("micro", "click a swatch to override (Save writes main.lua)",
        px + 10 * s, py, PAL.faint)
      py = py + 14 * s
    end
  elseif gbcOn and tsId then
    Kit.text("micro", "no GBC world data for tileset " .. tostring(tsId),
      px + 10 * s, py, PAL.faint)
    py = py + 14 * s
  end

  if mapUsesTrueColor(S, map) then
    if prow("Map palette", function(fx, fy, fw, fh_)
      Kit.text("small", "(ignored — TrueColor)", fx, fy + 6 * s, PAL.faint)
    end) then return py end
  elseif gbcOn and Preview.hasTilesetGbcGroups(S, tsId) then
    if prow("SGB palette", function(fx, fy, fw, fh_)
      Kit.text("small", "(unused while GBC ON)", fx, fy + 6 * s, PAL.faint)
    end) then return py end
  else
    local gbc = Preview.useGbcPalettes(S)
    if prow("Map palette", function(fx, fy, fw, fh_)
      local mid = map.id or S.mapId
      PalettePicker.row(S, {
        x = fx, y = fy, w = fw, h = fh_,
        current = map.palette or "",
        effective = mapPaletteName(S, map),
        emptyLabel = "(inherit)",
        clearLabel = "(inherit FieldDefaults)",
        allowClear = true,
        title = gbc and "MAP PALETTE (GBC)" or "MAP PALETTE (SGB)",
        tooltip = gbc
          and "Choose this map's background palette (GBC pack colors)"
          or "Choose this map's background palette (ROM/cache SGB)",
        onPick = function(id)
          map = mutate()
          map.palette = id
          App.markDirty()
        end,
        owner = {
          kind = "map",
          entityId = mid,
          entityLabel = mid,
          assign = function(id)
            map = mutate()
            map.palette = id
            App.markDirty()
          end,
        },
      })
    end) then return py end
    Kit.text("micro", "effective: " .. mapPaletteName(S, map),
      px + 10 * s, py, PAL.faint)
    py = py + 14 * s
  end

  if prow("Music", function(fx, fy, fw, fh_)
    local cur, ownedSong = mapSongFor(S, map.id)
    local label = cur ~= "" and cur or "(none)"
    local clearW = ownedSong and 64 * s or 0
    local gap = ownedSong and 4 * s or 0
    local cycleW = math.max(80 * s, fw - clearW - gap)
    if Kit.button(fx, fy, cycleW, fh_,
        Kit.ellipsize("small", label, cycleW - 8 * s), {
          kind = "ghost",
          tooltip = "Cycle this map's song (mod.content.map_songs)",
        }) then
      setMapSong(S, map.id, cycle(songIds(S), cur), App)
    end
    if ownedSong and Kit.button(fx + cycleW + gap, fy, clearW, fh_, "Clear", {
        kind = "danger",
        tooltip = "Remove mod song override (restore vanilla)",
      }) then
      setMapSong(S, map.id, nil, App)
    end
  end) then return py end
  if prow("Music id", function(fx, fy, fw, fh_)
    local cur = select(1, mapSongFor(S, map.id))
    local v = field(App, "mp_music", fx, fy, fw, fh_, cur, "Music_...",
      function() return Autocomplete.songIds(S) end)
    if v ~= cur then
      setMapSong(S, map.id, (v ~= "" and v) or nil, App)
    end
  end) then return py end

  Kit.text("micro", "Connections (auto two-way)", px + 10 * s, py, PAL.caption)
  py = py + 14 * s
  Kit.text("micro", "Sets return link with offset negated",
    px + 10 * s, py, PAL.faint)
  py = py + 16 * s
  map.connections = map.connections or {}
  local fromId = map.id or S.mapId
  for _, dir in ipairs({ "north", "south", "east", "west" }) do
    if py + fh > listBottom then break end
    local cur = map.connections[dir]
    local val = cur and cur.map or ""
    local v = field(App, "mp_c_" .. dir, px + 10 * s, py, propW - 20 * s, fh,
      val, dir, function() return Autocomplete.mapIds(S) end)
    local wantMap = (v == "") and nil or v:upper():gsub("%s+", "_")
    local curMap = cur and cur.map or ""
    local curOff = cur and (cur.offset or 0) or 0
    if (curMap or "") ~= (wantMap or "") then
      map = applyConnectionEdit(S, fromId, dir, wantMap, curOff, App) or mutate()
    end
    if wantMap and map.connections and map.connections[dir] then
      local off = tonumber(field(App, "mp_co_" .. dir,
        px + 10 * s, py + fh + 2 * s, 60 * s, fh - 4 * s,
        tostring(map.connections[dir].offset or 0), "0")) or 0
      if off ~= (map.connections[dir].offset or 0) then
        map = applyConnectionEdit(S, fromId, dir, wantMap, off, App) or mutate()
      end
      Kit.text("micro", "offset", px + 78 * s, py + fh + 6 * s, PAL.faint)
      local dest = resolveMapDef(S, wantMap)
      local back = dest and dest.connections and dest.connections[oppositeDir(dir)]
      local ok = back and back.map == fromId
        and (back.offset or 0) == -(map.connections[dir].offset or 0)
      Kit.text("micro", ok and "<-> linked" or (dest and "<-> pending" or "missing"),
        px + 120 * s, py + fh + 6 * s, ok and PAL.green or PAL.red)
      py = py + fh + 2 * s
    end
    py = py + fh + 4 * s
  end
  return py
end

-- Block palette for map.tileset (Tiled: tile = Gen1 block). RM XP–style
-- left-column tileset dock under the map list.
local function drawTilesetDock(S, map, mutate, App, dx, dy, dw, dh)
  local s = Kit.scale
  Kit.card(dx, dy, dw, dh, 10 * s)
  local pad = 8 * s
  local active = map.tileset or "OVERWORLD"
  S.mapPaletteTileset = active
  if S._mapPaletteFor ~= S.mapId then
    S._mapPaletteFor = S.mapId
    S.mapBlockOffset = 0
  end

  local narrow = dw < 260 * s
  local headerH = narrow and 44 * s or 22 * s
  local headerY = dy + pad
  Kit.text("micro", "TILESET", dx + pad, headerY, PAL.caption)
  local ownedActive = S.project.tilesets and S.project.tilesets[active]
  Kit.text("micro", Kit.ellipsize("micro", active, dw - 20 * s),
    dx + pad, headerY + 12 * s,
    (ownedActive and ownedActive._mapLocal) and PAL.green or PAL.muted)
  local findW = 40 * s
  local assignW = 52 * s
  local cloneW = 48 * s
  local gfxW = 40 * s
  local btnY = narrow and (headerY + 22 * s) or headerY
  local btnX = narrow and (dx + pad)
    or (dx + dw - pad - findW - assignW - cloneW - gfxW - 12 * s)
  if Kit.button(btnX, btnY, cloneW, 20 * s, "Clone", {
      kind = "good",
      tooltip = "Duplicate tileset for this map (RPG Maker–style local Passage)",
    }) then
    local m = ensureOwned(S, S.mapId)
    if m then
      local _, newId, err = cloneTilesetForMap(S, m, App)
      S.status = newId
        and ("Tileset slot " .. newId)
        or ("Clone failed: " .. tostring(err))
    end
  end
  if Kit.button(btnX + cloneW + 4 * s, btnY, assignW, 20 * s, "Assign", {
        kind = "accent",
        tooltip = "Switch this map's tileset slot",
      }) then
    openTilesetPicker(S)
  end
  if Kit.button(btnX + cloneW + assignW + 8 * s, btnY, findW, 20 * s, "Find", {
      kind = "ghost", tooltip = "Search / preview tilesets to assign",
    }) then
    openTilesetPicker(S)
  end
  if Kit.button(btnX + cloneW + assignW + findW + 12 * s, btnY, gfxW, 20 * s, "GFX", {
      kind = "ghost",
      tooltip = "Open tileset editor (flags + blocks) on the GFX tab",
    }) then
    S.tab = "gfx"
    S.gfxMode = "tilesets"
    S.tilesetEditId = active
    S.gfxTilesetPane = "flags"
  end

  -- Footer: 2x2 when narrow so labels stay readable.
  local footerRows = (dw < 300 * s) and 2 or 1
  local footerH = footerRows * 26 * s + (footerRows - 1) * 4 * s
  local gridY = headerY + headerH + 8 * s
  local gridH = math.max(48 * s, dy + dh - pad - footerH - 8 * s - gridY)
  local gridX = dx + pad
  local gridW = dw - 2 * pad
  local innerW = Kit.scrollInnerWidth(gridW)
  local gap = 4 * s
  -- Left dock is narrow: prefer 2–3 columns of larger thumbs.
  local wantCols = narrow and 3 or 4
  local thumb = math.floor((innerW - gap * (wantCols - 1)) / wantCols)
  thumb = Theme.clamp(thumb, 28 * s, 52 * s)
  local cols = math.max(1, math.floor((innerW + gap) / (thumb + gap)))
  local rows = math.max(1, math.floor((gridH + gap) / (thumb + gap)))
  local perPage = cols * rows
  local maxB = blockCount(S, active)
  S.paintBlock = S.paintBlock or 1
  if S.paintBlock >= maxB then S.paintBlock = math.max(0, maxB - 1) end

  S.mapBlockOffset = Kit.scroll(gridX, gridY, gridW, gridH,
    S.mapBlockOffset or 0, maxB, perPage, cols, "mapBlockOffset")
  local start = S.mapBlockOffset or 0
  Kit.pushClip(gridX, gridY, innerW, gridH)
  for n = 0, perPage - 1 do
    local i = start + n
    if i >= maxB then break end
    local c = n % cols
    local r = math.floor(n / cols)
    local bx = gridX + c * (thumb + gap)
    local by = gridY + r * (thumb + gap)
    local on = (S.paintBlock or 1) == i
    local isBorder = (map.borderBlock or 0) == i
    drawBlockThumb(S, active, i, bx, by, thumb)
    if on then
      love.graphics.setColor(0.24, 0.88, 0.54, 1)
      love.graphics.rectangle("line", bx - 1, by - 1, thumb + 2, thumb + 2)
      love.graphics.setColor(1, 1, 1, 1)
    end
    if isBorder then
      love.graphics.setColor(0.95, 0.75, 0.2, 0.95)
      love.graphics.rectangle("line", bx + 2, by + 2, thumb - 4, thumb - 4)
      love.graphics.setColor(1, 1, 1, 1)
    end
    if Kit.press(bx, by, thumb, thumb) then
      S.paintBlock = i
      S.mapEditMode = "map"
      S.mapTool = "paint"
      S.status = string.format("Pencil: block %d (%s)", i, tostring(active))
    end
  end
  Kit.popClip()
  S.mapBlockOffset = Kit.scrollbar(gridX, gridY, gridW, gridH,
    S.mapBlockOffset or 0, maxB, perPage, "mapBlockOffset")

  local actions = {
    { label = "Replace PNG", kind = "accent", tip = "Import PNG for this map's tileset",
      run = function()
        importTilesetPng(S, App, active, { rebuildBlocks = false })
      end },
    { label = "+ New PNG", kind = "good", tip = "Register a new tileset from a PNG sheet",
      run = function()
        importTilesetPng(S, App, nil, { createNew = true, rebuildBlocks = true })
      end },
    { label = "Import TMX", kind = "accent", tip = "Import a Pokemonium / Tiled .tmx map",
      run = function()
        local picked = ModIO.chooseFile("Pokemonium / Tiled TMX",
          "Tiled map (*.tmx)|*.tmx|All (*.*)|*.*")
        if picked then Maps.importTmx(S, picked, App) end
      end },
    { label = "Set border", kind = "ghost",
      tip = "Use selected paint block as map.borderBlock (out-of-bounds fill)",
      run = function()
        map = mutate()
        map.borderBlock = S.paintBlock or 0
        MapLoader.invalidate(map.id)
        App.markDirty()
        S.status = "Border block → " .. tostring(map.borderBlock)
      end },
  }
  local colsF = (footerRows == 2) and 2 or 4
  local fw = math.floor((gridW - 6 * s * (colsF - 1)) / colsF)
  local fhBtn = 24 * s
  for i, act in ipairs(actions) do
    local c = (i - 1) % colsF
    local r = math.floor((i - 1) / colsF)
    local bx = gridX + c * (fw + 6 * s)
    local by = dy + dh - pad - footerH + r * (fhBtn + 4 * s)
    if Kit.button(bx, by, fw, fhBtn, act.label, {
        kind = act.kind, tooltip = act.tip,
      }) then
      act.run()
    end
  end
  return map
end

local function drawListPicker(S, key, count, px, py, propW, fh, s, accent)
  if count == 0 then
    Kit.text("micro", "(none -- use tools to place)", px + 10 * s, py, PAL.faint)
    return py + 20 * s, nil
  end
  local idx = S[key] or 1
  if idx < 1 then idx = 1 end
  if idx > count then idx = count end
  S[key] = idx
  if Kit.stepper(px + 10 * s, py, 28 * s, fh, "-", { radius = 6 * s }) then
    S[key] = math.max(1, idx - 1)
  end
  Kit.text("mono", string.format("%d / %d", S[key], count),
    px + 46 * s, py + 6 * s, accent or PAL.text)
  if Kit.stepper(px + 120 * s, py, 28 * s, fh, "+", { radius = 6 * s }) then
    S[key] = math.min(count, idx + 1)
  end
  return py + fh + 8 * s, S[key]
end

local function drawWarps(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  map.warps = map.warps or {}
  local pick = S.warpDestPick
  if pick and py + 16 * s <= listBottom then
    Kit.text("micro", string.format(
      "Picking dest for %s#%d — click map (Esc cancel)",
      tostring(pick.sourceMapId), pick.sourceWarpIndex or 0),
      px + 10 * s, py, PAL.green or PAL.caption)
    py = py + 18 * s
    S.status = string.format(
      "Set dest for %s#%d — switch maps, click cell (Esc cancel)",
      tostring(pick.sourceMapId), pick.sourceWarpIndex or 0)
  end
  py, S.mapWarpIndex = drawListPicker(S, "mapWarpIndex", #map.warps, px, py, propW, fh, s, PAL.blue)
  local i = S.mapWarpIndex
  local w = i and map.warps[i]
  if not w then return py end

  local function row(label, body)
    if py + fh + 20 * s > listBottom then return true end
    Kit.text("micro", label, px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    body(px + 10 * s, py, propW - 20 * s, fh)
    py = py + fh + 6 * s
  end

  row("Cell X / Y", function(fx, fy, fw, fh_)
    local x = tonumber(field(App, "wp_x", fx, fy, 50 * s, fh_, tostring(w.x or 0), "0")) or 0
    local y = tonumber(field(App, "wp_y", fx + 60 * s, fy, 50 * s, fh_, tostring(w.y or 0), "0")) or 0
    if x ~= (w.x or 0) or y ~= (w.y or 0) then
      map = mutate(); map.warps[i].x = x; map.warps[i].y = y
    end
  end)
  row("Dest map", function(fx, fy, fw, fh_)
    local v = field(App, "wp_dm", fx, fy, fw, fh_, w.destMap or "", "PALLET_TOWN")
    v = v:upper():gsub("%s+", "_")
    if v ~= (w.destMap or "") then map = mutate(); map.warps[i].destMap = v end
  end)
  row("Dest warp #", function(fx, fy, fw, fh_)
    local v = tonumber(field(App, "wp_dw", fx, fy, 60 * s, fh_,
      tostring(w.destWarp or 1), "1")) or 1
    if v ~= (w.destWarp or 1) then map = mutate(); map.warps[i].destWarp = v end
  end)

  local armedHere = pick and pick.sourceMapId == (map.id or S.mapId)
    and pick.sourceWarpIndex == i
  if not armedHere and py + 32 * s <= listBottom then
    if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Set destination",
        { kind = "primary" }) then
      armWarpDestPick(S, map.id or S.mapId, i)
    end
    py = py + 34 * s
  end

  -- Advance py even when the button is drawn so FormPane scroll height
  -- includes it (otherwise the clip hides Delete warp under the footer).
  if py + 32 * s <= listBottom then
    if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Delete warp",
        { kind = "danger" }) then
      local mid = map.id or S.mapId
      if pick and pick.sourceMapId == mid and pick.sourceWarpIndex == i then
        clearWarpDestPick(S, "Set destination cancelled")
      elseif pick and pick.sourceMapId == mid and pick.sourceWarpIndex > i then
        pick.sourceWarpIndex = pick.sourceWarpIndex - 1
      end
      map = mutate()
      table.remove(map.warps, i)
      S.mapWarpIndex = math.min(i, #map.warps)
      MapLoader.invalidate(map.id)
      App.markDirty()
    end
    py = py + 34 * s
  end
  return py
end

local function armPlaceSprite(S, id)
  S.placeSprite = id
  S.mapTool = "object"
  S.status = "OBJECT tool: " .. tostring(id)
end

local function assignObjectSprite(S, map, mutate, App, objIndex, id)
  if objIndex and map.objects and map.objects[objIndex] then
    map = mutate()
    map.objects[objIndex].sprite = id
  end
  armPlaceSprite(S, id)
  spriteCache[id] = nil
  SpriteUtil.invalidateIdCache(S)
  App.markDirty()
  return map
end

local function createCustomSprite(S, App, map, mutate, objIndex, withBrowse)
  local nid = SpriteUtil.createNew(S)
  if not nid then return map end
  map = assignObjectSprite(S, map, mutate, App, objIndex, nid)
  S.mapSpriteCustomOnly = true
  S.mapSpriteOffset = 0
  if withBrowse then
    App.pickFile("Sprite PNG", "PNG (*.png)|*.png|All|*.*", function(picked)
      local rec = S.project and S.project.sprites and S.project.sprites[nid]
      if not rec then return end
      App.importToMod(picked, nil, function(rel)
        rec.image = rel
        spriteCache[nid] = nil
        SpriteUtil.invalidateIdCache(S)
        Preview.invalidate()
        App.markDirty()
        S.status = "Custom sprite " .. nid .. " ← " .. rel
      end)
    end)
  else
    S.status = "Created " .. nid .. " — Browse PNG or place on map"
  end
  return map
end

local function drawObjects(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  map.objects = map.objects or {}
  py, S.mapObjectIndex = drawListPicker(S, "mapObjectIndex", #map.objects,
    px, py, propW, fh, s, PAL.green)
  local i = S.mapObjectIndex
  local obj = i and map.objects[i]

  -- Always available: create custom sprites for place / assign
  if py + fh + 8 * s <= listBottom then
    local bw = math.floor((propW - 28 * s) / 2)
    if Kit.button(px + 10 * s, py, bw, fh, "+ New sprite", {
        kind = "good",
        tooltip = "Register SPRITE_MOD_* and arm Object place tool",
      }) then
      map = createCustomSprite(S, App, map, mutate, i, false)
      obj = i and map.objects[i]
    end
    if Kit.button(px + 16 * s + bw, py, bw, fh, "+ PNG sprite", {
        kind = "accent",
        tooltip = "Create custom sprite and import a PNG",
      }) then
      map = createCustomSprite(S, App, map, mutate, i, true)
      obj = i and map.objects[i]
    end
    py = py + fh + 8 * s
  end

  if not obj then
    Kit.text("micro", "Create a sprite above, then place with the Object tool.",
      px + 10 * s, py, PAL.faint)
    return py + 20 * s
  end

  -- Top of form so Delete is never clipped under the footer / scroll.
  if py + 32 * s <= listBottom then
    if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Delete object",
        { kind = "danger" }) then
      map = mutate()
      local removed = map.objects[i]
      table.remove(map.objects, i)
      for j, o in ipairs(map.objects) do o.index = j end
      cleanupRemovedMapObject(S, map, i, removed)
      S.mapObjectIndex = math.min(i, #map.objects)
      MapLoader.invalidate(map.id)
      App.markDirty()
      S.status = "Deleted object #" .. tostring(i)
        .. " (cleared trainer text/flags/scripts)"
    end
    py = py + 34 * s
  end

  -- sprite preview + place-sprite arm
  local def = spriteDef(S, obj.sprite)
  if py + 56 * s < listBottom then
    if def and def.image then
      Preview.draw(S, def.image, px + 10 * s, py, 48 * s, 48 * s,
        spritePreviewPal(S, def))
    else
      Theme.col(PAL.rowBg, 1)
      love.graphics.rectangle("fill", px + 10 * s, py, 48 * s, 48 * s, 6 * s, 6 * s)
      Kit.text("micro", "?", px + 28 * s, py + 18 * s, PAL.faint)
    end
    Kit.text("micro", obj.sprite or "?", px + 66 * s, py + 8 * s, PAL.muted)
    if Kit.button(px + 66 * s, py + 24 * s, 120 * s, 22 * s, "Use to place",
        { kind = "ghost" }) then
      armPlaceSprite(S, obj.sprite)
    end
    py = py + 56 * s
  end

  -- Inline edit for project-owned (custom) sprites
  if SpriteUtil.isOwned(S, obj.sprite) and py + fh * 4 <= listBottom then
    local rec = S.project.sprites[obj.sprite]
    Kit.text("micro", "Custom sprite", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    Kit.text("micro", Kit.ellipsize("micro", tostring(rec.image or ""), propW - 120 * s),
      px + 10 * s, py + 8 * s, PAL.muted)
    if Kit.button(px + propW - 106 * s, py, 96 * s, fh, "Browse", {
        kind = "ghost", tooltip = "Import PNG for this sprite",
      }) then
      local sid = obj.sprite
      App.pickFile("Sprite PNG", "PNG (*.png)|*.png|All|*.*", function(picked)
        local e = S.project.sprites[sid]
        if not e then return end
        App.importToMod(picked, nil, function(rel)
          e.image = rel
          -- Full-color imports usually need TrueColor (skip SGB remap).
          e.trueColor = true
          spriteCache[sid] = nil
          Preview.invalidate()
          App.markDirty()
        end)
      end)
    end
    py = py + fh + 6 * s
    Kit.text("micro", "Frames", px + 10 * s, py + 6 * s, PAL.caption)
    do
      local cur = rec.frames or 1
      local v = tonumber(field(App, "ob_spr_fr", px + 70 * s, py, 50 * s, fh,
        tostring(cur), "1")) or cur
      v = math.max(1, math.min(16, math.floor(v)))
      if v ~= cur then
        rec.frames = v
        spriteCache[obj.sprite] = nil
        App.markDirty()
      end
    end
    local walkOn = rec.walker and true or false
    if Kit.chip(px + 130 * s, py, 80 * s, fh, walkOn and "WALKER" or "STILL",
        walkOn, PAL.green, nil, "6-frame walk cycle sheet") then
      rec.walker = not walkOn
      if not rec.walker then rec.walker = nil end
      spriteCache[obj.sprite] = nil
      App.markDirty()
    end
    py = py + fh + 6 * s
    Kit.text("micro", "TrueColor", px + 10 * s, py + 6 * s, PAL.caption)
    do
      local on = rec.trueColor and true or false
      if Kit.chip(px + 90 * s, py, 80 * s, fh, on and "YES" or "NO", on, PAL.yellow,
          nil, "YES = raw PNG colors (skip SGB palette remap)") then
        rec.trueColor = (not on) or nil
        if not rec.trueColor then rec.trueColor = nil end
        spriteCache[obj.sprite] = nil
        Preview.invalidate()
        App.markDirty()
      end
    end
    if Kit.button(px + 180 * s, py, 90 * s, fh, "GFX tab", {
        kind = "ghost", font = "small",
        tooltip = "Open this sprite on the GFX tab",
      }) then
      S.tab = "gfx"
      S.gfxMode = "sprites"
      S.spriteEditId = obj.sprite
    end
    py = py + fh + 8 * s
  end

  -- sprite picker grid
  if py + 14 * s <= listBottom then
    Kit.text("micro", "Sprite picker (click to set)", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
  end
  do
    local customOnly = S.mapSpriteCustomOnly and true or false
    if Kit.chip(px + 10 * s, py, 70 * s, 22 * s, "Custom", customOnly, PAL.yellow,
        nil, "Show only mod-registered sprites") then
      S.mapSpriteCustomOnly = not customOnly
      S.mapSpriteOffset = 0
      customOnly = S.mapSpriteCustomOnly
    end
    if Kit.chip(px + 86 * s, py, 50 * s, 22 * s, "All", not customOnly, PAL.green) then
      S.mapSpriteCustomOnly = false
      S.mapSpriteOffset = 0
      customOnly = false
    end
    py = py + 26 * s

    local list = spriteIds(S, customOnly)
    local q = S.mapSpriteQuery or ""
    local nq = field(App, "ob_spr_q", px + 10 * s, py, propW - 20 * s, fh, q, "filter SPRITE_")
    if nq ~= q then S.mapSpriteQuery = nq; S.mapSpriteOffset = 0 end
    py = py + fh + 6 * s
    local ql = nq:lower()
    local filtered = {}
    for _, id in ipairs(list) do
      if ql == "" or id:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    if customOnly and #filtered == 0 then
      Kit.text("micro", "(no custom sprites yet — use + New sprite)",
        px + 10 * s, py, PAL.faint)
      py = py + 20 * s
    end
    local thumb = 32 * s
    local gap = 4 * s
    local cols = math.max(1, math.floor((propW - 20 * s) / (thumb + gap)))
    local maxShow = cols * 4
    local total = #filtered
    local off = S.mapSpriteOffset or 0
    if total > 0 and off >= total then
      off = 0
      S.mapSpriteOffset = 0
    end
    local shown = 0
    local idx = off + 1
    while shown < maxShow and idx <= total and py + thumb <= listBottom do
      for c = 0, cols - 1 do
        if shown >= maxShow or idx > total then break end
        local id = filtered[idx]
        local bx = px + 10 * s + c * (thumb + gap)
        local sdef = spriteDef(S, id)
        if sdef and sdef.image then
          Preview.draw(S, sdef.image, bx, py, thumb, thumb,
            spritePreviewPal(S, sdef))
        else
          Theme.col(PAL.rowBg, 1)
          love.graphics.rectangle("fill", bx, py, thumb, thumb, 3, 3)
        end
        if obj.sprite == id then
          love.graphics.setColor(0.24, 0.88, 0.54, 1)
          love.graphics.rectangle("line", bx - 1, py - 1, thumb + 2, thumb + 2)
          love.graphics.setColor(1, 1, 1, 1)
        end
        if SpriteUtil.isOwned(S, id) then
          love.graphics.setColor(1, 0.8, 0.2, 0.9)
          love.graphics.rectangle("fill", bx + thumb - 6, py + 2, 4, 4)
          love.graphics.setColor(1, 1, 1, 1)
        end
        if Kit.press(bx, py, thumb, thumb) then
          map = assignObjectSprite(S, map, mutate, App, i, id)
          obj = map.objects[i]
        end
        idx = idx + 1
        shown = shown + 1
      end
      py = py + thumb + gap
    end
    -- Always offer More when there are multiple pages; wrap past the end.
    if total > maxShow and py + 26 * s <= listBottom then
      if Kit.button(px + 10 * s, py, 90 * s, 24 * s, "More...", {
          kind = "ghost", tooltip = "Next page (wraps to start)",
        }) then
        local nextOff = off + maxShow
        if nextOff >= total then nextOff = 0 end
        S.mapSpriteOffset = nextOff
      end
      if off > 0 and Kit.button(px + 110 * s, py, 70 * s, 24 * s, "Top", {
          kind = "ghost", tooltip = "Back to first sprites",
        }) then
        S.mapSpriteOffset = 0
      end
      local page = math.floor(off / maxShow) + 1
      local pages = math.max(1, math.ceil(total / maxShow))
      Kit.text("micro", string.format("%d/%d", page, pages),
        px + 190 * s, py + 6 * s, PAL.faint)
      py = py + 28 * s
    end
  end

  local function row(label, body)
    if py + fh + 20 * s > listBottom then return true end
    Kit.text("micro", label, px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    body(px + 10 * s, py, propW - 20 * s, fh)
    py = py + fh + 6 * s
  end

  row("Cell X / Y", function(fx, fy, fw, fh_)
    local x = tonumber(field(App, "ob_x", fx, fy, 50 * s, fh_, tostring(obj.x or 0), "0")) or 0
    local y = tonumber(field(App, "ob_y", fx + 60 * s, fy, 50 * s, fh_, tostring(obj.y or 0), "0")) or 0
    if x ~= (obj.x or 0) or y ~= (obj.y or 0) then
      map = mutate(); map.objects[i].x = x; map.objects[i].y = y
    end
  end)
  row("Movement", function(fx, fy, fw, fh_)
    if Kit.button(fx, fy, fw, fh_, tostring(obj.movement or "STAY"), { kind = "ghost" }) then
      map = mutate()
      map.objects[i].movement = cycle(MOVEMENTS, obj.movement or "STAY")
      App.markDirty()
    end
  end)
  row("Range / facing", function(fx, fy, fw, fh_)
    if Kit.button(fx, fy, fw, fh_, tostring(obj.range or "NONE"), { kind = "ghost" }) then
      map = mutate()
      map.objects[i].range = cycle(RANGES, tostring(obj.range or "NONE"))
      App.markDirty()
    end
  end)
  row("Text id", function(fx, fy, fw, fh_)
    local mid = map.id or S.mapId
    local v = field(App, "ob_text", fx, fy, fw - 70 * s, fh_, obj.text or "", "TEXT_",
      function() return Autocomplete.textIds(S, mid) end)
    if v ~= (obj.text or "") then map = mutate(); map.objects[i].text = v end
    if obj.text and obj.text ~= ""
        and Kit.button(fx + fw - 64 * s, fy, 64 * s, fh_, "Event",
          { kind = "ghost", tooltip = "Open this object's talk script in Events" }) then
      S.tab = "events"
      S.eventsMode = "scripts"
      S.eventMapId = map.id
      S.eventScriptKey = map.id .. "/" .. obj.text
    end
  end)

  -- Talk role / shop stock (text_pointers markers on this object's TEXT_*)
  local textId = obj.text
  local ptrEntry = textId and select(1, resolveTextPtr(S, map.id, textId))
  local role = ptrRole(ptrEntry)
  local ROLES = {
    { id = "talk", label = "Talk" },
    { id = "shop", label = "Shop" },
    { id = "nurse", label = "Nurse" },
    { id = "pc", label = "PC" },
    { id = "cable", label = "Cable" },
  }
  if py + fh + 20 * s <= listBottom then
    Kit.text("micro", "Talk role", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local rx = px + 10 * s
    for _, r in ipairs(ROLES) do
      local on = role == r.id
      local bw = Kit.textWidth("micro", r.label) + 14 * s
      if Kit.chip(rx, py, bw, fh, r.label, on, PAL.green) and not on then
        local tid = textId
        if not tid or tid == "" then
          map = mutate()
          tid = string.format("TEXT_%s_OBJ%d", map.id, i)
          map.objects[i].text = tid
          textId = tid
          obj = map.objects[i]
        end
        local entry = ensureTextPtr(S, map.id, tid)
        if entry then
          local keep = nil
          if r.id == "shop" then
            local src = entry.mart or (ptrEntry and ptrEntry.mart)
            if src then
              keep = {}
              for mi, id in ipairs(src) do keep[mi] = id end
            end
          end
          setPtrRole(entry, r.id, keep)
          App.markDirty()
        end
      end
      rx = rx + bw + 4 * s
    end
    py = py + fh + 6 * s
  end

  if role == "shop" and textId and textId ~= "" then
    local mart = (ptrEntry and ptrEntry.mart) or {}
    if py + 14 * s <= listBottom then
      Kit.text("micro",
        string.format("Shop stock (%d)", #mart),
        px + 10 * s, py, PAL.caption)
      py = py + 14 * s
    end
    local items = allItemIds(S)
    for mi, itemId in ipairs(mart) do
      if py + fh + 4 * s > listBottom then break end
      local label = itemId or "?"
      if Kit.button(px + 10 * s, py, propW - 56 * s, fh, label, { kind = "accent" }) then
        if #items > 0 then
          local entry = ensureTextPtr(S, map.id, textId)
          if entry and entry.mart then
            entry.mart[mi] = cycle(items, itemId)
            App.markDirty()
          end
        end
      end
      if Kit.button(px + propW - 40 * s, py, 30 * s, fh, "X", { kind = "danger" }) then
        local entry = ensureTextPtr(S, map.id, textId)
        if entry and entry.mart then
          table.remove(entry.mart, mi)
          App.markDirty()
        end
      end
      py = py + fh + 4 * s
    end
    if py + 28 * s <= listBottom
        and Kit.button(px + 10 * s, py, propW - 20 * s, 26 * s, "+ Add item",
          { kind = "good" }) then
      local entry = ensureTextPtr(S, map.id, textId)
      if entry then
        entry.mart = entry.mart or {}
        entry.mart[#entry.mart + 1] = (#items > 0 and items[1]) or "POKE_BALL"
        App.markDirty()
      end
      py = py + 32 * s
    end
  end

  row("Name", function(fx, fy, fw, fh_)
    local v = field(App, "ob_name", fx, fy, fw, fh_, obj.name or "", "NAME")
    if v ~= (obj.name or "") then
      map = mutate()
      map.objects[i].name = (v ~= "" and v) or nil
    end
  end)

  -- Fixed wild: object.pokemon + level → OverworldState static wild battle
  if py + fh + 20 * s <= listBottom then
    Kit.text("micro", "Fixed wild (cell)", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local isWild = obj.pokemon and obj.pokemon ~= ""
    if Kit.chip(px + 10 * s, py, 100 * s, fh, isWild and "ON" or "OFF",
        isWild, PAL.yellow) then
      map = mutate()
      if isWild then
        map.objects[i].pokemon = nil
        map.objects[i].level = nil
      else
        -- Mutually exclusive with trainer battle on the same object.
        map.objects[i].trainerClass = nil
        map.objects[i].trainerParty = nil
        map.objects[i].pokemon = S.placeWildSpecies or "ARTICUNO"
        map.objects[i].level = tonumber(S.placeWildLevel) or 50
        local tid = map.objects[i].text
        if not tid or tid == "" then
          tid = string.format("TEXT_%s_WILD%d", map.id, i)
          map.objects[i].text = tid
        end
        local cry = "_" .. (map.id or "MAP") .. "Wild" .. i
        local entry = ensureTextPtr(S, map.id, tid)
        if entry and (not entry.text or entry.text == "") then
          entry.text = cry
        end
        State.ensureProjectFields(S.project)
        local key = (entry and entry.text) or cry
        S.project.text[key] = S.project.text[key] or "Gyaoo!"
      end
      App.markDirty()
      obj = map.objects[i]
      isWild = obj.pokemon and obj.pokemon ~= ""
    end
    py = py + fh + 6 * s
  end

  if obj.pokemon and obj.pokemon ~= "" then
    row("Species", function(fx, fy, fw, fh_)
      SpeciesPicker.field(S, {
        x = fx, y = fy, w = fw, h = fh_,
        current = obj.pokemon or "ARTICUNO",
        title = "FIXED WILD SPECIES",
        onPick = function(id)
          map = mutate()
          map.objects[i].pokemon = id
          S.placeWildSpecies = id
          App.markDirty()
        end,
      })
    end)
    row("Level", function(fx, fy, fw, fh_)
      local cur = tonumber(obj.level) or 50
      local v = tonumber(field(App, "ob_wild_lv", fx, fy, 70 * s, fh_,
        tostring(cur), "50")) or cur
      v = math.max(1, math.min(100, v))
      if v ~= cur then
        map = mutate()
        map.objects[i].level = v
        S.placeWildLevel = v
      end
    end)
    if py + 14 * s <= listBottom then
      Kit.text("micro", "Talk cry uses this object's Text id (Dialog tab).",
        px + 10 * s, py, PAL.faint)
      py = py + 16 * s
    end
  end

  -- Trainer battle: object.trainerClass engages OverworldState:engageTrainer
  if py + fh + 20 * s <= listBottom then
    Kit.text("micro", "Trainer battle", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local isTrainer = obj.trainerClass and obj.trainerClass ~= ""
    if Kit.chip(px + 10 * s, py, 100 * s, fh, isTrainer and "ON" or "OFF",
        isTrainer, PAL.red) then
      map = mutate()
      if isTrainer then
        map.objects[i].trainerClass = nil
        map.objects[i].trainerParty = nil
      else
        map.objects[i].pokemon = nil
        map.objects[i].level = nil
        map.objects[i].trainerClass = S.trainerId or "OPP_YOUNGSTER"
        map.objects[i].trainerParty = tonumber(S.placeTrainerParty) or 1
        State.ensureProjectFields(S.project)
        local label = State.mapLabel(S, map.id)
        local idx = map.objects[i].index or i
        S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
        if not S.project.trainer_headers[label][idx] then
          local base = "_" .. (map.id or "MAP") .. "Trainer" .. idx
          local beat = State.modFlag(S.project,
            "BEAT_" .. (map.id or "MAP") .. "_" .. idx)
          S.project.eventFlags = S.project.eventFlags or {}
          S.project.eventFlags[beat] = true
          S.project.trainer_headers[label][idx] = {
            range = 2,
            battle = base .. "Battle",
            won = base .. "Won",
            after = base .. "After",
            event = beat,
            opponent = map.objects[i].trainerClass,
            party = map.objects[i].trainerParty or 1,
          }
          S.project.text[base .. "Battle"] = "Let's fight!"
          S.project.text[base .. "Won"] = "I lost..."
          S.project.text[base .. "After"] = "You're strong."
        end
      end
      App.markDirty()
      obj = map.objects[i]
      isTrainer = obj.trainerClass and obj.trainerClass ~= ""
    end
    if Kit.button(px + 120 * s, py, 110 * s, fh, "Edit parties",
        { kind = "ghost" }) then
      if obj.trainerClass then S.trainerId = obj.trainerClass end
      S.tab = "trainers"
    end
    py = py + fh + 6 * s
  end

  if obj.trainerClass and obj.trainerClass ~= "" then
    row("Class (OPP_*)", function(fx, fy, fw, fh_)
      local v = field(App, "ob_tc", fx, fy, fw, fh_, obj.trainerClass or "", "OPP_",
        function() return Autocomplete.trainerIds(S) end)
      v = v ~= "" and v:upper():gsub("%s+", "_") or nil
      if v ~= obj.trainerClass then
        map = mutate()
        map.objects[i].trainerClass = v
        if v then S.trainerId = v end
        local label = State.mapLabel(S, map.id)
        local idx = map.objects[i].index or i
        State.ensureProjectFields(S.project)
        if S.project.trainer_headers[label]
            and S.project.trainer_headers[label][idx] then
          S.project.trainer_headers[label][idx].opponent = v
        end
      end
    end)
    row("Party index", function(fx, fy, fw, fh_)
      local cur = obj.trainerParty or 1
      local v = tonumber(field(App, "ob_tp", fx, fy, 60 * s, fh_, tostring(cur), "1")) or 1
      v = math.max(1, v)
      if v ~= cur then
        map = mutate()
        map.objects[i].trainerParty = v
        S.placeTrainerParty = v
        local label = State.mapLabel(S, map.id)
        local idx = map.objects[i].index or i
        if S.project.trainer_headers[label]
            and S.project.trainer_headers[label][idx] then
          S.project.trainer_headers[label][idx].party = v
        end
      end
    end)

    -- Battle / won / after lines live on trainer_headers[mapLabel][objIndex]
    State.ensureProjectFields(S.project)
    local label = State.mapLabel(S, map.id)
    local idx = obj.index or i
    local projH = S.project.trainer_headers[label]
      and S.project.trainer_headers[label][idx]
    local baseH = S.data and S.data.trainer_headers
      and S.data.trainer_headers[label]
      and S.data.trainer_headers[label][idx]
    local hdr = projH or baseH
    local function ensureHdr()
      State.ensureProjectFields(S.project)
      S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
      if not S.project.trainer_headers[label][idx] then
        local copy = {}
        if baseH then for k, v in pairs(baseH) do copy[k] = v end end
        copy.opponent = copy.opponent or obj.trainerClass
        copy.party = copy.party or obj.trainerParty or 1
        copy.range = copy.range or 2
        local base = "_" .. (map.id or "MAP") .. "Trainer" .. idx
        copy.battle = copy.battle or (base .. "Battle")
        copy.won = copy.won or (base .. "Won")
        copy.after = copy.after or (base .. "After")
        if not copy.event or copy.event == "" then
          copy.event = State.modFlag(S.project,
            "BEAT_" .. (map.id or "MAP") .. "_" .. idx)
        end
        S.project.eventFlags = S.project.eventFlags or {}
        S.project.eventFlags[copy.event] = true
        S.project.trainer_headers[label][idx] = copy
        for _, key in ipairs({ "battle", "won", "after" }) do
          local tid = copy[key]
          if tid and S.project.text[tid] == nil then
            local body = (S.data and S.data.text and S.data.text[tid]) or ""
            if body == "" then
              body = (key == "battle" and "Let's fight!")
                or (key == "won" and "I lost...")
                or "You're strong."
            end
            S.project.text[tid] = body
          end
        end
      end
      return S.project.trainer_headers[label][idx]
    end

    row("Sight range", function(fx, fy, fw, fh_)
      local cur = (hdr and hdr.range) or 0
      local v = tonumber(field(App, "ob_tr", fx, fy, 50 * s, fh_, tostring(cur), "2")) or 0
      if v ~= cur then
        ensureHdr().range = v
        App.markDirty()
      end
    end)

    local function textBody(tid)
      if not tid then return "" end
      if S.project.text and S.project.text[tid] ~= nil then
        return S.project.text[tid]
      end
      if S.data and S.data.text and S.data.text[tid] then
        return S.data.text[tid]
      end
      return ""
    end
    local function editLine(caption, key, placeholder)
      if py + fh + 20 * s > listBottom then return end
      Kit.text("micro", caption, px + 10 * s, py, PAL.caption)
      py = py + 14 * s
      local tid = hdr and hdr[key]
      local body = textBody(tid)
      local shown = body:gsub("\n", "\\n"):gsub("\f", "\\f")
      local v = field(App, "ob_" .. key .. "_" .. i, px + 10 * s, py,
        propW - 20 * s, fh, shown, placeholder)
      local decoded = v:gsub("\\n", "\n"):gsub("\\f", "\f")
      if decoded ~= body then
        local h = ensureHdr()
        if not h[key] or h[key] == "" then
          h[key] = "_" .. (map.id or "MAP") .. "Trainer" .. idx
            .. key:sub(1, 1):upper() .. key:sub(2)
        end
        S.project.text[h[key]] = decoded
        App.markDirty()
      end
      py = py + fh + 6 * s
    end
    editLine("Before battle", "battle", "Let's fight!")
    editLine("On win", "won", "I lost...")
    editLine("After (defeated)", "after", "You're strong.")

    row("Beat flag", function(fx, fy, fw, fh_)
      -- Field id includes map + object index so typing never bleeds.
      local cur = (hdr and hdr.event) or ""
      local v = field(App, "ob_ev_" .. tostring(map.id) .. "_" .. idx,
        fx, fy, fw, fh_, cur, "MOD_BEAT_…")
      v = (v ~= "" and v) or nil
      if v ~= (cur ~= "" and cur or nil) then
        local h = ensureHdr()
        -- If other object indices share this table ref, clone them first.
        local bucket = S.project.trainer_headers[label]
        if type(bucket) == "table" then
          for other, oh in pairs(bucket) do
            if other ~= idx and oh == h then
              local copy = {}
              for k, val in pairs(oh) do copy[k] = val end
              bucket[other] = copy
            end
          end
        end
        if not v then
          v = State.modFlag(S.project,
            "BEAT_" .. (map.id or "MAP") .. "_" .. idx)
        else
          v = State.modFlag(S.project, v)
        end
        -- Do not write eventFlags on each keystroke (leaves H / HI / HIDE_…).
        h.event = v
        hdr = h
        App.markDirty()
      end
    end)
  end

  row("Hidden", function(fx, fy, fw, fh_)
    local on = obj.hidden and true or false
    if Kit.chip(fx, fy, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
      map = mutate()
      map.objects[i].hidden = (not on) or nil
      App.markDirty()
    end
  end)

  return py
end

local function drawSigns(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  map.signs = map.signs or {}
  py, S.mapSignIndex = drawListPicker(S, "mapSignIndex", #map.signs, px, py, propW, fh, s, PAL.yellow)
  local i = S.mapSignIndex
  local sign = i and map.signs[i]
  if not sign then return py end

  local function row(label, body)
    if py + fh + 20 * s > listBottom then return true end
    Kit.text("micro", label, px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    body(px + 10 * s, py, propW - 20 * s, fh)
    py = py + fh + 6 * s
  end

  row("Cell X / Y", function(fx, fy, fw, fh_)
    local x = tonumber(field(App, "sg_x", fx, fy, 50 * s, fh_, tostring(sign.x or 0), "0")) or 0
    local y = tonumber(field(App, "sg_y", fx + 60 * s, fy, 50 * s, fh_, tostring(sign.y or 0), "0")) or 0
    if x ~= (sign.x or 0) or y ~= (sign.y or 0) then
      map = mutate(); map.signs[i].x = x; map.signs[i].y = y
    end
  end)
  row("Text id", function(fx, fy, fw, fh_)
    local mid = map.id or S.mapId
    local v = field(App, "sg_text", fx, fy, fw, fh_, sign.text or "", "TEXT_",
      function() return Autocomplete.textIds(S, mid) end)
    if v ~= (sign.text or "") then map = mutate(); map.signs[i].text = v end
  end)
  if py + 32 * s <= listBottom then
    if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Delete sign",
        { kind = "danger" }) then
      map = mutate()
      table.remove(map.signs, i)
      S.mapSignIndex = math.min(i, #map.signs)
      MapLoader.invalidate(map.id)
      App.markDirty()
    end
    py = py + 34 * s
  end
  return py
end

local function drawHiddenItems(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  State.ensureProjectFields(S.project)
  local mapId = map.id or S.mapId
  local items, owned = resolveHiddenItems(S, mapId)
  items = items or {}

  Kit.text("micro", "Hidden items (field.hiddenItems)", px + 10 * s, py, PAL.muted)
  py = py + 18 * s
  if not owned and #items > 0 then
    Kit.text("micro", "Vanilla -- edit to override", px + 10 * s, py, PAL.faint)
    py = py + 16 * s
  elseif #items == 0 then
    Kit.text("micro", "No hidden items on this map.", px + 10 * s, py, PAL.faint)
    py = py + 18 * s
  end

  Kit.text("micro", "Pickups (x, y, item)", px + 10 * s, py, PAL.caption)
  py = py + 16 * s
  for hi = 1, #items do
    if py + fh > listBottom - 36 * s then break end
    local h = items[hi]
    local x = tonumber(field(App, "hi_x_" .. hi, px + 10 * s, py, 40 * s, fh,
      tostring(h.x or 0), "0")) or 0
    local y = tonumber(field(App, "hi_y_" .. hi, px + 56 * s, py, 40 * s, fh,
      tostring(h.y or 0), "0")) or 0
    local item = field(App, "hi_it_" .. hi, px + 102 * s, py, propW - 154 * s, fh,
      h.item or "POTION", "POTION"):upper():gsub("%s+", "_")
    if x ~= (h.x or 0) or y ~= (h.y or 0) or item ~= (h.item or "") then
      local list = ensureHiddenItems(S, mapId)
      list[hi] = { x = x, y = y, item = item }
      App.markDirty()
    end
    if Kit.button(px + propW - 42 * s, py, 28 * s, fh, "X", { kind = "danger" }) then
      local list = ensureHiddenItems(S, mapId)
      table.remove(list, hi)
      App.markDirty()
      break
    end
    py = py + fh + 4 * s
  end

  if py + 30 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "+ Add", { kind = "good" }) then
      local list = ensureHiddenItems(S, mapId)
      list[#list + 1] = { x = 0, y = 0, item = "POTION" }
      App.markDirty()
    end
    py = py + 32 * s
  end
  if owned and #items > 0 and py + 36 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "Clear all",
        { kind = "ghost" }) then
      S.project.hiddenItems[mapId] = {}
      App.markDirty()
    end
    py = py + 36 * s
  end
  return py
end

local function drawBadgeGates(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  State.ensureProjectFields(S.project)
  local mapId = map.id or S.mapId
  local gate, owned, deleted = resolveBadgeGate(S, mapId)

  Kit.text("micro", "Badge gate (field.badgeGates)", px + 10 * s, py, PAL.muted)
  py = py + 18 * s

  if deleted or not gate then
    if deleted then
      Kit.text("micro",
        "Gate removed for this mod (Save writes DELETE so it stays gone).",
        px + 10 * s, py, PAL.yellow)
      py = py + 18 * s
    else
      Kit.text("micro", "No badge gate on this map.", px + 10 * s, py, PAL.faint)
      py = py + 18 * s
    end
    if py + 30 * s <= listBottom
        and Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add gate",
          { kind = "good" }) then
      ensureBadgeGate(S, mapId)
      App.markDirty()
    end
    return py + 36 * s
  end

  -- Remove sits at the top so it is never clipped below the panel.
  if py + 30 * s <= listBottom
      and Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Remove gate", {
        kind = "danger",
        tooltip = "Delete this badge gate (emits mod.DELETE on Save)",
      }) then
    removeBadgeGate(S, mapId)
    App.markDirty()
    return py + 36 * s
  end
  py = py + 34 * s

  if not owned then
    Kit.text("micro", "Vanilla — edit clones into the mod", px + 10 * s, py, PAL.faint)
    py = py + 16 * s
  end

  local function row(label, body)
    if py + fh + 20 * s > listBottom then return true end
    Kit.text("micro", label, px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    body(px + 10 * s, py, propW - 20 * s, fh)
    py = py + fh + 6 * s
  end

  local function patchGate(fieldKey, value)
    local g = ensureBadgeGate(S, mapId)
    if g[fieldKey] ~= value then
      g[fieldKey] = value
      syncLiveBadgeGate(S, mapId, g)
      App.markDirty()
    end
  end

  row("Badge", function(fx, fy, fw, fh_)
    local v = field(App, "bg_badge", fx, fy, fw, fh_,
      gate.badge or "BOULDERBADGE", "BOULDERBADGE"):upper():gsub("%s+", "_")
    if v ~= (gate.badge or "") then patchGate("badge", v) end
  end)
  row("Text id", function(fx, fy, fw, fh_)
    local v = field(App, "bg_text", fx, fy, fw, fh_, gate.text or "", "TEXT_*")
    if v ~= (gate.text or "") then patchGate("text", v ~= "" and v or nil) end
  end)
  row("Fail text id", function(fx, fy, fw, fh_)
    local v = field(App, "bg_fail", fx, fy, fw, fh_, gate.failText or "", "TEXT_*")
    if v ~= (gate.failText or "") then patchGate("failText", v ~= "" and v or nil) end
  end)
  row("Pass text id", function(fx, fy, fw, fh_)
    local v = field(App, "bg_pass", fx, fy, fw, fh_, gate.passText or "", "TEXT_*")
    if v ~= (gate.passText or "") then patchGate("passText", v ~= "" and v or nil) end
  end)
  row("Passed flag", function(fx, fy, fw, fh_)
    local v = field(App, "bg_flag", fx, fy, fw, fh_,
      gate.passedFlag or "", "PASSED_* or EVENT_*")
    if v ~= (gate.passedFlag or "") then patchGate("passedFlag", v ~= "" and v or nil) end
  end)

  local coords = gate.coords or {}
  Kit.text("micro", "Guard cells (x, y)", px + 10 * s, py, PAL.caption)
  py = py + 16 * s
  for ci = 1, #coords do
    if py + fh > listBottom - 36 * s then break end
    local c = coords[ci]
    local cx = tonumber(field(App, "bg_x_" .. ci, px + 10 * s, py, 40 * s, fh,
      tostring(c.x or 0), "0")) or 0
    local cy = tonumber(field(App, "bg_y_" .. ci, px + 56 * s, py, 40 * s, fh,
      tostring(c.y or 0), "0")) or 0
    if cx ~= (c.x or 0) or cy ~= (c.y or 0) then
      local g = ensureBadgeGate(S, mapId)
      g.coords = g.coords or cloneGateCoords(coords)
      g.coords[ci] = { x = cx, y = cy }
      syncLiveBadgeGate(S, mapId, g)
      App.markDirty()
    end
    if Kit.button(px + propW - 42 * s, py, 28 * s, fh, "X", { kind = "danger" }) then
      local g = ensureBadgeGate(S, mapId)
      g.coords = g.coords or cloneGateCoords(coords)
      table.remove(g.coords, ci)
      syncLiveBadgeGate(S, mapId, g)
      App.markDirty()
      break
    end
    py = py + fh + 4 * s
  end
  if py + 30 * s <= listBottom
      and Kit.button(px + 10 * s, py, 100 * s, 28 * s, "+ Add cell",
        { kind = "accent" }) then
    local g = ensureBadgeGate(S, mapId)
    g.coords = g.coords or cloneGateCoords(coords)
    g.coords[#g.coords + 1] = { x = 0, y = 0 }
    syncLiveBadgeGate(S, mapId, g)
    App.markDirty()
    py = py + 32 * s
  end
  return py
end

local function drawEncounters(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  py = EncounterEdit.drawWild(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  if py + 36 * s <= listBottom then
    if Kit.button(px + 10 * s, py, propW - 20 * s, 30 * s,
        "Specials on Encounters tab", { kind = "ghost" }) then
      S.tab = "encounters"
      S.encountersMode = "special"
      if S.mapId then S.encountersMapId = S.mapId end
    end
    py = py + 36 * s
  end
  return py
end

function Maps.draw(S, x, y, w, h, App)
  acS = S
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end

  syncMapEditMode(S)
  S.mapViewMode = S.mapViewMode or "editor"

  -- Left column: map list (top) + tileset palette (bottom) — RM XP layout.
  local leftW = math.min(250 * s, w * 0.28)
  Kit.caption(x, y, "MAPS")
  local modeX = x + Kit.textWidth("caption", "MAPS") + 12 * s
  local modeY = y
  for _, mode in ipairs({
    { id = "editor", label = "Editor" },
    { id = "world", label = "World" },
  }) do
    local on = S.mapViewMode == mode.id
    local bw = Kit.textWidth("micro", mode.label) + 14 * s
    if Kit.chip(modeX, modeY, bw, 22 * s, mode.label, on, PAL.green, nil,
        mode.id == "world"
          and "Show this map and its N/S/E/W neighbors"
          or "RM XP–style map editor") then
      S.mapViewMode = mode.id
      if mode.id == "world" then S._worldFitKey = nil end
    end
    modeX = modeX + bw + 4 * s
  end
  -- Map | Events layer toggle (like RM XP tile vs event layer).
  modeX = modeX + 8 * s
  for _, mode in ipairs({
    { id = "map", label = "Map", tip = "Pencil / tileset / Passage" },
    { id = "events", label = "Events", tip = "NPCs, transfers, signs, trainers" },
  }) do
    local on = (S.mapEditMode or "map") == mode.id
    local bw = Kit.textWidth("micro", mode.label) + 14 * s
    if Kit.chip(modeX, modeY, bw, 22 * s, mode.label, on, PAL.blue, nil, mode.tip) then
      syncMapEditMode(S, mode.id)
      if mode.id == "map" then
        S.status = "Map layer: Pencil paints blocks · Passage edits tileset slot"
      else
        S.status = "Event layer: place NPCs / Transfers / signs"
      end
    end
    modeX = modeX + bw + 4 * s
  end

  local qh = 26 * s
  local qy = y + 24 * s
  local q, qChanged = Search.field(S, "mapQuery", x, qy, leftW, qh, "search maps...")
  if qChanged then S.mapListOffset = 0 end

  local leftTop = qy + qh + 6 * s
  local leftBot = y + h
  local leftBodyH = leftBot - leftTop
  local newMapH = 30 * s
  local listFrac = 0.40
  local mapListH = math.max(100 * s, leftBodyH * listFrac - newMapH - 6 * s)
  local tilesetY = leftTop + mapListH + newMapH + 10 * s
  local tilesetH = math.max(120 * s, leftBot - tilesetY)

  Kit.card(x, leftTop, leftW, mapListH, 10 * s)

  local ids = allMapIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local mdef = S.project.maps[id]
        or (S.data.maps and S.data.maps[id])
      local label = mdef and tostring(mdef.label or "") or ""
      local ts = mdef and tostring(mdef.tileset or "") or ""
      if id:lower():find(ql, 1, true)
          or label:lower():find(ql, 1, true)
          or ts:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  local rowH = 26 * s
  local perPage = math.max(1, math.floor((mapListH - 14 * s) / (rowH + 3 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = leftW - 12 * s
  local mapScrollH = mapListH - 14 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.mapListOffset = Kit.scroll(mapScrollX, leftTop + 6 * s, mapScrollW,
    mapScrollH, S.mapListOffset or 0, #ids, perPage, nil, "mapListOffset")
  local mapNav = RegList.bindNav(S, ids, {
    selKey = "mapId",
    offsetKey = "mapListOffset",
    perPage = perPage,
    onSelect = function(id)
      S._mapIdDraft = nil
      S._mapCenteredFor = nil
      S._mapPaletteFor = nil
      S.mapSel, S._mapSelDraft, S._mapShiftDraft = nil, nil, nil
      S._mapSelFor = id
      S.mapObjectIndex, S.mapWarpIndex, S.mapSignIndex = 1, 1, 1
      if S.mapViewMode == "world" then S._worldFitKey = nil end
    end,
  })
  local ry = leftTop + 6 * s
  for i = (S.mapListOffset or 0) + 1, math.min(#ids, (S.mapListOffset or 0) + perPage) do
    local id = ids[i]
    local rowOwned = S.project.maps[id] ~= nil
    if Kit.row(mapScrollX, ry, mapRowW, rowH, S.mapId == id, PAL.green) then
      mapNav.activate()
      S.mapId = id
      S._mapIdDraft = nil
      S._mapCenteredFor = nil
      S._mapPaletteFor = nil
      S.mapSel, S._mapSelDraft, S._mapShiftDraft = nil, nil, nil
      S._mapSelFor = id
      S.mapObjectIndex, S.mapWarpIndex, S.mapSignIndex = 1, 1, 1
      if S.mapViewMode == "world" then S._worldFitKey = nil end
    end
    local textX = mapScrollX + 6 * s
    local textMax = math.max(8, mapRowW - 12 * s)
    local label = Kit.ellipsize("mono", id, textMax)
    Kit.pushClip(mapScrollX, ry, mapRowW, rowH)
    Kit.text("mono", label, textX, ry + 5 * s, rowOwned and PAL.text or PAL.muted)
    Kit.popClip()
    ry = ry + rowH + 3 * s
  end
  S.mapListOffset = Kit.scrollbar(mapScrollX, leftTop + 6 * s, mapScrollW,
    mapScrollH, S.mapListOffset or 0, #ids, perPage, "mapListOffset")

  if Kit.button(x, leftTop + mapListH + 4 * s, leftW, newMapH, "+ New map",
      { kind = "good" }) then
    local nid = "NEW_MAP"
    local n = 1
    while S.project.maps[nid] or (S.data.maps and S.data.maps[nid]) do
      n = n + 1; nid = "NEW_MAP_" .. n
    end
    local idx = S.project.nextMapIndex or 1000
    S.project.nextMapIndex = idx + 1
    local ts = tilesetIds(S)[1] or "OVERWORLD"
    S.project.maps[nid] = defaultMap(nid, idx, ts)
    S.mapId = nid
    S.mapPaletteTileset = ts
    S._mapPaletteFor = nid
    S._mapCenteredFor = nil
    syncMapEditMode(S, "map")
    App.markDirty()
  end

  local map, owned = resolveMapDef(S, S.mapId)
  if not map then
    local first = ids[1]
    S.mapId = first
    map, owned = resolveMapDef(S, first)
  end

  local function mutate()
    map = ensureOwned(S, S.mapId)
    owned = true
    return map
  end

  if map then
    map = drawTilesetDock(S, map, mutate, App, x, tilesetY, leftW, tilesetH) or map
  else
    Kit.emptyBox(x, tilesetY, leftW, tilesetH, "No map selected")
  end

  -- Center + right
  local split = 6 * s
  local mainX = x + leftW + 10 * s
  local mainW = math.max(120 * s, w - leftW - 10 * s)
  -- Keep a usable map canvas; Theme.clamp breaks when min > max.
  local canvasMin = 140 * s
  local rightMinWanted = 280 * s
  local rightMaxByCanvas = math.max(120 * s, mainW - split - canvasMin)
  local rightMin = math.min(rightMinWanted, rightMaxByCanvas)
  local rightMax = math.max(rightMin, math.min(
    rightMaxByCanvas, math.max(rightMin, (w - leftW) * 0.48)))
  local rightDefault = Theme.clamp(320 * s, rightMin, rightMax)
  local rightW = Theme.clamp(S.mapRightW or rightDefault, rightMin, rightMax)

  if S.mapViewMode == "world" then
    local propW = math.min(260 * s, rightW + 40 * s)
    local worldY = qy
    local worldH = h - (worldY - y)
    drawWorldView(S, App, mainX, worldY, mainW, worldH, propW)
    return
  end

  -- Tool strip (filtered by Map / Events mode)
  local tools
  if (S.mapEditMode or "map") == "events" then
    tools = {
      { id = "object", label = "Event", tip = "Place / select NPC events" },
      { id = "warp", label = "Transfer", tip = "Place map transfers (warps)" },
      { id = "sign", label = "Sign", tip = "Place signs" },
      { id = "trainer", label = "Trainer", tip = "Place a trainer event" },
      { id = "wild", label = "Wild", tip = "Place a fixed wild encounter" },
    }
  else
    tools = {
      { id = "paint", label = "Pencil", tip = "Paint the selected tileset block" },
      { id = "erase", label = "Eraser", tip = "Paint block 0 (empty)" },
      { id = "pick", label = "Pick", tip = "Sample a block from the map" },
      { id = "select", label = "Select", tip = "Marquee select blocks (copy/paste/shift)" },
      { id = "collision", label = "Passage",
        tip = "Walk/solid/water/grass on this map's tileset slot" },
    }
  end
  local tx = mainX
  for _, tool in ipairs(tools) do
    local on = (S.mapTool or "paint") == tool.id
    local label = tool.label or tool.id:upper()
    local bw = math.max(58 * s, Kit.textWidth("micro", label) + 14 * s)
    if Kit.chip(tx, y, bw, 26 * s, label, on, PAL.blue, nil, tool.tip) then
      S.mapTool = tool.id
      if EVENT_TOOLS[tool.id] then
        syncMapEditMode(S, "events")
        if tool.id == "warp" then S.mapSection = "warps"
        elseif tool.id == "sign" then S.mapSection = "signs"
        else S.mapSection = "objects" end
      else
        syncMapEditMode(S, "map")
      end
      if tool.id == "collision" then
        S.mapShowCollision = true
        S.mapCollisionMode = S.mapCollisionMode or "solid"
        S.status = "Passage: paints this map's tileset slot (auto-clones if shared)"
      elseif tool.id == "paint" then
        S.status = "Pencil: paint blocks from the tileset palette"
      elseif tool.id == "object" then
        S.status = "Event: click the map to place an NPC"
      elseif tool.id == "warp" then
        S.status = "Transfer: click the map to place a warp"
      elseif tool.id == "wild" then
        S.placeWildSpecies = S.placeWildSpecies or "ARTICUNO"
        S.placeWildLevel = S.placeWildLevel or 50
        S.placeSprite = S.placeSprite or "SPRITE_BIRD"
        S.status = string.format("Wild: %s Lv%d — click a cell",
          tostring(S.placeWildSpecies), tonumber(S.placeWildLevel) or 50)
      elseif tool.id == "trainer" then
        S.trainerId = S.trainerId or "OPP_YOUNGSTER"
        S.placeTrainerParty = S.placeTrainerParty or 1
        S.placeSprite = S.placeSprite or "SPRITE_YOUNGSTER"
        S.status = string.format("Trainer: %s party %d — click a cell",
          tostring(S.trainerId), tonumber(S.placeTrainerParty) or 1)
      end
    end
    tx = tx + bw + 4 * s
  end
  if (S.mapTool or "paint") == "collision" then
    for _, mode in ipairs({
      { id = "solid", label = "Solid", tip = "Blocked / not walkable", accent = PAL.red },
      { id = "walk", label = "Walk", tip = "Passable (walkable list)", accent = PAL.green },
      { id = "water", label = "Water", tip = "Surf water", accent = PAL.blue },
      { id = "grass", label = "Grass", tip = "Tall grass (wild encounters)",
        accent = { 240, 70, 220 } },
      { id = "shore", label = "Shore", tip = "Shore / beach edge", accent = PAL.blue },
      { id = "ledge", label = "Ledge", tip = "Click ledge cell; hop dir below",
        accent = { 255, 140, 40 } },
      { id = "none", label = "None", tip = "Clear grass / water / shore / ledge",
        accent = PAL.steel },
    }) do
      local on = (S.mapCollisionMode or "solid") == mode.id
      local mw = Kit.textWidth("micro", mode.label) + 14 * s
      if Kit.chip(tx, y, mw, 26 * s, mode.label, on, mode.accent, nil, mode.tip) then
        S.mapCollisionMode = mode.id
        if mode.id == "ledge" then
          S.mapLedgeDir = S.mapLedgeDir or "down"
        end
      end
      tx = tx + mw + 3 * s
    end
    if (S.mapCollisionMode or "solid") == "ledge" then
      for _, d in ipairs({
        -- ASCII only — editor fonts often lack Unicode arrows (tofu □).
        { id = "down", label = "v" },
        { id = "left", label = "<" },
        { id = "right", label = ">" },
        { id = "up", label = "^" },
      }) do
        local on = (S.mapLedgeDir or "down") == d.id
        if Kit.chip(tx, y, 28 * s, 26 * s, d.label, on, { 255, 140, 40 }, nil,
            "Hop direction: " .. d.id) then
          S.mapLedgeDir = d.id
        end
        tx = tx + 31 * s
      end
    end
  end
  if Kit.button(tx + 4 * s, y, 64 * s, 26 * s, "Dialog", {
      kind = "ghost", tooltip = "Edit this map's NPC / sign text",
    }) then
    S.tab = "dialog"
    S.dialogMapId = S.mapId
  end
  tx = tx + 72 * s
  if Kit.stepper(tx, y, 26 * s, 26 * s, "-", {
      radius = 6 * s, tooltip = "Zoom out",
    }) then
    S.mapZoom = clampZoom((S.mapZoom or 2) - 0.25)
  end
  Kit.text("mono", string.format("%.1fx", S.mapZoom or 2),
    tx + 28 * s, y + 6 * s, PAL.muted)
  if Kit.stepper(tx + 70 * s, y, 26 * s, 26 * s, "+", {
      radius = 6 * s, tooltip = "Zoom in",
    }) then
    S.mapZoom = clampZoom((S.mapZoom or 2) + 0.25)
  end
  if Kit.button(tx + 100 * s, y, 44 * s, 26 * s, "Fit", { kind = "ghost" }) then
    S._mapCenteredFor = nil
  end
  if Kit.chip(tx + 150 * s, y, 52 * s, 26 * s, "Grid",
      S.mapShowGrid, PAL.steel, nil,
      "Toggle paint-block grid (32px)") then
    S.mapShowGrid = not S.mapShowGrid
  end

  local barY = y + 30 * s
  local barH = 34 * s
  if S._mapSelFor ~= S.mapId then
    S.mapSel, S._mapSelDraft, S._mapShiftDraft = nil, nil, nil
    S._mapSelFor = S.mapId
  end
  if map and (S.mapTool or "paint") == "select" then
    barH = 38 * s
    local bx = mainX
    if Kit.button(bx, barY + 4 * s, 44 * s, 28 * s, "All", {
        kind = "accent", tooltip = "Select every block on this map",
      }) then
      S.mapSel = selectAllBlocks(map)
      S._mapSelFor = S.mapId
      S.status = "Selected all blocks"
    end
    bx = bx + 48 * s
    if Kit.button(bx, barY + 4 * s, 52 * s, 28 * s, "Clear", {
        kind = "ghost", tooltip = "Clear block selection",
      }) then
      S.mapSel, S._mapSelDraft = nil, nil
      S.status = "Selection cleared"
    end
    bx = bx + 58 * s
    if Kit.button(bx, barY + 4 * s, 52 * s, 28 * s, "Copy", {
        kind = "accent",
        tooltip = "Copy selection (Ctrl+C). Paste with Ctrl+V or Shift+RMB",
      }) then
      local x0, y0, x1, y1 = normalizeBlockSel(S.mapSel)
      if not x0 then
        S.status = "Select a region (or All) before copying"
      else
        local bw, bh = copyBlocksToClip(S, map, x0, y0, x1, y1)
        if bw then
          S.status = string.format("Copied %dx%d — Ctrl+V or Shift+RMB to paste",
            bw, bh)
        end
      end
    end
    bx = bx + 56 * s
    if Kit.button(bx, barY + 4 * s, 52 * s, 28 * s, "Paste", {
        kind = "good",
        tooltip = "Paste clipboard at hover / selection top-left (Ctrl+V)",
      }) then
      local dx, dy = pasteDestBlock(S, map)
      local ok, msg = pasteClipAt(S, S.mapId, dx, dy, App)
      S.status = msg or (ok and "Pasted" or "Paste failed")
      map = resolveMapDef(S, S.mapId)
    end
    bx = bx + 58 * s
    Kit.text("micro", "dx", bx, barY + 2 * s, PAL.caption)
    Kit.text("micro", "dy", bx + 54 * s, barY + 2 * s, PAL.caption)
    local draft = S._mapShiftDraft
    if draft == nil or draft.forId ~= S.mapId then
      draft = { forId = S.mapId, dx = "0", dy = "0" }
      S._mapShiftDraft = draft
    end
    local dxStr = Kit.textfield("mp_sh_dx", bx, barY + 14 * s, 48 * s, 22 * s,
      draft.dx, "0")
    local dyStr = Kit.textfield("mp_sh_dy", bx + 54 * s, barY + 14 * s, 48 * s, 22 * s,
      draft.dy, "0")
    local shifting = (Kit.focus == "mp_sh_dx" or Kit.focus == "mp_sh_dy")
    if shifting then
      draft.dx, draft.dy = dxStr, dyStr
    else
      draft.dx = tostring(math.floor(tonumber(dxStr) or 0))
      draft.dy = tostring(math.floor(tonumber(dyStr) or 0))
    end
    bx = bx + 112 * s
    local function applyShift(dx, dy)
      local sel = S.mapSel
      if not sel then
        S.status = "Select a region (or All) before shifting"
        return
      end
      local x0, y0, x1, y1 = normalizeBlockSel(sel)
      if not x0 then
        S.status = "Select a region (or All) before shifting"
        return
      end
      shiftMapRegion(S, S.mapId, x0, y0, x1, y1, dx, dy, App)
      map = resolveMapDef(S, S.mapId)
    end
    if Kit.button(bx, barY + 4 * s, 56 * s, 28 * s, "Apply", {
        kind = "good",
        tooltip = "Shift by dx,dy blocks",
      }) then
      applyShift(tonumber(draft.dx) or 0, tonumber(draft.dy) or 0)
    end
    bx = bx + 62 * s
    for _, n in ipairs({
      -- ASCII only — editor fonts often lack Unicode arrows (tofu □).
      { label = "<", dx = -1, dy = 0 },
      { label = ">", dx = 1, dy = 0 },
      { label = "^", dx = 0, dy = -1 },
      { label = "v", dx = 0, dy = 1 },
    }) do
      if Kit.button(bx, barY + 4 * s, 28 * s, 28 * s, n.label, {
          kind = "ghost",
          tooltip = string.format("Nudge (%d, %d)", n.dx, n.dy),
        }) then
        applyShift(n.dx, n.dy)
      end
      bx = bx + 32 * s
    end
  elseif map and (S.mapTool or "paint") == "wild" then
    barH = 38 * s
    local bx = mainX
    Kit.text("micro", "Species", bx, barY + 2 * s, PAL.caption)
    Kit.text("micro", "Lv", bx + 200 * s, barY + 2 * s, PAL.caption)
    SpeciesPicker.field(S, {
      x = bx, y = barY + 14 * s, w = 190 * s, h = 22 * s,
      current = S.placeWildSpecies or "ARTICUNO",
      title = "PLACE WILD SPECIES",
      onPick = function(id)
        S.placeWildSpecies = id
      end,
    })
    local lv = tonumber(field(App, "mp_wild_lv", bx + 200 * s, barY + 14 * s,
      48 * s, 22 * s, tostring(S.placeWildLevel or 50), "50")) or 50
    S.placeWildLevel = math.max(1, math.min(100, lv))
  elseif map and (S.mapTool or "paint") == "trainer" then
    barH = 38 * s
    local bx = mainX
    Kit.text("micro", "Class (OPP_*)", bx, barY + 2 * s, PAL.caption)
    Kit.text("micro", "Party", bx + 170 * s, barY + 2 * s, PAL.caption)
    local cls = field(App, "mp_tr_cls", bx, barY + 14 * s, 160 * s, 22 * s,
      S.trainerId or "OPP_YOUNGSTER", "OPP_YOUNGSTER",
      function() return Autocomplete.trainerIds(S) end)
      :upper():gsub("%s+", "_")
    if cls ~= "" then S.trainerId = cls end
    local pty = tonumber(field(App, "mp_tr_pty", bx + 170 * s, barY + 14 * s,
      48 * s, 22 * s, tostring(S.placeTrainerParty or 1), "1")) or 1
    S.placeTrainerParty = math.max(1, pty)
  elseif map then
    local thumb = 28 * s
    local tsId = map.tileset
    drawBlockThumb(S, tsId, S.paintBlock or 1, mainX, barY, thumb)
    Kit.text("micro", "brush " .. tostring(S.paintBlock or 1),
      mainX + thumb + 6 * s, barY + 2 * s, PAL.caption)
    Kit.text("micro", Kit.ellipsize("micro", tsId or "?", 120 * s),
      mainX + thumb + 6 * s, barY + 14 * s, PAL.muted)
    local bx = mainX + thumb + 140 * s
    if Kit.chip(bx, barY + 2 * s, 90 * s, barH - 4 * s, "Terrain",
        S.mapShowCollision, PAL.red, nil,
        "Overlay: red=solid blue=water magenta=grass orange=ledge") then
      S.mapShowCollision = not S.mapShowCollision
    end
    bx = bx + 98 * s
    local showNb = S.mapShowNeighbors ~= false
    if Kit.chip(bx, barY + 2 * s, 96 * s, barH - 4 * s, "Neighbors",
        showNb, PAL.blue, nil, "Draw connected maps at seams") then
      S.mapShowNeighbors = not showNb
    end
  end

  -- Canvas (center) + properties (right)
  local canvasY = barY + barH + 4 * s
  local bodyH = math.max(80 * s, y + h - canvasY)
  do
    local vHitX = mainX + mainW - rightW - split
    local drag = S._mapSplits and S._mapSplits.rightW
    if Kit.mouseDown and not Kit.blockClicks then
      if drag or Kit.hit(vHitX, canvasY, split, bodyH) then
        S._mapSplits = S._mapSplits or {}
        S._mapSplits.rightW = true
        local mx = tonumber(Kit.mouseX) or (mainX + mainW - rightW)
        rightW = Theme.clamp(mainX + mainW - mx, rightMin, rightMax)
        S.mapRightW = rightW
        vHitX = mainX + mainW - rightW - split
      end
    elseif drag then
      S._mapSplits.rightW = nil
    end
    S.mapRightW = rightW
  end
  -- Re-clamp against live mainW (window resize / HiDPI scale mid-drag).
  rightW = Theme.clamp(rightW, rightMin, rightMax)
  S.mapRightW = rightW
  local vHitX = mainX + mainW - rightW - split
  local canvasW = math.max(canvasMin, vHitX - mainX)
  -- If the window is too narrow, shrink the drawer instead of overlapping.
  if canvasW + split + rightW > mainW then
    rightW = math.max(rightMin, mainW - split - canvasW)
    rightW = Theme.clamp(rightW, rightMin, rightMax)
    S.mapRightW = rightW
    vHitX = mainX + mainW - rightW - split
    canvasW = math.max(40 * s, vHitX - mainX)
  end
  local canvasH = bodyH
  local px = vHitX + split
  local propW = math.max(120 * s, rightW)

  if not map then
    Kit.emptyBox(mainX, canvasY, canvasW, canvasH, "No maps -- add one or Import TMX")
    return
  end

  Kit.card(mainX, canvasY, canvasW, canvasH, 12 * s)
  local pad = 8 * s
  S._mapViewHit = Kit.hit(mainX + pad, canvasY + pad,
    math.max(0, canvasW - 2 * pad), math.max(0, canvasH - 2 * pad))
  drawMapPreview(S, map, mainX, canvasY, canvasW, canvasH, App)

  do
    local hotV = Kit.hit(vHitX, canvasY, split, bodyH)
      or (S._mapSplits and S._mapSplits.rightW)
    Theme.col(PAL.cardBorder, hotV and 0.75 or 0.3)
    love.graphics.rectangle("fill", vHitX, canvasY, split, bodyH)
  end

  -- Right properties drawer (mode-filtered sections)
  if S.mapSection == "blocks" then S.mapSection = "basics" end
  syncMapEditMode(S)
  S.mapSection = S.mapSection or "basics"
  local title = map.id .. (owned and "" or " (vanilla)")
  Kit.card(px, canvasY, propW, bodyH, 12 * s)
  Kit.text("micro", Kit.ellipsize("micro", title, propW - 16 * s),
    px + 8 * s, canvasY + 6 * s,
    (S.mapEditMode == "events") and PAL.blue or PAL.heading)
  Kit.text("micro",
    (S.mapEditMode == "events") and "Event properties" or "Map properties",
    px + 8 * s, canvasY + 18 * s, PAL.faint)

  local sx = px + 8 * s
  local secY = canvasY + 34 * s
  local allow = (S.mapEditMode == "events") and EVENT_MODE_SECTIONS or MAP_MODE_SECTIONS
  for _, sec in ipairs(SECTIONS) do
    if allow[sec.id] then
      local on = S.mapSection == sec.id
      local bw = Kit.textWidth("micro", sec.label) + 14 * s
      if sx + bw > px + propW - 8 * s then
        sx = px + 8 * s
        secY = secY + 28 * s
      end
      if Kit.chip(sx, secY, bw, 24 * s, sec.label, on, PAL.green) then
        S.mapSection = sec.id
      end
      sx = sx + bw + 3 * s
    end
  end
  local footerH = 68 * s
  local viewX = px + pad
  local viewY = secY + 30 * s
  local viewW = propW - 2 * pad
  local viewH = math.max(40 * s, canvasY + bodyH - viewY - footerH)
  FormPane.track(S, "mapFormScroll",
    tostring(S.mapId) .. "|" .. tostring(S.mapSection) .. "|"
      .. tostring(S.mapEditMode))
  local contentY, view = FormPane.begin(S, "mapFormScroll", viewX, viewY, viewW, viewH)
  local formX = view.x or viewX
  local formW = view.contentW or viewW
  local contentTop = contentY
  local listBottom = contentY + 4000 * s
  local fh = 26 * s

  if S.mapSection == "basics" then
    contentY = drawBasics(S, map, mutate, App, formX, contentY, formW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "warps" then
    contentY = drawWarps(S, map, mutate, App, formX, contentY, formW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "objects" then
    contentY = drawObjects(S, map, mutate, App, formX, contentY, formW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "signs" then
    contentY = drawSigns(S, map, mutate, App, formX, contentY, formW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "encounters" then
    contentY = drawEncounters(S, map, mutate, App, formX, contentY, formW,
      listBottom, fh, s) or contentY
  elseif S.mapSection == "hidden" then
    contentY = drawHiddenItems(S, map, mutate, App, formX, contentY, formW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "gates" then
    contentY = drawBadgeGates(S, map, mutate, App, formX, contentY, formW, listBottom, fh, s)
      or contentY
  end
  FormPane.finish(S, "mapFormScroll", contentTop, contentY, view)

  local fy = canvasY + bodyH - footerH + 4 * s
  if Kit.button(px + 10 * s, fy, propW - 20 * s, 26 * s, "Clear markers",
      { kind = "ghost" }) then
    local mid = map.id or S.mapId
    if S.warpDestPick and S.warpDestPick.sourceMapId == mid then
      clearWarpDestPick(S, "Set destination cancelled")
    end
    map = mutate()
    map.warps, map.objects, map.signs = {}, {}, {}
    MapLoader.invalidate(map.id)
    App.markDirty()
  end
  if owned and Kit.button(px + 10 * s, fy + 30 * s, propW - 20 * s, 26 * s, "Delete map",
      { kind = "danger" }) then
    local mid = map.id
    S.project.maps[mid] = nil
    if S._vanillaMapBackup and S._vanillaMapBackup[mid] then
      S.data.maps[mid] = S._vanillaMapBackup[mid]
      S._vanillaMapBackup[mid] = nil
    elseif map._isNew then
      S.data.maps[mid] = nil
    end
    MapLoader.invalidate(mid)
    S.mapId = next(S.project.maps) or ids[1]
    S._mapIdDraft = nil
    S._mapCenteredFor = nil
    App.markDirty()
  end

  if S.importReport and S.importReport ~= "" then
    local brief = S.importReport:gsub("\r", ""):match("([^\n]+)") or ""
    Kit.text("micro", brief, mainX, canvasY - 14 * s, PAL.faint)
  end
end

Maps.allMapIds = allMapIds
Maps.ensureOwned = ensureOwned
Maps.resolveMapDef = resolveMapDef

return Maps
