-- Export / import Tiled TMX for content-editor maps.
-- Our export: one Tiled tile = one engine block (32x32), GID = blockId + 1.
-- Pokemonium / foreign TMX is converted to that block format on import.

local ModIO = require("ModIO")
local Generation = require("Generation")
local Preview = require("Preview")

local TmxIO = {}

local SEP = package.config:sub(1, 1)
local function join(...)
  local parts = { ... }
  for i = 1, #parts do
    parts[i] = tostring(parts[i] or ""):gsub("[/\\]+$", "")
  end
  return table.concat(parts, SEP)
end

local function xml(s)
  s = tostring(s or "")
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function resolveMap(S, mapId)
  if not mapId then return nil end
  return (S.project and S.project.maps and S.project.maps[mapId])
    or Generation.dataMaps(S)[mapId]
end

local function resolveTileset(S, tilesetId)
  if not tilesetId then return nil end
  return (S.project and S.project.tilesets and S.project.tilesets[tilesetId])
    or Generation.dataTilesets(S)[tilesetId]
end

local function layeredSource(S, mapId)
  return S.project and S.project.layeredMaps and S.project.layeredMaps[mapId]
end

local function blocksFromLayered(source)
  local w = math.floor((source.cellWidth or 0) / 2)
  local h = math.floor((source.cellHeight or 0) / 2)
  if w < 1 or h < 1 then return nil end
  local layer = source.layers and source.layers[1]
  local cells = layer and layer.cells
  if type(cells) ~= "table" then return nil end
  local blocks = {}
  for by = 0, h - 1 do
    for bx = 0, w - 1 do
      local index = (by * 2) * source.cellWidth + (bx * 2) + 1
      local ref = cells[index]
      local tile = ref and tonumber(ref.tile) or 0
      blocks[#blocks + 1] = math.floor(tile / 4)
    end
  end
  return blocks, w, h
end

local function mapPayload(S, mapId)
  local map = resolveMap(S, mapId)
  if not map then return nil, "unknown map" end
  local source = layeredSource(S, mapId)
  local blocks, width, height
  if source then
    blocks, width, height = blocksFromLayered(source)
  end
  if not blocks then
    blocks = map.blocks
    width = map.width
    height = map.height
  end
  if type(blocks) ~= "table" or type(width) ~= "number" or type(height) ~= "number" then
    return nil, "map has no block grid"
  end
  return {
    id = map.id or mapId,
    map = map,
    blocks = blocks,
    width = width,
    height = height,
    tileset = map.tileset,
    source = source,
  }
end

local function loadImageData(S, path)
  if type(path) ~= "string" or path == "" then return nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, data = pcall(Assets.imageData, path)
    if ok and data then return data end
  end
  local resolved, kind = Preview.resolve(S, path)
  if not resolved or not (love and love.image and love.image.newImageData) then
    return nil
  end
  if kind == "disk" then
    local bytes = ModIO.readText(resolved)
    if type(bytes) ~= "string" or bytes == "" then return nil end
    local okFd, fd = pcall(love.filesystem.newFileData, bytes, "tiles.png")
    if not (okFd and fd) then return nil end
    local ok, data = pcall(love.image.newImageData, fd)
    return ok and data or nil
  end
  local ok, data = pcall(love.image.newImageData, resolved)
  return ok and data or nil
end

local function writePng(imageData, path)
  if not (imageData and imageData.encode) then return false, "no encode" end
  local ok, fileData = pcall(imageData.encode, imageData, "png")
  if not (ok and fileData) then return false, fileData end
  local bytes = fileData.getString and fileData:getString() or tostring(fileData)
  return ModIO.writeText(path, bytes)
end

local function buildBlockAtlas(S, tileset)
  local sheet = loadImageData(S, tileset and tileset.image)
  local blocks = tileset and tileset.blocks
  if not (sheet and type(blocks) == "table" and #blocks > 0) then
    return nil
  end
  local perRow = tileset.tilesPerRow or 16
  local n = #blocks
  local cols = 16
  local rows = math.max(1, math.ceil(n / cols))
  local atlas = love.image.newImageData(cols * 32, rows * 32)
  for bi = 0, n - 1 do
    local block = blocks[bi + 1]
    local ax = (bi % cols) * 32
    local ay = math.floor(bi / cols) * 32
    if type(block) == "table" then
      for i = 0, 15 do
        local tid = block[i + 1] or 0
        local sx = (tid % perRow) * 8
        local sy = math.floor(tid / perRow) * 8
        local dx = ax + (i % 4) * 8
        local dy = ay + math.floor(i / 4) * 8
        if atlas.paste then
          pcall(atlas.paste, atlas, sheet, dx, dy, sx, sy, 8, 8)
        end
      end
    end
  end
  return atlas, n, cols, cols * 32, rows * 32
end

local function csvBlocks(blocks, width, height)
  local lines = {}
  for y = 0, height - 1 do
    local row = {}
    for x = 0, width - 1 do
      local bid = tonumber(blocks[y * width + x + 1]) or 0
      row[#row + 1] = tostring(bid + 1)
    end
    local line = table.concat(row, ",")
    if y < height - 1 then line = line .. "," end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

local function objectXml(kind, obj, id)
  local cx = tonumber(obj.x) or 0
  local cy = tonumber(obj.y) or 0
  local props = {}
  local function prop(name, value, typ)
    if value == nil or value == "" then return end
    if typ then
      props[#props + 1] = string.format(
        '   <property name="%s" type="%s" value="%s"/>',
        xml(name), typ, xml(value))
    else
      props[#props + 1] = string.format(
        '   <property name="%s" value="%s"/>', xml(name), xml(value))
    end
  end
  if kind == "warp" then
    prop("destMap", obj.destMap or obj.map)
    prop("destWarp", obj.destWarp or obj.dest or 0, "int")
  elseif kind == "sign" then
    prop("text", obj.text or obj.script or "")
  else
    prop("sprite", obj.sprite)
    prop("movement", obj.movement)
    prop("range", obj.range, "int")
    prop("text", obj.text)
    prop("facing", obj.facing or obj.range)
  end
  return string.format(
    '  <object id="%d" name="%s" type="%s" x="%d" y="%d" width="16" height="16">\n'
      .. "   <properties>\n%s\n   </properties>\n  </object>",
    id, xml(kind), xml(kind), cx * 16, cy * 16, table.concat(props, "\n"))
end

function TmxIO.defaultFolder(S)
  if not (S and S.path) then return nil end
  return join(S.path, "exports", "tmx")
end

function TmxIO.exportMap(S, mapId, folder)
  folder = folder or TmxIO.defaultFolder(S)
  if not folder then return false, "no mod open" end
  local payload, err = mapPayload(S, mapId)
  if not payload then return false, err end
  local made, makeErr = ModIO.ensureDirectory(folder)
  if not made then return false, makeErr end

  local tileset = resolveTileset(S, payload.tileset) or {}
  local tsName = payload.tileset or "TILESET"
  local pngName = tsName:lower():gsub("[^a-z0-9_-]", "_") .. "_blocks.png"
  local atlas, tilecount, columns, imgW, imgH = buildBlockAtlas(S, tileset)
  if atlas then
    local okPng, pngErr = writePng(atlas, join(folder, pngName))
    if not okPng then return false, pngErr end
  else
    tilecount = tileset.blocks and #tileset.blocks or 256
    columns = 16
    imgW, imgH = 512, math.max(32, math.ceil(tilecount / 16) * 32)
    pngName = (tileset.image and tileset.image:match("([^/\\]+)$")) or pngName
  end

  local map = payload.map
  local objects, nextId = {}, 1
  local function addGroup(name, list, kind)
    if type(list) ~= "table" or #list == 0 then return end
    local body = {}
    for _, obj in ipairs(list) do
      body[#body + 1] = objectXml(kind, obj, nextId)
      nextId = nextId + 1
    end
    objects[#objects + 1] = string.format(
      ' <objectgroup id="%d" name="%s">\n%s\n </objectgroup>',
      #objects + 2, name, table.concat(body, "\n"))
  end
  addGroup("warps", map.warps, "warp")
  addGroup("signs", map.signs or map.bgEvents, "sign")
  addGroup("objects", map.objects, "object")

  local props = {
    string.format('  <property name="editor" value="gen1recomp"/>'),
    string.format('  <property name="mapId" value="%s"/>', xml(payload.id)),
    string.format('  <property name="tileset" value="%s"/>', xml(tsName)),
  }
  if type(map.palette) == "string" and map.palette ~= "" then
    props[#props + 1] = string.format(
      '  <property name="palette" value="%s"/>', xml(map.palette))
  end
  if type(map.environment) == "string" and map.environment ~= "" then
    props[#props + 1] = string.format(
      '  <property name="environment" value="%s"/>', xml(map.environment))
  end
  if map.generation or Generation.isGen2(S) then
    props[#props + 1] = string.format(
      '  <property name="generation" type="int" value="%s"/>',
      tostring(map.generation or 2))
  end

  local tmx = {
    '<?xml version="1.0" encoding="UTF-8"?>',
    string.format(
      '<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" '
        .. 'renderorder="right-down" width="%d" height="%d" tilewidth="32" '
        .. 'tileheight="32" infinite="0" nextlayerid="%d" nextobjectid="%d">',
      payload.width, payload.height, #objects + 2, nextId),
    " <properties>",
    table.concat(props, "\n"),
    " </properties>",
    string.format(
      ' <tileset firstgid="1" name="%s" tilewidth="32" tileheight="32" '
        .. 'tilecount="%d" columns="%d">',
      xml(tsName), tilecount, columns),
    string.format(
      '  <image source="%s" width="%d" height="%d"/>',
      xml(pngName), imgW, imgH),
    " </tileset>",
    string.format(
      ' <layer id="1" name="blocks" width="%d" height="%d">',
      payload.width, payload.height),
    '  <data encoding="csv">',
    csvBlocks(payload.blocks, payload.width, payload.height),
    "  </data>",
    " </layer>",
  }
  for _, group in ipairs(objects) do
    tmx[#tmx + 1] = group
  end
  tmx[#tmx + 1] = "</map>"

  local dest = join(folder, payload.id .. ".tmx")
  local ok, writeErr = ModIO.writeText(dest, table.concat(tmx, "\n") .. "\n")
  if not ok then return false, writeErr end
  return true, dest
end

local function attr(tag, name)
  local pat = name .. '%s*=%s*"([^"]*)"'
  return tag:match(pat)
end

local function parseCsv(text, width, height)
  local vals = {}
  for num in tostring(text or ""):gmatch("%d+") do
    vals[#vals + 1] = tonumber(num) or 0
  end
  local need = width * height
  while #vals < need do vals[#vals + 1] = 0 end
  return vals
end

local function parseObjects(xmlText, kind)
  local out = {}
  for obj in xmlText:gmatch("<object%s.-</object>") do
    local otype = attr(obj, "type") or attr(obj, "class") or ""
    local name = attr(obj, "name") or ""
    local hit = kind == "warp" and (otype:find("warp") or name:find("warp"))
      or kind == "sign" and (otype:find("sign") or name:find("sign"))
      or kind == "object" and (otype:find("object") or otype:find("npc")
        or name ~= "")
    if kind == "object" and (otype:find("warp") or otype:find("sign")) then
      hit = false
    end
    if hit then
      local x = tonumber(attr(obj, "x")) or 0
      local y = tonumber(attr(obj, "y")) or 0
      local rec = {
        x = math.floor(x / 16),
        y = math.floor(y / 16),
      }
      for pname, pval in obj:gmatch('<property%s+name="([^"]+)"[^>]*value="([^"]*)"') do
        if pname == "destMap" or pname == "map" then rec.destMap = pval
        elseif pname == "destWarp" or pname == "dest" then
          rec.destWarp = tonumber(pval) or 0
        elseif pname == "text" then rec.text = pval
        elseif pname == "sprite" then rec.sprite = pval
        elseif pname == "movement" then rec.movement = pval
        elseif pname == "range" then rec.range = tonumber(pval) or 0
        elseif pname == "facing" then rec.facing = pval
        end
      end
      out[#out + 1] = rec
    end
  end
  return out
end

function TmxIO.parse(path)
  local body, err = ModIO.readText(path)
  if not body then return nil, err end
  local mapTag = body:match("<map%s.->")
  if not mapTag then return nil, "not a TMX map" end
  local width = tonumber(attr(mapTag, "width"))
  local height = tonumber(attr(mapTag, "height"))
  local tilewidth = tonumber(attr(mapTag, "tilewidth")) or 32
  local tileheight = tonumber(attr(mapTag, "tileheight")) or 32
  if not (width and height) then return nil, "TMX missing width/height" end

  local props = {}
  for name, value in body:gmatch('<property%s+name="([^"]+)"[^>]*value="([^"]*)"') do
    props[name] = value
  end

  local firstgid = tonumber(body:match('firstgid="(%d+)"')) or 1
  local tilesetName = body:match('<tileset[^>]-name="([^"]+)"')
  local data = body:match('<layer[^>]-name="blocks".-<data[^>]*>(.-)</data>')
    or body:match("<data%s+encoding=\"csv\"[^>]*>(.-)</data>")
    or body:match("<data[^>]*>(.-)</data>")
  if not data then return nil, "TMX has no tile layer" end
  local gids = parseCsv(data, width, height)
  local blocks = {}
  for i = 1, width * height do
    local gid = tonumber(gids[i]) or 0
    if gid >= 0x20000000 then gid = gid % 0x20000000 end
    if gid == 0 then
      blocks[i] = 0
    else
      blocks[i] = math.max(0, gid - firstgid)
    end
  end
  return {
    width = width,
    height = height,
    tilewidth = tilewidth,
    tileheight = tileheight,
    props = props,
    tileset = tilesetName,
    blocks = blocks,
    warps = parseObjects(body, "warp"),
    signs = parseObjects(body, "sign"),
    objects = parseObjects(body, "object"),
    ours = props.editor == "gen1recomp",
  }
end

local function applyLayeredBlocks(S, mapId, map)
  local source = layeredSource(S, mapId)
  if not source then return end
  local tilesetId = source.baseTileset or map.tileset
  local width, height = map.width * 2, map.height * 2
  local cells, collision = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local block = map.blocks[math.floor(y / 2) * map.width + math.floor(x / 2) + 1] or 0
      cells[index] = {
        source = require("LayeredMap").runtimeSourceId(tilesetId),
        tile = block * 4 + (y % 2) * 2 + (x % 2),
      }
      collision[index] = source.collision and source.collision[index] or "walk"
    end
  end
  if source.layers and source.layers[1] then
    source.layers[1].cells = cells
  end
  source.collision = collision
  source.cellWidth, source.cellHeight = width, height
end

function TmxIO.canImportNative(parsed)
  return parsed and parsed.ours == true
end

function TmxIO.importFile(S, path, App)
  if not (S and S.project) then return false, "no project" end
  local body, readErr = ModIO.readText(path)
  if not body then return false, readErr end
  local ours = body:find('name="editor"%s+value="gen1recomp"')
    or body:find('value="gen1recomp"%s+name="editor"')
  if not ours then
    return require("TmxPokemonium").importFile(S, path, App)
  end
  local parsed, err = TmxIO.parse(path)
  if not parsed then return false, err end

  local mapId = parsed.props.mapId
  if type(mapId) ~= "string" or mapId == "" then
    mapId = (path:match("([^/\\]+)%.[Tt][Mm][Xx]$") or "IMPORTED_MAP")
      :gsub("[^%w_]", "_"):upper()
  end
  local existing = resolveMap(S, mapId)
  local map
  if existing then
    map = existing
    if S.project.maps[mapId] ~= map then
      local copy = {}
      for k, v in pairs(existing) do copy[k] = v end
      S.project.maps[mapId] = copy
      map = copy
    end
  else
    map = {
      id = mapId,
      tileset = parsed.tileset or (Generation.isGen2(S) and "TILESET_JOHTO" or "OVERWORLD"),
      _isNew = true,
    }
    S.project.maps[mapId] = map
  end
  map.id = mapId
  map.width = parsed.width
  map.height = parsed.height
  map.blocks = parsed.blocks
  if parsed.tileset and parsed.tileset ~= "" then
    map.tileset = parsed.tileset
  end
  if parsed.props.palette then map.palette = parsed.props.palette end
  if parsed.props.environment then map.environment = parsed.props.environment end
  if parsed.warps and #parsed.warps > 0 then map.warps = parsed.warps end
  if parsed.signs and #parsed.signs > 0 then map.signs = parsed.signs end
  if parsed.objects and #parsed.objects > 0 then map.objects = parsed.objects end
  applyLayeredBlocks(S, mapId, map)
  if S.data and S.data.maps then S.data.maps[mapId] = map end
  S.mapId = mapId
  S.builderMapId = mapId
  S._mapCenteredFor = nil
  if App and App.markDirty then App.markDirty() end
  pcall(function() require("src.world.MapLoader").invalidate(mapId) end)
  pcall(function()
    local Maps = require("Maps")
    if Maps.invalidateGoldPreview then Maps.invalidateGoldPreview(S, mapId) end
  end)
  return true, mapId
end

return TmxIO
