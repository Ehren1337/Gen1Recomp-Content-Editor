-- GFX tab: palettes, overworld sprites, tilesets.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local ModIO = require("ModIO")
local MapLoader = require("src.world.MapLoader")
local PAL = Theme.PAL

local Gfx = {}

local MODES = {
  { id = "palettes", label = "Palettes", tip = "SGB/GBC color palettes (4 colors)" },
  { id = "sprites", label = "Sprites", tip = "Overworld sprite sheets" },
  { id = "tilesets", label = "Tilesets",
    tip = "Walkable / grass / water / door / warp tile flags" },
}

local TILE_PX = 8  -- Gen1 tileset sheet cells are 8x8
local FLAG_MODES = {
  { id = "walk", label = "Walk", tip = "Passable (in walkable list)" },
  { id = "solid", label = "Solid", tip = "Collision / blocked (not walkable)" },
  { id = "water", label = "Water", tip = "Surfable water tile" },
  { id = "grass", label = "Grass", tip = "Tall grass (wild encounters)" },
  { id = "shore", label = "Shore", tip = "Shore / beach (surf edge)" },
}

local function parseRgb(s, fallback)
  local r, g, b = tostring(s or ""):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if r then return { tonumber(r), tonumber(g), tonumber(b) } end
  return fallback or { 0, 0, 0 }
end

local function fmtRgb(c)
  if type(c) ~= "table" then return "0,0,0" end
  if c.r then return string.format("%d,%d,%d", c.r, c.g, c.b) end
  return string.format("%d,%d,%d", c[1] or 0, c[2] or 0, c[3] or 0)
end

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

local function drawPalettePreview(colors, x, y, w, h, s)
  colors = colors or {}
  local sw = w / 4
  for i = 1, 4 do
    local c = colors[i] or { 40, 40, 40 }
    love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", x + (i - 1) * sw, y, sw - 2 * s, h, 4 * s, 4 * s)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function csvNums(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    local n = tonumber(part:match("%d+"))
    if n then out[#out + 1] = n end
  end
  return out
end

local function joinNums(t)
  if type(t) ~= "table" then return "" end
  return table.concat(t, ",")
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

local function cloneNumList(v)
  local a = {}
  for i = 1, #(v or {}) do a[i] = v[i] end
  return a
end

local function syncTilesetLive(S, id, ts)
  if S.data and S.data.tilesets then
    S.data.tilesets[id] = ts
  end
  MapLoader.invalidateAll()
end

local function tilesetTileCount(rec, img)
  local tpr = rec.tilesPerRow or 16
  if img then
    local cols = math.max(1, math.floor(img:getWidth() / TILE_PX))
    local rows = math.max(1, math.floor(img:getHeight() / TILE_PX))
    return cols * rows, cols
  end
  local maxId = 0
  for _, block in ipairs(rec.blocks or {}) do
    for _, t in ipairs(block) do
      if type(t) == "number" and t > maxId then maxId = t end
    end
  end
  return maxId + 1, tpr
end

-- Clickable 8x8 sheet: paint walk / solid / water / grass / shore.
-- Returns the Y after the painter (for FormPane content height).
local function drawTileFlagPainter(S, App, rec, ensureFn, id, x, y, w, s, palName)
  Kit.text("micro", "TILE FLAGS (click to paint)", x, y, PAL.caption)
  y = y + 14 * s
  S.gfxTileFlagMode = S.gfxTileFlagMode or "walk"
  local mx = x
  for _, mode in ipairs(FLAG_MODES) do
    local on = S.gfxTileFlagMode == mode.id
    local bw = Kit.textWidth("micro", mode.label) + 14 * s
    if mx + bw > x + w then
      mx = x
      y = y + 26 * s
    end
    if Kit.chip(mx, y, bw, 22 * s, mode.label, on, PAL.green, nil, mode.tip) then
      S.gfxTileFlagMode = mode.id
    end
    mx = mx + bw + 3 * s
  end
  y = y + 28 * s
  Kit.text("micro",
    "green=walk  red=solid  blue=water  cyan=shore  yellow=grass",
    x, y, PAL.faint)
  y = y + 14 * s

  local img = Preview.image(S, rec.image)
  local count, cols = tilesetTileCount(rec, img)
  cols = cols or (rec.tilesPerRow or 16)
  local cell = math.max(12 * s, math.min(20 * s, math.floor((w - 4 * s) / cols)))
  local rows = math.max(1, math.ceil(count / cols))
  local gridW = cols * cell
  local gridH = rows * cell
  local walk = {}
  for _, t in ipairs(rec.walkable or {}) do walk[t] = true end
  local water = {}
  for _, t in ipairs(rec.waterTiles or {}) do water[t] = true end
  local shore = {}
  for _, t in ipairs(rec.shoreTiles or {}) do shore[t] = true end
  local grass = rec.grassTile

  Kit.pushClip(x, y, w, gridH)
  Theme.col(PAL.bgBot, 1)
  love.graphics.rectangle("fill", x, y, gridW, gridH)

  local shaded = (not rec.trueColor) and Preview.pushPaletteShader(S, palName)
  if img and love.graphics.draw then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, cell / TILE_PX, cell / TILE_PX)
  end
  if shaded then Preview.popPaletteShader(shaded) end

  for tid = 0, count - 1 do
    local col = tid % cols
    local row = math.floor(tid / cols)
    local tx = x + col * cell
    local ty = y + row * cell

    if water[tid] then
      love.graphics.setColor(0.15, 0.45, 1, 0.4)
      love.graphics.rectangle("fill", tx, ty, cell, cell)
    end
    if shore[tid] then
      love.graphics.setColor(0.2, 0.85, 0.9, 0.35)
      love.graphics.rectangle("fill", tx, ty, cell, cell)
    end
    if walk[tid] then
      love.graphics.setColor(0.2, 0.9, 0.4, 0.28)
      love.graphics.rectangle("fill", tx, ty, cell, cell)
    else
      love.graphics.setColor(1, 0.2, 0.25, 0.32)
      love.graphics.rectangle("fill", tx, ty, cell, cell)
    end
    if grass ~= nil and grass == tid then
      love.graphics.setColor(1, 0.9, 0.15, 0.95)
      love.graphics.rectangle("line", tx + 1, ty + 1, cell - 2, cell - 2)
    end

    if Kit.press(tx, ty, cell, cell) then
      local e = ensureFn()
      e.walkable = e.walkable or {}
      e.waterTiles = e.waterTiles or {}
      e.shoreTiles = e.shoreTiles or {}
      local mode = S.gfxTileFlagMode or "walk"
      if mode == "walk" then
        listSet(e.walkable, tid, true)
      elseif mode == "solid" then
        listSet(e.walkable, tid, false)
      elseif mode == "water" then
        listSet(e.waterTiles, tid, listIndex(e.waterTiles, tid) == nil)
      elseif mode == "shore" then
        listSet(e.shoreTiles, tid, listIndex(e.shoreTiles, tid) == nil)
      elseif mode == "grass" then
        e.grassTile = (e.grassTile == tid) and nil or tid
      end
      syncTilesetLive(S, id, e)
      App.markDirty()
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  Kit.popClip()

  return y + gridH + 8 * s
