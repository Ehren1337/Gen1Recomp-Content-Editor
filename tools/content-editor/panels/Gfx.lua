-- GFX tab: palettes, overworld sprites, tilesets.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local ColorWheel = require("ColorWheel")
local Autocomplete = require("Autocomplete")
local ModIO = require("ModIO")
local SpriteUtil = require("SpriteUtil")
local MapLoader = require("src.world.MapLoader")
local PAL = Theme.PAL

local Gfx = {}

local MODES = {
  { id = "palettes", label = "Palettes", tip = "SGB/GBC color palettes (4 colors)" },
  { id = "sprites", label = "Sprites", tip = "Overworld sprite sheets" },
  { id = "tilesets", label = "Tilesets",
    tip = "Tileset editor: import PNG, paint flags, compose 4×4 blocks" },
}

local TILE_PX = 8  -- Gen1 tileset sheet cells are 8x8
local FLAG_MODES = {
  { id = "walk", label = "Walk", tip = "Passage O — passable (in walkable list)" },
  { id = "solid", label = "Solid", tip = "Passage X — blocked (not walkable)" },
  { id = "water", label = "Water", tip = "Surfable water tile" },
  { id = "grass", label = "Grass", tip = "Tall grass / bush (wild encounters)" },
  { id = "shore", label = "Shore", tip = "Shore / beach (surf edge)" },
  { id = "door", label = "Door", tip = "Door tile (doorTiles)" },
  { id = "warp", label = "Warp", tip = "Warp / carpet tile (warpTiles)" },
  { id = "counter", label = "Counter", tip = "Shop counter tile (counterTiles)" },
}
local TILE_ANIMS = {
  "TILEANIM_NONE",
  "TILEANIM_WATER",
  "TILEANIM_WATER_FLOWER",
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

local function rebuildBlocksFromSheet(rec, img)
  if not (rec and img) then return end
  local tw = math.max(1, math.floor(img:getWidth() / TILE_PX))
  local th = math.max(1, math.floor(img:getHeight() / TILE_PX))
  local tileCount = tw * th
  local nBlocks = math.max(1, math.floor(tileCount / 16))
  local blocks = {}
  for b = 0, nBlocks - 1 do
    local row = {}
    for i = 0, 15 do row[i + 1] = b * 16 + i end
    blocks[b + 1] = row
  end
  rec.blocks = blocks
  rec.tilesPerRow = tw
  rec.imageWidth = img:getWidth()
  rec.imageHeight = img:getHeight()
end

-- Clickable 8x8 sheet: paint walk / solid / water / grass / shore / door / warp / counter.
-- Returns the Y after the painter (for FormPane content height).
-- opts.onTileClick(tid) — optional override (block editor pick); skips flag paint.
local function drawTileFlagPainter(S, App, rec, ensureFn, id, x, y, w, s, palName, opts)
  opts = opts or {}
  Kit.text("micro",
    opts.title or "TILE FLAGS (sheet — map Passage paint is on Maps)",
    x, y, PAL.caption)
  y = y + 14 * s
  if not opts.pickOnly then
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
      "green=walk  red=solid  blue=water  cyan=shore  magenta=grass  yellow=door  orange=warp  purple=counter",
      x, y, PAL.faint)
    y = y + 14 * s
  end

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
  local door = {}
  for _, t in ipairs(rec.doorTiles or {}) do door[t] = true end
  local warp = {}
  for _, t in ipairs(rec.warpTiles or {}) do warp[t] = true end
  local counter = {}
  for _, t in ipairs(rec.counterTiles or {}) do counter[t] = true end
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

    if not opts.pickOnly then
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
        love.graphics.setColor(0.95, 0.2, 0.85, 0.45)
        love.graphics.rectangle("fill", tx, ty, cell, cell)
        love.graphics.setColor(1, 0.35, 0.95, 1)
        love.graphics.rectangle("line", tx + 1, ty + 1, cell - 2, cell - 2)
      end
      if door[tid] then
        love.graphics.setColor(0.95, 0.85, 0.15, 0.45)
        love.graphics.rectangle("line", tx + 1, ty + 1, cell - 2, cell - 2)
      end
      if warp[tid] then
        love.graphics.setColor(1, 0.55, 0.1, 0.5)
        love.graphics.rectangle("line", tx + 2, ty + 2, cell - 4, cell - 4)
      end
      if counter[tid] then
        love.graphics.setColor(0.7, 0.3, 0.95, 0.45)
        love.graphics.rectangle("fill", tx, ty + cell * 0.65, cell, cell * 0.35)
      end
    end

    if Kit.press(tx, ty, cell, cell) then
      if opts.onTileClick then
        opts.onTileClick(tid)
      else
        local e = ensureFn()
        e.walkable = e.walkable or {}
        e.waterTiles = e.waterTiles or {}
        e.shoreTiles = e.shoreTiles or {}
        e.doorTiles = e.doorTiles or {}
        e.warpTiles = e.warpTiles or {}
        e.counterTiles = e.counterTiles or {}
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
        elseif mode == "door" then
          listSet(e.doorTiles, tid, listIndex(e.doorTiles, tid) == nil)
        elseif mode == "warp" then
          listSet(e.warpTiles, tid, listIndex(e.warpTiles, tid) == nil)
        elseif mode == "counter" then
          listSet(e.counterTiles, tid, listIndex(e.counterTiles, tid) == nil)
        end
        syncTilesetLive(S, id, e)
        App.markDirty()
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  Kit.popClip()

  return y + gridH + 8 * s
