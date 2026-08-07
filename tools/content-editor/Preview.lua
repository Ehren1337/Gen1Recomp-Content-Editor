-- Draw image previews for content-editor panels (pokemon, trainers, …).

local Theme = require("Theme")
local PAL = Theme.PAL

local Preview = {}

local cache = {}  -- key -> Image | false
-- Reject huge imports so decode cannot freeze the LOVE window.
local MAX_PREVIEW_BYTES = 8 * 1024 * 1024  -- 8 MiB

local function existsFs(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function join(a, b)
  local sep = package.config:sub(1, 1)
  a = a:gsub("[/\\]+$", "")
  b = b:gsub("^[/\\]+", ""):gsub("/", sep)
  return a .. sep .. b
end

local function cacheKey(S, path)
  return (S and S.path or "") .. "|" .. path
end

local function loadFromDisk(absPath)
  local f = io.open(absPath, "rb")
  if not f then return nil, "cannot open" end
  -- Size check without reading the whole file into Lua when possible.
  local size = f:seek("end")
  f:seek("set")
  if type(size) == "number" and size > MAX_PREVIEW_BYTES then
    f:close()
    return nil, string.format("image too large (%d bytes; max %d)",
      size, MAX_PREVIEW_BYTES)
  end
  local bytes = f:read("*a")
  f:close()
  if not bytes or #bytes == 0 then return nil, "empty file" end
  if #bytes > MAX_PREVIEW_BYTES then
    return nil, string.format("image too large (%d bytes; max %d)",
      #bytes, MAX_PREVIEW_BYTES)
  end
  local name = absPath:match("[^/\\]+$") or "preview.png"
  local ok, fileData = pcall(love.filesystem.newFileData, bytes, name)
  if not ok or not fileData then
    return nil, "FileData failed: " .. tostring(fileData)
  end
  local ok2, img = pcall(love.graphics.newImage, fileData)
  if ok2 and img then return img end
  return nil, "decode failed: " .. tostring(img)
end

function Preview.resolve(S, path)
  if type(path) ~= "string" or path == "" then return nil end
  -- mod-relative first
  if S and S.path then
    local modPath = join(S.path, path)
    if existsFs(modPath) then return modPath, "disk" end
  end
  -- love source (assets/generated/…)
  if love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo(path) then
    return path, "love"
  end
  -- absolute / cwd
  if existsFs(path) then return path, "disk" end
  local root = love and love.filesystem and love.filesystem.getSource
    and love.filesystem.getSource()
  if root then
    local full = join(root, path)
    if existsFs(full) then return full, "disk" end
  end
  return nil
end

function Preview.image(S, path)
  if type(path) ~= "string" or path == "" then return nil end
  local key = cacheKey(S, path)
  if cache[key] ~= nil then
    return cache[key] or nil
  end
  local resolved, kind = Preview.resolve(S, path)
  if not resolved then
    cache[key] = false
    return nil
  end
  local img
  if kind == "love" then
    local ok, Assets = pcall(require, "src.render.Assets")
    if ok and Assets and Assets.image then
      local ok2, result = pcall(Assets.image, resolved)
      if ok2 then img = result end
    end
    if not img then
      local ok3, result = pcall(love.graphics.newImage, resolved)
      if ok3 then img = result end
    end
  else
    local loaded, err = loadFromDisk(resolved)
    img = loaded
    if not loaded and err then
      Preview._lastError = err .. " (" .. path .. ")"
    end
  end
  cache[key] = img or false
  return img
end

function Preview.invalidate()
  cache = {}
end

-- Drop only keys that mention this relative/absolute path (avoids reloading
-- every party icon after one sprite import).
function Preview.invalidatePath(path)
  if type(path) ~= "string" or path == "" then
    Preview.invalidate()
    return
  end
  local needle = path:gsub("\\", "/")
  local base = needle:match("([^/]+)$") or needle
  for key in pairs(cache) do
    local k = tostring(key):gsub("\\", "/")
    if k:find(needle, 1, true) or (base and k:find(base, 1, true)) then
      cache[key] = nil
    end
  end
end

function Preview.lastError()
  return Preview._lastError
end

-- Normalize a palette record / colors table to 4×{r,g,b} 0–255.
local function normalizeColors(rec)
  if type(rec) ~= "table" then return nil end
  local cols = rec.colors or rec
  if type(cols) ~= "table" or type(cols[1]) ~= "table" then return nil end
  local out = {}
  for i = 1, 4 do
    local c = cols[i] or { 0, 0, 0 }
    if c.r then out[i] = { c.r, c.g, c.b }
    else out[i] = { c[1] or 0, c[2] or 0, c[3] or 0 }
    end
  end
  return out
end

-- Sorted palette ids (vanilla order first, then project extras).
function Preview.paletteIds(S)
  local ids, seen = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local order = S and S.data and S.data.palettes and S.data.palettes.order
  if type(order) == "table" then
    for _, id in ipairs(order) do add(id) end
  end
  local dataPals = S and S.data and S.data.palettes and S.data.palettes.palettes
  if type(dataPals) == "table" then
    local extra = {}
    for id in pairs(dataPals) do
      if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do add(id) end
  end
  if S and S.project and S.project.palettes then
    local extra = {}
    for id in pairs(S.project.palettes) do
      if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do add(id) end
  end
  return ids
end

-- Resolve named palette colors (project override wins). Prefer GBC pack in
-- the editor — clearer tile contrast than SGB for map painting.
function Preview.paletteColors(S, name)
  if type(name) ~= "string" or name == "" then return nil end
  if S and S.project and S.project.palettes and S.project.palettes[name] then
    local cols = normalizeColors(S.project.palettes[name])
    if cols then return cols end
  end
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if ok and PaletteFX and PaletteFX.gbcPack then
    local pack = PaletteFX.gbcPack()
    local g = pack and pack.palettes and pack.palettes[name]
    if g then return normalizeColors(g) end
  end
  local data = S and S.data and S.data.palettes and S.data.palettes.palettes
  if data and data[name] then return normalizeColors(data[name]) end
  return nil
end

-- Effective map palette name (map.palette or FieldDefaults cascade).
function Preview.mapPaletteName(S, map)
  if type(map) ~= "table" then return "ROUTE" end
  if type(map.palette) == "string" and map.palette ~= "" then
    return map.palette
  end
  local ok, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  local pals = ok and FieldDefaults and FieldDefaults.FIELD and FieldDefaults.FIELD.palettes
  if not pals then return "ROUTE" end
  local mid = map.id
  if mid and pals.byMap and pals.byMap[mid] then return pals.byMap[mid] end
  local ts = map.tileset
  if ts and pals.byTileset and pals.byTileset[ts] then return pals.byTileset[ts] end
  if mid and type(pals.byPrefix) == "table" then
    for _, row in ipairs(pals.byPrefix) do
      if row.prefix and mid:sub(1, #row.prefix) == row.prefix then
        return row.palette or pals.default or "ROUTE"
      end
    end
  end
  return pals.default or "ROUTE"
end

-- Species battle palette name (authored → pack → MEWMON).
function Preview.monPaletteName(S, mon, speciesId)
  if mon and type(mon.palette) == "string" and mon.palette ~= "" then
    return mon.palette
  end
  local sid = speciesId or (mon and mon.id)
  local poke = S and S.data and S.data.palettes and S.data.palettes.pokemon
  if sid and poke and type(poke[sid]) == "string" and poke[sid] ~= "" then
    return poke[sid]
  end
  return "MEWMON"
end

-- Trainer battle pic palette (MEWMON unless a named paletteSource matches).
function Preview.trainerPaletteName(S, tr)
  if tr and type(tr.paletteSource) == "string" and tr.paletteSource ~= "" then
    if Preview.paletteColors(S, tr.paletteSource) then
      return tr.paletteSource
    end
  end
  return "MEWMON"
end

function Preview.drawSwatches(colors, x, y, w, h)
  local s = 1
  local KitOk, Kit = pcall(require, "Kit")
  if KitOk and Kit.scale then s = Kit.scale end
  w = w or (80 * s)
  h = h or (16 * s)
  colors = colors or {}
  local sw = w / 4
  for i = 1, 4 do
    local c = colors[i] or { 40, 40, 40 }
    love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", x + (i - 1) * sw, y, sw - 2 * s, h, 4 * s, 4 * s)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draw named-palette swatches (no-op if unknown). Returns height used.
function Preview.drawNamedSwatches(S, name, x, y, w, h)
  local colors = Preview.paletteColors(S, name)
  if not colors then return 0 end
  Preview.drawSwatches(colors, x, y, w, h)
  return h or 16
end

-- Live SGB shade-remap for grayscale draw calls (map canvas / block thumbs).
-- Skips when ADVANCED/GBC pack is active (art is already true-color).
function Preview.pushPaletteShader(S, nameOrColors)
  local colors = nameOrColors
  if type(nameOrColors) == "string" then
    colors = Preview.paletteColors(S, nameOrColors)
  end
  if type(colors) ~= "table" then return false end
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not (ok and PaletteFX and PaletteFX.shader and PaletteFX.sendColors) then
    return false
  end
  if PaletteFX.usesGbcPack and PaletteFX.usesGbcPack() then
    return false
  end
  local sh = PaletteFX.shader()
  if not sh then return false end
  PaletteFX.sendColors(sh, colors)
  love.graphics.setShader(sh)
  return true
end

function Preview.popPaletteShader(pushed)
  if pushed then love.graphics.setShader() end
end

local function loadImageData(S, path)
  if not (love and love.image and love.image.newImageData) then return nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, id = pcall(Assets.imageData, path)
    if ok and id then return id end
  end
  local resolved, kind = Preview.resolve(S, path)
  if not resolved then return nil end
  if kind == "disk" then
    local f = io.open(resolved, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    if not bytes or #bytes == 0 then return nil end
    local name = resolved:match("[^/\\]+$") or "preview.png"
    local okFd, fd = pcall(love.filesystem.newFileData, bytes, name)
    if not (okFd and fd) then return nil end
    local okId, id = pcall(love.image.newImageData, fd)
    return okId and id or nil
  end
  local ok, id = pcall(love.image.newImageData, resolved)
  return ok and id or nil
end

-- CPU shade-remap like BattleState.getImage (DMG r → palette color).
function Preview.imageWithPalette(S, path, colorsOrName)
  if type(path) ~= "string" or path == "" then return nil end
  local colors = colorsOrName
  local palName = nil
  if type(colorsOrName) == "string" then
    palName = colorsOrName
    colors = Preview.paletteColors(S, colorsOrName)
  end
  if type(colors) ~= "table" then return Preview.image(S, path) end
  local key = cacheKey(S, path) .. "#pal:" .. (palName or table.concat({
    colors[1][1], colors[1][2], colors[1][3],
    colors[2][1], colors[2][2], colors[2][3],
    colors[3][1], colors[3][2], colors[3][3],
    colors[4][1], colors[4][2], colors[4][3],
  }, ","))
  if cache[key] ~= nil then return cache[key] or nil end
  local data = loadImageData(S, path)
  if not data then
    cache[key] = Preview.image(S, path) or false
    return cache[key] or nil
  end
  local c = colors
  local okMap = pcall(function()
    data:mapPixel(function(_, _, r, g, b, a)
      if a == 0 then return r, g, b, a end
      local col = r > 0.83 and c[1] or r > 0.5 and c[2]
                  or r > 0.17 and c[3] or c[4]
      return (col[1] or 0) / 255, (col[2] or 0) / 255, (col[3] or 0) / 255, a
    end)
  end)
  if not okMap then
    cache[key] = Preview.image(S, path) or false
    return cache[key] or nil
  end
  local okImg, baked = pcall(love.graphics.newImage, data)
  cache[key] = (okImg and baked) or false
  return cache[key] or nil
end

-- Draw image fitted into maxW x maxH.  Optional paletteNameOrColors tints
-- DMG grayscale PNGs with an SGB 4-color palette.  Returns height consumed.
function Preview.draw(S, path, x, y, maxW, maxH, paletteNameOrColors)
  local s = 1
  local KitOk, Kit = pcall(require, "Kit")
  if KitOk and Kit.scale then s = Kit.scale end
  maxW = maxW or (96 * s)
  maxH = maxH or (96 * s)

  local img
  if paletteNameOrColors then
    img = Preview.imageWithPalette(S, path, paletteNameOrColors)
  else
    img = Preview.image(S, path)
  end
  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  love.graphics.rectangle("fill", x, y, maxW, maxH, 8 * s, 8 * s)

  if not img then
    love.graphics.setColor(1, 1, 1, 1)
    local msg = (path and path ~= "") and "no image" or "no path"
    if KitOk then
      Kit.text("micro", msg, x + 8 * s, y + maxH / 2 - 6 * s, PAL.faint)
    end
    return maxH
  end

  local iw, ih = img:getWidth(), img:getHeight()
  local scale = math.min(maxW / iw, maxH / ih)
  local dw, dh = iw * scale, ih * scale
  local dx = x + (maxW - dw) / 2
  local dy = y + (maxH - dh) / 2
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, dx, dy, 0, scale, scale)
  return maxH
end

Preview.drawWithPalette = Preview.draw

-- Trainer pic: prefer pic path, else basePic trainer's pic.
function Preview.trainerPicPath(S, tr)
  if not tr then return nil end
  if tr.pic and tr.pic ~= "" then return tr.pic end
  local baseId = tr.basePic
  if baseId and S.data and S.data.trainers and S.data.trainers[baseId] then
    return S.data.trainers[baseId].pic
  end
  if baseId and S.project and S.project.trainers and S.project.trainers[baseId] then
    return S.project.trainers[baseId].pic
  end
  return nil
end

function Preview.pokemonFront(S, mon)
  if not mon then return nil end
  return mon.spriteFront
end

local function spriteDef(S, spriteId)
  local sprites = S and S.data and S.data.sprites
  local def = sprites and sprites[spriteId]
  if def then return def end
  local proj = S and S.project and S.project.sprites
  return proj and proj[spriteId] or nil
end

local function spriteImage(S, spriteId, fallback)
  local def = spriteDef(S, spriteId)
  if def and def.image then return def.image end
  return fallback
end

local function spritePalette(S, spriteId)
  local def = spriteDef(S, spriteId)
  local src = def and def.paletteSource
  if type(src) == "string" and src ~= "" and Preview.paletteColors(S, src) then
    return src
  end
  return nil
end

-- Category stand-in sprite id for an item (nil when a custom icon is set).
local function itemCategorySpriteId(item)
  if not item then return nil end
  local entry = item.icon
  if type(entry) == "string" and entry ~= "" then return nil end
  if type(entry) == "table" and type(entry.image) == "string" and entry.image ~= "" then
    return nil
  end
  local id = tostring(item.id or "")
  local isBall = item.ball or id:find("_BALL$") or id == "SAFARI_BALL"
  if isBall then return "SPRITE_POKE_BALL" end
  if item.machine or id:match("^TM_") or id:match("^HM_") then
    return "SPRITE_CLIPBOARD"
  end
  if id:find("FOSSIL") or id == "OLD_AMBER" then return "SPRITE_FOSSIL" end
  if id == "POKEDEX" or id == "TOWN_MAP" then return "SPRITE_POKEDEX" end
  if id:find("_STONE$") then return "SPRITE_FOSSIL" end
  if item.keyItem or item.tossable == false then return "SPRITE_POKEDEX" end
  return "SPRITE_POKE_BALL"
end

-- Item icon path: custom item.icon, else a category stand-in from ROM art.
-- Gen1 bags are text-only; these are editor/UI helpers, not vanilla assets.
function Preview.itemIconPath(S, item)
  if not item then return nil end
  local entry = item.icon
  if type(entry) == "string" and entry ~= "" then return entry end
  if type(entry) == "table" and type(entry.image) == "string" and entry.image ~= "" then
    return entry.image
  end
  local id = tostring(item.id or "")
  local icons = S and S.data and S.data.icons and S.data.icons.icons
  local sid = itemCategorySpriteId(item)
  if sid == "SPRITE_POKE_BALL" and icons and icons.BALL then return icons.BALL end
  if (id:find("FOSSIL") or id == "OLD_AMBER") and icons and icons.HELIX then
    return icons.HELIX
  end
  if id:find("_STONE$") and icons and icons.FAIRY then return icons.FAIRY end
  local fallbacks = {
    SPRITE_POKE_BALL = "assets/generated/sprites/poke_ball.png",
    SPRITE_CLIPBOARD = "assets/generated/sprites/clipboard.png",
    SPRITE_FOSSIL = "assets/generated/sprites/fossil.png",
    SPRITE_POKEDEX = "assets/generated/sprites/pokedex.png",
  }
  return spriteImage(S, sid, fallbacks[sid] or "assets/generated/sprites/poke_ball.png")
end

-- Item icon palette (authored item.palette → category sprite paletteSource → MEWMON).
function Preview.itemPaletteName(S, item)
  if item and type(item.palette) == "string" and item.palette ~= "" then
    return item.palette
  end
  local sid = itemCategorySpriteId(item)
  return (sid and spritePalette(S, sid)) or "MEWMON"
end

function Preview.drawItemIcon(S, item, x, y, maxW, maxH, paletteName)
  local pal = paletteName or Preview.itemPaletteName(S, item)
  return Preview.draw(S, Preview.itemIconPath(S, item), x, y, maxW, maxH, pal)
end

-- Party-menu icon path + built-in class name (name => bake OBP0 like PartyMenu).
function Preview.pokemonIcon(S, mon, speciesId)
  if not mon and not speciesId then return nil, nil end
  local icons = S and S.data and S.data.icons
  if not icons then return nil, nil end
  local id = speciesId or (mon and (mon.id or mon.species))
  local vanilla = id and S.data.pokemon and S.data.pokemon[id]
  local def = mon or vanilla
  local entry = (icons.bySpecies and id and icons.bySpecies[id])
    or (mon and mon.icon)
    or (vanilla and vanilla.icon)
  local name, path
  if type(entry) == "string" then
    name = entry
    path = icons.icons and icons.icons[entry]
  elseif type(entry) == "table" then
    path = entry.image
  end
  local dex = (mon and mon.dex) or (vanilla and vanilla.dex) or (def and def.dex)
  if not path and dex and icons.byDex then
    name = icons.byDex[dex]
    path = name and icons.icons and icons.icons[name]
  end
  return path, name
end

local function loadObpIcon(S, path)
  if not (love and love.image and love.image.newImageData) then
    return Preview.image(S, path)
  end
  local data
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, id = pcall(Assets.imageData, path)
    if ok then data = id end
  end
  if not data then
    local resolved, kind = Preview.resolve(S, path)
    if not resolved then return nil end
    if kind == "disk" then
      -- Absolute host paths: decode via FileData (same size guard as sprites).
      local img = select(1, loadFromDisk(resolved))
      return img
    end
    local ok, id = pcall(love.image.newImageData, resolved)
    if ok then data = id end
  end
  if not data then return Preview.image(S, path) end
  local okMap = pcall(function()
    data:mapPixel(function(_, _, r, _, _, a)
      local v = 0
      if r > 0.5 then v = 1
      elseif r > 0.17 then v = 170 / 255
      end
      return v, v, v, a
    end)
  end)
  if not okMap then return Preview.image(S, path) end
  local okImg, baked = pcall(love.graphics.newImage, data)
  return okImg and baked or nil
end

-- Draw party icon. Built-in class names get the OBP0 shade bake, then an
-- optional SGB palette tint (species palette). Custom PNG icons remap
-- directly through the palette when one is provided.
function Preview.drawPokemonIcon(S, mon, x, y, maxW, maxH, speciesId, paletteName)
  local s = 1
  local KitOk, Kit = pcall(require, "Kit")
  if KitOk and Kit.scale then s = Kit.scale end
  maxW = maxW or (24 * s)
  maxH = maxH or (24 * s)
  local path, name = Preview.pokemonIcon(S, mon, speciesId)
  local pal = paletteName
  if pal == nil then
    pal = Preview.monPaletteName(S, mon, speciesId)
  end
  Theme.col(PAL.bgBot or { 10, 10, 20 }, 1)
  love.graphics.rectangle("fill", x, y, maxW, maxH, 6 * s, 6 * s)
  if not path then
    love.graphics.setColor(1, 1, 1, 1)
    if KitOk then
      Kit.text("micro", "?", x + maxW / 2 - 4 * s, y + maxH / 2 - 6 * s, PAL.faint)
    end
    return maxH, nil
  end
  -- Custom icons: full SGB remap. Built-in OBP icons: shade-bake then tint.
  if not name and pal then
    return Preview.draw(S, path, x, y, maxW, maxH, pal), name
  end
  local key = (S and S.path or "") .. "|icon|" .. path
    .. (name and "#obp" or "") .. (pal and ("#pal:" .. pal) or "")
  if cache[key] == nil then
    if name then
      -- Remap OBP grayscale through the species palette when available.
      if pal and Preview.paletteColors(S, pal) then
        cache[key] = Preview.imageWithPalette(S, path, pal) or loadObpIcon(S, path) or false
      else
        cache[key] = loadObpIcon(S, path) or false
      end
    else
      cache[key] = Preview.image(S, path) or false
    end
  end
  local img = cache[key]
  if not img then
    return Preview.draw(S, path, x, y, maxW, maxH, pal), name
  end
  local iw, ih = img:getWidth(), img:getHeight()
  -- Built-in icons are often 16x32 two-frame strips; show frame 1 (top).
  local srcH = ih
  if name and ih >= iw * 2 then srcH = math.floor(ih / 2) end
  local scale = math.min(maxW / iw, maxH / srcH)
  local dw, dh = iw * scale, srcH * scale
  local dx = x + (maxW - dw) / 2
  local dy = y + (maxH - dh) / 2
  love.graphics.setColor(1, 1, 1, 1)
  if name and srcH < ih then
    local qkey = key .. "|q"
    if cache[qkey] == nil then
      local ok, q = pcall(love.graphics.newQuad, 0, 0, iw, srcH, iw, ih)
      cache[qkey] = ok and q or false
    end
    if cache[qkey] then
      love.graphics.draw(img, cache[qkey], dx, dy, 0, scale, scale)
    else
      love.graphics.draw(img, dx, dy, 0, scale, scale)
    end
  else
    love.graphics.draw(img, dx, dy, 0, scale, scale)
  end
  return maxH, name
end

return Preview
