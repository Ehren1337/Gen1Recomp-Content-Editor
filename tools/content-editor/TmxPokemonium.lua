-- Convert Pokemonium / generic Tiled TMX into engine block maps + a tileset.
-- Each unique 32x32 composite becomes one block of 16 8x8 tiles.

local ModIO = require("ModIO")
local Generation = require("Generation")
local State = require("State")

local TmxPokemonium = {}

local SEP = package.config:sub(1, 1)
local FLIP_UNIT = 0x20000000
local SPECIAL = {
  collisions = true, collision = true, water = true,
  ledgesleft = true, ledgesright = true, ledgesdown = true, ledgesup = true,
  ledges = true, fringe = true, overhead = true,
}

local function join(...)
  local parts = { ... }
  for i = 1, #parts do
    parts[i] = tostring(parts[i] or ""):gsub("[/\\]+$", "")
  end
  return table.concat(parts, SEP)
end

local function dirname(path)
  return tostring(path or ""):match("^(.*)[/\\][^/\\]+$") or "."
end

local function basename(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function resolvePath(base, rel)
  rel = tostring(rel or ""):gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
  if rel == "" then return base end
  if rel:match("^[A-Za-z]:/") or rel:sub(1, 1) == "/" then
    return rel:gsub("/", SEP)
  end
  local combined = (tostring(base or ".") .. "/" .. rel):gsub("\\", "/")
  local prefix = combined:match("^([A-Za-z]:)") or ""
  local rest = combined:sub(#prefix + 1)
  local parts = {}
  for part in rest:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local out = prefix
  if prefix ~= "" then
    out = prefix .. SEP .. table.concat(parts, SEP)
  elseif combined:sub(1, 1) == "/" then
    out = SEP .. table.concat(parts, SEP)
  else
    out = table.concat(parts, SEP)
  end
  return out
end

local function attr(tag, name)
  return tag and tag:match(name .. '%s*=%s*"([^"]*)"')
end

local function safeId(name, fallback)
  local id = tostring(name or ""):upper():gsub("[^A-Z0-9_]", "_")
  id = id:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if id == "" then id = fallback or "PM_TILES" end
  if id:match("^%d") then id = "TS_" .. id end
  return id
end

local function safeFile(name)
  local s = tostring(name or ""):gsub("[^A-Za-z0-9._-]+", "_")
    :gsub("^[._]+", ""):gsub("[._]+$", "")
  return s ~= "" and s or "tiles"
end

local function layerKey(name)
  return tostring(name or ""):lower():gsub("%s+", "")
end

local function mapIdFromPath(path)
  local base = basename(path):gsub("%.[Tt][Mm][Xx]$", "")
  local x, y = base:match("^(-?%d+)%.(%-?%d+)$")
  if x then
    return ("PM_" .. x .. "_" .. y):gsub("%-", "M")
  end
  return "PM_" .. base:gsub("[^%w_]", "_"):upper()
end

local function worldCoords(path)
  local base = basename(path):gsub("%.[Tt][Mm][Xx]$", "")
  local x, y = base:match("^(-?%d+)%.(%-?%d+)$")
  if x then return tonumber(x), tonumber(y) end
end

local function imageKey(img)
  local w, h = img:getWidth(), img:getHeight()
  local parts = { tostring(w), tostring(h) }
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = img:getPixel(x, y)
      parts[#parts + 1] = string.char(
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5),
        math.floor(a * 255 + 0.5))
    end
  end
  return table.concat(parts)
end

function TmxPokemonium.collectTmx(path)
  if type(path) ~= "string" or path == "" then return {} end
  if path:lower():match("%.tmx$") then return { path } end
  local files = {}
  local cmd
  if SEP == "\\" then
    cmd = 'dir /b /a-d "' .. path .. '\\*.tmx" 2>nul'
  else
    cmd = 'ls -1 "' .. path .. '"/*.tmx 2>/dev/null'
  end
  local pipe = io.popen(cmd, "r")
  if pipe then
    for line in pipe:lines() do
      line = tostring(line or ""):gsub("%s+$", "")
      if line ~= "" then
        if line:find("[/\\]") then
          files[#files + 1] = line
        else
          files[#files + 1] = join(path, line)
        end
      end
    end
    pipe:close()
  end
  table.sort(files)
  return files
end

local function decodeGid(gid)
  gid = tonumber(gid) or 0
  if gid < 0 then gid = 0 end
  local flags = math.floor(gid / FLIP_UNIT)
  local raw = gid % FLIP_UNIT
  return raw,
    math.floor(flags / 4) % 2 == 1,
    math.floor(flags / 2) % 2 == 1,
    flags % 2 == 1
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

local function decodeBase64(text)
  text = tostring(text or ""):gsub("%s+", "")
  if text == "" then return "" end
  if love and love.data and love.data.decode then
    local ok, raw = pcall(love.data.decode, "string", "base64", text)
    if ok and type(raw) == "string" then return raw end
  end
  return ""
end

local function decompress(raw, compression)
  if not compression or compression == "" then return raw end
  if not (love and love.data and love.data.decompress) then return raw end
  local ok, out = pcall(love.data.decompress, "string", compression, raw)
  return (ok and type(out) == "string") and out or raw
end

local function unpackU32(raw, width, height)
  local vals = {}
  for i = 1, #raw, 4 do
    local b1, b2, b3, b4 = raw:byte(i, i + 3)
    if not b4 then break end
    vals[#vals + 1] = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  end
  local need = width * height
  while #vals < need do vals[#vals + 1] = 0 end
  return vals
end

local function decodeLayer(dataOpen, text, width, height)
  local encoding = (attr(dataOpen, "encoding") or "csv"):lower()
  local compression = (attr(dataOpen, "compression") or ""):lower()
  if encoding == "csv" and compression == "" then
    return parseCsv(text, width, height)
  end
  if encoding == "base64" then
    local raw = decompress(decodeBase64(text), compression)
    return unpackU32(raw, width, height)
  end
  return parseCsv(text, width, height)
end

local function loadImage(path)
  local bytes = ModIO.readText(path)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  if not (love and love.image and love.image.newImageData) then return nil end
  local name = basename(path)
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, name)
  if not (okFd and fd) then return nil end
  local ok, data = pcall(love.image.newImageData, fd)
  return ok and data or nil
end

local function applyColorKey(img, hex)
  hex = tostring(hex or ""):gsub("^#", "")
  if #hex ~= 6 or not img then return img end
  local kr = tonumber(hex:sub(1, 2), 16)
  local kg = tonumber(hex:sub(3, 4), 16)
  local kb = tonumber(hex:sub(5, 6), 16)
  if not (kr and kg and kb) then return img end
  local w, h = img:getWidth(), img:getHeight()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b = img:getPixel(x, y)
      if math.floor(r * 255 + 0.5) == kr
          and math.floor(g * 255 + 0.5) == kg
          and math.floor(b * 255 + 0.5) == kb then
        img:setPixel(x, y, r, g, b, 0)
      end
    end
  end
  return img
end

local function cloneMapped(src, dw, dh, mapX, mapY)
  local dst = love.image.newImageData(dw, dh)
  local w, h = src:getWidth(), src:getHeight()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      dst:setPixel(mapX(x, y), mapY(x, y), src:getPixel(x, y))
    end
  end
  return dst
end

local function applyFlips(src, flipH, flipV, flipD)
  if not (flipH or flipV or flipD) then return src end
  local img = src
  if flipD then
    local w, h = img:getWidth(), img:getHeight()
    img = cloneMapped(img, h, w,
      function(x, y) return y end,
      function(x, y) return x end)
  end
  if flipH then
    local w = img:getWidth()
    img = cloneMapped(img, w, img:getHeight(),
      function(x) return w - 1 - x end,
      function(_, y) return y end)
  end
  if flipV then
    local h = img:getHeight()
    img = cloneMapped(img, img:getWidth(), h,
      function(x) return x end,
      function(_, y) return h - 1 - y end)
  end
  return img
end

local function resizeNearest(src, dw, dh)
  local sw, sh = src:getWidth(), src:getHeight()
  if sw == dw and sh == dh then return src end
  local dst = love.image.newImageData(dw, dh)
  for y = 0, dh - 1 do
    local sy = math.floor(y * sh / dh)
    for x = 0, dw - 1 do
      dst:setPixel(x, y, src:getPixel(math.floor(x * sw / dw), sy))
    end
  end
  return dst
end

local function pasteHard(dst, src, dx, dy)
  local sw, sh = src:getWidth(), src:getHeight()
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      local r, g, b, a = src:getPixel(x, y)
      if a > 0 then
        dst:setPixel(dx + x, dy + y, r, g, b, a)
      end
    end
  end
end

local function crop(src, sx, sy, w, h)
  local dst = love.image.newImageData(w, h)
  dst:paste(src, 0, 0, sx, sy, w, h)
  return dst
end

local function tilesetFromXml(openTag, inner, baseDir, firstgid, nameHint)
  local name = attr(openTag, "name") or nameHint or "tiles"
  local tilewidth = tonumber(attr(openTag, "tilewidth")) or 32
  local tileheight = tonumber(attr(openTag, "tileheight")) or 32
  local columns = tonumber(attr(openTag, "columns")) or 0
  local tilecount = tonumber(attr(openTag, "tilecount")) or 0
  local imgTag = inner and (inner:match("<image%s.-/>") or inner:match("<image%s.->"))
  if not imgTag then return nil, "tileset " .. name .. " has no image" end
  local imagePath = resolvePath(baseDir, attr(imgTag, "source") or "")
  return {
    firstgid = firstgid,
    name = name,
    tilewidth = tilewidth,
    tileheight = tileheight,
    columns = columns,
    tilecount = tilecount,
    imagePath = imagePath,
    trans = attr(imgTag, "trans"),
    imageWidth = tonumber(attr(imgTag, "width")) or 0,
    imageHeight = tonumber(attr(imgTag, "height")) or 0,
  }
end

local function loadTsx(path, firstgid)
  local body = ModIO.readText(path)
  if not body then return nil, "missing tsx " .. path end
  local open = body:match("<tileset%s.->")
  if not open then return nil, "invalid tsx " .. path end
  local inner = body:match("<tileset%s.->(.-)</tileset>") or ""
  local name = attr(open, "name") or basename(path):gsub("%.[Tt][Ss][Xx]$", "")
  return tilesetFromXml(open, inner, dirname(path), firstgid, name)
end

local function parseTilesets(body, tmxDir, report)
  local tilesets = {}
  local pos = 1
  while true do
    local start = body:find("<tileset%s", pos)
    if not start then break end
    local gt = body:find(">", start)
    if not gt then break end
    local open = body:sub(start, gt)
    local firstgid = tonumber(attr(open, "firstgid")) or 1
    local source = attr(open, "source")
    if source then
      local tsxPath = resolvePath(tmxDir, source)
      local ts, err = loadTsx(tsxPath, firstgid)
      if ts then
        ts.tsxPath = tsxPath
        tilesets[#tilesets + 1] = ts
      else
        report[#report + 1] = err or ("bad tileset " .. source)
      end
      pos = gt + 1
    else
      local close = body:find("</tileset>", gt)
      local inner = close and body:sub(gt + 1, close - 1) or ""
      local ts, err = tilesetFromXml(open, inner, tmxDir, firstgid)
      if ts then
        tilesets[#tilesets + 1] = ts
      else
        report[#report + 1] = err or "bad embedded tileset"
      end
      pos = (close or gt) + 1
    end
  end
  table.sort(tilesets, function(a, b) return a.firstgid > b.firstgid end)
  return tilesets
end

local function parseLayers(body, width, height)
  local layers = {}
  local pos = 1
  while true do
    local start = body:find("<layer%s", pos)
    if not start then break end
    local close = body:find("</layer>", start)
    if not close then break end
    local chunk = body:sub(start, close + 7)
    local open = chunk:match("<layer%s.->") or ""
    local dataOpen = chunk:match("<data%s.->") or "<data>"
    local text = chunk:match("<data[^>]*>(.-)</data>") or ""
    layers[#layers + 1] = {
      name = attr(open, "name") or "",
      gids = decodeLayer(dataOpen, text, width, height),
    }
    pos = close + 1
  end
  return layers
end

local function objectRecord(obj)
  local rec = {
    name = attr(obj, "name") or "",
    type = attr(obj, "type") or attr(obj, "class") or "",
    x = tonumber(attr(obj, "x")) or 0,
    y = tonumber(attr(obj, "y")) or 0,
    properties = {},
  }
  for pname, pval in obj:gmatch('<property%s+name="([^"]+)"[^>]*value="([^"]*)"') do
    rec.properties[pname] = pval
  end
  return rec
end

local function parseObjects(body)
  local out = {}
  for obj in body:gmatch("<object%s.-</object>") do
    out[#out + 1] = objectRecord(obj)
  end
  for obj in body:gmatch("<object%s.-/>") do
    out[#out + 1] = objectRecord(obj)
  end
  return out
end

local function gidToLocal(gid, tilesets)
  local raw = gid % FLIP_UNIT
  if raw == 0 then return nil end
  for i = 1, #tilesets do
    local ts = tilesets[i]
    if ts.firstgid <= raw then
      return ts, raw - ts.firstgid
    end
  end
  return nil
end

local function ensureTilesetImage(ts, report)
  if ts.image then return ts.image end
  local img = loadImage(ts.imagePath)
  if not img then
    report[#report + 1] = "missing tileset image: " .. tostring(ts.imagePath)
    return nil
  end
  if ts.trans then applyColorKey(img, ts.trans) end
  local derived = (ts.tilewidth > 0)
    and math.max(1, math.floor(img:getWidth() / ts.tilewidth)) or 1
  if ts.columns <= 1 and derived > 1 then
    ts.columns = derived
  elseif ts.columns <= 0 then
    ts.columns = derived
  end
  ts.image = img
  ts.imageWidth = img:getWidth()
  ts.imageHeight = img:getHeight()
  return img
end

local function extractTile(ts, localId, report)
  local img = ensureTilesetImage(ts, report)
  if not img then return nil end
  local cols = math.max(1, ts.columns)
  local tw, th = ts.tilewidth, ts.tileheight
  local sx = (localId % cols) * tw
  local sy = math.floor(localId / cols) * th
  if sx < 0 or sy < 0 or sx + tw > img:getWidth() or sy + th > img:getHeight() then
    report[#report + 1] = string.format(
      "tile %s#%d out of range", ts.name, localId)
    return nil
  end
  return crop(img, sx, sy, tw, th)
end

local function renderGid(rawGid, tilesets, report)
  local raw, flipH, flipV, flipD = decodeGid(rawGid)
  if raw == 0 then return nil end
  local ts, localId = gidToLocal(rawGid, tilesets)
  if not ts then return nil end
  local tile = extractTile(ts, localId, report)
  if not tile then return nil end
  tile = applyFlips(tile, flipH, flipV, flipD)
  if tile:getWidth() ~= 32 or tile:getHeight() ~= 32 then
    tile = resizeNearest(tile, 32, 32)
  end
  return tile, ts
end

local function compositeStack(stack, tilesets, report)
  local canvas
  for i = 1, #stack do
    local tile, ts = renderGid(stack[i], tilesets, report)
    if tile then
      if ts then report._used = report._used or {} ; report._used[ts.name] = true end
      if not canvas then
        canvas = love.image.newImageData(32, 32)
      end
      pasteHard(canvas, tile, 0, 0)
    end
  end
  return canvas
end

local function writePng(imageData, path)
  if not (imageData and imageData.encode) then return false, "no encode" end
  local ok, fileData = pcall(imageData.encode, imageData, "png")
  if not (ok and fileData) then return false, fileData end
  local bytes = fileData.getString and fileData:getString() or tostring(fileData)
  return ModIO.writeText(path, bytes)
end

local function uniqueTilesetId(S, wanted)
  local id = safeId(wanted, "PM_TILES")
  local n = 2
  while (S.project.tilesets and S.project.tilesets[id])
      or Generation.dataTilesets(S)[id] do
    id = safeId(wanted, "PM_TILES") .. "_" .. n
    n = n + 1
  end
  return id
end

local function copySourceTilesets(S, tilesets, report)
  local destDir = join(S.path, "assets", "tilesets", "source")
  ModIO.ensureDirectory(destDir)
  local copied, seen = {}, {}
  for i = 1, #tilesets do
    local ts = tilesets[i]
    local key = ts.imagePath
    if key and not seen[key] then
      seen[key] = true
      local imgName = safeFile(basename(ts.imagePath))
      local destImg = join(destDir, imgName)
      if ModIO.copyFile(ts.imagePath, destImg) then
        copied[#copied + 1] = {
          name = ts.name,
          image = "assets/tilesets/source/" .. imgName,
        }
        report[#report + 1] = "copied source tileset " .. ts.name
      end
    end
  end
  return copied
end

local function convertOne(path, conv, report)
  local body, err = ModIO.readText(path)
  if not body then return nil, err end
  local mapTag = body:match("<map%s.->")
  if not mapTag then return nil, "not a TMX map" end
  local width = tonumber(attr(mapTag, "width"))
  local height = tonumber(attr(mapTag, "height"))
  local tilewidth = tonumber(attr(mapTag, "tilewidth")) or 32
  local tileheight = tonumber(attr(mapTag, "tileheight")) or 32
  if not (width and height) then return nil, "TMX missing width/height" end
  if tilewidth ~= 32 or tileheight ~= 32 then
    report[#report + 1] = string.format(
      "%s: tile size %dx%d (scaled to 32x32 blocks)",
      basename(path), tilewidth, tileheight)
  end

  local tilesets = parseTilesets(body, dirname(path), report)
  if #tilesets == 0 then return nil, "TMX has no tilesets" end
  for i = 1, #tilesets do conv.allTilesets[#conv.allTilesets + 1] = tilesets[i] end
  local layers = parseLayers(body, width, height)
  if #layers == 0 then return nil, "TMX has no tile layers" end

  local ground, collisions, waterLayers = {}, {}, {}
  for i = 1, #layers do
    local key = layerKey(layers[i].name)
    if key == "collisions" or key == "collision" then
      collisions[#collisions + 1] = layers[i].gids
    elseif key == "water" then
      waterLayers[#waterLayers + 1] = layers[i].gids
    elseif not SPECIAL[key] then
      ground[#ground + 1] = layers[i]
    end
  end
  if #ground == 0 then ground[1] = layers[1] end

  local blocks = {}
  local need = width * height
  for i = 1, need do
    local stack = {}
    local any = false
    for li = 1, #ground do
      local gid = ground[li].gids[i] or 0
      stack[li] = gid
      if gid % FLIP_UNIT ~= 0 then any = true end
    end
    if not any then
      blocks[i] = 0
    else
      local composed = compositeStack(stack, tilesets, report)
      if not composed then
        blocks[i] = 0
      else
        local key = imageKey(composed)
        local bid = conv.keyToBlock[key]
        if bid == nil then
          bid = conv.appendBlock(composed)
          conv.keyToBlock[key] = bid
        end
        blocks[i] = bid
      end
    end
  end

  for i = 1, need do
    local blocked = false
    for li = 1, #collisions do
      if (collisions[li][i] or 0) % FLIP_UNIT ~= 0 then
        blocked = true
        break
      end
    end
    if blocked then
      local row = conv.blockTiles[(blocks[i] or 0) + 1]
      if row then conv.walkableSet[row[13] or 0] = nil end
    end
    local wet = false
    for li = 1, #waterLayers do
      if (waterLayers[li][i] or 0) % FLIP_UNIT ~= 0 then
        wet = true
        break
      end
    end
    if wet then
      local row = conv.blockTiles[(blocks[i] or 0) + 1]
      if row then
        for t = 1, 16 do conv.waterSet[row[t]] = true end
      end
    end
  end

  local warps, objects, signs = {}, {}, {}
  local parsedObjs = parseObjects(body)
  for i = 1, #parsedObjs do
    local obj = parsedObjs[i]
    local bx = math.floor(obj.x / tilewidth)
    local by = math.floor(obj.y / tileheight)
    local cx, cy = bx * 2, by * 2
    local props = obj.properties
    local otype = (obj.type or ""):lower()
    local name = (obj.name or ""):lower()
    if otype:find("warp", 1, true) or name:find("warp", 1, true)
        or props.destMap or props.map then
      warps[#warps + 1] = {
        x = cx, y = cy,
        destMap = tostring(props.destMap or props.map or "PALLET_TOWN"),
        destWarp = tonumber(props.destWarp or props.warp) or 0,
      }
    elseif otype:find("sign", 1, true) or name:find("sign", 1, true) then
      signs[#signs + 1] = {
        x = cx, y = cy,
        text = props.text or obj.name or "SIGN",
      }
    elseif otype:find("npc", 1, true) or otype:find("object", 1, true)
        or obj.name ~= "" then
      objects[#objects + 1] = {
        index = #objects + 1,
        x = cx, y = cy,
        sprite = props.sprite or "SPRITE_RED",
        movement = props.movement or "STAY",
        range = tonumber(props.range) or 0,
        text = props.text or obj.name or "TEXT",
      }
    end
  end

  local wx, wy = worldCoords(path)
  return {
    id = mapIdFromPath(path),
    width = width,
    height = height,
    blocks = blocks,
    warps = warps,
    objects = objects,
    signs = signs,
    wx = wx,
    wy = wy,
  }
end

function TmxPokemonium.importPath(S, path, App)
  if not (S and S.project and S.path) then return false, "no project" end
  if not (love and love.image and love.image.newImageData) then
    return false, "python"
  end
  local files = TmxPokemonium.collectTmx(path)
  if #files == 0 then return false, "no .tmx files" end

  State.ensureProjectFields(S.project)
  local report = {
    string.format("converting %d Pokemonium TMX → engine blocks", #files),
  }
  local emptyBlock = {}
  for i = 1, 16 do emptyBlock[i] = 0 end
  local conv = {
    sheetTiles = { love.image.newImageData(8, 8) },
    blockTiles = { emptyBlock },
    walkableSet = {},
    waterSet = {},
    keyToBlock = {},
    allTilesets = {},
  }
  function conv.appendBlock(tile)
    local base = #conv.sheetTiles
    local ids = {}
    for row = 0, 3 do
      for col = 0, 3 do
        local tid = base + row * 4 + col
        conv.sheetTiles[tid + 1] = crop(tile, col * 8, row * 8, 8, 8)
        ids[row * 4 + col + 1] = tid
        conv.walkableSet[tid] = true
      end
    end
    conv.blockTiles[#conv.blockTiles + 1] = ids
    return #conv.blockTiles - 1
  end

  local converted = {}
  for i = 1, #files do
    local m, err = convertOne(files[i], conv, report)
    if m then
      converted[#converted + 1] = m
    else
      report[#report + 1] = "FAIL " .. basename(files[i]) .. ": " .. tostring(err)
    end
  end
  if #converted == 0 then
    return false, report[#report] or "no maps converted"
  end

  local tilesetId
  local firstExisting = S.project.maps[converted[1].id]
  local existingTs = firstExisting and firstExisting.tileset
    and S.project.tilesets[firstExisting.tileset]
  if existingTs and existingTs._isNew and not existingTs._layeredGenerated then
    tilesetId = firstExisting.tileset
  elseif #conv.allTilesets == 1 then
    tilesetId = uniqueTilesetId(S, conv.allTilesets[1].name)
  else
    tilesetId = uniqueTilesetId(S, "PM_TILES")
  end

  local nTiles = #conv.sheetTiles
  local cols = 16
  local rows = math.max(1, math.ceil(nTiles / cols))
  local atlas = love.image.newImageData(cols * 8, rows * 8)
  for i = 1, nTiles do
    local tile = conv.sheetTiles[i]
    if tile then
      atlas:paste(tile, ((i - 1) % cols) * 8, math.floor((i - 1) / cols) * 8, 0, 0, 8, 8)
    end
  end
  local rel = "assets/tilesets/" .. tilesetId:lower() .. ".png"
  ModIO.ensureDirectory(join(S.path, "assets", "tilesets"))
  local okPng, pngErr = writePng(atlas, join(S.path, (rel:gsub("/", SEP))))
  if not okPng then return false, pngErr end

  local walkable, waterTiles = {}, {}
  for id in pairs(conv.walkableSet) do walkable[#walkable + 1] = id end
  for id in pairs(conv.waterSet) do waterTiles[#waterTiles + 1] = id end
  table.sort(walkable)
  table.sort(waterTiles)
  local tsRec = {
    id = tilesetId,
    image = rel,
    tilesPerRow = 16,
    imageWidth = atlas:getWidth(),
    imageHeight = atlas:getHeight(),
    animation = "TILEANIM_NONE",
    doorTiles = {},
    warpTiles = {},
    counterTiles = {},
    blocks = conv.blockTiles,
    walkable = walkable,
    waterTiles = waterTiles,
    trueColor = true,
    _isNew = true,
  }
  S.project.tilesets[tilesetId] = tsRec
  if S.data and S.data.tilesets then S.data.tilesets[tilesetId] = tsRec end
  copySourceTilesets(S, conv.allTilesets, report)

  local byWorld = {}
  for i = 1, #converted do
    local m = converted[i]
    if m.wx then byWorld[m.wx .. "," .. m.wy] = m.id end
  end

  local gen2 = Generation.isGen2(S)
  local firstId
  for i = 1, #converted do
    local rec = converted[i]
    local existing = S.project.maps[rec.id]
    local index
    if existing and existing.index then
      index = existing.index
    else
      index = S.project.nextMapIndex or 1000
      S.project.nextMapIndex = index + 1
    end
    local connections = {}
    if rec.wx then
      local dirs = {
        { 0, -1, "north" }, { 0, 1, "south" },
        { -1, 0, "west" }, { 1, 0, "east" },
      }
      for d = 1, 4 do
        local nid = byWorld[(rec.wx + dirs[d][1]) .. "," .. (rec.wy + dirs[d][2])]
        if nid then connections[dirs[d][3]] = { map = nid, offset = 0 } end
      end
    end
    local map = existing or {}
    map.id = rec.id
    map.label = map.label or rec.id
    map.index = index
    map.tileset = tilesetId
    map.width = rec.width
    map.height = rec.height
    map.blocks = rec.blocks
    map.borderBlock = map.borderBlock or 0
    map.warps = rec.warps
    map.objects = rec.objects
    map.signs = rec.signs
    map.connections = connections
    map._isNew = true
    if gen2 then
      map.environment = map.environment or "TOWN"
      map.bgEvents = map.bgEvents or {}
    else
      map.environment = map.environment or "outside"
    end
    if map.outdoor == nil then
      map.outdoor = gen2 or map.environment == "outside"
    end
    S.project.maps[rec.id] = map
    if S.data and S.data.maps then S.data.maps[rec.id] = map end
    if S.project.layeredMaps then S.project.layeredMaps[rec.id] = nil end
    pcall(function() require("LayeredMap").convertMap(S, rec.id) end)
    pcall(function() require("src.world.MapLoader").invalidate(rec.id) end)
    report[#report + 1] = string.format(
      "%s: %dx%d blocks, %d warps, %d objects",
      rec.id, rec.width, rec.height, #rec.warps, #rec.objects)
    firstId = firstId or rec.id
  end

  if report._used then
    local used = {}
    for name in pairs(report._used) do used[#used + 1] = name end
    table.sort(used)
    report._used = nil
    report[#report + 1] = "used tileset(s): " .. table.concat(used, ", ")
  end
  report[#report + 1] = string.format(
    "tileset %s: %d unique blocks, %d 8x8 tiles",
    tilesetId, #conv.blockTiles - 1, nTiles)
  if nTiles > 256 then
    report[#report + 1] = "WARNING: " .. nTiles .. " 8x8 tiles (engine limit 256)"
  end
  if #conv.blockTiles > 256 then
    report[#report + 1] = "WARNING: " .. #conv.blockTiles .. " blocks (engine limit 256)"
  end

  S.mapId = firstId
  S.builderMapId = firstId
  S.builderSourceId = require("LayeredMap").runtimeSourceId(tilesetId)
  S.tilesetEditId = tilesetId
  S.mapPaletteTileset = tilesetId
  S._mapPaletteFor = firstId
  S._mapCenteredFor = nil
  S._mapNeedsRebuild = firstId
  S.importReport = table.concat(report, "\n")
  pcall(function() require("Preview").invalidatePath(rel) end)
  if App and App.markDirty then App.markDirty() end
  pcall(function() require("LayeredMap").compileProject(S) end)
  pcall(function() require("src.world.MapLoader").invalidate(firstId) end)
  pcall(function()
    local Maps = require("Maps")
    if Maps.invalidateGoldPreview then Maps.invalidateGoldPreview(S, firstId) end
  end)
  local summary = #converted == 1
    and (firstId .. " (converted to engine blocks)")
    or string.format("%d maps + tileset %s", #converted, tilesetId)
  return true, summary
end

function TmxPokemonium.importFile(S, path, App)
  return TmxPokemonium.importPath(S, path, App)
end

return TmxPokemonium
