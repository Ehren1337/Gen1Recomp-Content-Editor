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
local FormPane = require("FormPane")
local SpriteUtil = require("SpriteUtil")
local MapLoader = require("src.world.MapLoader")
local Map = require("src.world.Map")
local SpriteRenderer = require("src.render.SpriteRenderer")
local PAL = Theme.PAL

local Maps = {}

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
  local out = {}
  for i, slot in ipairs(slots or {}) do
    out[i] = { level = slot.level, species = slot.species }
  end
  return out
end

local function cloneEncounters(enc)
  if type(enc) ~= "table" then return nil end
  local out = {}
  for _, kind in ipairs({ "grass", "water" }) do
    local band = enc[kind]
    if type(band) == "table" then
      out[kind] = { rate = band.rate or 0, slots = cloneSlots(band.slots) }
    end
  end
  return out
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

local function resolveEncounters(S, mapId, mapDef)
  if mapDef and mapDef.encounters then return mapDef.encounters, true end
  if S.data and S.data.encounters and S.data.encounters[mapId] then
    return S.data.encounters[mapId], false
  end
  return nil, false
end

local function resolveSuperRod(S, mapId, mapDef)
  if mapDef and mapDef.superRod then return mapDef.superRod, true end
  if S.data and S.data.field and S.data.field.superRod
      and S.data.field.superRod[mapId] then
    return S.data.field.superRod[mapId], false
  end
  return nil, false
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

local function defaultFishing(S)
  local FieldDefaults = require("src.world.FieldDefaults")
  local fish = FieldDefaults.field(S.data, "fishing") or {}
  return fish
end

local function resolveOldRod(S)
  State.ensureProjectFields(S.project)
  if S.project.fishing and S.project.fishing.OLD_ROD then
    return S.project.fishing.OLD_ROD, true
  end
  local fish = defaultFishing(S)
  return fish.OLD_ROD, false
end

local function resolveGoodRod(S)
  State.ensureProjectFields(S.project)
  if S.project.fishing and S.project.fishing.GOOD_ROD then
    return S.project.fishing.GOOD_ROD, true
  end
  local fish = defaultFishing(S)
  return fish.GOOD_ROD, false
end