end

function Gfx.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  S.project.palettes = S.project.palettes or {}
  S.project.sprites = S.project.sprites or {}
  S.project.tilesets = S.project.tilesets or {}

  local modeY = RegList.modeChips(S, "gfxMode", MODES, x, y, s)
  local mode = S.gfxMode or "palettes"

  if mode == "palettes" then
    local proj = S.project.palettes
    local data = (S.data and S.data.palettes and S.data.palettes.palettes) or {}
    local ids = RegList.mergeIds(proj, data)
    local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
      "PALETTES", ids, {
        queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "paletteId",
        accent = PAL.yellow,
        isOwned = function(id) return proj[id] ~= nil end,
        footerLabel = "+ New palette",
        onFooter = function()
          local nid = "MOD_PAL"
          local n = 1
          while proj[nid] or data[nid] do n = n + 1; nid = "MOD_PAL_" .. n end
          proj[nid] = {
            colors = {
              { 248, 248, 248 }, { 168, 168, 168 },
              { 88, 88, 88 }, { 16, 16, 16 },
            },
            _isNew = true,
          }
          S.paletteId = nid
          App.markDirty()
        end,
      })
    if not S.paletteId then S.paletteId = shown[1] end
    local id = S.paletteId
    local owned = id and proj[id] ~= nil
    local rec = owned and proj[id] or data[id]
    if not id or not rec then
      Kit.emptyBox(formX, listY, formW, listH, "No palettes")
      return
    end
    Kit.caption(formX, modeY, id .. (owned and "" or "  (vanilla)"))
    local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
      "gfxFormScroll", "pal|" .. id, owned and 44 * s or 12 * s)
    local contentTop = fy
    local colors = normalizeColors(rec) or {
      { 248, 248, 248 }, { 168, 168, 168 }, { 88, 88, 88 }, { 16, 16, 16 },
    }
    drawPalettePreview(colors, viewX, fy, viewW, 36 * s, s)
    fy = fy + 44 * s
    local function ensure()
      if owned then return proj[id] end
      proj[id] = { colors = colors, _isNew = false }
      owned = true
      App.markDirty()
      return proj[id]
    end
    for i = 1, 4 do
      Kit.text("small", "C" .. i, viewX, fy + 6 * s, PAL.caption)
      local v = RegList.field(App, "pal_c_" .. i, viewX + 40 * s, fy, viewW - 40 * s, 28 * s,
        fmtRgb(colors[i]), "r,g,b")
      local parsed = parseRgb(v, colors[i])
      if fmtRgb(parsed) ~= fmtRgb(colors[i]) then
        local e = ensure()
        e.colors = e.colors or colors
        e.colors[i] = parsed
        colors[i] = parsed
        Preview.invalidate()
      end
      fy = fy + 36 * s
    end
    FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
    if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
        "Revert", { kind = "danger" }) then
      proj[id] = nil; App.markDirty()
    end
    return
  end

  if mode == "sprites" then
    local proj = S.project.sprites
    local data = (S.data and S.data.sprites) or {}
    local ids = RegList.mergeIds(proj, data)
    local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
      "SPRITES", ids, {
        queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "spriteEditId",
        accent = PAL.green,
        isOwned = function(id) return proj[id] ~= nil end,
        footerLabel = "+ New sprite",
        onFooter = function()
          local nid = "SPRITE_MOD"
          local n = 1
          while proj[nid] or data[nid] do n = n + 1; nid = "SPRITE_MOD_" .. n end
          proj[nid] = {
            id = nid, image = "assets/" .. nid:lower() .. ".png",
            frames = 1, walker = false, _isNew = true,
          }
          S.spriteEditId = nid
          App.markDirty()
        end,
      })
    if not S.spriteEditId then S.spriteEditId = shown[1] end
    local id = S.spriteEditId
    local owned = id and proj[id] ~= nil
    local rec = owned and proj[id] or data[id]
    if not id or not rec then
      Kit.emptyBox(formX, listY, formW, listH, "No sprites")
      return
    end
    local function ensure()
      if owned then return proj[id] end
      local copy = {}
      for k, v in pairs(rec) do copy[k] = v end
      copy._isNew = false
      proj[id] = copy
      owned = true
      App.markDirty()
      return copy
    end
    Kit.caption(formX, modeY, id .. (owned and "" or "  (vanilla)"))
    local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
      "gfxFormScroll", "spr|" .. id, owned and 44 * s or 12 * s)
    local contentTop = fy
    local prev = 64 * s
    -- Overworld sprites: tint with paletteSource when it names an SGB palette;
    -- trueColor art stays raw.
    local sprPal = nil
    if not rec.trueColor then
      local src = rec.paletteSource
      if type(src) == "string" and src ~= "" and Preview.paletteColors(S, src) then
        sprPal = src
      else
        sprPal = "MEWMON"
      end
    end
    Preview.draw(S, rec.image, viewX + viewW - prev, fy, prev, prev, sprPal)
    if sprPal then
      Preview.drawNamedSwatches(S, sprPal,
        viewX + viewW - prev, fy + prev + 4 * s, prev, 12 * s)
    end
    local labelW = 110 * s
    local fh = 28 * s
    local fieldW = viewW - labelW - prev - 12 * s
    local function row(label, body)
      Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
      body(viewX + labelW, fy, fieldW, fh)
      fy = fy + fh + 8 * s
    end
    row("Image", function(fx, fy_, fw, fh_)
      Kit.text("micro", Kit.ellipsize("micro", tostring(rec.image or ""), fw - 100 * s),
        fx, fy_ + 8 * s, PAL.muted)
      if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Browse", {
          kind = "ghost", tooltip = "Import overworld sprite PNG",
        }) then
        local sid = id
        App.pickFile("Sprite PNG", "PNG (*.png)|*.png|All|*.*",
          function(picked)
            State.ensureProjectFields(S.project)
            local e = S.project.sprites[sid]
            if not e then
              e = {}
              for k, v in pairs(rec) do e[k] = v end
              e._isNew = false
              S.project.sprites[sid] = e
            end
            App.importToMod(picked, nil, function(rel)
              e.image = rel
            end)
          end)
      end
    end)
    row("Frames", function(fx, fy_, fw, fh_)
      local cur = rec.frames or 1
      local v = RegList.num(App, "spr_fr", fx, fy_, 60 * s, fh_, cur)
      v = math.max(1, math.min(16, v))
      if v ~= cur then ensure().frames = v end
    end)
    row("Walker", function(fx, fy_, fw, fh_)
      local on = rec.walker and true or false
      if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.green) then
        ensure().walker = not on
        App.markDirty()
      end
    end)
    row("TrueColor", function(fx, fy_, fw, fh_)
      local on = rec.trueColor and true or false
      if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
        local e = ensure()
        e.trueColor = not on
        if not e.trueColor then e.trueColor = nil end
        App.markDirty()
      end
    end)
    row("Palette src", function(fx, fy_, fw, fh_)
      local cur = rec.paletteSource or ""
      local v = RegList.field(App, "spr_ps", fx, fy_, math.max(40 * s, fw - 88 * s), fh_, cur, "optional")
      if v ~= cur then
        local e = ensure()
        e.paletteSource = (v ~= "" and v) or nil
      end
      if sprPal then
        Preview.drawNamedSwatches(S, sprPal, fx + fw - 80 * s,
          fy_ + (fh_ - 14 * s) / 2, 80 * s, 14 * s)
      end
    end)
    FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
    if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
        "Revert", { kind = "danger" }) then
      proj[id] = nil; App.markDirty()
    end
    return
  end

  -- tilesets
  local proj = S.project.tilesets
  local data = (S.data and S.data.tilesets) or {}
  local ids = RegList.mergeIds(proj, data)
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
    "TILESETS", ids, {
      queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "tilesetEditId",
      accent = PAL.blue,
      isOwned = function(id) return proj[id] ~= nil end,
      footerLabel = "+ New tileset",
      onFooter = function()
        local nid = "MOD_TILES"
        local n = 1
        while proj[nid] or data[nid] do n = n + 1; nid = "MOD_TILES_" .. n end
        local blocks = {}
        for i = 1, 16 do
          local row = {}
          for j = 1, 16 do row[j] = 0 end
          blocks[i] = row
        end
        proj[nid] = {
          id = nid, image = "assets/" .. nid:lower() .. ".png",
          tilesPerRow = 16, blocks = blocks, walkable = { 1 },
          waterTiles = {}, shoreTiles = {},
          doorTiles = {}, warpTiles = {}, counterTiles = {},
          animation = "TILEANIM_NONE", _isNew = true,
        }
        S.tilesetEditId = nid
        App.markDirty()
      end,
    })
  if not S.tilesetEditId then S.tilesetEditId = shown[1] end
  local id = S.tilesetEditId
  local owned = id and proj[id] ~= nil
  local rec = owned and proj[id] or data[id]
  if not id or not rec then
    Kit.emptyBox(formX, listY, formW, listH, "No tilesets")
    return
  end
  local function ensure()
    if owned then return proj[id] end
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
    copy._isNew = false
    proj[id] = copy
    owned = true
    syncTilesetLive(S, id, copy)
    App.markDirty()
    return copy
  end

  local function editList(key, value)
    local e = ensure()
    e[key] = value
    syncTilesetLive(S, id, e)
  end
  Kit.caption(formX, modeY, id .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "gfxFormScroll", "ts|" .. id, owned and 44 * s or 12 * s)
  local contentTop = fy
  local prev = 72 * s
  -- Preview palette for grayscale tileset sheets (cycle with chip below).
  local tsPals = Preview.paletteIds(S)
  if not S.gfxTilesetPalPreview or not Preview.paletteColors(S, S.gfxTilesetPalPreview) then
    S.gfxTilesetPalPreview = (#tsPals > 0 and tsPals[1]) or "ROUTE"
  end
  local tsPal = S.gfxTilesetPalPreview
  Preview.draw(S, rec.image, viewX + viewW - prev, fy, prev, prev,
    (not rec.trueColor) and tsPal or nil)
  if not rec.trueColor then
    Preview.drawNamedSwatches(S, tsPal,
      viewX + viewW - prev, fy + prev + 4 * s, prev, 12 * s)
  end
  local labelW = 120 * s
  local fh = 28 * s
  local fieldW = viewW - labelW - prev - 12 * s
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end
  if not rec.trueColor then
    row("Preview pal", function(fx, fy_, fw, fh_)
      if Kit.button(fx, fy_, math.min(fw, 160 * s), fh_,
          Kit.ellipsize("small", tsPal, math.min(fw, 160 * s) - 8 * s),
          { kind = "ghost", tooltip = "Cycle SGB palette used for this PNG preview" })
          and #tsPals > 0 then
        local idx = 1
        for i, id in ipairs(tsPals) do
          if id == tsPal then idx = i; break end
        end
        S.gfxTilesetPalPreview = tsPals[(idx % #tsPals) + 1]
      end
      Preview.drawNamedSwatches(S, S.gfxTilesetPalPreview,
        fx + fw - 80 * s, fy_ + (fh_ - 14 * s) / 2, 80 * s, 14 * s)
    end)
  end
  row("Image", function(fx, fy_, fw, fh_)
    Kit.text("micro", Kit.ellipsize("micro", tostring(rec.image or ""), fw - 100 * s),
      fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Browse", {
        kind = "ghost", tooltip = "Import tileset PNG → assets/tilesets/",
      }) then
      local tid = id
      App.pickFile("Tileset PNG", "PNG (*.png)|*.png|All|*.*",
        function(picked)
          State.ensureProjectFields(S.project)
          local e = S.project.tilesets[tid]
          if not e then
            e = ensure()
          end
          local base = App.assetBaseName(picked, "tiles.png")
          if not base:lower():match("%.png$") then base = base .. ".png" end
          App.importToMod(picked, "assets/tilesets/" .. base, function(rel)
            e.image = rel
            local Preview = require("Preview")
            local img = Preview.image(S, rel)
            if img then
              e.imageWidth = img:getWidth()
              e.imageHeight = img:getHeight()
            end
          end)
        end)
    end
  end)
  row("Walkable", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.walkable)
    local v = RegList.field(App, "ts_walk", fx, fy_, fw, fh_, cur, "1,16,19")
    if v ~= cur then editList("walkable", csvNums(v)) end
  end)
  Kit.text("micro", "Passable 8x8 tile ids. Anything else is solid (collision).",
    viewX + labelW, fy - 4 * s, PAL.faint)
  fy = fy + 12 * s
  row("Grass tile", function(fx, fy_, fw, fh_)
    local cur = rec.grassTile ~= nil and tostring(rec.grassTile) or ""
    local v = RegList.field(App, "ts_grass", fx, fy_, fw, fh_, cur, "82")
    if v ~= cur then
      local e = ensure()
      e.grassTile = tonumber(v)
      syncTilesetLive(S, id, e)
    end
  end)
  row("Water tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.waterTiles)
    local v = RegList.field(App, "ts_water", fx, fy_, fw, fh_, cur, "20")
    if v ~= cur then editList("waterTiles", csvNums(v)) end
  end)
  row("Shore tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.shoreTiles)
    local v = RegList.field(App, "ts_shore", fx, fy_, fw, fh_, cur, "50,72")
    if v ~= cur then editList("shoreTiles", csvNums(v)) end
  end)
  row("Door tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.doorTiles)
    local v = RegList.field(App, "ts_door", fx, fy_, fw, fh_, cur, "27")
    if v ~= cur then editList("doorTiles", csvNums(v)) end
  end)
  row("Warp tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.warpTiles)
    local v = RegList.field(App, "ts_warp", fx, fy_, fw, fh_, cur, "19,27")
    if v ~= cur then editList("warpTiles", csvNums(v)) end
  end)
  row("Counter tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.counterTiles)
    local v = RegList.field(App, "ts_ctr", fx, fy_, fw, fh_, cur, "18")
    if v ~= cur then editList("counterTiles", csvNums(v)) end
  end)
  row("Animation", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.animation or "TILEANIM_NONE")
    local v = RegList.field(App, "ts_anim", fx, fy_, fw, fh_, cur, "TILEANIM_NONE")
    if v ~= cur then
      local e = ensure(); e.animation = v; syncTilesetLive(S, id, e)
    end
  end)
  row("TrueColor", function(fx, fy_, fw, fh_)
    local on = rec.trueColor and true or false
    if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
      local e = ensure()
      e.trueColor = not on
      if not e.trueColor then e.trueColor = nil end
      syncTilesetLive(S, id, e)
      App.markDirty()
    end
  end)
  Kit.text("micro",
    string.format("%d blocks · paint flags below or edit tile-id lists",
      #(rec.blocks or {})),
    viewX, fy, PAL.faint)
  fy = fy + 18 * s
  -- Refresh rec after possible ensure() so painter sees owned lists.
  rec = owned and proj[id] or rec
  fy = drawTileFlagPainter(S, App, rec, ensure, id, viewX, fy, viewW, s, tsPal)
  FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    proj[id] = nil; App.markDirty()
  end
end

return Gfx
