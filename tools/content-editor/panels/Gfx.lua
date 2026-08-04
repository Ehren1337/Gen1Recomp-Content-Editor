-- GFX tab: palettes, overworld sprites, tilesets.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local ModIO = require("ModIO")
local PAL = Theme.PAL

local Gfx = {}

local MODES = {
  { id = "palettes", label = "Palettes", tip = "SGB/GBC color palettes (4 colors)" },
  { id = "sprites", label = "Sprites", tip = "Overworld sprite sheets" },
  { id = "tilesets", label = "Tilesets", tip = "Walkable / door / warp tile lists" },
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
      if k == "walkable" or k == "doorTiles" or k == "warpTiles" or k == "counterTiles" then
        local a = {}
        for i = 1, #(v or {}) do a[i] = v[i] end
        copy[k] = a
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
    copy._isNew = false
    proj[id] = copy
    owned = true
    App.markDirty()
    return copy
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
    if v ~= cur then ensure().walkable = csvNums(v) end
  end)
  row("Door tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.doorTiles)
    local v = RegList.field(App, "ts_door", fx, fy_, fw, fh_, cur, "27")
    if v ~= cur then ensure().doorTiles = csvNums(v) end
  end)
  row("Warp tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.warpTiles)
    local v = RegList.field(App, "ts_warp", fx, fy_, fw, fh_, cur, "19,27")
    if v ~= cur then ensure().warpTiles = csvNums(v) end
  end)
  row("Counter tiles", function(fx, fy_, fw, fh_)
    local cur = joinNums(rec.counterTiles)
    local v = RegList.field(App, "ts_ctr", fx, fy_, fw, fh_, cur, "18")
    if v ~= cur then ensure().counterTiles = csvNums(v) end
  end)
  row("Animation", function(fx, fy_, fw, fh_)
    local cur = tostring(rec.animation or "TILEANIM_NONE")
    local v = RegList.field(App, "ts_anim", fx, fy_, fw, fh_, cur, "TILEANIM_NONE")
    if v ~= cur then ensure().animation = v end
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
  Kit.text("micro",
    string.format("%d blocks · edit walk/door/warp lists as tile ids",
      #(rec.blocks or {})),
    viewX, fy, PAL.faint)
  fy = fy + 20 * s
  FormPane.finish(S, "gfxFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    proj[id] = nil; App.markDirty()
  end
end

return Gfx
