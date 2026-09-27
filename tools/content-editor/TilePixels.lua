-- Tile sheets kept as pixel data inside the project (and the saved mod), so a
-- map made from a PNG keeps working after that PNG is deleted.
--
-- A baked source has image = "@pixels/<source id>" and a `pixels` record:
--   tileWidth, tileHeight, columns, count  sheet layout (tile n = column n%columns)
--   digits    hex digits per pixel (2 up to 256 colours, 4 above)
--   palette   one string, 8 hex digits (rrggbbaa) per colour
--   tiles     one hex string per distinct tile
--   index     for tile n (1-based: n+1), which entry of `tiles` it is
-- Plain Lua and love.image only: the same file is inlined into Gen 3 mods,
-- which cannot read files.
local M = {}

M.PREFIX = "@pixels/"

function M.path(id) return M.PREFIX .. tostring(id) end

function M.idFor(path)
  return type(path) == "string" and path:match("^@pixels/(.+)$") or nil
end

local function byte(v)
  v = math.floor((tonumber(v) or 0) * 255 + 0.5)
  if v < 0 then return 0 elseif v > 255 then return 255 end
  return v
end

-- ImageData -> pixels record. Tiles past the image edge read as transparent.
function M.encode(imageData, columns, count, tileWidth, tileHeight)
  local tw, th = tileWidth or 16, tileHeight or 16
  local w, h = imageData:getDimensions()
  columns = math.max(1, tonumber(columns) or math.floor(w / tw))
  count = tonumber(count) or columns * math.floor(h / th)
  local palette, colourOf = {}, {}
  local codes, seen, uniques, index = {}, {}, {}, {}
  for t = 0, count - 1 do
    local sx, sy = (t % columns) * tw, math.floor(t / columns) * th
    local tile = {}
    for y = 0, th - 1 do
      for x = 0, tw - 1 do
        local key = "00000000"
        local px, py = sx + x, sy + y
        if px < w and py < h then
          local r, g, b, a = imageData:getPixel(px, py)
          a = byte(a)
          if a > 0 then
            key = string.format("%02x%02x%02x%02x", byte(r), byte(g), byte(b), a)
          end
        end
        local code = colourOf[key]
        if not code then
          palette[#palette + 1] = key
          code = #palette - 1
          colourOf[key] = code
        end
        tile[#tile + 1] = code
      end
    end
    local sig = table.concat(tile, ",")
    local u = seen[sig]
    if not u then
      uniques[#uniques + 1] = tile
      u = #uniques
      seen[sig] = u
    end
    index[t + 1] = u
  end
  local digits = #palette <= 256 and 2 or 4
  local fmt = "%0" .. digits .. "x"
  local tiles = {}
  for u, tile in ipairs(uniques) do
    local parts = {}
    for i, code in ipairs(tile) do parts[i] = string.format(fmt, code) end
    tiles[u] = table.concat(parts)
  end
  return {
    tileWidth = tw, tileHeight = th, columns = columns, count = count,
    digits = digits, palette = table.concat(palette), tiles = tiles,
    index = index,
  }
end

-- pixels record -> width, height, RGBA8 byte string of the whole sheet.
function M.decode(p)
  local tw, th = p.tileWidth or 16, p.tileHeight or 16
  local columns, count, d = p.columns or 1, p.count or 0, p.digits or 2
  local rows = math.max(1, math.ceil(count / columns))
  local colours = {}
  for i = 0, math.floor(#p.palette / 8) - 1 do
    local o = i * 8
    colours[i] = string.char(tonumber(p.palette:sub(o + 1, o + 2), 16),
      tonumber(p.palette:sub(o + 3, o + 4), 16),
      tonumber(p.palette:sub(o + 5, o + 6), 16),
      tonumber(p.palette:sub(o + 7, o + 8), 16))
  end
  local clear = string.char(0, 0, 0, 0)
  local blankRow = clear:rep(tw)
  local tileRows = {}
  for u, hex in ipairs(p.tiles or {}) do
    local rowsOut = {}
    for y = 0, th - 1 do
      local parts = {}
      for x = 0, tw - 1 do
        local o = (y * tw + x) * d
        parts[x + 1] = colours[tonumber(hex:sub(o + 1, o + d), 16)] or clear
      end
      rowsOut[y + 1] = table.concat(parts)
    end
    tileRows[u] = rowsOut
  end
  local out = {}
  for ty = 0, rows - 1 do
    for y = 1, th do
      for tx = 0, columns - 1 do
        local u = (p.index or {})[ty * columns + tx + 1]
        out[#out + 1] = u and tileRows[u] and tileRows[u][y] or blankRow
      end
    end
  end
  return columns * tw, rows * th, table.concat(out)
end

function M.imageData(p)
  local w, h, bytes = M.decode(p)
  return love.image.newImageData(w, h, "rgba8", bytes)
end

-- Distinct tiles, first-seen order (for the Map Builder tile picker).
function M.uniqueTiles(p)
  local seen, out = {}, {}
  for t = 0, (p.count or 0) - 1 do
    local u = (p.index or {})[t + 1]
    if u and not seen[u] then
      seen[u] = true
      out[#out + 1] = t
    end
  end
  return out
end

return M
