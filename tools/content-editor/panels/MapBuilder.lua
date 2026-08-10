-- Native 16x16 layered map authoring panel.

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
local LayeredMap = require("LayeredMap")

local MapBuilder = {}
local PAL = Theme.PAL
local CELL = LayeredMap.CELL_SIZE

local TOOLS = {
  { id = "pencil", label = "Pencil", tip = "Paint the selected 16x16 tile" },
  { id = "eraser", label = "Eraser", tip = "Erase cells; drag for a range" },
  { id = "fill", label = "Fill", tip = "Flood-fill matching cells" },
  { id = "rectangle", label = "Rectangle", tip = "Drag a filled rectangle" },
  { id = "picker", label = "Picker", tip = "Pick a source tile from the map" },
  { id = "select", label = "Select", tip = "Drag ranges; Shift adds another" },
  { id = "collision", label = "Collision", tip = "Paint cell passage" },
  { id = "warp", label = "Warp", tip = "Place directed, two-way, or custom-return warps" },
  { id = "pan", label = "Pan", tip = "Drag the map without painting" },
}

-- Shared panel helpers

local quadCache = setmetatable({}, { __mode = "k" })

local function clamp(value, low, high)
  value = tonumber(value) or low
  return math.max(low, math.min(high, value))
end

local function sortedKeys(bucket)
  local out = {}
  for key in pairs(bucket or {}) do out[#out + 1] = key end
  table.sort(out)
  return out
end

local function field(App, id, x, y, w, h, value, placeholder)
  local result = Kit.textfield(id, x, y, w, h, value, placeholder)
  if result ~= tostring(value or "") then App.markDirty() end
  return result
end

local function mapSource(S)
  return S.project and S.project.layeredMaps
    and S.project.layeredMaps[S.builderMapId]
end

local function mapRecord(S)
  return S.project and S.project.maps and S.project.maps[S.builderMapId]
end

local function quad(image, x, y, w, h)
  local bucket = quadCache[image]
  if not bucket then
    bucket = {}
    quadCache[image] = bucket
  end
  local key = table.concat({ x, y, w, h }, ":")
  if not bucket[key] then
    local iw, ih = image:getDimensions()
    bucket[key] = love.graphics.newQuad(x, y, w, h, iw, ih)
  end
  return bucket[key]
end

local function animationTile(source, tile)
  local frames = source and source.animations and source.animations[tile]
  if not frames or #frames < 2 then return tile end
  local total = 0
  for _, frame in ipairs(frames) do
    total = total + math.max(16, tonumber(frame.duration) or 200)
  end
  local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
  local cursor = (now * 1000) % total
  for _, frame in ipairs(frames) do
    cursor = cursor - math.max(16, tonumber(frame.duration) or 200)
    if cursor < 0 then return frame.tile end
  end
  return frames[#frames].tile
end

local function drawSourceTile(S, source, tile, x, y, size, alpha)
  if not source or not source.image then return false end
  local image = Preview.image(S, source.image)
  if not image then return false end
  tile = animationTile(source, math.max(0, math.floor(tonumber(tile) or 0)))
  love.graphics.setColor(1, 1, 1, alpha or 1)
  if source.runtimeTileset then
    local blockId = math.floor(tile / 4)
    local quadrant = tile % 4
    local block = source.tileset.blocks and source.tileset.blocks[blockId + 1]
    if not block then return false end
    local qx, qy = quadrant % 2, math.floor(quadrant / 2)
    local scale = size / 16
    local perRow = source.tileset.tilesPerRow
      or math.max(1, math.floor(image:getWidth() / 8))
    for microY = 0, 1 do
      for microX = 0, 1 do
        local tileId = block[(qy * 2 + microY) * 4 + qx * 2 + microX + 1]
        if tileId then
          local sx = (tileId % perRow) * 8
          local sy = math.floor(tileId / perRow) * 8
          love.graphics.draw(image, quad(image, sx, sy, 8, 8),
            x + microX * 8 * scale, y + microY * 8 * scale,
            0, scale, scale)
        end
      end
    end
  else
    local columns = source.columns or math.max(1, math.floor(image:getWidth() / 16))
    local sx = (tile % columns) * 16
    local sy = math.floor(tile / columns) * 16
    local scale = size / 16
    love.graphics.draw(image, quad(image, sx, sy, 16, 16), x, y, 0, scale, scale)
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

local function refEqual(left, right)
  if left == right then return true end
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  return left.source == right.source and left.tile == right.tile
end

local function activeLayer(S, source)
  S.builderLayer = clamp(S.builderLayer or 1, 1, math.max(1, #source.layers))
  return source.layers[S.builderLayer], S.builderLayer
end

local function brushRef(S)
  if not S.builderSourceId then return nil end
  return { source = S.builderSourceId, tile = S.builderTile or 0 }
end

-- Editing primitives

local function paintCell(S, source, x, y, App, erase, deferDirty)
  local layer, layerIndex = activeLayer(S, source)
  if not layer then return false end
  local before = LayeredMap.getCell(source, layerIndex, x, y)
  local after = erase and nil or brushRef(S)
  if refEqual(before, after) then return false end
  LayeredMap.setCell(source, layerIndex, x, y, after)
  if not deferDirty then App.markDirty() end
  return true
end

local function paintCollisionCell(S, source, x, y)
  local index = y * source.cellWidth + x + 1
  local mode = S.builderCollision or "solid"
  if source.collision[index] == mode then return false end
  LayeredMap.setCollision(source, x, y, mode)
  return true
end

-- Visit every grid cell crossed by a quick mouse movement. Without this,
-- a fast drag only paints the cells sampled on rendered frames and leaves gaps.
local function visitCellLine(x0, y0, x1, y1, visit)
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local stepX = x0 < x1 and 1 or -1
  local stepY = y0 < y1 and 1 or -1
  local errorValue = dx - dy

  while true do
    visit(x0, y0)
    if x0 == x1 and y0 == y1 then break end
    local twiceError = 2 * errorValue
    if twiceError > -dy then
      errorValue = errorValue - dy
      x0 = x0 + stepX
    end
    if twiceError < dx then
      errorValue = errorValue + dx
      y0 = y0 + stepY
    end
  end
end

local function floodFill(S, source, x, y, App)
  local layer, layerIndex = activeLayer(S, source)
  if not layer then return end
  local replacement = brushRef(S)
  if not replacement then return end
  local target = LayeredMap.getCell(source, layerIndex, x, y)
  if refEqual(target, replacement) then return end
  local queue, cursor = { { x, y } }, 1
  local seen = {}
  local changed = false
  while cursor <= #queue do
    local point = queue[cursor]
    cursor = cursor + 1
    local px, py = point[1], point[2]
    local key = py * source.cellWidth + px + 1
    if not seen[key] and px >= 0 and py >= 0
        and px < source.cellWidth and py < source.cellHeight then
      seen[key] = true
      if refEqual(LayeredMap.getCell(source, layerIndex, px, py), target) then
        LayeredMap.setCell(source, layerIndex, px, py, replacement)
        changed = true
        queue[#queue + 1] = { px - 1, py }
        queue[#queue + 1] = { px + 1, py }
        queue[#queue + 1] = { px, py - 1 }
        queue[#queue + 1] = { px, py + 1 }
      end
    end
  end
  if changed then App.markDirty() end
end

local function normalizedRect(rect)
  if not rect then return nil end
  return math.min(rect.x0, rect.x1), math.min(rect.y0, rect.y1),
    math.max(rect.x0, rect.x1), math.max(rect.y0, rect.y1)
end

local function applyRectangle(S, source, rect, App, erase)
  local x0, y0, x1, y1 = normalizedRect(rect)
  if not x0 then return end
  local changed = false
  for y = y0, y1 do
    for x = x0, x1 do
      changed = paintCell(S, source, x, y, App, erase) or changed
    end
  end
  return changed
end

local function clearSelections(S, source, App)
  if not S.builderSelections or #S.builderSelections == 0 then return false end
  local changed = false
  for _, rect in ipairs(S.builderSelections) do
    changed = applyRectangle(S, source, rect, App, true) or changed
  end
  if changed then
    S.status = string.format("Cleared %d selected range(s)", #S.builderSelections)
  end
  return changed
end

local function sourceAtCell(S, source, x, y)
  for index = #source.layers, 1, -1 do
    local layer = source.layers[index]
    if layer.visible ~= false then
      local ref = LayeredMap.getCell(source, index, x, y)
      if ref then return ref, index end
    end
  end
  return nil
end

-- Warp placement workflow

-- Placement is a short state machine: source, destination, and optionally a
-- custom return point. Changing the selected map between clicks is expected.
local function ensureLayeredDestination(S, App)
  if mapSource(S) then return true end
  local source, err = LayeredMap.convertMap(S, S.builderMapId)
  if not source then
    S.status = "Convert failed: " .. tostring(err)
    return false
  end
  S.builderLayer = 1
  App.markDirty()
  S.status = "Converted " .. S.builderMapId .. " to editable layers"
  return true
end

local function completeWarp(S, App, point)
  local draft = S.builderWarpDraft
  local mode = S.builderWarpMode or "two_way"
  if not draft then
    S.builderWarpDraft = { phase = "destination", from = point, mode = mode }
    S.status = "Source placed — select a destination map and click its arrival cell"
    return
  end
  if draft.phase == "destination" then
    if mode == "custom_return" then
      draft.destination = point
      draft.phase = "return"
      S.status = "Arrival placed — select any map and click the return destination"
      return
    end
    local ok, err = LayeredMap.createWarpLink(
      S.project, mode, draft.from, point)
    if ok then
      S.builderWarpDraft = nil
      App.markDirty()
      S.status = mode == "two_way" and "Created two-way warp"
        or "Created one-way warp"
    else
      S.status = "Warp failed: " .. tostring(err)
    end
    return
  end
  local ok, err = LayeredMap.createWarpLink(
    S.project, "custom_return", draft.from, draft.destination, point)
  if ok then
    S.builderWarpDraft = nil
    App.markDirty()
    S.status = "Created warp with a custom return destination"
  else
    S.status = "Warp failed: " .. tostring(err)
  end
end

-- Canvas rendering and input

local function drawChecker(x, y, size)
  local half = size / 2
  love.graphics.setColor(0.16, 0.18, 0.22, 1)
  love.graphics.rectangle("fill", x, y, size, size)
  love.graphics.setColor(0.2, 0.22, 0.27, 1)
  love.graphics.rectangle("fill", x, y, half, half)
  love.graphics.rectangle("fill", x + half, y + half, half, half)
end

local function drawSelections(S, source)
  for _, rect in ipairs(S.builderSelections or {}) do
    local x0, y0, x1, y1 = normalizedRect(rect)
    love.graphics.setColor(0.25, 0.65, 1, 0.18)
    love.graphics.rectangle("fill", x0 * CELL, y0 * CELL,
      (x1 - x0 + 1) * CELL, (y1 - y0 + 1) * CELL)
    love.graphics.setColor(0.35, 0.75, 1, 0.95)
    love.graphics.rectangle("line", x0 * CELL + 0.5, y0 * CELL + 0.5,
      (x1 - x0 + 1) * CELL - 1, (y1 - y0 + 1) * CELL - 1)
  end
  if S.builderRangeDraft then
    local x0, y0, x1, y1 = normalizedRect(S.builderRangeDraft)
    love.graphics.setColor(1, 0.75, 0.25, 0.22)
    love.graphics.rectangle("fill", x0 * CELL, y0 * CELL,
      (x1 - x0 + 1) * CELL, (y1 - y0 + 1) * CELL)
  end
end

local function drawWarpNodes(S, source)
  for _, node in ipairs(LayeredMap.nodesForMap(S.project, S.builderMapId)) do
    local cx, cy = node.x * CELL + CELL / 2, node.y * CELL + CELL / 2
    local selected = S.builderWarpNodeId == node.id
    love.graphics.setColor(node.active and 1 or 0.25,
      node.active and 0.38 or 0.7, node.active and 0.18 or 1, 0.82)
    love.graphics.circle("fill", cx, cy, selected and 6 or 5)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("line", cx, cy, selected and 7 or 6)
  end
end

local function fitCanvas(S, source, viewW, viewH)
  local mapW, mapH = source.cellWidth * CELL, source.cellHeight * CELL
  local zoom = math.min(viewW / math.max(1, mapW), viewH / math.max(1, mapH))
  zoom = clamp(zoom, 0.25, 6)
  S.builderZoom = zoom
  S.builderCamX = (mapW - viewW / zoom) / 2
  S.builderCamY = (mapH - viewH / zoom) / 2
  S._builderFitFor = source.id .. ":" .. source.cellWidth .. "x" .. source.cellHeight
end

local function drawCanvas(S, source, x, y, w, h, App)
  local pad = 8 * Kit.scale
  local vx, vy = x + pad, y + pad
  local vw, vh = math.max(1, w - pad * 2), math.max(1, h - pad * 2)
  local fitKey = source.id .. ":" .. source.cellWidth .. "x" .. source.cellHeight
  if S._builderFitFor ~= fitKey then fitCanvas(S, source, vw, vh) end
  local zoom = clamp(S.builderZoom or 1, 0.25, 8)
  S.builderZoom = zoom

  love.graphics.setScissor(math.floor(vx), math.floor(vy),
    math.ceil(vw), math.ceil(vh))
  love.graphics.push()
  love.graphics.translate(vx, vy)
  love.graphics.scale(zoom, zoom)
  love.graphics.translate(-(S.builderCamX or 0), -(S.builderCamY or 0))

  for cy = 0, source.cellHeight - 1 do
    for cx = 0, source.cellWidth - 1 do
      local dx, dy = cx * CELL, cy * CELL
      drawChecker(dx, dy, CELL)
      for _, layer in ipairs(source.layers or {}) do
        if layer.visible ~= false then
          local ref = layer.cells[cy * source.cellWidth + cx + 1]
          if ref then
            local tileSource = LayeredMap.sourceDescriptor(S, ref.source)
            drawSourceTile(S, tileSource, ref.tile, dx, dy, CELL,
              clamp(layer.opacity or 1, 0, 1))
          end
        end
      end
      if (S.builderTool or "pencil") == "collision" then
        local mode = source.collision[cy * source.cellWidth + cx + 1] or "solid"
        local colors = {
          solid = { 1, 0.2, 0.2 }, walk = { 0.2, 1, 0.4 },
          grass = { 1, 0.2, 0.9 }, water = { 0.15, 0.55, 1 },
          shore = { 0.95, 0.75, 0.25 },
        }
        local color = colors[mode] or colors.solid
        love.graphics.setColor(color[1], color[2], color[3], 0.28)
        love.graphics.rectangle("fill", dx, dy, CELL, CELL)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 0.18)
  for gx = 0, source.cellWidth do
    love.graphics.line(gx * CELL, 0, gx * CELL, source.cellHeight * CELL)
  end
  for gy = 0, source.cellHeight do
    love.graphics.line(0, gy * CELL, source.cellWidth * CELL, gy * CELL)
  end
  drawSelections(S, source)
  drawWarpNodes(S, source)
  love.graphics.pop()
  love.graphics.setScissor()

  local over = Kit.hit(vx, vy, vw, vh)
  local function mouseCell()
    local worldX = (Kit.mouseX - vx) / zoom + (S.builderCamX or 0)
    local worldY = (Kit.mouseY - vy) / zoom + (S.builderCamY or 0)
    return math.floor(worldX / CELL), math.floor(worldY / CELL)
  end
  local cx, cy = mouseCell()
  local inMap = cx >= 0 and cy >= 0
    and cx < source.cellWidth and cy < source.cellHeight
  if over and inMap then
    S.builderHoverX, S.builderHoverY = cx, cy
  end

  local middle = love.mouse and love.mouse.isDown and love.mouse.isDown(3)
  local space = love.keyboard and love.keyboard.isDown
    and (love.keyboard.isDown("space") or love.keyboard.isDown("lalt"))
  local tool = S.builderTool or "pencil"
  local panning = tool == "pan" or middle or space
  if over and inMap and Kit.mouseClicked and not Kit.blockClicks
      and (tool == "fill" or tool == "picker" or tool == "warp") then
    if tool == "fill" then
      floodFill(S, source, cx, cy, App)
    elseif tool == "picker" then
      local ref, layerIndex = sourceAtCell(S, source, cx, cy)
      if ref then
        S.builderSourceId, S.builderTile = ref.source, ref.tile
        S.builderLayer = layerIndex
        S.builderTool = "pencil"
        S.status = "Picked tile — Pencil armed"
      end
    else
      completeWarp(S, App, { map = S.builderMapId, x = cx, y = cy })
    end
  elseif Kit.mouseDown and not Kit.blockClicks and (over or S._builderDrag) then
    if panning then
      if not S._builderDrag or not S._builderDrag.pan then
        S._builderDrag = {
          pan = true, mx = Kit.mouseX, my = Kit.mouseY,
          camX = S.builderCamX or 0, camY = S.builderCamY or 0,
        }
      else
        S.builderCamX = S._builderDrag.camX
          - (Kit.mouseX - S._builderDrag.mx) / zoom
        S.builderCamY = S._builderDrag.camY
          - (Kit.mouseY - S._builderDrag.my) / zoom
      end
    elseif inMap and (tool == "rectangle" or tool == "select" or tool == "eraser") then
      if not S._builderDrag then
        S._builderDrag = { range = true, x0 = cx, y0 = cy, tool = tool }
      end
      S.builderRangeDraft = {
        x0 = S._builderDrag.x0, y0 = S._builderDrag.y0, x1 = cx, y1 = cy,
      }
    elseif inMap and (tool == "pencil" or tool == "collision") then
      local stroke = S._builderStroke
      if not stroke or stroke.tool ~= tool then
        if stroke then App.endEditBatch() end
        App.beginEditBatch()
        stroke = { tool = tool, x = cx, y = cy }
        S._builderStroke = stroke
      end

      local changed = false
      visitCellLine(stroke.x, stroke.y, cx, cy, function(px, py)
        if px >= 0 and py >= 0
            and px < source.cellWidth and py < source.cellHeight then
          if tool == "pencil" then
            changed = paintCell(S, source, px, py, App, false, true) or changed
          else
            changed = paintCollisionCell(S, source, px, py) or changed
          end
        end
      end)
      stroke.x, stroke.y = cx, cy
      if changed then App.markDirty() end
    end
  elseif S._builderDrag then
    if S._builderDrag.range and S.builderRangeDraft then
      local rect = S.builderRangeDraft
      if S._builderDrag.tool == "select" then
        local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
        if not shift then S.builderSelections = {} end
        S.builderSelections = S.builderSelections or {}
        S.builderSelections[#S.builderSelections + 1] = rect
      elseif S._builderDrag.tool == "eraser" then
        applyRectangle(S, source, rect, App, true)
      else
        applyRectangle(S, source, rect, App, false)
      end
    end
    S._builderDrag = nil
    S.builderRangeDraft = nil
  end

  if not Kit.mouseDown and S._builderStroke then
    App.endEditBatch()
    S._builderStroke = nil
  end

  love.graphics.setColor(1, 1, 1, 1)
  local coord = inMap and string.format("cell %d, %d", cx, cy) or ""
  Kit.text("micro", coord, vx + 6 * Kit.scale, vy + vh - 18 * Kit.scale, PAL.heading)
end

local function filteredMapIds(S)
  local query = tostring(S.builderMapQuery or ""):upper()
  local ids = {}
  for _, id in ipairs(LayeredMap.allMapIds(S)) do
    if query == "" or id:upper():find(query, 1, true) then ids[#ids + 1] = id end
  end
  return ids
end

-- Map and tileset browsers

local function newMapTilesets(S)
  local ids = sortedKeys(S.data and S.data.tilesets)
  if #ids == 0 then ids[1] = "OVERWORLD" end
  return ids
end

local function beginNewMap(S)
  local ids = newMapTilesets(S)
  local selected = ids[1]
  for _, id in ipairs(ids) do
    if id == "OVERWORLD" then selected = id; break end
  end
  S.builderNewMap = {
    id = "NEW_MAP", width = "20", height = "18", tileset = selected,
  }
  Kit.blur()
end

local function drawNewMapForm(S, x, y, w, App)
  local draft = S.builderNewMap
  if not draft then return end
  Kit.text("micro", "Map ID", x, y + 5 * Kit.scale, PAL.caption)
  draft.id = Kit.textfield("builder_new_map_id", x + 52 * Kit.scale, y,
    w - 52 * Kit.scale, 24 * Kit.scale, draft.id, "MY_NEW_MAP")
  y = y + 30 * Kit.scale
  Kit.text("micro", "Size", x, y + 5 * Kit.scale, PAL.caption)
  draft.width = Kit.textfield("builder_new_map_w", x + 52 * Kit.scale, y,
    48 * Kit.scale, 24 * Kit.scale, draft.width, "20")
  Kit.text("micro", "x", x + 105 * Kit.scale, y + 5 * Kit.scale, PAL.muted)
  draft.height = Kit.textfield("builder_new_map_h", x + 118 * Kit.scale, y,
    48 * Kit.scale, 24 * Kit.scale, draft.height, "18")
  Kit.text("micro", "cells", x + 171 * Kit.scale, y + 5 * Kit.scale, PAL.muted)
  y = y + 30 * Kit.scale

  local tilesets = newMapTilesets(S)
  local selectedIndex = 1
  for index, id in ipairs(tilesets) do
    if id == draft.tileset then selectedIndex = index; break end
  end
  if Kit.stepper(x, y, 24 * Kit.scale, 24 * Kit.scale, "<") then
    selectedIndex = ((selectedIndex - 2) % #tilesets) + 1
    draft.tileset = tilesets[selectedIndex]
  end
  Kit.textCenter("micro", Kit.ellipsize("micro", draft.tileset, w - 56 * Kit.scale),
    x + 28 * Kit.scale, y + 5 * Kit.scale, w - 56 * Kit.scale, PAL.heading)
  if Kit.stepper(x + w - 24 * Kit.scale, y, 24 * Kit.scale, 24 * Kit.scale, ">") then
    selectedIndex = (selectedIndex % #tilesets) + 1
    draft.tileset = tilesets[selectedIndex]
  end
  y = y + 31 * Kit.scale

  local width, height = tonumber(draft.width), tonumber(draft.height)
  local validSize = width and height and width >= 2 and height >= 2
    and width % 2 == 0 and height % 2 == 0
  local half = (w - 4 * Kit.scale) / 2
  if Kit.button(x, y, half, 25 * Kit.scale, "Create", {
      kind = "good", enabled = validSize,
      tooltip = "Map dimensions must be even 16x16-cell values",
    }) then
    local source = LayeredMap.createMap(
      S, draft.id, width, height, draft.tileset)
    S.builderNewMap = nil
    S.builderMapId = source.id
    S.builderLayer = 1
    S.builderSourceId = LayeredMap.runtimeSourceId(source.baseTileset)
    S.builderSelections = {}
    S._builderFitFor = nil
    App.markDirty()
    S.status = "Created custom map " .. source.id
  end
  if Kit.button(x + half + 4 * Kit.scale, y, half, 25 * Kit.scale,
      "Cancel", { kind = "ghost" }) then
    S.builderNewMap = nil
    Kit.blur()
  end
end

local function drawMapList(S, x, y, w, h, App)
  Kit.card(x, y, w, h, 10 * Kit.scale)
  Kit.text("caption", "MAPS", x + 10 * Kit.scale, y + 8 * Kit.scale, PAL.heading)
  S.builderMapQuery = Kit.textfield("builder_map_search",
    x + 10 * Kit.scale, y + 28 * Kit.scale, w - 20 * Kit.scale,
    26 * Kit.scale, S.builderMapQuery or "", "Filter map IDs")
  local ids = filteredMapIds(S)
  if not S.builderMapId then
    S.builderMapId = sortedKeys(S.project.layeredMaps)[1] or ids[1]
  end
  local rowH = 25 * Kit.scale
  local listY = y + 60 * Kit.scale
  local footerH = (S.builderNewMap and 154 or 66) * Kit.scale
  local listH = math.max(rowH, h - (listY - y) - footerH)
  local perPage = math.max(1, math.floor(listH / rowH))
  local offset = clamp(S.builderMapOffset or 0, 0, math.max(0, #ids - perPage))
  local innerW = w - 28 * Kit.scale
  local scrollId = "builderMapOffset"
  offset = Kit.scroll(x + 8 * Kit.scale, listY, w - 16 * Kit.scale, listH,
    offset, #ids, perPage, 3, scrollId)
  Kit.pushClip(x + 8 * Kit.scale, listY, innerW, listH)
  for row = 1, perPage do
    local id = ids[offset + row]
    if not id then break end
    local ry = listY + (row - 1) * rowH
    local layered = S.project.layeredMaps[id] ~= nil
    if Kit.row(x + 8 * Kit.scale, ry, innerW, rowH - 2 * Kit.scale,
        id == S.builderMapId, PAL.blue, 5 * Kit.scale) then
      S.builderMapId = id
      S.builderLayer = 1
      S.builderSelections = {}
      S._builderFitFor = nil
      if S.builderWarpDraft and not S.project.layeredMaps[id] then
        ensureLayeredDestination(S, App)
      end
    end
    Kit.text("micro", Kit.ellipsize("micro", id, innerW - 42 * Kit.scale),
      x + 14 * Kit.scale, ry + 6 * Kit.scale,
      layered and PAL.heading or PAL.muted)
    if layered then
      Kit.textRight("micro", "L", x + innerW, ry + 6 * Kit.scale, PAL.green)
    end
  end
  Kit.popClip()
  S.builderMapOffset = Kit.scrollbar(x + w - 18 * Kit.scale, listY,
    10 * Kit.scale, listH, offset, #ids, perPage, scrollId)

  local fy = y + h - footerH + 6 * Kit.scale
  if S.builderNewMap then
    drawNewMapForm(S, x + 8 * Kit.scale, fy, w - 16 * Kit.scale, App)
    return
  end
  local half = (w - 24 * Kit.scale) / 2
  if Kit.button(x + 8 * Kit.scale, fy, half, 26 * Kit.scale, "+ New", {
      kind = "good", tooltip = "Create a blank layered custom map",
    }) then
    beginNewMap(S)
  end
  local canConvert = S.builderMapId and not mapSource(S)
  if Kit.button(x + 12 * Kit.scale + half, fy, half, 26 * Kit.scale,
      "Convert", { kind = "accent", enabled = canConvert,
        tooltip = "Preserve this map and open it as editable 16x16 layers" }) then
    ensureLayeredDestination(S, App)
  end
  local selected = S.builderMapId or "none"
  Kit.text("micro", Kit.ellipsize("micro", selected, w - 16 * Kit.scale),
    x + 8 * Kit.scale, fy + 34 * Kit.scale, PAL.faint)
end

local function importTileset(S, App)
  if not (S.project and S.path) then return end
  App.pickFile("Import 16x16 tileset PNG",
    "PNG (*.png)|*.png|All files (*.*)|*.*", function(picked)
      local base = App.assetBaseName(picked, "tiles.png")
      if not base:lower():match("%.png$") then base = base .. ".png" end
      local rel = "assets/mapbuilder/sources/" .. base
      App.importToMod(picked, rel, function(imported)
        local image = Preview.image(S, imported)
        if not image then
          S.status = "Imported PNG could not be decoded"
          return
        end
        local width, height = image:getDimensions()
        local stem = base:gsub("%.[Pp][Nn][Gg]$", "")
        local source, err = LayeredMap.addTileSource(
          S.project, stem, imported, width, height)
        if not source then
          S.status = "Tileset import failed: " .. tostring(err)
          return
        end
        S.builderSourceId = source.id
        S.builderTile = 0
        App.markDirty()
        S.status = string.format("Imported %s — %d tiles", source.id, source.count)
      end)
    end)
end

local function drawTilePalette(S, source, x, y, w, h, App)
  Kit.card(x, y, w, h, 10 * Kit.scale)
  Kit.text("caption", "TILESETS", x + 10 * Kit.scale, y + 8 * Kit.scale, PAL.heading)
  if Kit.button(x + w - 90 * Kit.scale, y + 5 * Kit.scale,
      80 * Kit.scale, 24 * Kit.scale, "Import PNG", {
        kind = "good", tooltip = "Add a custom PNG arranged as 16x16 tiles",
      }) then importTileset(S, App) end

  local ids = source and LayeredMap.sourceIds(S, source.id) or sortedKeys(
    S.project.mapTileSources)
  if not S.builderSourceId or not LayeredMap.sourceDescriptor(S, S.builderSourceId) then
    S.builderSourceId = ids[1]
  end
  local sy = y + 34 * Kit.scale
  local sourceIndex = 1
  for index, id in ipairs(ids) do
    if id == S.builderSourceId then sourceIndex = index; break end
  end
  if Kit.stepper(x + 8 * Kit.scale, sy, 26 * Kit.scale, 24 * Kit.scale, "<",
      { tooltip = "Previous tileset source" }) and #ids > 0 then
    sourceIndex = ((sourceIndex - 2) % #ids) + 1
    S.builderSourceId, S.builderTile, S.builderTileOffset = ids[sourceIndex], 0, 0
  end
  local sourceLabel = LayeredMap.sourceDescriptor(S, S.builderSourceId)
  sourceLabel = sourceLabel and (sourceLabel.name or sourceLabel.id) or "No source"
  Kit.textCenter("micro", Kit.ellipsize("micro", sourceLabel, w - 84 * Kit.scale),
    x + 38 * Kit.scale, sy + 5 * Kit.scale, w - 76 * Kit.scale, PAL.heading)
  if Kit.stepper(x + w - 34 * Kit.scale, sy, 26 * Kit.scale, 24 * Kit.scale, ">",
      { tooltip = "Next tileset source" }) and #ids > 0 then
    sourceIndex = (sourceIndex % #ids) + 1
    S.builderSourceId, S.builderTile, S.builderTileOffset = ids[sourceIndex], 0, 0
  end

  local descriptor = LayeredMap.sourceDescriptor(S, S.builderSourceId)
  local gridY = sy + 30 * Kit.scale
  local gridH = math.max(20 * Kit.scale, h - (gridY - y) - 8 * Kit.scale)
  if not descriptor then
    Kit.emptyBox(x + 8 * Kit.scale, gridY, w - 16 * Kit.scale, gridH,
      "Import a 16x16 PNG tileset")
    return
  end
  local tileSize = 34 * Kit.scale
  local columns = math.max(1, math.floor((w - 28 * Kit.scale) / tileSize))
  local rows = math.max(1, math.floor(gridH / tileSize))
  local perPage = columns * rows
  local count = descriptor.count or 0
  local offset = clamp(S.builderTileOffset or 0, 0, math.max(0, count - perPage))
  local scrollId = "builderTileOffset"
  offset = Kit.scroll(x + 8 * Kit.scale, gridY, w - 16 * Kit.scale, gridH,
    offset, count, perPage, columns, scrollId)
  offset = math.floor(offset / columns) * columns
  Kit.pushClip(x + 8 * Kit.scale, gridY, w - 28 * Kit.scale, gridH)
  for slot = 0, perPage - 1 do
    local tile = offset + slot
    if tile >= count then break end
    local col, row = slot % columns, math.floor(slot / columns)
    local tx, ty = x + 8 * Kit.scale + col * tileSize, gridY + row * tileSize
    local selected = (S.builderTile or 0) == tile
    if selected then
      love.graphics.setColor(0.2, 0.65, 1, 0.35)
      love.graphics.rectangle("fill", tx, ty, tileSize - 2, tileSize - 2, 4, 4)
    end
    drawChecker(tx + 3 * Kit.scale, ty + 3 * Kit.scale, 28 * Kit.scale)
    drawSourceTile(S, descriptor, tile,
      tx + 3 * Kit.scale, ty + 3 * Kit.scale, 28 * Kit.scale, 1)
    if Kit.press(tx, ty, tileSize - 2, tileSize - 2) then
      S.builderTile = tile
    end
  end
  Kit.popClip()
  S.builderTileOffset = Kit.scrollbar(x + w - 18 * Kit.scale, gridY,
    10 * Kit.scale, gridH, offset, count, perPage, scrollId)
end

-- Toolbars and property panes

local function drawToolbar(S, source, x, y, w, App)
  local tx, toolY = x, y
  local firstLimit = x + w - 190 * Kit.scale
  for _, tool in ipairs(TOOLS) do
    local bw = math.max(48 * Kit.scale,
      Kit.textWidth("micro", tool.label) + 14 * Kit.scale)
    local limit = toolY == y and firstLimit or x + w
    if tx + bw > limit and tx > x then
      toolY = toolY + 29 * Kit.scale
      tx = x
    end
    if Kit.chip(tx, toolY, bw, 26 * Kit.scale, tool.label,
        (S.builderTool or "pencil") == tool.id, PAL.blue, PAL.steel, tool.tip) then
      S.builderTool = tool.id
      S.builderRangeDraft = nil
      if tool.id ~= "warp" then S.builderWarpDraft = nil end
    end
    tx = tx + bw + 3 * Kit.scale
  end
  local zx = x + w - 184 * Kit.scale
  if Kit.stepper(zx, y, 26 * Kit.scale, 26 * Kit.scale, "-") then
    S.builderZoom = clamp((S.builderZoom or 1) - 0.25, 0.25, 8)
  end
  Kit.text("mono", string.format("%.2fx", S.builderZoom or 1),
    zx + 30 * Kit.scale, y + 6 * Kit.scale, PAL.muted)
  if Kit.stepper(zx + 82 * Kit.scale, y, 26 * Kit.scale, 26 * Kit.scale, "+") then
    S.builderZoom = clamp((S.builderZoom or 1) + 0.25, 0.25, 8)
  end
  if Kit.button(zx + 112 * Kit.scale, y, 68 * Kit.scale, 26 * Kit.scale,
      "Fit", { kind = "ghost" }) then S._builderFitFor = nil end

  local barY = toolY + 31 * Kit.scale
  if (S.builderTool or "pencil") == "collision" then
    local bx = x
    for _, mode in ipairs(LayeredMap.COLLISION_MODES) do
      local bw = Kit.textWidth("micro", mode) + 16 * Kit.scale
      if Kit.chip(bx, barY, bw, 24 * Kit.scale, mode,
          (S.builderCollision or "solid") == mode, PAL.green, PAL.steel) then
        S.builderCollision = mode
      end
      bx = bx + bw + 3 * Kit.scale
    end
  elseif (S.builderTool or "pencil") == "select" then
    local count = #(S.builderSelections or {})
    Kit.text("micro", string.format("%d selected range(s)", count),
      x, barY + 5 * Kit.scale, PAL.muted)
    if Kit.button(x + 140 * Kit.scale, barY, 90 * Kit.scale, 24 * Kit.scale,
        "Clear tiles", { kind = "danger", enabled = count > 0,
          tooltip = "Erase the active layer inside every selected range" }) then
      clearSelections(S, source, App)
    end
    if Kit.button(x + 236 * Kit.scale, barY, 74 * Kit.scale, 24 * Kit.scale,
        "Deselect", { kind = "ghost", enabled = count > 0 }) then
      S.builderSelections = {}
    end
  elseif (S.builderTool or "pencil") == "warp" then
    local draft = S.builderWarpDraft
    local instruction = not draft and "Click the source cell"
      or draft.phase == "destination" and "Select a map, then click the arrival cell"
      or "Select a map, then click the return destination"
    Kit.text("micro", instruction, x, barY + 5 * Kit.scale, PAL.yellow)
    if draft and Kit.button(x + 330 * Kit.scale, barY,
        70 * Kit.scale, 24 * Kit.scale, "Cancel", { kind = "ghost" }) then
      S.builderWarpDraft = nil
      S.status = "Warp placement cancelled"
    end
  else
    local layer = activeLayer(S, source)
    local label = layer and layer.name or "No layer"
    Kit.text("micro", "Active layer: " .. label,
      x, barY + 5 * Kit.scale, PAL.muted)
  end
  return barY + 29 * Kit.scale
end

local function drawLayersPane(S, source, x, y, w, h, App)
  local rowH = 28 * Kit.scale
  local listH = math.max(rowH, math.min(
    math.max(rowH, h - 104 * Kit.scale),
    math.max(rowH, #source.layers * rowH)))
  local perPage = math.max(1, math.floor(listH / rowH))
  local offset = clamp(S.builderLayerOffset or 0, 0,
    math.max(0, #source.layers - perPage))
  local scrollId = "builderLayerOffset"
  offset = Kit.scroll(x, y, w, listH, offset, #source.layers,
    perPage, 2, scrollId)
  local rowW = w - (#source.layers > perPage and 14 * Kit.scale or 0)
  Kit.pushClip(x, y, w, listH)
  for row = 1, perPage do
    local index = offset + row
    local layer = source.layers[index]
    if not layer then break end
    local ry = y + (row - 1) * rowH
    if Kit.row(x, ry, rowW, rowH - 2 * Kit.scale,
        S.builderLayer == index, PAL.blue, 5 * Kit.scale) then
      S.builderLayer = index
    end
    Kit.text("micro", Kit.ellipsize("micro", layer.name, rowW - 88 * Kit.scale),
      x + 7 * Kit.scale, ry + 7 * Kit.scale,
      layer.visible == false and PAL.faint or PAL.heading)
    if Kit.chip(x + rowW - 80 * Kit.scale, ry + 2 * Kit.scale,
        34 * Kit.scale, 22 * Kit.scale, "Eye", layer.visible ~= false,
        PAL.green, PAL.steel) then
      layer.visible = layer.visible == false and true or false
      App.markDirty()
    end
    if Kit.chip(x + rowW - 42 * Kit.scale, ry + 2 * Kit.scale,
        40 * Kit.scale, 22 * Kit.scale, "Out", layer.export ~= false,
        PAL.blue, PAL.steel, "Included in the saved game map by default") then
      layer.export = layer.export == false and true or false
      App.markDirty()
    end
  end
  Kit.popClip()
  if #source.layers > perPage then
    S.builderLayerOffset = Kit.scrollbar(x + w - 11 * Kit.scale, y,
      10 * Kit.scale, listH, offset, #source.layers, perPage,
      scrollId)
  else
    S.builderLayerOffset = 0
  end
  local by = y + listH + 5 * Kit.scale
  local bw = (w - 12 * Kit.scale) / 4
  if Kit.button(x, by, bw, 25 * Kit.scale, "+", { kind = "good" }) then
    local _, index = LayeredMap.addLayer(source, "Decoration")
    S.builderLayer = index
    App.markDirty()
  end
  if Kit.button(x + bw + 4 * Kit.scale, by, bw, 25 * Kit.scale, "Up",
      { kind = "accent" }) then
    S.builderLayer = LayeredMap.moveLayer(source, S.builderLayer or 1, 1)
    App.markDirty()
  end
  if Kit.button(x + (bw + 4 * Kit.scale) * 2, by, bw, 25 * Kit.scale, "Down",
      { kind = "accent" }) then
    S.builderLayer = LayeredMap.moveLayer(source, S.builderLayer or 1, -1)
    App.markDirty()
  end
  if Kit.button(x + (bw + 4 * Kit.scale) * 3, by, bw, 25 * Kit.scale, "X",
      { kind = "danger", enabled = (S.builderLayer or 1) > 1,
        tooltip = "Remove the selected layer" }) then
    local ok, err = LayeredMap.removeLayer(source, S.builderLayer or 1)
    if ok then
      S.builderLayer = clamp((S.builderLayer or 1) - 1, 1, #source.layers)
      App.markDirty()
    else S.status = err end
  end
  local layer = activeLayer(S, source)
  if layer then
    by = by + 34 * Kit.scale
    Kit.text("micro", "Name", x, by + 5 * Kit.scale, PAL.caption)
    local name = field(App, "builder_layer_name", x + 54 * Kit.scale, by,
      w - 54 * Kit.scale, 24 * Kit.scale, layer.name or layer.id, "Layer name")
    if name ~= (layer.name or layer.id) then layer.name = name end
    by = by + 32 * Kit.scale
    Kit.text("micro", "Opacity", x, by + 5 * Kit.scale, PAL.caption)
    if Kit.stepper(x + 70 * Kit.scale, by, 26 * Kit.scale, 24 * Kit.scale, "-") then
      layer.opacity = clamp((layer.opacity or 1) - 0.1, 0, 1)
      App.markDirty()
    end
    Kit.text("mono", string.format("%.0f%%", (layer.opacity or 1) * 100),
      x + 102 * Kit.scale, by + 5 * Kit.scale, PAL.heading)
    if Kit.stepper(x + 154 * Kit.scale, by, 26 * Kit.scale, 24 * Kit.scale, "+") then
      layer.opacity = clamp((layer.opacity or 1) + 0.1, 0, 1)
      App.markDirty()
    end
  end
end

local function drawTilesetPane(S, x, y, w, h, App)
  local source = LayeredMap.sourceDescriptor(S, S.builderSourceId)
  if not source then
    Kit.emptyBox(x, y, w, math.min(h, 100 * Kit.scale), "Import a tileset PNG")
    return
  end
  Kit.text("micro", source.name or source.id, x, y, PAL.heading)
  y = y + 24 * Kit.scale
  if source.runtimeTileset then
    Kit.text("micro", "Game tileset source. Import a PNG to define custom animation.",
      x, y, PAL.muted)
    return
  end
  Kit.text("micro", "Color mode", x, y + 5 * Kit.scale, PAL.caption)
  local cx = x + 82 * Kit.scale
  for _, option in ipairs({
    { id = "palette", label = "Palette" },
    { id = "true_color", label = "True color" },
  }) do
    local bw = Kit.textWidth("micro", option.label) + 16 * Kit.scale
    if Kit.chip(cx, y, bw, 24 * Kit.scale, option.label,
        (source.colorMode or "true_color") == option.id,
        PAL.blue, PAL.steel) then
      source.colorMode = option.id
      App.markDirty()
    end
    cx = cx + bw + 4 * Kit.scale
  end
  y = y + 38 * Kit.scale
  local tile = S.builderTile or 0
  local frames = source.animations and source.animations[tile]
  local count = frames and #frames or 1
  local duration = frames and frames[1] and frames[1].duration or 200
  Kit.text("micro", "Selected tile " .. tostring(tile) .. " animation", x, y, PAL.caption)
  y = y + 18 * Kit.scale
  local ax = x
  for _, frameCount in ipairs({ 1, 2, 3, 4, 6, 8 }) do
    local label = frameCount == 1 and "Static" or tostring(frameCount)
    local bw = frameCount == 1 and 58 * Kit.scale or 32 * Kit.scale
    if Kit.chip(ax, y, bw, 24 * Kit.scale, label, count == frameCount,
        PAL.green, PAL.steel,
        "Frames use consecutive tiles starting at the selected tile") then
      local ok, err = LayeredMap.setSourceAnimation(
        source, tile, frameCount, duration)
      if ok then App.markDirty() else S.status = err end
    end
    ax = ax + bw + 3 * Kit.scale
  end
  y = y + 34 * Kit.scale
  Kit.text("micro", "Frame time (ms)", x, y + 5 * Kit.scale, PAL.caption)
  local value = field(App, "builder_anim_ms", x + 110 * Kit.scale, y,
    70 * Kit.scale, 24 * Kit.scale, tostring(duration), "200")
  if Kit.focus ~= "builder_anim_ms" and frames then
    local nextDuration = math.max(16, math.floor(tonumber(value) or duration))
    if nextDuration ~= duration then
      LayeredMap.setSourceAnimation(source, tile, count, nextDuration)
      App.markDirty()
    end
  end
end

local function nodeTargetText(project, node)
  local target = node.targetNode and project.mapWarpNodes[node.targetNode]
  if target then
    return string.format("%s (%d,%d)", target.map, target.x, target.y)
  end
  if node.targetMap and node.targetIndex then
    return string.format("%s warp %d", node.targetMap, node.targetIndex)
  end
  return "arrival only"
end

local function drawWarpsPane(S, source, x, y, w, h, App)
  local bottom = y + h
  Kit.text("micro", "New warp", x, y, PAL.caption)
  y = y + 18 * Kit.scale
  local wx = x
  for _, mode in ipairs({
    { id = "two_way", label = "Two-way" },
    { id = "one_way", label = "One-way" },
    { id = "custom_return", label = "Custom return" },
  }) do
    local bw = Kit.textWidth("micro", mode.label) + 16 * Kit.scale
    if Kit.chip(wx, y, bw, 24 * Kit.scale, mode.label,
        (S.builderWarpMode or "two_way") == mode.id, PAL.blue, PAL.steel) then
      S.builderWarpMode = mode.id
      S.builderWarpDraft = nil
      S.builderTool = "warp"
    end
    wx = wx + bw + 3 * Kit.scale
  end
  y = y + 34 * Kit.scale
  local nodes = LayeredMap.nodesForMap(S.project, S.builderMapId)
  Kit.text("micro", string.format("Endpoints on this map (%d)", #nodes), x, y, PAL.caption)
  y = y + 18 * Kit.scale
  local rowH = 30 * Kit.scale
  local listH = math.max(rowH, bottom - y - 38 * Kit.scale)
  local perPage = math.max(1, math.floor(listH / rowH))
  local offset = clamp(S.builderWarpOffset or 0, 0,
    math.max(0, #nodes - perPage))
  local scrollId = "builderWarpOffset"
  offset = Kit.scroll(x, y, w, listH, offset, #nodes, perPage, 2, scrollId)
  local rowW = w - (#nodes > perPage and 14 * Kit.scale or 0)
  Kit.pushClip(x, y, w, listH)
  for row = 1, perPage do
    local index = offset + row
    local node = nodes[index]
    if not node then break end
    local label = string.format("%s (%d,%d) -> %s",
      node.active and "Warp" or "Arrival", node.x, node.y,
      nodeTargetText(S.project, node))
    local ry = y + (row - 1) * rowH
    if Kit.row(x, ry, rowW, 27 * Kit.scale,
        S.builderWarpNodeId == node.id, PAL.blue, 5 * Kit.scale) then
      S.builderWarpNodeId = node.id
    end
    Kit.text("micro", Kit.ellipsize("micro", label, rowW - 12 * Kit.scale),
      x + 6 * Kit.scale, ry + 7 * Kit.scale,
      node.active and PAL.heading or PAL.muted)
  end
  Kit.popClip()
  if #nodes > perPage then
    S.builderWarpOffset = Kit.scrollbar(x + w - 11 * Kit.scale, y,
      10 * Kit.scale, listH, offset, #nodes, perPage, scrollId)
  else
    S.builderWarpOffset = 0
  end
  y = y + listH
  local selected = S.builderWarpNodeId
    and S.project.mapWarpNodes[S.builderWarpNodeId]
  if Kit.button(x, y + 4 * Kit.scale, w, 26 * Kit.scale,
      "Delete selected endpoint", { kind = "danger", enabled = selected ~= nil,
        tooltip = "Targets pointing here become inactive arrival records" }) then
    LayeredMap.removeWarpNode(S.project, selected.id)
    S.builderWarpNodeId = nil
    App.markDirty()
    S.status = "Deleted warp endpoint"
  end
end

local function drawProperties(S, source, x, y, w, h, App)
  Kit.card(x, y, w, h, 10 * Kit.scale)
  local px, py = x + 10 * Kit.scale, y + 9 * Kit.scale
  local innerW = w - 20 * Kit.scale
  local map = mapRecord(S)
  Kit.text("caption", source.id, px, py, PAL.heading)
  py = py + 24 * Kit.scale
  if map then
    local label = field(App, "builder_map_label", px, py, innerW,
      26 * Kit.scale, map.label or source.id, "Map label")
    if label ~= (map.label or source.id) then map.label = label end
  end
  py = py + 34 * Kit.scale
  Kit.text("micro", "Size in 16x16 cells (even numbers)", px, py, PAL.caption)
  py = py + 17 * Kit.scale
  local draft = S._builderSizeDraft
  if not draft or draft.map ~= source.id then
    draft = { map = source.id, w = tostring(source.cellWidth),
      h = tostring(source.cellHeight) }
    S._builderSizeDraft = draft
  end
  local widthText = Kit.textfield("builder_map_w", px, py,
    62 * Kit.scale, 25 * Kit.scale, draft.w, "20")
  local heightText = Kit.textfield("builder_map_h", px + 70 * Kit.scale, py,
    62 * Kit.scale, 25 * Kit.scale, draft.h, "18")
  if Kit.focus == "builder_map_w" or Kit.focus == "builder_map_h" then
    draft.w, draft.h = widthText, heightText
  else
    local newWidth = math.floor(tonumber(widthText) or source.cellWidth)
    local newHeight = math.floor(tonumber(heightText) or source.cellHeight)
    draft.w, draft.h = tostring(newWidth), tostring(newHeight)
    if newWidth ~= source.cellWidth or newHeight ~= source.cellHeight then
      local ok, result = LayeredMap.resizeMap(
        S.project, source.id, newWidth, newHeight)
      if ok then
        S._builderFitFor = nil
        S.builderSelections = {}
        App.markDirty()
        S.status = result > 0
          and string.format("Resized map; removed %d out-of-bounds endpoint/event(s)", result)
          or "Resized map safely"
      else
        S.status = "Resize rejected: " .. tostring(result)
        draft.w, draft.h = tostring(source.cellWidth), tostring(source.cellHeight)
      end
    end
  end
  if Kit.button(px + innerW - 92 * Kit.scale, py,
      92 * Kit.scale, 25 * Kit.scale, "Events", {
        kind = "ghost", tooltip = "Open NPCs, signs, encounters, and advanced map settings",
      }) then
    S.mapId = source.id
    S.tab = "maps"
  end
  py = py + 36 * Kit.scale
  local tabs = {
    { id = "layers", label = "Layers" },
    { id = "tileset", label = "Tileset" },
    { id = "warps", label = "Warps" },
  }
  S.builderPane = S.builderPane or "layers"
  local tx = px
  for _, tab in ipairs(tabs) do
    local bw = (innerW - 8 * Kit.scale) / 3
    if Kit.chip(tx, py, bw, 26 * Kit.scale, tab.label,
        S.builderPane == tab.id, PAL.blue, PAL.steel) then
      S.builderPane = tab.id
      if tab.id == "warps" then S.builderTool = "warp" end
    end
    tx = tx + bw + 4 * Kit.scale
  end
  py = py + 35 * Kit.scale
  local remaining = y + h - py - 8 * Kit.scale
  if S.builderPane == "tileset" then
    drawTilesetPane(S, px, py, innerW, remaining, App)
  elseif S.builderPane == "warps" then
    drawWarpsPane(S, source, px, py, innerW, remaining, App)
  else
    drawLayersPane(S, source, px, py, innerW, remaining, App)
  end
end

-- Public panel API

function MapBuilder.keypressed(S, key, App)
  if not S or not S.project then return false end
  if key == "escape" and S.builderNewMap then
    S.builderNewMap = nil
    Kit.blur()
    S.status = "New map cancelled"
    return true
  end
  local source = mapSource(S)
  if not source then return false end
  if key == "delete" or key == "backspace" then
    if #(S.builderSelections or {}) > 0 and Kit.focus == nil then
      clearSelections(S, source, App)
      return true
    end
  elseif key == "escape" and S.builderWarpDraft then
    S.builderWarpDraft = nil
    S.status = "Warp placement cancelled"
    return true
  end
  return false
end

function MapBuilder.draw(S, x, y, w, h, App)
  if not (S and S.project) then
    Kit.emptyBox(x, y, w, h, "Open or create a mod first")
    return
  end
  LayeredMap.ensureProject(S.project)
  S.builderTool = S.builderTool or "pencil"
  S.builderTile = S.builderTile or 0
  S.builderCollision = S.builderCollision or "solid"
  S.builderWarpMode = S.builderWarpMode or "two_way"

  local s = Kit.scale
  local leftW = math.min(270 * s, math.max(220 * s, w * 0.22))
  local rightW = math.min(330 * s, math.max(270 * s, w * 0.25))
  local gap = 9 * s
  local centerX = x + leftW + gap
  local centerW = math.max(220 * s, w - leftW - rightW - gap * 2)
  local rightX = centerX + centerW + gap

  local mapListMin = S.builderNewMap and 244 * s or 210 * s
  local mapListH = math.min(290 * s, math.max(mapListMin, h * 0.43))
  drawMapList(S, x, y, leftW, mapListH, App)
  drawTilePalette(S, mapSource(S), x, y + mapListH + gap,
    leftW, h - mapListH - gap, App)

  local source = mapSource(S)
  if not source then
    Kit.card(centerX, y, centerW, h, 10 * s)
    Kit.emptyBox(centerX + 12 * s, y + 12 * s,
      centerW - 24 * s, h - 24 * s,
      "Select a map, then Convert — or create a new layered map")
    Kit.card(rightX, y, rightW, h, 10 * s)
    Kit.text("small", "LAYERED MAPS", rightX + 14 * s, y + 16 * s, PAL.heading)
    Kit.text("micro", "Original maps remain unchanged until converted.",
      rightX + 14 * s, y + 48 * s, PAL.muted)
    return
  end

  local canvasY = drawToolbar(S, source, centerX, y, centerW, App)
  Kit.card(centerX, canvasY, centerW, y + h - canvasY, 10 * s)
  drawCanvas(S, source, centerX, canvasY, centerW, y + h - canvasY, App)
  drawProperties(S, source, rightX, y, rightW, h, App)
end

return MapBuilder