end

-- Visual Gen1 block composer: pick a block, edit its 4×4 tile ids from the sheet.
local function drawBlockEditor(S, App, rec, ensureFn, id, x, y, w, s, palName)
  Kit.text("micro", "BLOCKS (each map cell = one 4×4 block of 8×8 tiles)", x, y, PAL.caption)
  y = y + 14 * s

  local ePeek = rec
  local blocks = ePeek.blocks or {}
  local nBlocks = #blocks
  S.gfxBlockEditId = math.max(0, math.min(math.max(0, nBlocks - 1),
    tonumber(S.gfxBlockEditId) or 0))

  local btnH = 24 * s
  if Kit.button(x, y, 88 * s, btnH, "+ Block", {
      kind = "good", font = "small",
      tooltip = "Append a new 4×4 block (all tile 0)",
    }) then
    local e = ensureFn()
    e.blocks = e.blocks or {}
    local row = {}
    for i = 1, 16 do row[i] = 0 end
    e.blocks[#e.blocks + 1] = row
    S.gfxBlockEditId = #e.blocks - 1
    syncTilesetLive(S, id, e)
    App.markDirty()
  end
  if Kit.button(x + 94 * s, y, 88 * s, btnH, "- Last", {
      kind = "danger", font = "small",
      tooltip = "Remove the last block",
    }) and nBlocks > 1 then
    local e = ensureFn()
    table.remove(e.blocks, #e.blocks)
    S.gfxBlockEditId = math.min(S.gfxBlockEditId or 0, #e.blocks - 1)
    syncTilesetLive(S, id, e)
    App.markDirty()
  end
  if Kit.button(x + 188 * s, y, 120 * s, btnH, "Rebuild sheet", {
      kind = "ghost", font = "small",
      tooltip = "Rebuild sequential blocks from PNG size (16 tiles each)",
    }) then
    local e = ensureFn()
    local img = Preview.image(S, e.image)
    if img then
      rebuildBlocksFromSheet(e, img)
      S.gfxBlockEditId = 0
      syncTilesetLive(S, id, e)
      App.markDirty()
      S.status = "Rebuilt " .. #e.blocks .. " blocks from sheet"
    else
      S.status = "No tileset image — Browse a PNG first"
    end
  end
  y = y + btnH + 8 * s

  local live = (S.project.tilesets and S.project.tilesets[id]) or rec
  blocks = live.blocks or {}
  nBlocks = #blocks
  if nBlocks == 0 then
    Kit.text("micro", "No blocks yet — Rebuild sheet or + Block", x, y, PAL.muted)
    return y + 20 * s
  end

  local thumb = 36 * s
  local gap = 4 * s
  local perRow = math.max(1, math.floor((w + gap) / (thumb + gap)))
  local img = Preview.image(S, live.image)
  local bid = math.max(0, math.min(nBlocks - 1, tonumber(S.gfxBlockEditId) or 0))
  S.gfxBlockEditId = bid
  local maxRows = 3
  local startRow = tonumber(S.gfxBlockStripRow) or 0
  local totalRows = math.max(1, math.ceil(nBlocks / perRow))
  if startRow > totalRows - 1 then startRow = math.max(0, totalRows - 1) end
  S.gfxBlockStripRow = startRow
  if Kit.chip(x + w - 70 * s, y - btnH - 8 * s, 32 * s, btnH, "^",
      false, PAL.blue, nil, "Scroll blocks up") and startRow > 0 then
    S.gfxBlockStripRow = startRow - 1
    startRow = S.gfxBlockStripRow
  end
  if Kit.chip(x + w - 34 * s, y - btnH - 8 * s, 32 * s, btnH, "v",
      false, PAL.blue, nil, "Scroll blocks down") and startRow < totalRows - maxRows then
    S.gfxBlockStripRow = startRow + 1
    startRow = S.gfxBlockStripRow
  end

  local rowsShown = math.min(maxRows, totalRows - startRow)
  local stripH = rowsShown * (thumb + gap)
  Kit.pushClip(x, y, w, stripH)
  for i = 0, nBlocks - 1 do
    local col = i % perRow
    local row = math.floor(i / perRow)
    if row < startRow or row >= startRow + rowsShown then
      -- skip
    else
      local bx = x + col * (thumb + gap)
      local by = y + (row - startRow) * (thumb + gap)
      local block = blocks[i + 1]
      Theme.col(PAL.rowBg, 1)
      love.graphics.rectangle("fill", bx, by, thumb, thumb, 3 * s, 3 * s)
      if type(block) == "table" and img then
        local tileDraw = thumb / 4
        local per = live.tilesPerRow or 16
        local iw, ih = img:getDimensions()
        local shaded = (not live.trueColor) and Preview.pushPaletteShader(S, palName)
        love.graphics.setColor(1, 1, 1, 1)
        for r = 0, 3 do
          for c = 0, 3 do
            local tid = block[r * 4 + c + 1] or 0
            if type(tid) == "number" and love.graphics.newQuad then
              local q = love.graphics.newQuad(
                (tid % per) * TILE_PX, math.floor(tid / per) * TILE_PX,
                TILE_PX, TILE_PX, iw, ih)
              love.graphics.draw(img, q, bx + c * tileDraw, by + r * tileDraw,
                0, tileDraw / TILE_PX, tileDraw / TILE_PX)
            end
          end
        end
        if shaded then Preview.popPaletteShader(shaded) end
      end
      if i == bid then
        love.graphics.setColor(0.3, 0.75, 1, 1)
        love.graphics.rectangle("line", bx, by, thumb, thumb, 3 * s, 3 * s)
      end
      if Kit.press(bx, by, thumb, thumb) then
        S.gfxBlockEditId = i
        S.gfxBlockCell = nil
      end
    end
  end
  Kit.popClip()
  love.graphics.setColor(1, 1, 1, 1)
  y = y + stripH + 6 * s

  Kit.text("micro",
    string.format("Block %d / %d — click a cell, then a sheet tile",
      bid, math.max(0, nBlocks - 1)),
    x, y, PAL.caption)
  y = y + 14 * s

  local block = blocks[bid + 1]
  if type(block) ~= "table" then
    return y + 8 * s
  end
  local cell = math.min(40 * s, math.floor((w - 8 * s) / 4))
  for r = 0, 3 do
    for c = 0, 3 do
      local ci = r * 4 + c + 1
      local cx = x + c * (cell + 2 * s)
      local cy = y + r * (cell + 2 * s)
      local tid = block[ci] or 0
      if img then
        local per = live.tilesPerRow or 16
        local iw, ih = img:getDimensions()
        local shaded = (not live.trueColor) and Preview.pushPaletteShader(S, palName)
        love.graphics.setColor(1, 1, 1, 1)
        if type(tid) == "number" and love.graphics.newQuad then
          local q = love.graphics.newQuad(
            (tid % per) * TILE_PX, math.floor(tid / per) * TILE_PX,
            TILE_PX, TILE_PX, iw, ih)
          love.graphics.draw(img, q, cx, cy, 0, cell / TILE_PX, cell / TILE_PX)
        end
        if shaded then Preview.popPaletteShader(shaded) end
      else
        Theme.col(PAL.rowBg, 1)
        love.graphics.rectangle("fill", cx, cy, cell, cell)
      end
      local selected = S.gfxBlockCell == ci
      love.graphics.setColor(selected and 0.3 or 1, selected and 0.85 or 1,
        selected and 1 or 1, selected and 1 or 0.35)
      love.graphics.rectangle("line", cx, cy, cell, cell)
      Kit.text("micro", tostring(tid), cx + 2 * s, cy + 2 * s, PAL.heading)
      if Kit.press(cx, cy, cell, cell) then
        S.gfxBlockCell = ci
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  y = y + 4 * (cell + 2 * s) + 8 * s

  if S.gfxBlockCell then
    Kit.text("micro", "Pick a tile from the sheet below for cell "
      .. tostring(S.gfxBlockCell), x, y, PAL.yellow)
    y = y + 14 * s
    y = drawTileFlagPainter(S, App, live, ensureFn, id, x, y, w, s, palName, {
      pickOnly = true,
      title = "SHEET (click to set selected block cell)",
      onTileClick = function(tid)
        local e = ensureFn()
        e.blocks = e.blocks or {}
        local b = e.blocks[(S.gfxBlockEditId or 0) + 1]
        if type(b) ~= "table" then return end
        b[S.gfxBlockCell] = tid
        syncTilesetLive(S, id, e)
        App.markDirty()
      end,
    })
  end
  return y
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
    local gbcOn = Preview.useGbcPalettes(S)
    if Kit.chip(x, modeY, 120 * s, 22 * s, gbcOn and "GBC ON" or "GBC OFF",
        gbcOn, PAL.yellow, nil,
        gbcOn and "List/resolve GBC pack palettes"
          or "ROM/cache SGB palettes only") then
      Preview.setUseGbcPalettes(S, not gbcOn)
      S.status = (not gbcOn)
        and "GBC palettes ON — pokered-gbc pack colors"
        or "GBC palettes OFF — ROM/cache SGB colors"
    end
    modeY = modeY + 28 * s
    local ids = Preview.paletteIds(S)
    local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
      "PALETTES", ids, {
        queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "paletteId",
        accent = PAL.yellow,
        isOwned = function(id) return proj[id] ~= nil end,
        footerLabel = "+ New palette",
        onFooter = function()
          local nid = "MOD_PAL"
          local n = 1
          local known = {}
          for _, pid in ipairs(Preview.paletteIds(S)) do known[pid] = true end
          while proj[nid] or data[nid] or known[nid] do
            n = n + 1; nid = "MOD_PAL_" .. n
          end
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
    if not rec and id then
      -- GBC/Yellow pack-only entry: synthesize a read-only view until edited.
      local cols = Preview.paletteColors(S, id)
      if cols then rec = { colors = cols } end
    end
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
      local sw = 28 * s
      local c = colors[i] or { 40, 40, 40 }
      love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
        (c[3] or 0) / 255, 1)
      love.graphics.rectangle("fill", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
      love.graphics.setColor(1, 1, 1, 0.35)
      love.graphics.rectangle("line", viewX + 36 * s, fy + 2 * s, sw, 24 * s, 4 * s, 4 * s)
      love.graphics.setColor(1, 1, 1, 1)
      if Kit.press(viewX + 36 * s, fy + 2 * s, sw, 24 * s) then
        local slot = i
        ColorWheel.open(S, {
          title = "C" .. slot .. " · " .. tostring(id),
          color = c,
          onChange = function(rgb)
            local e = ensure()
            e.colors = e.colors or colors
            e.colors[slot] = {
              math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
            }
            colors[slot] = e.colors[slot]
            Preview.invalidate()
          end,
          onApply = function(rgb)
            local e = ensure()
            e.colors = e.colors or colors
            e.colors[slot] = {
              math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
              math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
            }
            colors[slot] = e.colors[slot]
            Preview.invalidate()
          end,
        })
      end
      local v = RegList.field(App, "pal_c_" .. i, viewX + 36 * s + sw + 8 * s, fy,
        viewW - 36 * s - sw - 8 * s, 28 * s, fmtRgb(colors[i]), "r,g,b")
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
          local nid = SpriteUtil.createNew(S)
          if nid then
            S.spriteEditId = nid
            App.markDirty()
          end
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
              -- Full-color PNG imports usually need TrueColor.
              e.trueColor = true
              Preview.invalidate()
              App.markDirty()
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
      if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow,
          nil, "YES = raw PNG colors (skip SGB palette remap)") then
        local e = ensure()
        e.trueColor = not on
        if not e.trueColor then e.trueColor = nil end
        Preview.invalidate()
        App.markDirty()
      end
      Kit.text("micro", on and "raw PNG" or "SGB remap",
        fx + 90 * s, fy_ + 8 * s, PAL.faint)
    end)
    row("Palette src", function(fx, fy_, fw, fh_)
      if rec.trueColor then
        Kit.text("small", "(ignored — TrueColor)", fx, fy_ + 6 * s, PAL.faint)
        return
      end
      local cur = rec.paletteSource or ""
      local v = RegList.suggestField(App, S, "spr_ps", fx, fy_,
        math.max(40 * s, fw - 88 * s), fh_, cur, "optional",
        function() return Autocomplete.paletteIds(S) end)
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
      proj[id] = nil
      SpriteUtil.invalidateIdCache(S)
      if S.spriteEditId == id then S.spriteEditId = nil end
      App.markDirty()
    end
    return
  end

  -- tilesets (full editor: image, flags, blocks)
  local proj = S.project.tilesets
  local data = (S.data and S.data.tilesets) or {}
  local ids = RegList.mergeIds(proj, data)

  local function createBlankTileset()
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
      id = nid,
      image = "assets/tilesets/" .. nid:lower() .. ".png",
      tilesPerRow = 16, blocks = blocks, walkable = { 1 },
      waterTiles = {}, shoreTiles = {},
      doorTiles = {}, warpTiles = {}, counterTiles = {},
      animation = "TILEANIM_NONE", _isNew = true,
    }
    syncTilesetLive(S, nid, proj[nid])
    S.tilesetEditId = nid
    S.gfxTilesetPane = "flags"
    App.markDirty()
    S.status = "Created " .. nid .. " — Browse a PNG, then paint flags / blocks"
  end

  local function createTilesetFromPng()
    App.pickFile("Tileset PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
      function(picked)
        State.ensureProjectFields(S.project)
        local base = App.assetBaseName(picked, "tiles.png")
        if not base:lower():match("%.png$") then base = base .. ".png" end
        local stem = base:gsub("%.[Pp][Nn][Gg]$", ""):gsub("[^%w_]", "_"):upper()
        if stem == "" then stem = "MOD_TILES" end
        local nid, n = stem, 1
        while proj[nid] or data[nid] do
          n = n + 1
          nid = stem .. "_" .. n
        end
        App.importToMod(picked, "assets/tilesets/" .. base, function(rel)
          local e = {
            id = nid, image = rel, tilesPerRow = 16, blocks = {},
            walkable = { 1 }, waterTiles = {}, shoreTiles = {},
            doorTiles = {}, warpTiles = {}, counterTiles = {},
            animation = "TILEANIM_NONE", _isNew = true,
          }
          local img = Preview.image(S, rel)
          if img then rebuildBlocksFromSheet(e, img) end
          proj[nid] = e
          syncTilesetLive(S, nid, e)
          S.tilesetEditId = nid
          S.gfxTilesetPane = "flags"
          App.markDirty()
          S.status = "Imported tileset " .. nid
        end)
      end)
  end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
    "TILESETS", ids, {
      queryKey = "gfxQuery", offsetKey = "gfxListOffset", selKey = "tilesetEditId",
      accent = PAL.blue,
      isOwned = function(id) return proj[id] ~= nil end,
      footerLabel = "+ New blank",
      onFooter = createBlankTileset,
    })
  -- Second create action above the list footer area (form column).
  if Kit.button(formX + formW - 132 * s, modeY, 128 * s, 26 * s, "New from PNG", {
      kind = "accent", font = "small",
      tooltip = "Import a PNG into assets/tilesets/ and build blocks",
    }) then
    createTilesetFromPng()
  end
  if not S.tilesetEditId then S.tilesetEditId = shown[1] end
  local id = S.tilesetEditId
  local owned = id and proj[id] ~= nil
  local rec = owned and proj[id] or data[id]
  if not id or not rec then
    Kit.emptyBox(formX, listY, formW, listH, "No tilesets — New blank or New from PNG")
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
    copy.doorTiles = copy.doorTiles or {}
    copy.warpTiles = copy.warpTiles or {}
    copy.counterTiles = copy.counterTiles or {}
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
  Kit.caption(formX, modeY, "TILESET EDITOR · "
    .. id .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "gfxFormScroll", "ts|" .. id, owned and 44 * s or 12 * s)
  local contentTop = fy
  local prev = 72 * s
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

  -- Flags vs Blocks pane switch
  S.gfxTilesetPane = S.gfxTilesetPane or "flags"
  do
    local pane = S.gfxTilesetPane
    if Kit.chip(viewX, fy, 70 * s, 22 * s, "Flags", pane == "flags", PAL.green,
        nil, "Paint walk/solid/water/door/warp/counter on the sheet") then
      S.gfxTilesetPane = "flags"
    end
    if Kit.chip(viewX + 76 * s, fy, 70 * s, 22 * s, "Blocks", pane == "blocks", PAL.blue,
        nil, "Compose Gen1 4×4 blocks from sheet tiles") then
      S.gfxTilesetPane = "blocks"
    end
    Kit.text("micro", string.format("%d blocks", #(rec.blocks or {})),
      viewX + 156 * s, fy + 4 * s, PAL.faint)
    fy = fy + 28 * s
  end

  if not rec.trueColor then
    row("Preview pal", function(fx, fy_, fw, fh_)
      if Kit.button(fx, fy_, math.min(fw, 160 * s), fh_,
          Kit.ellipsize("small", tsPal, math.min(fw, 160 * s) - 8 * s),
          { kind = "ghost", tooltip = "Cycle SGB palette used for this PNG preview" })
          and #tsPals > 0 then
        local idx = 1
        for i, pid in ipairs(tsPals) do
          if pid == tsPal then idx = i; break end
        end
        S.gfxTilesetPalPreview = tsPals[(idx % #tsPals) + 1]
      end
      Preview.drawNamedSwatches(S, S.gfxTilesetPalPreview,
        fx + fw - 80 * s, fy_ + (fh_ - 14 * s) / 2, 80 * s, 14 * s)
    end)
  end
  if Preview.useGbcPalettes(S) and Preview.hasTilesetGbcGroups(S, id) then
    local names = Preview.GBC_GROUP_NAMES
    local groups = Preview.tilesetGbcGroups(S, id)
    local ownedGbc = Preview.tilesetGbcGroupsOwned(S, id)
    Kit.text("micro", "GBC BG groups"
        .. (ownedGbc and " (mod)" or " (vanilla)"),
      viewX, fy, PAL.caption)
    fy = fy + 14 * s
    local sw = 20 * s
    local gap = 3 * s
    for gi = 1, 8 do
      local label = names[gi] or ("G" .. (gi - 1))
      Kit.text("micro", label, viewX, fy + 4 * s, PAL.muted)
      local g = groups and groups[gi]
      local bx = viewX + 48 * s
      for ci = 1, 4 do
        local c = (g and g[ci]) or { 40, 40, 40 }
        local sx = bx + (ci - 1) * (sw + gap)
        love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
          (c[3] or 0) / 255, 1)
        love.graphics.rectangle("fill", sx, fy, sw, 18 * s, 3 * s, 3 * s)
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.rectangle("line", sx, fy, sw, 18 * s, 3 * s, 3 * s)
        love.graphics.setColor(1, 1, 1, 1)
        if Kit.press(sx, fy, sw, 18 * s) then
          local groupI, colorI, tid = gi, ci, id
          ColorWheel.open(S, {
            title = label .. " C" .. colorI .. " · " .. tostring(tid),
            color = c,
            onChange = function(rgb)
              Preview.ensureTilesetGbcGroups(S, tid)
              local ow = S.project.gbcWorld.groupColors[tid]
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
              Preview.setTilesetGbcGroupColor(S, tid, groupI, colorI, rgb)
              App.markDirty()
              S.status = "GBC " .. label .. " C" .. colorI .. " updated"
            end,
          })
        end
      end
      fy = fy + 22 * s
    end
    if ownedGbc then
      if Kit.button(viewX, fy, 100 * s, fh, "Revert GBC", {
          kind = "danger",
          tooltip = "Clear mod overrides for this tileset's 8 BG groups",
        }) then
        Preview.clearTilesetGbcGroups(S, id)
        App.markDirty()
      end
      fy = fy + fh + 8 * s
    else
      fy = fy + 6 * s
    end
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
          if not e then e = ensure() end
          local base = App.assetBaseName(picked, "tiles.png")
          if not base:lower():match("%.png$") then base = base .. ".png" end
          App.importToMod(picked, "assets/tilesets/" .. base, function(rel)
            e.image = rel
            local img = Preview.image(S, rel)
            if img then
              e.imageWidth = img:getWidth()
              e.imageHeight = img:getHeight()
              if not e.blocks or #e.blocks == 0 then
                rebuildBlocksFromSheet(e, img)
              end
            end
            syncTilesetLive(S, tid, e)
          end)
        end)
    end
  end)
  row("Animation", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.animation or "TILEANIM_NONE")
    local mx = fx
    for _, anim in ipairs(TILE_ANIMS) do
      local label = anim:gsub("^TILEANIM_", "")
      local bw = Kit.textWidth("micro", label) + 12 * s
      if Kit.chip(mx, fy_ + 2 * s, bw, fh_ - 4 * s, label, cur == anim, PAL.blue) then
        local e = ensure()
        e.animation = anim
        syncTilesetLive(S, id, e)
        App.markDirty()
      end
      mx = mx + bw + 3 * s
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

  rec = owned and proj[id] or rec
  if S.gfxTilesetPane == "blocks" then
    fy = drawBlockEditor(S, App, rec, ensure, id, viewX, fy, viewW, s, tsPal)
  else
    -- Compact CSV lists (advanced) above the painter
    row("Walkable", function(fx, fy_, fw, fh_)
      local cur = joinNums(rec.walkable)
      local v = RegList.field(App, "ts_walk", fx, fy_, fw, fh_, cur, "1,16,19")
      if v ~= cur then editList("walkable", csvNums(v)) end
    end)
    row("Grass tile", function(fx, fy_, fw, fh_)
      local cur = rec.grassTile ~= nil and tostring(rec.grassTile) or ""
      local v = RegList.field(App, "ts_grass", fx, fy_, fw, fh_, cur, "82")
      if v ~= cur then
        local e = ensure()
        e.grassTile = tonumber(v)
        syncTilesetLive(S, id, e)
      end
    end)
    row("Water / Shore", function(fx, fy_, fw, fh_)
      local half = math.floor((fw - 6 * s) / 2)
      local curW = joinNums(rec.waterTiles)
      local vW = RegList.field(App, "ts_water", fx, fy_, half, fh_, curW, "20")
      if vW ~= curW then editList("waterTiles", csvNums(vW)) end
      local curS = joinNums(rec.shoreTiles)
      local vS = RegList.field(App, "ts_shore", fx + half + 6 * s, fy_, half, fh_, curS, "50")
      if vS ~= curS then editList("shoreTiles", csvNums(vS)) end
    end)
    row("Door / Warp", function(fx, fy_, fw, fh_)
      local half = math.floor((fw - 6 * s) / 2)
      local curD = joinNums(rec.doorTiles)
      local vD = RegList.field(App, "ts_door", fx, fy_, half, fh_, curD, "27")
      if vD ~= curD then editList("doorTiles", csvNums(vD)) end
      local curW = joinNums(rec.warpTiles)
      local vW = RegList.field(App, "ts_warp", fx + half + 6 * s, fy_, half, fh_, curW, "19")
      if vW ~= curW then editList("warpTiles", csvNums(vW)) end
    end)
    row("Counter", function(fx, fy_, fw, fh_)
      local cur = joinNums(rec.counterTiles)
      local v = RegList.field(App, "ts_ctr", fx, fy_, fw, fh_, cur, "18")
      if v ~= cur then editList("counterTiles", csvNums(v)) end
    end)
    rec = owned and proj[id] or rec
    fy = drawTileFlagPainter(S, App, rec, ensure, id, viewX, fy, viewW, s, tsPal)
  end
  FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    local dropped = proj[id]
    proj[id] = nil
    if S.data and S.data.tilesets and S.data.tilesets[id] == dropped then
      local bak = S._vanillaTilesetBackup and S._vanillaTilesetBackup[id]
      S.data.tilesets[id] = bak
    elseif S.data and S.data.tilesets and type(S.data.tilesets[id]) == "table"
        and S.data.tilesets[id]._isNew then
      S.data.tilesets[id] = nil
    end
    if S.tilesetEditId == id then S.tilesetEditId = nil end
    MapLoader.invalidateAll()
    App.markDirty()
  end
end

return Gfx
