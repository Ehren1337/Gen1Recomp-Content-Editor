-- Native layered map source and compiler.
--
-- The editor works in 16x16 walk cells. Saving folds the exported layers into
-- the runtime's 32x32 block format and one generated tileset per map. The
-- source stays in editor_project.lua, while the game only sees normal map and
-- tileset registry records.

local ModIO = require("ModIO")
local Preview = require("Preview")

local LayeredMap = {}

LayeredMap.CELL_SIZE = 16
LayeredMap.COLOR_MODES = { "palette", "true_color" }
LayeredMap.COLLISION_MODES = {
  "solid", "walk", "grass", "water", "shore",
}

local RUNTIME_PREFIX = "@runtime:"

-- Project model and identifiers

local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, child in pairs(value) do
    out[deepCopy(key, seen)] = deepCopy(child, seen)
  end
  return out
end

local function sortedKeys(bucket)
  local out = {}
  for key in pairs(bucket or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function listSet(values)
  local out = {}
  for _, value in ipairs(values or {}) do out[value] = true end
  return out
end

local function clamp(value, low, high)
  value = tonumber(value) or low
  return math.max(low, math.min(high, value))
end

local function cleanId(value, fallback)
  local id = tostring(value or ""):upper():gsub("[^A-Z0-9_]", "_")
  id = id:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if id == "" then id = fallback or "MAP" end
  if id:match("^%d") then id = "MAP_" .. id end
  return id
end

local function ensureProject(project)
  project.layeredMaps = project.layeredMaps or {}
  project.mapTileSources = project.mapTileSources or {}
  project.mapWarpNodes = project.mapWarpNodes or {}
  project.maps = project.maps or {}
  project.tilesets = project.tilesets or {}
  project.nextMapIndex = project.nextMapIndex or 1000
  project.nextWarpNode = project.nextWarpNode or 1
  return project
end

function LayeredMap.ensureProject(project)
  return ensureProject(project)
end

function LayeredMap.runtimeSourceId(tilesetId)
  return RUNTIME_PREFIX .. tostring(tilesetId or "OVERWORLD")
end

function LayeredMap.isRuntimeSource(sourceId)
  return type(sourceId) == "string"
    and sourceId:sub(1, #RUNTIME_PREFIX) == RUNTIME_PREFIX
end

function LayeredMap.runtimeTilesetId(sourceId)
  if not LayeredMap.isRuntimeSource(sourceId) then return nil end
  return sourceId:sub(#RUNTIME_PREFIX + 1)
end

local function resolveMap(S, mapId)
  return (S.project and S.project.maps and S.project.maps[mapId])
    or (S.data and S.data.maps and S.data.maps[mapId])
end

local function resolveTileset(S, tilesetId)
  return (S.project and S.project.tilesets and S.project.tilesets[tilesetId])
    or (S.data and S.data.tilesets and S.data.tilesets[tilesetId])
end

function LayeredMap.allMapIds(S)
  local seen, ids = {}, {}
  local function add(bucket)
    for id in pairs(bucket or {}) do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  add(S.project and S.project.layeredMaps)
  add(S.project and S.project.maps)
  add(S.data and S.data.maps)
  table.sort(ids)
  return ids
end

local function uniqueMapId(S, wanted)
  local base = cleanId(wanted, "NEW_MAP")
  local id, suffix = base, 1
  while resolveMap(S, id) or (S.project.layeredMaps and S.project.layeredMaps[id]) do
    suffix = suffix + 1
    id = base .. "_" .. suffix
  end
  return id
end

local function uniqueSourceId(project, wanted)
  local base = cleanId(wanted, "CUSTOM_TILES")
  local id, suffix = base, 1
  while project.mapTileSources[id] do
    suffix = suffix + 1
    id = base .. "_" .. suffix
  end
  return id
end

local function defaultEnvironment(tilesetId)
  if tilesetId == "CAVERN" then return "cave" end
  if tilesetId == "OVERWORLD" or tilesetId == "PLATEAU" then
    return "outside"
  end
  return "inside"
end

local function cellIndex(mapSource, x, y)
  return y * mapSource.cellWidth + x + 1
end

local function defaultRuntimeRef(tilesetId, x, y, block)
  local quadrant = (y % 2) * 2 + (x % 2)
  return {
    source = LayeredMap.runtimeSourceId(tilesetId),
    tile = (block or 0) * 4 + quadrant,
  }
end

-- Map creation and conversion

function LayeredMap.createMap(S, wantedId, cellWidth, cellHeight, tilesetId)
  local project = ensureProject(assert(S.project, "no project"))
  local id = uniqueMapId(S, wantedId)
  local width = math.max(2, math.floor(tonumber(cellWidth) or 20))
  local height = math.max(2, math.floor(tonumber(cellHeight) or 18))
  if width % 2 ~= 0 then width = width + 1 end
  if height % 2 ~= 0 then height = height + 1 end
  tilesetId = tilesetId or "OVERWORLD"

  local cells, collision = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      cells[index] = defaultRuntimeRef(tilesetId, x, y, 0)
      collision[index] = "walk"
    end
  end

  local source = {
    id = id,
    cellWidth = width,
    cellHeight = height,
    baseTileset = tilesetId,
    layers = {
      {
        id = "ground", name = "Ground", visible = true, export = true,
        opacity = 1, cells = cells,
      },
    },
    collision = collision,
  }
  project.layeredMaps[id] = source

  local environment = defaultEnvironment(tilesetId)
  local blockWidth, blockHeight = width / 2, height / 2
  local blocks = {}
  for i = 1, blockWidth * blockHeight do blocks[i] = 0 end
  project.maps[id] = {
    id = id,
    label = id,
    index = project.nextMapIndex,
    tileset = tilesetId,
    environment = environment,
    outdoor = environment == "outside",
    width = blockWidth,
    height = blockHeight,
    blocks = blocks,
    borderBlock = 0,
    warps = {}, objects = {}, signs = {}, connections = {},
    _isNew = true,
    _layeredSource = id,
  }
  project.nextMapIndex = project.nextMapIndex + 1
  return source, project.maps[id]
end

local function ownedMap(S, mapId)
  local project = ensureProject(assert(S.project, "no project"))
  if project.maps[mapId] then return project.maps[mapId] end
  local base = S.data and S.data.maps and S.data.maps[mapId]
  if not base then return nil end
  local copy = deepCopy(base)
  copy.id = mapId
  copy._isNew = false
  project.maps[mapId] = copy
  return copy
end

local function collisionMode(tileset, tile)
  if not tileset or tile == nil then return "solid" end
  if tileset.grassTile == tile then return "grass" end
  if listSet(tileset.waterTiles)[tile] then return "water" end
  if listSet(tileset.shoreTiles)[tile] then return "shore" end
  if listSet(tileset.walkable)[tile] then return "walk" end
  return "solid"
end

local function rawCellTile(map, tileset, x, y)
  local blockX, blockY = math.floor(x / 2), math.floor(y / 2)
  local blockId = map.blocks[blockY * map.width + blockX + 1] or 0
  local block = tileset and tileset.blocks and tileset.blocks[blockId + 1]
  if not block then return nil, blockId end
  local tileX = (x % 2) * 2
  local tileY = (y % 2) * 2 + 1
  return block[tileY * 4 + tileX + 1], blockId
end

local function nodeAt(project, mapId, x, y)
  for _, node in pairs(project.mapWarpNodes or {}) do
    if node.map == mapId and node.x == x and node.y == y then return node end
  end
  return nil
end

local function newNode(project, mapId, x, y)
  local id
  repeat
    id = "WARP_" .. tostring(project.nextWarpNode)
    project.nextWarpNode = project.nextWarpNode + 1
  until project.mapWarpNodes[id] == nil
  local node = {
    id = id, map = mapId, x = x, y = y,
    active = false, order = project.nextWarpNode - 1,
  }
  project.mapWarpNodes[id] = node
  return node
end

function LayeredMap.nodeAt(project, mapId, x, y)
  ensureProject(project)
  return nodeAt(project, mapId, x, y)
end

function LayeredMap.ensureWarpNode(project, mapId, x, y)
  ensureProject(project)
  return nodeAt(project, mapId, x, y) or newNode(project, mapId, x, y)
end

local function importMapWarps(S, map)
  local project = ensureProject(S.project)
  local created = {}
  for index, warp in ipairs(map.warps or {}) do
    local node = nodeAt(project, map.id, warp.x, warp.y)
      or newNode(project, map.id, warp.x, warp.y)
    node.active = true
    node.originalIndex = index
    node.targetMap = warp.destMap
    node.targetIndex = warp.destWarp
    created[index] = node
  end

  -- Reconnect stable nodes whenever both maps have been converted. External
  -- destinations retain their original map/index pair until then.
  for _, node in pairs(project.mapWarpNodes) do
    if node.targetMap and node.targetIndex then
      for _, candidate in pairs(project.mapWarpNodes) do
        if candidate.map == node.targetMap
            and candidate.originalIndex == node.targetIndex then
          node.targetNode = candidate.id
          break
        end
      end
    end
  end
end

function LayeredMap.convertMap(S, mapId)
  local project = ensureProject(assert(S.project, "no project"))
  if project.layeredMaps[mapId] then return project.layeredMaps[mapId] end
  local map = ownedMap(S, mapId)
  if not map then return nil, "unknown map " .. tostring(mapId) end
  local tileset = resolveTileset(S, map.tileset)
  if not (tileset and type(tileset.blocks) == "table") then
    return nil, "map tileset is unavailable: " .. tostring(map.tileset)
  end

  local width, height = map.width * 2, map.height * 2
  local cells, collision = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local tile, block = rawCellTile(map, tileset, x, y)
      cells[index] = defaultRuntimeRef(map.tileset, x, y, block)
      collision[index] = collisionMode(tileset, tile)
    end
  end
  local source = {
    id = mapId,
    cellWidth = width,
    cellHeight = height,
    baseTileset = map.tileset,
    layers = {
      {
        id = "ground", name = "Ground", visible = true, export = true,
        opacity = 1, cells = cells,
      },
    },
    collision = collision,
  }
  project.layeredMaps[mapId] = source
  map._layeredSource = mapId
  importMapWarps(S, map)
  return source
end

-- Editable map operations

function LayeredMap.resize(source, newWidth, newHeight)
  if type(source) ~= "table" then return false, "no layered map" end
  local width = math.max(2, math.floor(tonumber(newWidth) or source.cellWidth))
  local height = math.max(2, math.floor(tonumber(newHeight) or source.cellHeight))
  if width % 2 ~= 0 or height % 2 ~= 0 then
    return false, "map size must use even 16x16-cell dimensions"
  end
  if width == source.cellWidth and height == source.cellHeight then return true end
  local oldWidth, oldHeight = source.cellWidth, source.cellHeight
  for _, layer in ipairs(source.layers or {}) do
    local cells = {}
    for y = 0, height - 1 do
      for x = 0, width - 1 do
        if x < oldWidth and y < oldHeight then
          cells[y * width + x + 1] = layer.cells[y * oldWidth + x + 1]
        end
      end
    end
    layer.cells = cells
  end
  local collision = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      collision[y * width + x + 1] =
        (x < oldWidth and y < oldHeight)
          and source.collision[y * oldWidth + x + 1] or "solid"
    end
  end
  source.collision = collision
  source.cellWidth, source.cellHeight = width, height
  return true
end

function LayeredMap.resizeMap(project, mapId, newWidth, newHeight)
  ensureProject(project)
  local source = project.layeredMaps[mapId]
  local ok, err = LayeredMap.resize(source, newWidth, newHeight)
  if not ok then return false, err end
  local removed = 0
  local drop = {}
  for id, node in pairs(project.mapWarpNodes) do
    if node.map == mapId
        and (node.x >= source.cellWidth or node.y >= source.cellHeight) then
      drop[#drop + 1] = id
    end
  end
  for _, id in ipairs(drop) do
    LayeredMap.removeWarpNode(project, id)
    removed = removed + 1
  end
  local map = project.maps[mapId]
  if map then
    map.width, map.height = source.cellWidth / 2, source.cellHeight / 2
    local function trimEvents(list)
      for index = #(list or {}), 1, -1 do
        local event = list[index]
        if event.x >= source.cellWidth or event.y >= source.cellHeight then
          table.remove(list, index)
          removed = removed + 1
        end
      end
    end
    trimEvents(map.objects)
    trimEvents(map.warps)
    trimEvents(map.signs)
    trimEvents(map.bgEvents)
  end
  return true, removed
end

function LayeredMap.addLayer(source, name)
  local base = cleanId(name, "LAYER"):lower()
  local id, suffix = base, 1
  local used = {}
  for _, layer in ipairs(source.layers or {}) do used[layer.id] = true end
  while used[id] do
    suffix = suffix + 1
    id = base .. "_" .. suffix
  end
  local layer = {
    id = id,
    name = tostring(name or "Layer " .. (#source.layers + 1)),
    visible = true,
    export = true,
    opacity = 1,
    cells = {},
  }
  source.layers[#source.layers + 1] = layer
  return layer, #source.layers
end

function LayeredMap.removeLayer(source, index)
  if index == 1 then return false, "Ground cannot be removed" end
  if not source.layers[index] then return false, "unknown layer" end
  table.remove(source.layers, index)
  return true
end

function LayeredMap.moveLayer(source, index, direction)
  local target = index + direction
  if index < 1 or target < 1 or target > #source.layers then return index end
  source.layers[index], source.layers[target] =
    source.layers[target], source.layers[index]
  return target
end

function LayeredMap.setCell(source, layerIndex, x, y, ref)
  if x < 0 or y < 0 or x >= source.cellWidth or y >= source.cellHeight then
    return false
  end
  local layer = source.layers[layerIndex]
  if not layer then return false end
  layer.cells[cellIndex(source, x, y)] = ref and deepCopy(ref) or nil
  return true
end

function LayeredMap.getCell(source, layerIndex, x, y)
  local layer = source.layers[layerIndex]
  if not layer then return nil end
  return layer.cells[cellIndex(source, x, y)]
end

function LayeredMap.setCollision(source, x, y, mode)
  if x < 0 or y < 0 or x >= source.cellWidth or y >= source.cellHeight then
    return false
  end
  local valid = false
  for _, value in ipairs(LayeredMap.COLLISION_MODES) do
    if value == mode then valid = true; break end
  end
  if not valid then return false end
  source.collision[cellIndex(source, x, y)] = mode
  return true
end

-- Tileset sources and animation

function LayeredMap.addTileSource(project, wantedId, image, width, height)
  ensureProject(project)
  width, height = tonumber(width), tonumber(height)
  if not width or not height or width < 16 or height < 16
      or width % 16 ~= 0 or height % 16 ~= 0 then
    return nil, "tileset PNG dimensions must be multiples of 16 pixels"
  end
  local id = uniqueSourceId(project, wantedId)
  local source = {
    id = id,
    name = id,
    image = image,
    tileWidth = 16,
    tileHeight = 16,
    columns = width / 16,
    count = (width / 16) * (height / 16),
    colorMode = "true_color",
    animations = {},
  }
  project.mapTileSources[id] = source
  return source
end

function LayeredMap.sourceDescriptor(S, sourceId)
  if LayeredMap.isRuntimeSource(sourceId) then
    local tilesetId = LayeredMap.runtimeTilesetId(sourceId)
    local tileset = resolveTileset(S, tilesetId)
    if not tileset then return nil end
    return {
      id = sourceId,
      name = tilesetId .. " (game blocks)",
      image = tileset.image,
      colorMode = tileset.trueColor and "true_color" or "palette",
      runtimeTileset = tilesetId,
      tileset = tileset,
      columns = 8,
      count = #(tileset.blocks or {}) * 4,
    }
  end
  return S.project and S.project.mapTileSources
    and S.project.mapTileSources[sourceId]
end

function LayeredMap.sourceIds(S, mapId)
  local ids, seen = {}, {}
  local function add(id)
    if id and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local mapSource = S.project and S.project.layeredMaps
    and S.project.layeredMaps[mapId]
  if mapSource and mapSource.baseTileset then
    add(LayeredMap.runtimeSourceId(mapSource.baseTileset))
  end

  -- A layered map may paint from any loaded game tileset. Keep the base
  -- source first, then expose the complete runtime registry alphabetically.
  local runtimeIds, runtimeSeen = {}, {}
  for _, bucket in ipairs({ S.project and S.project.tilesets,
      S.data and S.data.tilesets }) do
    for tilesetId in pairs(bucket or {}) do
      if not runtimeSeen[tilesetId] then
        runtimeSeen[tilesetId] = true
        runtimeIds[#runtimeIds + 1] = tilesetId
      end
    end
  end
  table.sort(runtimeIds)
  for _, tilesetId in ipairs(runtimeIds) do
    add(LayeredMap.runtimeSourceId(tilesetId))
  end

  for _, id in ipairs(sortedKeys(S.project and S.project.mapTileSources)) do
    add(id)
  end
  return ids
end

function LayeredMap.setAnimationFrames(source, tile, frames)
  if not source or source.runtimeTileset then
    return false, "import a PNG to define a custom animation"
  end
  tile = math.floor(tonumber(tile) or 0)
  if tile < 0 or tile >= (source.count or 0) then
    return false, "animation tile is outside the source"
  end
  source.animations = source.animations or {}
  local normalized = {}
  for _, frame in ipairs(frames or {}) do
    local frameTile = math.floor(tonumber(frame.tile) or -1)
    if frameTile < 0 or frameTile >= (source.count or 0) then
      return false, "frame tile is outside the source"
    end
    normalized[#normalized + 1] = {
      tile = frameTile,
      duration = math.max(16, math.floor(tonumber(frame.duration) or 200)),
    }
  end
  source.animations[tile] = #normalized > 1 and normalized or nil
  return true
end

function LayeredMap.setSourceAnimation(source, tile, frameCount, duration)
  if not source or source.runtimeTileset then
    return false, "import a PNG to define a custom animation"
  end
  tile = math.floor(tonumber(tile) or 0)
  if tile < 0 or tile >= (source.count or 0) then
    return false, "animation tile is outside the source"
  end
  frameCount = math.floor(tonumber(frameCount) or 1)
  if frameCount <= 1 then
    return LayeredMap.setAnimationFrames(source, tile, {})
  end
  frameCount = math.min(frameCount, (source.count or 1) - tile)
  local frames = {}
  for offset = 0, frameCount - 1 do
    frames[#frames + 1] = { tile = tile + offset, duration = duration }
  end
  return LayeredMap.setAnimationFrames(source, tile, frames)
end

local function validPoint(point)
  return type(point) == "table" and type(point.map) == "string"
    and type(point.x) == "number" and type(point.y) == "number"
end

-- Warp endpoints are stored as a graph with stable ids. Runtime warp indexes
-- are assigned only during compilation, so inserting or deleting another
-- endpoint does not silently change a link in the editor project.
function LayeredMap.createWarpLink(project, mode, from, destination, returnPoint)
  ensureProject(project)
  if not validPoint(from) or not validPoint(destination) then
    return false, "source and destination cells are required"
  end
  if mode == "custom_return" and not validPoint(returnPoint) then
    return false, "custom return cell is required"
  end
  local first = LayeredMap.ensureWarpNode(project, from.map, from.x, from.y)
  local second = LayeredMap.ensureWarpNode(
    project, destination.map, destination.x, destination.y)
  first.active = true
  first.targetNode = second.id
  first.targetMap, first.targetIndex = nil, nil

  if mode == "two_way" then
    second.active = true
    second.targetNode = first.id
    second.targetMap, second.targetIndex = nil, nil
  elseif mode == "custom_return" then
    local third = LayeredMap.ensureWarpNode(
      project, returnPoint.map, returnPoint.x, returnPoint.y)
    second.active = true
    second.targetNode = third.id
    second.targetMap, second.targetIndex = nil, nil
    if third.targetNode == nil then third.active = false end
  else
    -- The destination record supplies arrival coordinates but does not fire.
    second.active = false
    second.targetNode = nil
    second.targetMap, second.targetIndex = nil, nil
  end
  return true, first.id, second.id
end

function LayeredMap.removeWarpNode(project, nodeId)
  ensureProject(project)
  if not project.mapWarpNodes[nodeId] then return false end
  project.mapWarpNodes[nodeId] = nil
  for _, node in pairs(project.mapWarpNodes) do
    if node.targetNode == nodeId then
      node.targetNode = nil
      node.active = false
    end
  end
  return true
end

function LayeredMap.nodesForMap(project, mapId)
  ensureProject(project)
  local nodes = {}
  for _, node in pairs(project.mapWarpNodes) do
    if node.map == mapId then nodes[#nodes + 1] = node end
  end
  table.sort(nodes, function(left, right)
    local lo = left.order or 0
    local ro = right.order or 0
    if lo == ro then return left.id < right.id end
    return lo < ro
  end)
  return nodes
end

function LayeredMap.renameMap(project, oldId, newId)
  ensureProject(project)
  local namespace = cleanId(project.id, "MOD")
  local oldTilesetId = namespace .. "_" .. cleanId(oldId, "MAP") .. "_LAYERED"
  local oldTileset = project.tilesets[oldTilesetId]
  if oldTileset and oldTileset._layeredGenerated then
    project.tilesets[oldTilesetId] = nil
  end
  if project.layeredMaps[oldId] then
    local source = project.layeredMaps[oldId]
    project.layeredMaps[oldId] = nil
    source.id = newId
    project.layeredMaps[newId] = source
  end
  for _, node in pairs(project.mapWarpNodes) do
    if node.map == oldId then node.map = newId end
    if node.targetMap == oldId then node.targetMap = newId end
  end
end

function LayeredMap.removeMap(project, mapId)
  ensureProject(project)
  local namespace = cleanId(project.id, "MOD")
  local tilesetId = namespace .. "_" .. cleanId(mapId, "MAP") .. "_LAYERED"
  local tileset = project.tilesets[tilesetId]
  if tileset and tileset._layeredGenerated then project.tilesets[tilesetId] = nil end
  project.layeredMaps[mapId] = nil
  local drop = {}
  for id, node in pairs(project.mapWarpNodes) do
    if node.map == mapId then drop[#drop + 1] = id end
  end
  for _, id in ipairs(drop) do LayeredMap.removeWarpNode(project, id) end
end

-- Runtime compiler

-- Source sampling -----------------------------------------------------------

local function readImageData(S, path)
  local resolved, kind = Preview.resolve(S, path)
  if not resolved then error("image is unavailable: " .. tostring(path), 0) end
  if kind == "love" then
    local ok, image = pcall(love.image.newImageData, resolved)
    if ok and image then return image end
    error("could not decode " .. tostring(path) .. ": " .. tostring(image), 0)
  end
  local file = io.open(resolved, "rb")
  if not file then error("could not read " .. tostring(resolved), 0) end
  local bytes = file:read("*a")
  file:close()
  local name = resolved:match("[^/\\]+$") or "tiles.png"
  local okFile, fileData = pcall(love.filesystem.newFileData, bytes, name)
  if not okFile or not fileData then
    error("could not prepare " .. tostring(path), 0)
  end
  local ok, image = pcall(love.image.newImageData, fileData)
  if ok and image then return image end
  error("could not decode " .. tostring(path) .. ": " .. tostring(image), 0)
end

local function imageFor(context, source)
  local key = source.id or source.image
  if context.images[key] then return context.images[key] end
  local image = readImageData(context.S, source.image)
  context.images[key] = image
  return image
end

local function runtimeMicroTile(tileset, cellTile, micro)
  local blockId = math.floor(cellTile / 4)
  local quadrant = cellTile % 4
  local block = tileset.blocks and tileset.blocks[blockId + 1]
  if not block then return nil end
  local qx, qy = quadrant % 2, math.floor(quadrant / 2)
  local mx, my = micro % 2, math.floor(micro / 2)
  return block[(qy * 2 + my) * 4 + qx * 2 + mx + 1]
end

local function animationFor(source, tile)
  if source.runtimeTileset then return nil end
  return source.animations and source.animations[tile]
end

local function paletteSample(r, g, b, a, colors)
  if not colors or a <= 0 then return r, g, b, a end
  local light = (r + g + b) / 3
  local color = light > 0.83 and colors[1]
    or light > 0.5 and colors[2]
    or light > 0.17 and colors[3] or colors[4]
  if not color then return r, g, b, a end
  return color[1] / 255, color[2] / 255, color[3] / 255, a
end

local function sourcePixel(context, source, tile, micro, x, y, paletteColors)
  local image = imageFor(context, source)
  local sx, sy
  if source.runtimeTileset then
    local microTile = runtimeMicroTile(source.tileset, tile, micro)
    if microTile == nil then return 0, 0, 0, 0 end
    local columns = source.tileset.tilesPerRow
      or math.max(1, math.floor(image:getWidth() / 8))
    sx = (microTile % columns) * 8 + x
    sy = math.floor(microTile / columns) * 8 + y
  else
    local columns = source.columns or math.max(1, math.floor(image:getWidth() / 16))
    sx = (tile % columns) * 16 + (micro % 2) * 8 + x
    sy = math.floor(tile / columns) * 16 + math.floor(micro / 2) * 8 + y
  end
  if sx < 0 or sy < 0 or sx >= image:getWidth() or sy >= image:getHeight() then
    return 0, 0, 0, 0
  end
  local r, g, b, a = image:getPixel(sx, sy)
  if paletteColors and source.colorMode ~= "true_color" then
    return paletteSample(r, g, b, a, paletteColors)
  end
  return r, g, b, a
end

local function colorByte(value)
  return math.floor(clamp(value, 0, 1) * 255 + 0.5)
end

-- Custom art can ship with the mod, but the transform sandbox deliberately
-- cannot read arbitrary mod files. Embed only the used 8x8 samples in the
-- generated recipe; base-game samples stay as coordinates into the player's
-- own imported cache.
local function embeddedMicro(context, source, tile, micro)
  local bytes = {}
  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = sourcePixel(context, source, tile, micro, x, y, nil)
      bytes[#bytes + 1] = string.char(
        colorByte(r), colorByte(g), colorByte(b), colorByte(a))
    end
  end
  local raw = table.concat(bytes)
  local id = context.pixelIds[raw]
  if not id then
    id = "P" .. tostring(#context.pixels + 1)
    context.pixelIds[raw] = id
    context.pixels[#context.pixels + 1] = { id = id, bytes = raw }
  end
  return id
end

local function transformSpec(context, refs, micro, animatedIndex, frameTile,
    paletteColors)
  local layers = {}
  for index, ref in ipairs(refs) do
    local tile = index == animatedIndex and frameTile or ref.tile
    local layer = { opacity = ref.opacity }
    local source = ref.source
    local generatedPrefix = "assets/generated/"
    if source.runtimeTileset
        and type(source.image) == "string"
        and source.image:sub(1, #generatedPrefix) == generatedPrefix then
      local microTile = runtimeMicroTile(source.tileset, tile, micro)
      local relative = source.image:sub(#generatedPrefix + 1)
      layer.base = relative
      layer.tile = microTile or 0
      layer.columns = source.tileset.tilesPerRow or 16
      context.bases[relative] = true
    else
      layer.pixels = embeddedMicro(context, source, tile, micro)
    end
    if paletteColors and source.colorMode ~= "true_color" then
      layer.palette = paletteColors
    end
    layers[#layers + 1] = layer
  end
  return layers
end

local function transformSpecKey(spec)
  local parts = {}
  for _, layer in ipairs(spec or {}) do
    parts[#parts + 1] = table.concat({
      layer.base or "", layer.pixels or "", tostring(layer.tile or ""),
      tostring(layer.columns or ""), tostring(layer.opacity or 1),
    }, ":")
    if layer.palette then
      for _, color in ipairs(layer.palette) do
        parts[#parts + 1] = table.concat(color, ",")
      end
    end
  end
  return table.concat(parts, "|")
end

local function addTransformOutput(context, relative, width, height, placements)
  context.outputs[relative] = {
    path = relative, width = width, height = height, placements = placements,
  }
end

local function cellRefs(context, mapSource, index)
  local refs = {}
  for _, layer in ipairs(mapSource.layers or {}) do
    if layer.export ~= false then
      local ref = layer.cells and layer.cells[index]
      if ref then
        local source = LayeredMap.sourceDescriptor(context.S, ref.source)
        if not source then
          error("unknown map tileset source " .. tostring(ref.source), 0)
        end
        refs[#refs + 1] = {
          source = source,
          tile = math.max(0, math.floor(tonumber(ref.tile) or 0)),
          opacity = clamp(layer.opacity or 1, 0, 1),
        }
      end
    end
  end
  return refs
end

local function frameInfo(refs)
  local animatedIndex, frames
  for index, ref in ipairs(refs) do
    local candidate = animationFor(ref.source, ref.tile)
    if candidate and #candidate > 1 then
      if frames then
        return nil, nil, "a cell cannot stack more than one animated tile"
      end
      animatedIndex, frames = index, candidate
    end
  end
  return animatedIndex, frames
end

local function timing(frames)
  local function gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
  end
  local ticks, divisor = {}, nil
  for index, frame in ipairs(frames) do
    local count = math.max(1,
      math.floor((tonumber(frame.duration) or 200) * 60 / 1000 + 0.5))
    ticks[index] = count
    divisor = divisor and gcd(divisor, count) or count
  end
  local sequence = {}
  for index, count in ipairs(ticks) do
    for _ = 1, count / divisor do sequence[#sequence + 1] = index end
  end
  return divisor or 1, sequence
end

local function safeFilename(value)
  local name = tostring(value or "map"):lower():gsub("[^a-z0-9_-]", "_")
  return name ~= "" and name or "map"
end

local function derivedAssetPath(project, relative)
  return "save/mod-derived/" .. tostring(project.id) .. "/" .. relative
end

local function generatedTilesetId(project, mapId)
  return cleanId(project.id, "MOD") .. "_" .. cleanId(mapId, "MAP")
    .. "_LAYERED"
end

local function paletteForMap(S, map)
  local name = Preview.mapPaletteName(S, map)
  return Preview.paletteColors(S, name)
end

local function usesTrueColor(context, mapSource)
  for index = 1, mapSource.cellWidth * mapSource.cellHeight do
    for _, ref in ipairs(cellRefs(context, mapSource, index)) do
      if ref.source.colorMode == "true_color" then return true end
    end
  end
  return false
end

-- Assign final one-based runtime indexes after the complete endpoint graph is
-- known. Arrival-only nodes are retained because active warps may target them.
local function warpPlan(project)
  local groups, indexByNode, activeCells = {}, {}, {}
  for mapId in pairs(project.layeredMaps or {}) do
    groups[mapId] = LayeredMap.nodesForMap(project, mapId)
    activeCells[mapId] = {}
  end
  for mapId, nodes in pairs(groups) do
    for index, node in ipairs(nodes) do
      indexByNode[node.id] = index
      if node.active then
        activeCells[mapId][node.y * project.layeredMaps[mapId].cellWidth
          + node.x + 1] = true
      end
    end
  end
  local records = {}
  for mapId, nodes in pairs(groups) do
    records[mapId] = {}
    for index, node in ipairs(nodes) do
      local target = node.targetNode and project.mapWarpNodes[node.targetNode]
      local destMap, destWarp
      if target then
        destMap = target.map
        destWarp = indexByNode[target.id] or target.originalIndex
      else
        destMap = node.targetMap
        destWarp = node.targetIndex
      end
      if not destMap or not destWarp then
        destMap, destWarp = mapId, index
      end
      records[mapId][index] = {
        x = node.x, y = node.y,
        destMap = destMap, destWarp = destWarp,
      }
    end
  end
  return records, activeCells
end

-- Transform recipe generation ----------------------------------------------

local function luaString(value)
  local out = { '"' }
  value = tostring(value or "")
  for index = 1, #value do
    local byteValue = value:byte(index)
    if byteValue >= 32 and byteValue <= 126
        and byteValue ~= 34 and byteValue ~= 92 then
      out[#out + 1] = string.char(byteValue)
    else
      out[#out + 1] = string.format("\\%03d", byteValue)
    end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

local function luaLiteral(value)
  local kind = type(value)
  if kind == "nil" then return "nil" end
  if kind == "boolean" or kind == "number" then return tostring(value) end
  if kind == "string" then return luaString(value) end
  if kind ~= "table" then return "nil" end

  local length = #value
  local sequence = true
  local count = 0
  for key in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key > length
        or key % 1 ~= 0 then sequence = false end
  end
  local parts = {}
  if sequence and count == length then
    for index = 1, length do parts[#parts + 1] = luaLiteral(value[index]) end
  else
    for _, key in ipairs(sortedKeys(value)) do
      parts[#parts + 1] = "[" .. luaString(key) .. "]=" .. luaLiteral(value[key])
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function emitTransform(context)
  local bases = sortedKeys(context.bases)
  local pixels = {}
  for _, entry in ipairs(context.pixels) do pixels[entry.id] = entry.bytes end
  local outputs = {}
  for _, path in ipairs(sortedKeys(context.outputs)) do
    outputs[#outputs + 1] = context.outputs[path]
  end

  local lines = {
    "-- Generated by Map Builder. Saving the project rewrites this file.",
    "-- Base-game pixels are sampled from the player's imported cache; only",
    "-- custom source pixels used by the composed maps are stored here.",
    "local BASES = " .. luaLiteral(bases),
    "local PIXELS = " .. luaLiteral(pixels),
    "local OUTPUTS = " .. luaLiteral(outputs),
    "",
    "local function sample(layer, baseImages, x, y)",
    "  local r, g, b, a",
    "  if layer.base then",
    "    local image = baseImages[layer.base]",
    "    local sx = (layer.tile % layer.columns) * 8 + x",
    "    local sy = math.floor(layer.tile / layer.columns) * 8 + y",
    "    r, g, b, a = image:getPixel(sx, sy)",
    "  else",
    "    local raw = PIXELS[layer.pixels]",
    "    local offset = (y * 8 + x) * 4 + 1",
    "    local rb, gb, bb, ab = string.byte(raw, offset, offset + 3)",
    "    r, g, b, a = rb / 255, gb / 255, bb / 255, ab / 255",
    "  end",
    "  if layer.palette and a > 0 then",
    "    local light = (r + g + b) / 3",
    "    local color = light > 0.83 and layer.palette[1]",
    "      or light > 0.5 and layer.palette[2]",
    "      or light > 0.17 and layer.palette[3] or layer.palette[4]",
    "    r, g, b = color[1] / 255, color[2] / 255, color[3] / 255",
    "  end",
    "  return r, g, b, a * (layer.opacity or 1)",
    "end",
    "",
    "return function(ctx)",
    "  local baseImages = {}",
    "  for _, relative in ipairs(BASES) do",
    "    if not ctx.exists(relative) then return end",
    "    baseImages[relative] = ctx.readImage(relative)",
    "  end",
    "  for _, output in ipairs(OUTPUTS) do",
    "    local image = ctx.blank(output.width, output.height)",
    "    for _, placement in ipairs(output.placements) do",
    "      for y = 0, 7 do",
    "        for x = 0, 7 do",
    "          local outR, outG, outB, outA = 0, 0, 0, 0",
    "          local premulR, premulG, premulB = 0, 0, 0",
    "          for _, layer in ipairs(placement.layers) do",
    "            local r, g, b, a = sample(layer, baseImages, x, y)",
    "            premulR = r * a + premulR * (1 - a)",
    "            premulG = g * a + premulG * (1 - a)",
    "            premulB = b * a + premulB * (1 - a)",
    "            outA = a + outA * (1 - a)",
    "          end",
    "          if outA > 0 then",
    "            outR, outG, outB = premulR / outA, premulG / outA, premulB / outA",
    "          end",
    "          image:setPixel(placement.x + x, placement.y + y,",
    "            outR, outG, outB, outA)",
    "        end",
    "      end",
    "    end",
    "    ctx.writeImage(image, output.path)",
    "  end",
    "end",
    "",
  }
  local sep = package.config:sub(1, 1)
  local path = context.S.path .. sep .. "mapbuilder_transforms.lua"
  local ok, err = ModIO.writeText(path, table.concat(lines, "\n"))
  if not ok then return false, err end
  return ModIO.setMapBuilderTransform(context.S.path, "mapbuilder_transforms.lua")
end

-- Map assembly --------------------------------------------------------------

-- Each 16x16 editor cell becomes four 8x8 graphics tiles. Groups of four
-- editor cells are then deduplicated into the runtime's 32x32 map blocks.
local function compileMap(context, mapId, mapSource, warpRecords, activeWarpCells)
  local project, S = context.project, context.S
  local map = project.maps[mapId]
  if not map then error("layered map has no map record: " .. mapId, 0) end
  local width, height = mapSource.cellWidth, mapSource.cellHeight
  if width < 2 or height < 2 or width % 2 ~= 0 or height % 2 ~= 0 then
    error(mapId .. ": map dimensions must be even 16x16-cell values", 0)
  end

  for _, node in ipairs(LayeredMap.nodesForMap(project, mapId)) do
    if node.x < 0 or node.y < 0 or node.x >= width or node.y >= height then
      error(("%s: warp %s is outside the resized map"):format(mapId, node.id), 0)
    end
  end

  local trueColor = usesTrueColor(context, mapSource)
  local paletteColors = trueColor and paletteForMap(S, map) or nil
  local tiles, tileIds = {}, {}
  local cells = {}
  local animatedTiles = {}
  local walkable, water, shore, warp = {}, {}, {}, {}
  local grassTile

  local function addTile(spec, class, animationImages, frames)
    local animKey = ""
    if frames then
      local parts = {}
      for _, frame in ipairs(frames) do
        parts[#parts + 1] = tostring(frame.tile) .. ":" .. tostring(frame.duration)
      end
      animKey = "|anim=" .. table.concat(parts, ",")
    end
    local key = transformSpecKey(spec)
      .. "|class=" .. tostring(class or "") .. animKey
    local id = tileIds[key]
    if id ~= nil then return id end
    id = #tiles
    if id >= 256 then
      error(mapId .. ": composed graphics need more than 256 unique 8x8 tiles", 0)
    end
    tileIds[key] = id
    tiles[#tiles + 1] = { layers = spec, class = class }
    local baseClass = class and class:gsub("%+warp$", "") or nil
    if baseClass == "walk" then walkable[id] = true
    elseif baseClass == "grass" then
      walkable[id] = true
      -- The original format has one grass collision tile. Additional grass
      -- graphics remain walkable; the first one carries encounter behavior.
      grassTile = grassTile or id
    elseif baseClass == "water" then water[id] = true
    elseif baseClass == "shore" then shore[id] = true end
    if class and class:find("+warp", 1, true) then warp[id] = true end
    if animationImages and frames then
      local period, sequence = timing(frames)
      animatedTiles[#animatedTiles + 1] = {
        tile = id, kind = "frames", period = period,
        images = animationImages, sequence = sequence,
      }
    end
    return id
  end

  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local refs = cellRefs(context, mapSource, index)
      local animatedIndex, frames, frameErr = frameInfo(refs)
      if frameErr then
        error(("%s (%d,%d): %s"):format(mapId, x, y, frameErr), 0)
      end
      cells[index] = {}
      for micro = 0, 3 do
        local firstFrame = frames and frames[1].tile or nil
        local spec = transformSpec(
          context, refs, micro, animatedIndex, firstFrame, paletteColors)
        local class
        if micro == 2 then
          class = mapSource.collision[index] or "solid"
          if activeWarpCells and activeWarpCells[index] then
            class = class .. "+warp"
          end
        end
        local animationImages
        if frames then
          animationImages = {}
          for frameIndex, frame in ipairs(frames) do
            local frameSpec = transformSpec(context, refs, micro,
              animatedIndex, frame.tile, paletteColors)
            local rel = ("mapbuilder/%s/animations/%s_%d_%d_%d.png")
              :format(safeFilename(project.id), safeFilename(mapId),
                index, micro, frameIndex)
            addTransformOutput(context, rel, 8, 8, {
              { x = 0, y = 0, layers = frameSpec },
            })
            animationImages[#animationImages + 1] = derivedAssetPath(project, rel)
          end
        end
        cells[index][micro + 1] = addTile(spec, class, animationImages, frames)
      end
    end
  end

  if #tiles == 0 then
    addTile({}, "solid")
  end
  local atlasWidth = 128
  local atlasHeight = math.max(8, math.ceil(#tiles / 16) * 8)
  local atlasPlacements = {}
  for id, entry in ipairs(tiles) do
    local tileId = id - 1
    atlasPlacements[#atlasPlacements + 1] = {
      x = (tileId % 16) * 8,
      y = math.floor(tileId / 16) * 8,
      layers = entry.layers,
    }
  end
  local atlasTransformRel = "mapbuilder/" .. safeFilename(project.id) .. "/"
    .. safeFilename(mapId) .. "_tiles.png"
  addTransformOutput(context, atlasTransformRel,
    atlasWidth, atlasHeight, atlasPlacements)
  local atlasRel = derivedAssetPath(project, atlasTransformRel)

  local blocks, blockIds = {}, {}
  local function addBlock(block)
    local key = table.concat(block, ",")
    local id = blockIds[key]
    if id ~= nil then return id end
    id = #blocks
    if id >= 256 then error(mapId .. ": map needs more than 256 blocks", 0) end
    blockIds[key] = id
    blocks[#blocks + 1] = block
    return id
  end
  local mapBlocks = {}
  for blockY = 0, height / 2 - 1 do
    for blockX = 0, width / 2 - 1 do
      local block = {}
      for cellY = 0, 1 do
        for cellX = 0, 1 do
          local index = (blockY * 2 + cellY) * width
            + blockX * 2 + cellX + 1
          local microIds = cells[index]
          for microY = 0, 1 do
            for microX = 0, 1 do
              block[(cellY * 2 + microY) * 4
                + cellX * 2 + microX + 1] = microIds[microY * 2 + microX + 1]
            end
          end
        end
      end
      mapBlocks[#mapBlocks + 1] = addBlock(block)
    end
  end

  local function values(set)
    local out = {}
    for value in pairs(set) do out[#out + 1] = value end
    table.sort(out)
    return out
  end

  local tilesetId = generatedTilesetId(project, mapId)
  local tileset = {
    id = tilesetId,
    image = atlasRel,
    imageWidth = atlasWidth,
    imageHeight = atlasHeight,
    tilesPerRow = 16,
    blocks = blocks,
    walkable = values(walkable),
    waterTiles = values(water),
    shoreTiles = values(shore),
    doorTiles = {},
    warpTiles = values(warp),
    counterTiles = {},
    animation = "TILEANIM_NONE",
    trueColor = trueColor and true or nil,
    animatedTiles = #animatedTiles > 0 and animatedTiles or nil,
    _isNew = true,
    _layeredGenerated = true,
  }
  project.tilesets[tilesetId] = tileset

  map.tileset = tilesetId
  map.width, map.height = width / 2, height / 2
  map.blocks = mapBlocks
  map.borderBlock = 0
  map.warps = warpRecords or {}
  -- Carry this on both records.  The tileset flag is the canonical link, but
  -- editor/world previews can temporarily retain an older tileset object
  -- while a generated map is being rebuilt.  The map-level override makes
  -- the color contract immediate and is also what TileRenderer checks first.
  map.trueColor = trueColor and true or nil
  map._layeredSource = mapId
  return map, tileset
end

-- Compiler entry point ------------------------------------------------------

function LayeredMap.compileProject(S)
  if not (S and S.project and S.path) then return false, "no open mod" end
  local project = ensureProject(S.project)
  if not next(project.layeredMaps) then
    if project.layeredTransform then
      local removed, removeErr = ModIO.removeMapBuilderTransform(S.path)
      if not removed then return false, removeErr end
      project.layeredTransform = nil
      if S.manifestDraft and S.browseModId == project.id then
        S.manifestDraft.assets_transforms = nil
      end
    end
    return true, "no layered maps"
  end
  if not (love and love.image and love.image.newImageData) then
    return false, "layered maps require LÖVE image support"
  end

  local context = {
    S = S,
    project = project,
    images = {},
    bases = {},
    pixelIds = {},
    pixels = {},
    outputs = {},
  }
  local records, activeCells = warpPlan(project)
  local compiled = 0
  for _, mapId in ipairs(sortedKeys(project.layeredMaps)) do
    local ok, err = pcall(compileMap, context, mapId,
      project.layeredMaps[mapId], records[mapId], activeCells[mapId])
    if not ok then return false, err end
    compiled = compiled + 1
    if S.data then
      S.data.maps[mapId] = project.maps[mapId]
      local tilesetId = project.maps[mapId].tileset
      S.data.tilesets[tilesetId] = project.tilesets[tilesetId]
    end
  end
  local transformed, transformErr = emitTransform(context)
  if not transformed then return false, transformErr end
  project.layeredTransform = "mapbuilder_transforms.lua"
  if S.manifestDraft and S.browseModId == project.id then
    S.manifestDraft.assets_transforms = project.layeredTransform
  end
  pcall(function() require("src.world.MapLoader").invalidateAll() end)
  Preview.invalidate()
  return true, string.format("compiled %d layered map(s)", compiled)
end

LayeredMap.deepCopy = deepCopy
LayeredMap.cleanId = cleanId

return LayeredMap
