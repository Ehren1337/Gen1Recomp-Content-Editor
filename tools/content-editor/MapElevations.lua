-- Elevation painting and overlay shared by the active map and its neighbors.
local M = {}

function M.value(source, x, y)
  local i = y * source.cellWidth + x + 1
  local value = (source.gen3Elevation or {})[i]
  if value ~= nil then return value end
  return (source.collision or {})[i] == "water" and 0 or 3
end

function M.paint(source, x, y, value)
  if x < 0 or y < 0 or x >= source.cellWidth or y >= source.cellHeight
      or type(value) ~= "number" or value < 0 or value > 15 or value % 1 ~= 0 then return false end
  if M.value(source, x, y) == value then return false end
  source.gen3Elevation = source.gen3Elevation or {}
  source.gen3Elevation[y * source.cellWidth + x + 1] = value
  return true
end

function M.rectangle(source, rect, value)
  local changed = false
  for y = math.max(0, math.min(rect.y0, rect.y1)), math.min(source.cellHeight - 1, math.max(rect.y0, rect.y1)) do
    for x = math.max(0, math.min(rect.x0, rect.x1)), math.min(source.cellWidth - 1, math.max(rect.x0, rect.x1)) do
      changed = M.paint(source, x, y, value) or changed
    end
  end
  return changed
end

function M.fill(source, x, y, value)
  if x < 0 or y < 0 or x >= source.cellWidth or y >= source.cellHeight then return false end
  local target = M.value(source, x, y)
  if not M.paint(source, x, y, value) then return false end
  local queue, head = {{x, y}}, 1
  local function visit(nx, ny)
    if nx >= 0 and ny >= 0 and nx < source.cellWidth and ny < source.cellHeight
        and M.value(source, nx, ny) == target then
      M.paint(source, nx, ny, value)
      queue[#queue + 1] = {nx, ny}
    end
  end
  while head <= #queue do
    local cell = queue[head]
    head = head + 1
    visit(cell[1] - 1, cell[2]); visit(cell[1] + 1, cell[2])
    visit(cell[1], cell[2] - 1); visit(cell[1], cell[2] + 1)
  end
  return true
end

function M.reader(S, id)
  local source = (S.project.layeredMaps or {})[id]
  if source then
    return source.cellWidth, source.cellHeight, function(x, y)
      return M.value(source, x, y)
    end
  end
  local G = require("Gen3Map")
  local layout = G.layout(S.data, id, S.project)
  if not layout then return end
  return layout.width, layout.height, function(x, y)
    return G.cell(S.project, id, layout, x, y).elev
  end
end

function M.draw(S, id, camX, camY, viewW, viewH)
  if not S.mapShowElevations then return end
  local width, height, read = M.reader(S, id)
  if not read then return end
  local g = love.graphics
  local font = g.getFont()
  local scale = math.min(1, 10 / font:getHeight())
  for y = math.max(0, math.floor(camY / 16)), math.min(height - 1, math.floor((camY + viewH) / 16)) do
    for x = math.max(0, math.floor(camX / 16)), math.min(width - 1, math.floor((camX + viewW) / 16)) do
      local elevation = read(x, y)
      local value = tonumber(elevation)
      local label = value and tostring(value) or "?"
      -- Stable colors make equal elevations easy to follow across a seam.
      local hue = (value or 0) * 2.399963
      g.setColor(0.5 + 0.4 * math.cos(hue),
        0.5 + 0.4 * math.cos(hue + 2.094), 0.5 + 0.4 * math.cos(hue + 4.189), 0.5)
      g.rectangle("fill", x * 16, y * 16, 16, 16)
      local tx = x * 16 + (16 - font:getWidth(label) * scale) / 2
      local ty = y * 16 + (16 - font:getHeight() * scale) / 2
      g.setColor(0, 0, 0, 0.85)
      g.rectangle("fill", tx - 1, ty, font:getWidth(label) * scale + 2, font:getHeight() * scale)
      g.setColor(1, 1, 1, 1)
      g.print(label, tx, ty, 0, scale, scale)
    end
  end
  g.setColor(1, 1, 1, 1)
end

return M
