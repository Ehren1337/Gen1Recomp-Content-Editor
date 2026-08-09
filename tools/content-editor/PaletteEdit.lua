-- Before editing palette colors from a Pokemon / Item / Trainer / Map,
-- ask whether to clone a custom palette for that entity or edit the shared one.

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
local ColorWheel = require("ColorWheel")
local PAL = Theme.PAL

local PaletteEdit = {}

local KIND_LABEL = {
  pokemon = "Pokémon",
  item = "item",
  trainer = "trainer",
  map = "map",
  tileset = "tileset",
  sprite = "sprite",
}

local KIND_PREFIX = {
  pokemon = "PAL_PK_",
  item = "PAL_IT_",
  trainer = "PAL_TR_",
  map = "PAL_MAP_",
  tileset = "PAL_TS_",
  sprite = "PAL_SP_",
}

local function sanitizeId(id)
  return tostring(id or "CUSTOM"):upper():gsub("[^A-Z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

function PaletteEdit.suggestedId(kind, entityId)
  local prefix = KIND_PREFIX[kind] or "PAL_MOD_"
  return prefix .. sanitizeId(entityId)
end

function PaletteEdit.isOpen(S)
  return S and S.paletteEditAsk ~= nil
end

function PaletteEdit.close(S)
  if S then S.paletteEditAsk = nil end
  Kit.blur()
  Kit.suppressMouseUntilUp()
end

-- True when this palette is already a private clone for the entity.
function PaletteEdit.isCustomFor(S, kind, entityId, paletteId)
  if type(paletteId) ~= "string" or paletteId == "" then return false end
  if paletteId == PaletteEdit.suggestedId(kind, entityId) then return true end
  local rec = S and S.project and S.project.palettes and S.project.palettes[paletteId]
  local owner = rec and rec._for
  return type(owner) == "table"
    and owner.kind == kind
    and owner.id == entityId
end

local function cloneColors(src)
  local colors = {}
  for i = 1, 4 do
    local c = (src and src[i]) or { 248, 248, 248 }
    colors[i] = {
      math.max(0, math.min(255, tonumber(c[1]) or 0)),
      math.max(0, math.min(255, tonumber(c[2]) or 0)),
      math.max(0, math.min(255, tonumber(c[3]) or 0)),
    }
  end
  return colors
end

-- Create (or reuse) a private palette for the entity; assign via opts.assign.
function PaletteEdit.makeCustom(S, opts)
  opts = opts or {}
  local kind = opts.kind
  local entityId = opts.entityId
  local sharedId = opts.paletteId
  local customId = PaletteEdit.suggestedId(kind, entityId)
  S.project.palettes = S.project.palettes or {}
  if not S.project.palettes[customId] then
    local src = Preview.paletteColors(S, sharedId)
      or Preview.paletteColors(S, customId)
      or {
        { 248, 248, 248 }, { 168, 168, 168 }, { 88, 88, 88 }, { 16, 16, 16 },
      }
    S.project.palettes[customId] = {
      colors = cloneColors(src),
      _isNew = true,
      _for = { kind = kind, id = entityId },
    }
  else
    local rec = S.project.palettes[customId]
    rec._for = { kind = kind, id = entityId }
    if not rec.colors then
      Preview.ensureProjectPalette(S, customId)
    end
  end
  if opts.assign then opts.assign(customId) end
  return customId
end

-- opts:
--   kind, entityId, entityLabel?, paletteId,
--   assign(paletteId),  -- set entity field + markDirty / mutate
--   then(paletteId),    -- continue (open color wheel / apply rgb)
--   forceAsk?           -- ask even if already custom (unused)
function PaletteEdit.request(S, opts)
  opts = opts or {}
  if type(opts.thenFn) ~= "function" and type(opts["then"]) == "function" then
    opts.thenFn = opts["then"]
  end
  local thenFn = opts.thenFn or opts.continue
  if type(thenFn) ~= "function" then return end
  local kind = opts.kind
  local entityId = opts.entityId
  local paletteId = opts.paletteId
  if type(paletteId) ~= "string" or paletteId == "" then
    paletteId = "MEWMON"
  end

  if PaletteEdit.isCustomFor(S, kind, entityId, paletteId) then
    Preview.ensureProjectPalette(S, paletteId)
    thenFn(paletteId)
    return
  end

  S.paletteEditAsk = {
    kind = kind,
    entityId = entityId,
    entityLabel = opts.entityLabel or entityId,
    paletteId = paletteId,
    assign = opts.assign,
    thenFn = thenFn,
    -- Swallow the click that opened this modal (same frame would hit the
    -- dimmed backdrop and close instantly — looks like a flash).
    opened = true,
  }
end

function PaletteEdit.keypressed(S, key)
  if not PaletteEdit.isOpen(S) then return false end
  if key == "escape" then
    PaletteEdit.close(S)
    return true
  end
  return false
end

function PaletteEdit.draw(S, x, y, w, h)
  local ask = S and S.paletteEditAsk
  if not ask then return end
  local s = Kit.scale
  if ask.opened then
    ask.opened = nil
    Kit.mouseClicked = false
  end

  Theme.col(PAL.bgBot or PAL.card, 0.72)
  love.graphics.rectangle("fill", x, y, w, h)

  local boxW = math.min(w - 32 * s, 460 * s)
  local boxH = 220 * s
  local bx = x + (w - boxW) / 2
  local by = y + (h - boxH) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(bx, by, boxW, boxH) then
    PaletteEdit.close(S)
    return
  end

  Kit.card(bx, by, boxW, boxH, 12 * s)
  local pad = 16 * s
  local kindLabel = KIND_LABEL[ask.kind] or "entry"
  Kit.caption(bx + pad, by + pad, "Custom palette?")
  Kit.text("small",
    string.format("Edit colors for %s “%s”?", kindLabel, tostring(ask.entityLabel)),
    bx + pad, by + pad + 28 * s, PAL.text)
  Kit.text("micro",
    string.format("Shared palette: %s", tostring(ask.paletteId)),
    bx + pad, by + pad + 52 * s, PAL.muted)
  Kit.text("micro",
    "Custom = new palette only for this " .. kindLabel
      .. ". Shared = change " .. tostring(ask.paletteId) .. " everywhere.",
    bx + pad, by + pad + 72 * s, PAL.faint)

  local btnH = 34 * s
  local btnY = by + boxH - pad - btnH
  local gap = 8 * s
  local btnW = (boxW - pad * 2 - gap * 2) / 3

  if Kit.button(bx + pad, btnY, btnW, btnH, "Cancel", { kind = "ghost" }) then
    PaletteEdit.close(S)
    return
  end
  if Kit.button(bx + pad + btnW + gap, btnY, btnW, btnH, "Edit shared", {
      kind = "ghost",
      tooltip = "Override " .. tostring(ask.paletteId) .. " for the whole mod",
    }) then
    local sharedId = ask.paletteId
    local thenFn = ask.thenFn
    Preview.ensureProjectPalette(S, sharedId)
    PaletteEdit.close(S)
    if thenFn then thenFn(sharedId) end
    return
  end
  if Kit.button(bx + pad + (btnW + gap) * 2, btnY, btnW, btnH, "Make custom", {
      kind = "primary",
      tooltip = "Clone a private palette for this " .. kindLabel,
    }) then
    local thenFn = ask.thenFn
    local customId = PaletteEdit.makeCustom(S, ask)
    PaletteEdit.close(S)
    local okApp, App = pcall(require, "App")
    if okApp and App.markDirty then App.markDirty() end
    if thenFn then thenFn(customId) end
  end
end

-- Inline C1–C4 swatches + RGB fields + color wheel (Pokemon / Items / Trainers).
-- opts: kind, entityId, entityLabel, paletteId, assign(id), App,
--       x, y, labelW, fieldW, fh, fieldPrefix
-- Returns the y below the rows.
function PaletteEdit.drawColorRows(S, opts)
  opts = opts or {}
  local s = Kit.scale
  local App = opts.App
  local kind = opts.kind
  local entityId = opts.entityId
  local palId = opts.paletteId
  if type(palId) ~= "string" or palId == "" then palId = "MEWMON" end
  local colors = Preview.paletteColors(S, palId) or {
    { 248, 248, 248 }, { 168, 168, 168 }, { 88, 88, 88 }, { 16, 16, 16 },
  }
  local x = opts.x or 0
  local fy = opts.y or 0
  local labelW = opts.labelW or (100 * s)
  local fieldW = opts.fieldW or (200 * s)
  local fh = opts.fh or (28 * s)
  local prefix = opts.fieldPrefix or ("pal_" .. tostring(kind) .. "_")
  local custom = PaletteEdit.isCustomFor(S, kind, entityId, palId)

  Kit.text("micro",
    "colors · " .. tostring(palId)
      .. (custom and " (custom)" or "  (click swatch = wheel)"),
    x + labelW, fy, PAL.faint)
  fy = fy + 14 * s

  local function applySlot(pal, slot, rgb)
    local rec = Preview.ensureProjectPalette(S, pal)
    if not rec then return end
    rec.colors = rec.colors or {}
    rec.colors[slot] = {
      math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
      math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
      math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
    }
    Preview.invalidate()
    if App and App.markDirty then App.markDirty() end
  end

  local function editSlot(slot, rgbOrOpenWheel)
    PaletteEdit.request(S, {
      kind = kind,
      entityId = entityId,
      entityLabel = opts.entityLabel or entityId,
      paletteId = palId,
      assign = opts.assign,
      thenFn = function(resolved)
        palId = resolved
        if rgbOrOpenWheel == true then
          local cols = Preview.paletteColors(S, resolved) or colors
          ColorWheel.open(S, {
            title = "C" .. slot .. " · " .. tostring(resolved),
            color = cols[slot] or colors[slot],
            onChange = function(rgb) applySlot(resolved, slot, rgb) end,
            onApply = function(rgb) applySlot(resolved, slot, rgb) end,
          })
        else
          applySlot(resolved, slot, rgbOrOpenWheel)
        end
      end,
    })
  end

  for i = 1, 4 do
    local c = colors[i] or { 0, 0, 0 }
    local cur = string.format("%d,%d,%d", c[1] or 0, c[2] or 0, c[3] or 0)
    Kit.text("small", "C" .. i, x, fy + 6 * s, PAL.caption)
    local sw = 28 * s
    love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
      (c[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", x + labelW, fy + 2 * s, sw, fh - 4 * s,
      4 * s, 4 * s)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("line", x + labelW, fy + 2 * s, sw, fh - 4 * s,
      4 * s, 4 * s)
    love.graphics.setColor(1, 1, 1, 1)
    if Kit.press(x + labelW, fy + 2 * s, sw, fh - 4 * s) then
      editSlot(i, true)
    end
    local v = Kit.textfield(prefix .. i, x + labelW + sw + 8 * s, fy,
      math.max(40 * s, fieldW - sw - 8 * s), fh, cur, "r,g,b")
    if v ~= cur then
      local r, g, b = tostring(v):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
      if r then editSlot(i, { tonumber(r), tonumber(g), tonumber(b) }) end
    end
    fy = fy + fh + 6 * s
  end
  return fy + 2 * s
end

return PaletteEdit