local function defaultMap(id, index, tileset)
  local w, h = 10, 9
  local blocks = {}
  for i = 1, w * h do blocks[i] = 1 end
  return {
    id = id,
    label = id,
    index = index,
    tileset = tileset or "OVERWORLD",
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

local function field(App, id, x, y, w, h, value, ph)
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

local function spriteIds(S, customOnly)
  local proj = S.project and S.project.sprites
  if customOnly then
    local ids = {}
    for id in pairs(proj or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
  end
  local key = tostring(proj and next(proj)) .. ":" .. tostring(S.data and S.data.sprites and next(S.data.sprites))
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

local function drawBlockThumb(S, tilesetId, blockId, x, y, size)
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
  local shaded = Preview.pushPaletteShader(S, mapPaletteName(S))
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
    Preview.draw(S, ts.image, sx, sy, sheetW, sheetH, mapPaletteName(S))
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
  if Kit.mouseDown and not Kit.blockClicks and (S._worldDrag or S._worldViewHit) then
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
        local pal = mapPaletteName(S, def)
        local shaded = Preview.pushPaletteShader(S, pal)
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

  Kit.text("micro", "Connections", px + 10 * s, y, PAL.caption)
  y = y + 16 * s
  map.connections = map.connections or {}
  local listBottom = py + canvasH - 16 * s
  for _, dir in ipairs({ "north", "south", "east", "west" }) do
    if y + fh > listBottom then break end
    local cur = map.connections[dir]
    local val = cur and cur.map or ""
    local v = field(App, "mp_wc_" .. dir, px + 10 * s, y, propW - 20 * s, fh,
      val, dir)
    local want = (v == "") and nil or {
      map = v:upper():gsub("%s+", "_"),
      offset = (cur and cur.offset) or 0,
    }
    local curMap = cur and cur.map or ""
    local wantMap = want and want.map or ""
    if curMap ~= wantMap then
      map = mutate()
      map.connections = map.connections or {}
      map.connections[dir] = want
      S._worldFitKey = nil
      App.markDirty()
    end
    if want and map.connections[dir] then
      local off = tonumber(field(App, "mp_wco_" .. dir,
        px + 10 * s, y + fh + 2 * s, 60 * s, fh - 4 * s,
        tostring(map.connections[dir].offset or 0), "0")) or 0
      if off ~= (map.connections[dir].offset or 0) then
        map = mutate()
        map.connections[dir].offset = off
        S._worldFitKey = nil
        App.markDirty()
      end
      Kit.text("micro", "offset", px + 78 * s, y + fh + 6 * s, PAL.faint)
      local dest = want.map
      local ok = layout.positions[dest] ~= nil
        or (S.data.maps and S.data.maps[dest])
        or (S.project.maps and S.project.maps[dest])
      Kit.text("micro", ok and "linked" or "missing",
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
local function lovePathForModAsset(S, rel)
  if type(rel) ~= "string" or rel == "" then return rel end
  if rel:match("^mods/") or rel:match("^save/") then return rel end
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

local function applyToolAtCell(S, mapDef, cx, cy, App)
  if cx < 0 or cy < 0 or cx >= mapDef.width * 2 or cy >= mapDef.height * 2 then
    return
  end
  local owned = ensureOwned(S, mapDef.id or S.mapId)
  if not owned then return end
  mapDef = owned
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local idx = by * mapDef.width + bx + 1
  local tool = S.mapTool or "paint"

  if tool == "pick" then
    S.paintBlock = mapDef.blocks[idx] or 0
    S.mapTool = "paint"
    S.mapPaletteTileset = mapDef.tileset
    S.status = string.format("Picked block %s (tileset=%s) -- paint armed",
      tostring(S.paintBlock), tostring(mapDef.tileset))
    return
  elseif tool == "paint" then
    local bid = S.paintBlock or 1
    if mapDef.blocks[idx] ~= bid then
      mapDef.blocks[idx] = bid
      S._mapNeedsRebuild = mapDef.id
    else
      return
    end
  elseif tool == "erase" then
    if mapDef.blocks[idx] ~= 0 then
      mapDef.blocks[idx] = 0
      S._mapNeedsRebuild = mapDef.id
    else
      return
    end
  elseif tool == "warp" then
    mapDef.warps = mapDef.warps or {}
    mapDef.warps[#mapDef.warps + 1] = {
      x = cx, y = cy, destMap = "PALLET_TOWN", destWarp = 0,
    }
    S.mapSection = "warps"
    S.mapWarpIndex = #mapDef.warps
    S.status = string.format("Warp at cell (%d,%d)", cx, cy)
  elseif tool == "sign" then
    mapDef.signs = mapDef.signs or {}
    local n = #mapDef.signs + 1
    local textId = "TEXT_" .. (mapDef.id or "MAP") .. "_SIGN" .. n
    mapDef.signs[n] = { x = cx, y = cy, text = textId }
    S.mapSection = "signs"
    S.mapSignIndex = n
    S.dialogMapId = mapDef.id
    S.dialogTextId = textId
  elseif tool == "object" then
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
    mapDef.objects = mapDef.objects or {}
    local n = #mapDef.objects + 1
    local class = S.trainerId or "OPP_YOUNGSTER"
    local textId = "TEXT_" .. (mapDef.id or "MAP") .. "_TRAINER" .. n
    local spr = S.placeSprite or "SPRITE_YOUNGSTER"
    mapDef.objects[n] = {
      index = n, x = cx, y = cy,
      sprite = spr, movement = "STAY", range = "DOWN",
      text = textId,
      trainerClass = class, trainerParty = 1,
    }
    State.ensureProjectFields(S.project)
    local label = State.mapLabel(S, mapDef.id)
    S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
    S.project.trainer_headers[label][n] = {
      range = 2,
      battle = "_" .. (mapDef.id or "MAP") .. "Trainer" .. n .. "Battle",
      won = "_" .. (mapDef.id or "MAP") .. "Trainer" .. n .. "Won",
      after = "_" .. (mapDef.id or "MAP") .. "Trainer" .. n .. "After",
      event = State.modFlag(S.project, "BEAT_" .. class .. "_" .. n),
      opponent = class,
      party = 1,
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
    S.status = string.format("Placed %s as object #%d", class, n)
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
      S.mapSection = "objects"; S.mapObjectIndex = best
    elseif kind == "warp" then
      S.mapSection = "warps"; S.mapWarpIndex = best
    elseif kind == "sign" then
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
            Preview.draw(S, def.image, px - camX, py - camY - 4, CELL, CELL)
          end
        end
      else
        love.graphics.setColor(0.3, 0.9, 0.45, 0.85)
        love.graphics.rectangle("fill",
          px - camX + 2, py - camY + 2, CELL - 4, CELL - 4)
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
  for cy = y0, y1 do
    for cx = x0, x1 do
      if not Map.defIsWalkableCell(mapDef, ts, cx, cy) then
        if Map.defIsWaterCell(mapDef, ts, cx, cy) then
          love.graphics.setColor(0.15, 0.45, 1, 0.28)
        else
          love.graphics.setColor(1, 0.2, 0.2, 0.32)
        end
        love.graphics.rectangle("fill",
          cx * CELL - camX, cy * CELL - camY, CELL, CELL)
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
  love.graphics.rectangle("fill", vx, vy, vw, vh, 8 * s, 8 * s)

  prepareLiveMap(S, S.mapId, mapDef)
  local ok, map = pcall(MapLoader.load, S.data, S.mapId)
  if not ok then
    Kit.text("mono", "Failed to load map: " .. tostring(map),
      vx + 8 * s, vy + 8 * s, PAL.red)
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
          local nPal = mapPaletteName(S, nb.def)
          local nShaded = Preview.pushPaletteShader(S, nPal)
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

    local palName = mapPaletteName(S, mapDef)
    local shaded = Preview.pushPaletteShader(S, palName)
    love.graphics.setColor(1, 1, 1, 1)
    map.renderer:draw(camX, camY, worldW, worldH)
    Preview.popPaletteShader(shaded)
    love.graphics.setColor(1, 1, 1, 0.22)
    love.graphics.rectangle("line",
      - camX, - camY,
      map.widthCells * CELL, map.heightCells * CELL)
    drawCollisionOverlay(S, mapDef)
    drawMarkerOverlays(S, mapDef)
    love.graphics.pop()
    love.graphics.setScissor()
  end

  local tool = S.mapTool or "paint"
  local brush = (tool == "paint" or tool == "erase" or tool == "pick")
  local over = Kit.hit(vx, vy, vw, vh)
  -- Middle / right button always pans (Kit.mouseDown is left-only).
  local auxPan = false
  if love and love.mouse and love.mouse.isDown then
    auxPan = love.mouse.isDown(2) or love.mouse.isDown(3)
  end
  local spacePan = love.keyboard.isDown("space")
    or love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
  local panHeld = (auxPan or spacePan)
    and not Kit.blockClicks
    and (over or (S._mapDrag and S._mapDrag.pan))

  if panHeld then
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
    end
  elseif Kit.mouseDown and not Kit.blockClicks and (S._mapDrag or over) then
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
        end
      end
    end
  elseif S._mapDrag then
    if not S._mapDrag.brush and not S._mapDrag.pan and not S._mapDrag.moved then
      local z = S.mapZoom or 2
      local wx = (S._mapDrag.mx - vx) / z + S._mapDrag.camX
      local wy = (S._mapDrag.my - vy) / z + S._mapDrag.camY
      local cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
      applyToolAtCell(S, mapDef, cx, cy, App)
    end
    S._mapDrag = nil
    S._lastPaintCell = nil
  end

  local palName = mapPaletteName(S, mapDef)
  local swH = 12 * s
  local swX, swY = vx + 6 * s, vy + vh - 34 * s
  Preview.drawNamedSwatches(S, palName, swX, swY, 72 * s, swH)
  Kit.text("micro", palName, vx + 84 * s, swY + 1 * s, PAL.faint)
  if Kit.press(swX, swY, 160 * s, swH + 2 * s) then
    PalettePicker.open(S, {
      current = mapDef.palette,
      allowClear = true,
      clearLabel = "(inherit FieldDefaults)",
      title = "MAP SGB PALETTE",
      onPick = function(id)
        local owned = ensureOwned(S, mapDef.id or S.mapId)
        if owned then
          owned.palette = id
          App.markDirty()
        end
      end,
    })
  end
  local hint
  local ts = tostring(mapDef.tileset or "?")
  if brush then
    hint = string.format(
      "%.1fx  %s  blk=%s  drag=paint  MMB/RMB/Space=pan  hold WASD",
      S.mapZoom, ts, tostring(S.paintBlock or 1))
  else
    hint = string.format("%.1fx  %s  drag=pan  hold WASD  click=%s",
      S.mapZoom, ts, tool)
  end
  Kit.text("micro", hint, vx + 6 * s, vy + vh - 16 * s, PAL.faint)
end

-- Hold WASD / arrows to pan continuously (Shift = faster).
function Maps.update(S, dt)
  if not S or S.mapTilesetPicker then return end
  if Kit.focus then return end
  if Kit.blockClicks then return end
  if not (love and love.keyboard and love.keyboard.isDown) then return end
  local dx, dy = 0, 0
  if love.keyboard.isDown("left") or love.keyboard.isDown("a") then dx = dx - 1 end
  if love.keyboard.isDown("right") or love.keyboard.isDown("d") then dx = dx + 1 end
  if love.keyboard.isDown("up") or love.keyboard.isDown("w") then dy = dy - 1 end
  if love.keyboard.isDown("down") or love.keyboard.isDown("s") then dy = dy + 1 end
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
  end
end

function Maps.wheelmoved(S, dy)
  if not S then return false end
  -- Modal owns the wheel (Kit.scroll on the list). Do not zoom the map.
  if S.mapTilesetPicker then return false end
  if S.mapViewMode == "world" and S._worldViewHit then
    S.worldZoom = clampWorldZoom(
      (S.worldZoom or 0.25) + (dy > 0 and 0.05 or -0.05))
    return true
  end
  if not S._mapViewW then return false end
  if S._mapViewHit then
    S.mapZoom = clampZoom((S.mapZoom or 2) + (dy > 0 and 0.25 or -0.25))
    return true
  end
  return false
end

function Maps.keypressed(S, key)
  -- Escape / typing handled at App while the tileset modal is up.
  if S.mapTilesetPicker then return true end
  -- WASD / arrows pan continuously in Maps.update (hold to move).
  if key == "up" or key == "down" or key == "left" or key == "right"
      or key == "w" or key == "a" or key == "s" or key == "d" then
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
    return
  end
  local function mutate()
    return ensureOwned(S, S.mapId)
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
    S.mapTilesetPicker = nil
    Kit.blur()
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
    S.mapTilesetPicker = nil
    Kit.blur()
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

  local btnH = 26 * s
  local btnGap = 4 * s
  local footerH = btnH * 2 + btnGap + 6 * s
  local listY = cy + qh + 8 * s
  local listH = py + ph - pad - listY - footerH
  local rowH = 32 * s
  local thumb = 24 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(listW)
  p.offset = Kit.scroll(cx, listY, listW, listH, p.offset or 0, #list, perPage)

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
      if Kit.hover(cx, ry, innerW, rowH) then p.focus = id end
      if Kit.row(cx, ry, innerW, rowH, on or focused, PAL.blue) then
        applyMapTileset(S, map, id, App, mutate)
        S.mapTilesetPicker = nil
        Kit.blur()
        Kit.popClip()
        return
      end
      drawBlockThumb(S, id, 1, cx + 4 * s, ry + (rowH - thumb) / 2, thumb)
      local label = Kit.ellipsize("mono", id, math.max(8, innerW - thumb - 16 * s))
      Kit.text("mono", label, cx + 4 * s + thumb + 6 * s, ry + 8 * s,
        on and PAL.heading or (modded and PAL.text or PAL.muted))
      ry = ry + rowH + 3 * s
    end
    Kit.popClip()
  end
  p.offset = Kit.scrollbar(cx, listY, listW, listH, p.offset or 0, #list, perPage)

  local focusId = p.focus or map.tileset or list[1]
  local by = listY + listH + 6 * s
  if Kit.button(cx, by, listW, btnH, "Replace PNG", {
      kind = "accent",
      tooltip = "Import a PNG over this tileset's image (assets/tilesets/)",
    }) then
    importTilesetPng(S, App, focusId, { rebuildBlocks = false })
  end
  if Kit.button(cx, by + btnH + btnGap, listW, btnH, "+ New from PNG", {
      kind = "good",
      tooltip = "Register a new tileset from a PNG sheet",
    }) then
    importTilesetPng(S, App, nil, { createNew = true, rebuildBlocks = true })
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

  if prow("Index", function(fx, fy, fw, fh_)
    local cur = map.index or 0
    local v = tonumber(field(App, "mp_idx", fx, fy, 80 * s, fh_, tostring(cur), "0")) or 0
    if v ~= cur then map = mutate(); map.index = v end
  end) then return py end

  if prow("Size W x H (blocks)", function(fx, fy, fw, fh_)
    local ww = field(App, "mp_w", fx, fy, 60 * s, fh_, tostring(map.width), "10")
    local hh = field(App, "mp_h", fx + 70 * s, fy, 60 * s, fh_, tostring(map.height), "9")
    local nw, nh = tonumber(ww) or map.width, tonumber(hh) or map.height
    nw = math.max(1, math.min(64, nw))
    nh = math.max(1, math.min(64, nh))
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
  end) then return py end

  if prow("Tileset", function(fx, fy, fw, fh_)
    local label = Kit.ellipsize("mono", map.tileset or "?", fw - 100 * s)
    Kit.text("mono", label, fx, fy + 6 * s, PAL.heading)
    if Kit.button(fx + fw - 96 * s, fy, 96 * s, fh_, "Assign", {
        kind = "accent",
        tooltip = "Switch map.tileset (Gen1: one tileset per map)",
      }) then
      openTilesetPicker(S)
    end
  end) then return py end

  if prow("Border", function(fx, fy, fw, fh_)
    local v = tonumber(field(App, "mp_border", fx, fy, 60 * s, fh_,
      tostring(map.borderBlock or 0), "0")) or 0
    if v ~= (map.borderBlock or 0) then
      map = mutate(); map.borderBlock = v; MapLoader.invalidate(map.id)
    end
  end) then return py end

  if prow("SGB palette", function(fx, fy, fw, fh_)
    PalettePicker.row(S, {
      x = fx, y = fy, w = fw, h = fh_,
      current = map.palette or "",
      effective = mapPaletteName(S, map),
      emptyLabel = "(inherit)",
      clearLabel = "(inherit FieldDefaults)",
      allowClear = true,
      title = "MAP SGB PALETTE",
      tooltip = "Choose this map's SGB background palette",
      onPick = function(id)
        map = mutate()
        map.palette = id
        App.markDirty()
      end,
    })
  end) then return py end
  Kit.text("micro", "effective: " .. mapPaletteName(S, map),
    px + 10 * s, py, PAL.faint)
  py = py + 14 * s

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
    local v = field(App, "mp_music", fx, fy, fw, fh_, cur, "Music_...")
    if v ~= cur then
      setMapSong(S, map.id, (v ~= "" and v) or nil, App)
    end
  end) then return py end

  Kit.text("micro", "Connections (neighbor map id)", px + 10 * s, py, PAL.caption)
  py = py + 16 * s
  map.connections = map.connections or {}
  for _, dir in ipairs({ "north", "south", "east", "west" }) do
    if py + fh > listBottom then break end
    local cur = map.connections[dir]
    local val = cur and cur.map or ""
    local v = field(App, "mp_c_" .. dir, px + 10 * s, py, propW - 20 * s, fh,
      val, dir)
    local want = (v == "") and nil or { map = v:upper():gsub("%s+", "_"),
      offset = (cur and cur.offset) or 0 }
    local curMap = cur and cur.map or ""
    local wantMap = want and want.map or ""
    if curMap ~= wantMap then
      map = mutate()
      map.connections = map.connections or {}
      map.connections[dir] = want
    end
    if want and map.connections[dir] then
      local off = tonumber(field(App, "mp_co_" .. dir,
        px + 10 * s, py + fh + 2 * s, 60 * s, fh - 4 * s,
        tostring(map.connections[dir].offset or 0), "0")) or 0
      if off ~= (map.connections[dir].offset or 0) then
        map = mutate()
        map.connections[dir].offset = off
      end
      Kit.text("micro", "offset", px + 78 * s, py + fh + 6 * s, PAL.faint)
      py = py + fh + 2 * s
    end
    py = py + fh + 4 * s
  end
  return py
end

-- Bottom dock: Gen1 block palette for map.tileset only (like Tiled: tile=block).
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

  local headerH = 26 * s
  local footerH = 28 * s
  local headerY = dy + pad
  local findW = 48 * s
  local assignW = 64 * s
  Kit.text("micro", "tileset=" .. Kit.ellipsize("micro", active, dw - 200 * s),
    dx + pad, headerY + 6 * s, PAL.caption)
  if Kit.button(dx + dw - pad - findW - assignW - 6 * s, headerY, assignW, headerH,
      "Assign", {
        kind = "accent",
        tooltip = "Switch map.tileset (one tileset per map)",
      }) then
    openTilesetPicker(S)
  end
  if Kit.button(dx + dw - pad - findW, headerY, findW, headerH, "Find", {
      kind = "ghost", tooltip = "Search / preview tilesets to assign",
    }) then
    openTilesetPicker(S)
  end

  local gridY = headerY + headerH + 6 * s
  local gridH = math.max(40 * s, dy + dh - pad - footerH - 6 * s - gridY)
  local gridX = dx + pad
  local gridW = dw - 2 * pad
  local innerW = Kit.scrollInnerWidth(gridW)
  local thumb = 36 * s
  local gap = 3 * s
  local cols = math.max(1, math.floor(innerW / (thumb + gap)))
  local rows = math.max(1, math.floor(gridH / (thumb + gap)))
  local perPage = cols * rows
  local maxB = blockCount(S, active)
  S.paintBlock = S.paintBlock or 1
  if S.paintBlock >= maxB then S.paintBlock = math.max(0, maxB - 1) end

  S.mapBlockOffset = Kit.scroll(gridX, gridY, gridW, gridH,
    S.mapBlockOffset or 0, maxB, perPage, cols)
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
    drawBlockThumb(S, active, i, bx, by, thumb)
    if on then
      love.graphics.setColor(0.24, 0.88, 0.54, 1)
      love.graphics.rectangle("line", bx - 1, by - 1, thumb + 2, thumb + 2)
      love.graphics.setColor(1, 1, 1, 1)
    end
    if Kit.press(bx, by, thumb, thumb) then
      S.paintBlock = i
      S.mapTool = "paint"
      S.status = string.format("tileset=%s block=%d", tostring(active), i)
    end
  end
  Kit.popClip()
  S.mapBlockOffset = Kit.scrollbar(gridX, gridY, gridW, gridH,
    S.mapBlockOffset or 0, maxB, perPage)

  local fy = dy + dh - pad - footerH + 2 * s
  local fw = math.floor((gridW - 12 * s) / 3)
  if Kit.button(gridX, fy, fw, footerH - 4 * s, "Replace PNG", {
      kind = "accent", tooltip = "Import PNG for this map's tileset",
    }) then
    importTilesetPng(S, App, active, { rebuildBlocks = false })
  end
  if Kit.button(gridX + fw + 6 * s, fy, fw, footerH - 4 * s, "+ New PNG", {
      kind = "good", tooltip = "Register a new tileset from a PNG sheet",
    }) then
    importTilesetPng(S, App, nil, { createNew = true, rebuildBlocks = true })
  end
  if Kit.button(gridX + 2 * (fw + 6 * s), fy, fw, footerH - 4 * s, "Import TMX", {
      kind = "accent", tooltip = "Import a Pokemonium / Tiled .tmx map",
    }) then
    local picked = ModIO.chooseFile("Pokemonium / Tiled TMX",
      "Tiled map (*.tmx)|*.tmx|All (*.*)|*.*")
    if picked then Maps.importTmx(S, picked, App) end
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
      tostring(w.destWarp or 0), "0")) or 0
    if v ~= (w.destWarp or 0) then map = mutate(); map.warps[i].destWarp = v end
  end)
  if py + 32 * s <= listBottom
      and Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Delete warp",
        { kind = "danger" }) then
    map = mutate()
    table.remove(map.warps, i)
    S.mapWarpIndex = math.min(i, #map.warps)
    MapLoader.invalidate(map.id)
    App.markDirty()
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

  -- sprite preview + place-sprite arm
  local def = spriteDef(S, obj.sprite)
  if py + 56 * s < listBottom then
    if def and def.image then
      Preview.draw(S, def.image, px + 10 * s, py, 48 * s, 48 * s)
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
  if SpriteUtil.isOwned(S, obj.sprite) and py + fh * 3 <= listBottom then
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
          Preview.draw(S, sdef.image, bx, py, thumb, thumb)
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
    local v = field(App, "ob_text", fx, fy, fw - 70 * s, fh_, obj.text or "", "TEXT_")
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
        map.objects[i].trainerClass = S.trainerId or "OPP_YOUNGSTER"
        map.objects[i].trainerParty = 1
        State.ensureProjectFields(S.project)
        local label = State.mapLabel(S, map.id)
        local idx = map.objects[i].index or i
        S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
        if not S.project.trainer_headers[label][idx] then
          local base = "_" .. (map.id or "MAP") .. "Trainer" .. idx
          S.project.trainer_headers[label][idx] = {
            range = 2,
            battle = base .. "Battle",
            won = base .. "Won",
            after = base .. "After",
            event = State.modFlag(S.project, "BEAT_TRAINER_" .. idx),
            opponent = map.objects[i].trainerClass,
            party = 1,
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
      local v = field(App, "ob_tc", fx, fy, fw, fh_, obj.trainerClass or "", "OPP_")
      v = v ~= "" and v:upper():gsub("%s+", "_") or nil
      if v ~= obj.trainerClass then
        map = mutate()
        map.objects[i].trainerClass = v
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
      if v ~= cur then
        map = mutate()
        map.objects[i].trainerParty = v
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
        copy.event = copy.event
          or State.modFlag(S.project, "BEAT_TRAINER_" .. idx)
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
  end

  row("Hidden", function(fx, fy, fw, fh_)
    local on = obj.hidden and true or false
    if Kit.chip(fx, fy, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
      map = mutate()
      map.objects[i].hidden = (not on) or nil
      App.markDirty()
    end
  end)

  if py + 32 * s <= listBottom
      and Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Delete object",
        { kind = "danger" }) then
    map = mutate()
    table.remove(map.objects, i)
    for j, o in ipairs(map.objects) do o.index = j end
    S.mapObjectIndex = math.min(i, #map.objects)
    MapLoader.invalidate(map.id)
    App.markDirty()
  end
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
    local v = field(App, "sg_text", fx, fy, fw, fh_, sign.text or "", "TEXT_")
    if v ~= (sign.text or "") then map = mutate(); map.signs[i].text = v end
  end)
  if py + 32 * s <= listBottom
      and Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "Delete sign",
        { kind = "danger" }) then
    map = mutate()
    table.remove(map.signs, i)
    S.mapSignIndex = math.min(i, #map.signs)
    MapLoader.invalidate(map.id)
    App.markDirty()
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

  if py + 30 * s <= listBottom
      and Kit.button(px + 10 * s, py, 100 * s, 28 * s, "+ Add", { kind = "good" }) then
    local list = ensureHiddenItems(S, mapId)
    list[#list + 1] = { x = 0, y = 0, item = "POTION" }
    App.markDirty()
    py = py + 32 * s
  end
  if owned and #items > 0 and py + 36 * s <= listBottom
      and Kit.button(px + 10 * s, py, 100 * s, 28 * s, "Clear all",
        { kind = "ghost" }) then
    S.project.hiddenItems[mapId] = {}
    App.markDirty()
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

local ENC_KINDS = {
  { id = "grass", label = "GRASS" },
  { id = "water", label = "WATER" },
  { id = "super", label = "SUPER" },
  { id = "old", label = "OLD" },
  { id = "good", label = "GOOD" },
}

local function ensureEncounterBand(map, kind)
  map.encounters = map.encounters or {}
  if not map.encounters[kind] then
    map.encounters[kind] = { rate = 0, slots = {} }
  end
  map.encounters[kind].slots = map.encounters[kind].slots or {}
  return map.encounters[kind]
end

local function drawSlotRows(S, App, px, py, propW, listBottom, fh, s,
    kindKey, slots, onChange, onDelete, maxSlots)
  Kit.text("micro", "Slots (level, species)", px + 10 * s, py, PAL.caption)
  py = py + 16 * s
  for si = 1, #(slots or {}) do
    if py + fh > listBottom - 36 * s then break end
    local slot = slots[si]
    local speciesDef = (S.project.pokemon and S.project.pokemon[slot.species])
      or (S.data.pokemon and S.data.pokemon[slot.species])
    if speciesDef and speciesDef.spriteFront then
      Preview.draw(S, speciesDef.spriteFront, px + 10 * s, py, 24 * s, 24 * s,
        Preview.monPaletteName(S, speciesDef, slot.species))
    end
    local lx = px + 40 * s
    local lvl = tonumber(field(App, "enc_lv_" .. kindKey .. si, lx, py, 40 * s, fh,
      tostring(slot.level or 1), "1")) or 1
    local sp = field(App, "enc_sp_" .. kindKey .. si, lx + 48 * s, py, 110 * s, fh,
      slot.species or "PIDGEY", "PIDGEY"):upper():gsub("%s+", "_")
    if lvl ~= (slot.level or 1) or sp ~= (slot.species or "") then
      onChange(si, { level = math.max(1, lvl), species = sp })
    end
    if Kit.button(px + propW - 42 * s, py, 28 * s, fh, "X", { kind = "danger" }) then
      onDelete(si)
      break
    end
    py = py + math.max(fh, 26 * s) + 4 * s
  end
  if #(slots or {}) < (maxSlots or 10) and py + 30 * s <= listBottom
      and Kit.button(px + 10 * s, py, 100 * s, 28 * s, "+ Slot", { kind = "accent" }) then
    onChange(#(slots or {}) + 1, { level = 5, species = "MAGIKARP" }, true)
    py = py + 32 * s
  end
  return py
end

local function drawEncounters(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  State.ensureProjectFields(S.project)
  local enc = resolveEncounters(S, S.mapId, map)
  local superSlots = resolveSuperRod(S, S.mapId, map)

  S.mapEncKind = S.mapEncKind or "grass"
  local sx, sy = px + 10 * s, py
  for _, kind in ipairs(ENC_KINDS) do
    local on = S.mapEncKind == kind.id
    local bw = Kit.textWidth("micro", kind.label) + 14 * s
    if sx + bw > px + propW - 10 * s then
      sx = px + 10 * s
      sy = sy + fh + 4 * s
    end
    if Kit.chip(sx, sy, bw, fh, kind.label, on, PAL.green) then
      S.mapEncKind = kind.id
    end
    sx = sx + bw + 4 * s
  end
  py = sy + fh + 10 * s

  local kind = S.mapEncKind

  if kind == "grass" or kind == "water" then
    local band = enc and enc[kind]
    if not band then
      Kit.text("micro", "No " .. kind .. " encounters on this map.",
        px + 10 * s, py, PAL.faint)
      py = py + 18 * s
      if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add " .. kind,
          { kind = "good" }) then
        map = mutate()
        local b = ensureEncounterBand(map, kind)
        b.rate = kind == "grass" and 25 or 5
        b.slots = {
          { level = kind == "grass" and 3 or 5,
            species = kind == "grass" and "PIDGEY" or "TENTACOOL" },
        }
        App.markDirty()
      end
      return py + 36 * s
    end

    Kit.text("micro", "Rate (0-255)", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local rate = tonumber(field(App, "enc_rate_" .. kind, px + 10 * s, py, 70 * s, fh,
      tostring(band.rate or 0), "0")) or 0
    if rate ~= (band.rate or 0) then
      map = mutate()
      ensureEncounterBand(map, kind).rate = math.max(0, math.min(255, rate))
    end
    py = py + fh + 8 * s

    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, kind, band.slots,
      function(si, slot, isAdd)
        map = mutate()
        local b = ensureEncounterBand(map, kind)
        if isAdd then b.slots[#b.slots + 1] = slot
        else b.slots[si] = slot end
        App.markDirty()
      end,
      function(si)
        map = mutate()
        table.remove(ensureEncounterBand(map, kind).slots, si)
        App.markDirty()
      end, 10)

    if py + 36 * s <= listBottom
        and Kit.button(px + 10 * s, py, 100 * s, 28 * s, "Clear " .. kind,
          { kind = "ghost" }) then
      map = mutate()
      if map.encounters then map.encounters[kind] = nil end
      App.markDirty()
    end
    return py + 36 * s

  elseif kind == "super" then
    Kit.text("micro", "Super Rod group for this map (field.superRod).",
      px + 10 * s, py, PAL.muted)
    py = py + 18 * s
    if not superSlots then
      Kit.text("micro", "No Super Rod table here.", px + 10 * s, py, PAL.faint)
      py = py + 18 * s
      if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add Super Rod",
          { kind = "good" }) then
        map = mutate()
        map.superRod = { { level = 15, species = "POLIWAG" } }
        App.markDirty()
      end
      return py + 36 * s
    end
    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, "super", superSlots,
      function(si, slot, isAdd)
        map = mutate()
        map.superRod = map.superRod or cloneSlots(superSlots)
        if isAdd then map.superRod[#map.superRod + 1] = slot
        else map.superRod[si] = slot end
        App.markDirty()
      end,
      function(si)
        map = mutate()
        map.superRod = map.superRod or cloneSlots(superSlots)
        table.remove(map.superRod, si)
        App.markDirty()
      end, 10)
    if py + 36 * s <= listBottom
        and Kit.button(px + 10 * s, py, 110 * s, 28 * s, "Clear Super",
          { kind = "ghost" }) then
      map = mutate()
      map.superRod = {}
      App.markDirty()
    end
    return py + 36 * s

  elseif kind == "old" then
    Kit.text("micro", "Old Rod (global -- always hooks this mon).",
      px + 10 * s, py, PAL.muted)
    py = py + 18 * s
    local def = select(1, resolveOldRod(S)) or { always = { species = "MAGIKARP", level = 5 } }
    local always = def.always or { species = "MAGIKARP", level = 5 }
    Kit.text("micro", "Level", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local lvl = tonumber(field(App, "enc_old_lv", px + 10 * s, py, 50 * s, fh,
      tostring(always.level or 5), "5")) or 5
    local sp = field(App, "enc_old_sp", px + 70 * s, py, 140 * s, fh,
      always.species or "MAGIKARP", "MAGIKARP"):upper():gsub("%s+", "_")
    if lvl ~= (always.level or 5) or sp ~= (always.species or "") then
      S.project.fishing.OLD_ROD = {
        always = { level = math.max(1, lvl), species = sp },
      }
      App.markDirty()
    end
    py = py + fh + 10 * s
    if S.project.fishing.OLD_ROD
        and Kit.button(px + 10 * s, py, 120 * s, 28 * s, "Revert Old",
          { kind = "danger" }) then
      S.project.fishing.OLD_ROD = nil
      App.markDirty()
    end
    return py + 36 * s

  else -- good
    Kit.text("micro", "Good Rod (global pool -- ~1/3 bite).",
      px + 10 * s, py, PAL.muted)
    py = py + 18 * s
    local def = select(1, resolveGoodRod(S)) or {
      pool = {
        { species = "GOLDEEN", level = 10 },
        { species = "POLIWAG", level = 10 },
      },
    }
    local pool = def.pool or {}
    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, "good", pool,
      function(si, slot, isAdd)
        local cur = resolveGoodRod(S)
        local base = (cur and cur.pool) and cloneSlots(cur.pool) or cloneSlots(pool)
        if isAdd then base[#base + 1] = slot else base[si] = slot end
        S.project.fishing.GOOD_ROD = { pool = base }
        App.markDirty()
      end,
      function(si)
        local cur = resolveGoodRod(S)
        local base = (cur and cur.pool) and cloneSlots(cur.pool) or cloneSlots(pool)
        table.remove(base, si)
        S.project.fishing.GOOD_ROD = { pool = base }
        App.markDirty()
      end, 8)
    if S.project.fishing.GOOD_ROD and py + 36 * s <= listBottom
        and Kit.button(px + 10 * s, py, 120 * s, 28 * s, "Revert Good",
          { kind = "danger" }) then
      S.project.fishing.GOOD_ROD = nil
      App.markDirty()
    end
    return py + 36 * s
  end
end

function Maps.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end

  local listW = math.min(200 * s, w * 0.22)
  Kit.caption(x, y, "MAPS")
  S.mapViewMode = S.mapViewMode or "editor"
  local modeY = y
  local modeX = x + Kit.textWidth("caption", "MAPS") + 16 * s
  for _, mode in ipairs({
    { id = "editor", label = "Editor" },
    { id = "world", label = "World" },
  }) do
    local on = S.mapViewMode == mode.id
    local bw = Kit.textWidth("micro", mode.label) + 16 * s
    if Kit.chip(modeX, modeY, bw, 22 * s, mode.label, on, PAL.green, nil,
        mode.id == "world"
          and "Show this map and its N/S/E/W neighbors"
          or "Paint blocks, warps, objects") then
      S.mapViewMode = mode.id
      if mode.id == "world" then S._worldFitKey = nil end
    end
    modeX = modeX + bw + 4 * s
  end
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "mapQuery", x, qy, listW, qh, "search maps...")
  if qChanged then S.mapListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allMapIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local map = S.project.maps[id]
        or (S.data.maps and S.data.maps[id])
      local label = map and tostring(map.label or "") or ""
      local ts = map and tostring(map.tileset or "") or ""
      if id:lower():find(ql, 1, true)
          or label:lower():find(ql, 1, true)
          or ts:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  local rowH = 28 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 3 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = listW - 12 * s
  local mapScrollH = listH - 16 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.mapListOffset = Kit.scroll(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.mapListOffset or 0, #ids, perPage)
  local ry = listY + 8 * s
  for i = (S.mapListOffset or 0) + 1, math.min(#ids, (S.mapListOffset or 0) + perPage) do
    local id = ids[i]
    local owned = S.project.maps[id] ~= nil
    if Kit.row(mapScrollX, ry, mapRowW, rowH, S.mapId == id, PAL.green) then
      S.mapId = id
      S._mapIdDraft = nil
      S._mapCenteredFor = nil
      S._mapPaletteFor = nil
      S.mapObjectIndex, S.mapWarpIndex, S.mapSignIndex = 1, 1, 1
      if S.mapViewMode == "world" then S._worldFitKey = nil end
    end
    local textX = mapScrollX + 6 * s
    local textMax = math.max(8, mapRowW - 12 * s)
    local label = Kit.ellipsize("mono", id, textMax)
    if Kit.textWidth("mono", label) > textMax + 0.5 then
      local unit = math.max(1, Kit.textWidth("mono", "W"))
      local n = math.max(0, math.floor(textMax / unit) - 3)
      label = (n > 0 and id:sub(1, n) or "") .. "..."
    end
    Kit.pushClip(mapScrollX, ry, mapRowW, rowH)
    Kit.text("mono", label, textX, ry + 6 * s, owned and PAL.text or PAL.muted)
    Kit.popClip()
    ry = ry + rowH + 3 * s
  end
  S.mapListOffset = Kit.scrollbar(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.mapListOffset or 0, #ids, perPage)

  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New map", { kind = "good" }) then
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
    App.markDirty()
  end

  local map, owned = resolveMapDef(S, S.mapId)
  if not map then
    local first = ids[1]
    S.mapId = first
    map, owned = resolveMapDef(S, first)
  end

  local mainX = x + listW + 12 * s
  local mainW = w - listW - 12 * s

  if S.mapViewMode == "world" then
    local propW = 260 * s
    local worldY = qy
    local worldH = h - (worldY - y)
    drawWorldView(S, App, mainX, worldY, mainW, worldH, propW)
    return
  end

  local dockH = math.min(200 * s, math.max(140 * s, h * 0.28))

  local tools = {
    { id = "paint", tip = "Stamp the selected block (drag to paint)" },
    { id = "erase", tip = "Paint block 0 (empty / void)" },
    { id = "pick", tip = "Click the map to sample a block into the brush" },
    { id = "select", tip = "Pan the map (or hold Space while painting)" },
    { id = "warp", tip = "Place or select warps" },
    { id = "object", tip = "Place NPCs / objects" },
    { id = "sign", tip = "Place signs" },
    { id = "trainer", tip = "Place a trainer object" },
  }
  local tx = mainX
  for _, tool in ipairs(tools) do
    local on = (S.mapTool or "paint") == tool.id
    local bw = (tool.id == "trainer" or tool.id == "select" or tool.id == "object")
      and 70 * s or 54 * s
    if Kit.chip(tx, y, bw, 26 * s, tool.id:upper(), on, PAL.blue, nil, tool.tip) then
      S.mapTool = tool.id
      if tool.id == "object" or tool.id == "trainer" then S.mapSection = "objects" end
    end
    tx = tx + bw + 4 * s
  end
  if Kit.button(tx + 4 * s, y, 72 * s, 26 * s, "Dialog", {
      kind = "ghost", tooltip = "Edit this map's NPC / sign text",
    }) then
    S.tab = "dialog"
    S.dialogMapId = S.mapId
  end
  tx = tx + 80 * s
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

  -- Paint / view strip under tools
  local barY = y + 30 * s
  local barH = 34 * s
  if map then
    local thumb = 28 * s
    local tsId = map.tileset
    drawBlockThumb(S, tsId, S.paintBlock or 1, mainX, barY, thumb)
    Kit.text("micro", "block " .. tostring(S.paintBlock or 1),
      mainX + thumb + 6 * s, barY + 2 * s, PAL.caption)
    Kit.text("micro", Kit.ellipsize("micro", tsId or "?", 140 * s),
      mainX + thumb + 6 * s, barY + 14 * s, PAL.muted)
    local bx = mainX + thumb + 160 * s
    if Kit.chip(bx, barY + 2 * s, 90 * s, barH - 4 * s, "Collision",
        S.mapShowCollision, PAL.red) then
      S.mapShowCollision = not S.mapShowCollision
    end
    bx = bx + 98 * s
    local showNb = S.mapShowNeighbors ~= false
    if Kit.chip(bx, barY + 2 * s, 96 * s, barH - 4 * s, "Neighbors",
        showNb, PAL.blue, nil, "Draw connected maps at N/S/E/W seams") then
      S.mapShowNeighbors = not showNb
    end
    bx = bx + 104 * s
    local spr = S.placeSprite or "SPRITE_RED"
    local sdef = spriteDef(S, spr)
    if sdef and sdef.image then
      Preview.draw(S, sdef.image, bx, barY, thumb, thumb)
    else
      Theme.col(PAL.rowBg, 1)
      love.graphics.rectangle("fill", bx, barY, thumb, thumb, 3, 3)
    end
    Kit.text("micro", "place", bx + thumb + 4 * s, barY + 2 * s, PAL.caption)
    Kit.text("micro", Kit.ellipsize("micro", spr, 120 * s),
      bx + thumb + 4 * s, barY + 14 * s, PAL.muted)
    if Kit.press(bx, barY, thumb + 130 * s, thumb) then
      S.mapSection = "objects"
      S.mapTool = "object"
    end
  end

  local canvasY = barY + barH + 4 * s
  local dockY = y + h - dockH
  local canvasH = math.max(80 * s, dockY - canvasY - 6 * s)

  if not map then
    Kit.emptyBox(mainX, canvasY, mainW, canvasH, "No maps -- add one or Import TMX")
    return
  end

  local propW = 260 * s
  local canvasW = mainW - propW - 12 * s
  Kit.card(mainX, canvasY, canvasW, canvasH, 12 * s)

  local pad = 8 * s
  S._mapViewHit = Kit.hit(mainX + pad, canvasY + pad,
    math.max(0, canvasW - 2 * pad), math.max(0, canvasH - 2 * pad))

  drawMapPreview(S, map, mainX, canvasY, canvasW, canvasH, App)

  local px = mainX + canvasW + 12 * s
  local py = canvasY
  local title = map.id .. (owned and "" or " (vanilla)")
  Kit.caption(px, py - 18 * s, Kit.ellipsize("caption", title, propW))
  Kit.card(px, py, propW, canvasH, 12 * s)

  local function mutate()
    map = ensureOwned(S, S.mapId)
    owned = true
    return map
  end

  if S.mapSection == "blocks" then S.mapSection = "basics" end
  S.mapSection = S.mapSection or "basics"
  local sx = px + 8 * s
  local secY = py + 8 * s
  for _, sec in ipairs(SECTIONS) do
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
  local footerH = 68 * s
  local viewX = px + pad
  local viewY = secY + 30 * s
  local viewW = propW - 2 * pad
  local viewH = math.max(40 * s, py + canvasH - viewY - footerH)
  FormPane.track(S, "mapFormScroll",
    tostring(S.mapId) .. "|" .. tostring(S.mapSection))
  local contentY, view = FormPane.begin(S, "mapFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = contentY
  local listBottom = contentY + 4000 * s
  local fh = 26 * s

  if S.mapSection == "basics" then
    contentY = drawBasics(S, map, mutate, App, px, contentY, propW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "warps" then
    contentY = drawWarps(S, map, mutate, App, px, contentY, propW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "objects" then
    contentY = drawObjects(S, map, mutate, App, px, contentY, propW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "signs" then
    contentY = drawSigns(S, map, mutate, App, px, contentY, propW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "encounters" then
    contentY = drawEncounters(S, map, mutate, App, px, contentY, propW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "hidden" then
    contentY = drawHiddenItems(S, map, mutate, App, px, contentY, propW, listBottom, fh, s)
      or contentY
  elseif S.mapSection == "gates" then
    contentY = drawBadgeGates(S, map, mutate, App, px, contentY, propW, listBottom, fh, s)
      or contentY
  end
  FormPane.finish(S, "mapFormScroll", contentTop, contentY, view)

  local fy = py + canvasH - footerH + 4 * s
  if Kit.button(px + 10 * s, fy, propW - 20 * s, 26 * s, "Clear markers",
      { kind = "ghost" }) then
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

  map = drawTilesetDock(S, map, mutate, App, mainX, dockY, mainW, dockH) or map

  if S.importReport and S.importReport ~= "" then
    local brief = S.importReport:gsub("\r", ""):match("([^\n]+)") or ""
    Kit.text("micro", brief, mainX, dockY - 14 * s, PAL.faint)
  end
end

return Maps
