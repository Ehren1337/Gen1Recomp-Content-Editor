-- Shared palette picker modal for Maps / Pokemon / Trainers / Items / GFX.
-- Lists ROM-cache + GBC pack names (see Preview.paletteIds).

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
local ColorWheel = require("ColorWheel")
local PaletteEdit = require("PaletteEdit")
local PAL = Theme.PAL

local PalettePicker = {}

function PalettePicker.isOpen(S)
  return S and S.palettePicker ~= nil
end

function PalettePicker.close(S)
  if not S then return end
  S.palettePicker = nil
  Kit.blur()
end

-- opts: current, allowClear, clearLabel, title, onPick(id|nil),
--       owner = { kind, entityId, entityLabel, assign(id) } for custom-palette ask
function PalettePicker.open(S, opts)
  opts = opts or {}
  local cur = opts.current
  if cur == "" then cur = nil end
  S.palettePicker = {
    query = "",
    offset = 0,
    opened = true,
    focus = cur,
    current = cur,
    allowClear = opts.allowClear and true or false,
    clearLabel = opts.clearLabel or "(default)",
    title = opts.title or "CHOOSE PALETTE",
    onPick = opts.onPick,
    owner = opts.owner,
  }
end

function PalettePicker.keypressed(S, key)
  if not PalettePicker.isOpen(S) then return false end
  if key == "escape" then
    PalettePicker.close(S)
    return true
  end
  -- Let Kit/textfield handle typing (search). Only Esc is consumed here.
  return false
end

-- Compact row control: "Choose" button + swatches. Returns nothing.
function PalettePicker.row(S, opts)
  opts = opts or {}
  local s = Kit.scale
  local x, y, w, h = opts.x, opts.y, opts.w, opts.h
  local cur = opts.current or ""
  local effective = opts.effective or (cur ~= "" and cur) or opts.fallback
  local label = (cur ~= "" and cur) or (opts.emptyLabel or "(default)")
  local swW = 80 * s
  local btnW = math.max(72 * s, w - swW - 8 * s)
  if Kit.button(x, y, btnW, h,
      Kit.ellipsize("small", label, btnW - 8 * s), {
        kind = "accent",
        tooltip = opts.tooltip or "Pick a palette (GBC pack colors)",
      }) then
    PalettePicker.open(S, {
      current = cur ~= "" and cur or nil,
      allowClear = opts.allowClear,
      clearLabel = opts.clearLabel or opts.emptyLabel,
      title = opts.title,
      onPick = opts.onPick,
      owner = opts.owner,
    })
  end
  if effective then
    Preview.drawNamedSwatches(S, effective, x + w - swW, y + (h - 14 * s) / 2,
      swW, 14 * s)
  end
end

local function pick(S, id)
  local p = S.palettePicker
  local cb = p and p.onPick
  PalettePicker.close(S)
  if cb then cb(id) end
end

function PalettePicker.draw(S, x, y, w, h)
  local p = S and S.palettePicker
  if not p then return end
  local s = Kit.scale
  -- Swallow only the click that opened the modal so it does not also hit a
  -- row / Use button. Do NOT leave Kit.blockClicks on — that disabled search,
  -- list picks, and Accept inside this same draw.
  if p.opened then
    p.opened = nil
    Kit.mouseClicked = false
  end

  Theme.col(PAL.bgBot or PAL.card, 0.72)
  love.graphics.rectangle("fill", x, y, w, h)

  local pw = math.min(w - 24 * s, 560 * s)
  local ph = math.min(h - 24 * s, 480 * s)
  local px = x + (w - pw) / 2
  local py = y + (h - ph) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(px, py, pw, ph) then
    PalettePicker.close(S)
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, p.title or "CHOOSE PALETTE")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    PalettePicker.close(S)
    return
  end
  cy = cy + 22 * s

  local listW = math.min(260 * s, inner * 0.48)
  local prevX = cx + listW + 12 * s
  local prevW = inner - listW - 12 * s

  local qh = 28 * s
  local q = Kit.textfield("pal_pick_q", cx, cy, listW, qh, p.query or "",
    "search palettes...")
  if q ~= (p.query or "") then
    p.query = q
    p.offset = 0
  end

  local list = Preview.paletteIds(S)
  if (p.query or "") ~= "" then
    local filtered, ql = {}, p.query:lower()
    for _, id in ipairs(list) do
      if id:lower():find(ql, 1, true) then filtered[#filtered + 1] = id end
    end
    list = filtered
  end

  local footerH = 0
  if p.allowClear then footerH = 34 * s end
  local listY = cy + qh + 8 * s
  local listH = py + ph - pad - listY - footerH - 4 * s
  local rowH = 34 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(listW)
  p.offset = Kit.scroll(cx, listY, listW, listH, p.offset or 0, #list, perPage)

  if #list == 0 then
    Kit.emptyBox(cx, listY, listW, listH, "No palettes match")
  else
    local focusOk = false
    for _, id in ipairs(list) do
      if id == p.focus then focusOk = true; break end
    end
    if not focusOk then
      p.focus = list[(p.offset or 0) + 1] or list[1]
    end
    Kit.pushClip(cx, listY, innerW, listH)
    local ry = listY
    for i = (p.offset or 0) + 1, math.min(#list, (p.offset or 0) + perPage) do
      local id = list[i]
      local on = p.current == id
      local focused = p.focus == id
      if Kit.hover(cx, ry, innerW, rowH) then p.focus = id end
      if Kit.row(cx, ry, innerW, rowH, on or focused, PAL.yellow) then
        pick(S, id)
        Kit.popClip()
        return
      end
      Preview.drawNamedSwatches(S, id, cx + 6 * s, ry + (rowH - 14 * s) / 2,
        56 * s, 14 * s)
      local label = Kit.ellipsize("mono", id, math.max(8, innerW - 72 * s))
      local owned = S.project and S.project.palettes and S.project.palettes[id]
      Kit.text("mono", label, cx + 68 * s, ry + 9 * s,
        on and PAL.heading or (owned and PAL.text or PAL.muted))
      ry = ry + rowH + 3 * s
    end
    Kit.popClip()
  end
  p.offset = Kit.scrollbar(cx, listY, listW, listH, p.offset or 0, #list, perPage)

  if p.allowClear then
    local by = listY + listH + 4 * s
    if Kit.button(cx, by, listW, 28 * s, p.clearLabel or "(default)", {
        kind = "ghost",
        tooltip = "Clear authored palette (use engine default)",
      }) then
      pick(S, nil)
      return
    end
  end

  local focusId = p.focus or p.current or list[1]
  Kit.text("micro", Kit.ellipsize("micro", tostring(focusId or ""), prevW),
    prevX, listY, PAL.caption)
  local swY = listY + 18 * s
  local swH = 28 * s
  if focusId then
    Preview.drawNamedSwatches(S, focusId, prevX, swY, prevW, swH)
    local colors = Preview.paletteColors(S, focusId) or {
      { 248, 248, 248 }, { 168, 168, 168 }, { 88, 88, 88 }, { 16, 16, 16 },
    }
    local cy2 = swY + swH + 10 * s
    local owned = S.project and S.project.palettes and S.project.palettes[focusId]
    Kit.text("micro", owned and "edit colors (mod)" or "edit colors (clones into mod)",
      prevX, cy2, PAL.faint)
    cy2 = cy2 + 16 * s
    local fieldH = 26 * s
    local owner = p.owner
    local function writeSlot(pal, slot, rgb)
      local rec = Preview.ensureProjectPalette(S, pal)
      if not rec then return end
      rec.colors = rec.colors or {}
      rec.colors[slot] = {
        math.max(0, math.min(255, tonumber(rgb[1]) or 0)),
        math.max(0, math.min(255, tonumber(rgb[2]) or 0)),
        math.max(0, math.min(255, tonumber(rgb[3]) or 0)),
      }
      Preview.invalidate()
      local okApp, App = pcall(require, "App")
      if okApp and App.markDirty then App.markDirty() end
    end
    local function editSlot(slot, rgbOrOpenWheel)
      local function go(resolved)
        focusId = resolved
        p.focus = resolved
        p.current = resolved
        if rgbOrOpenWheel == true then
          local cols = Preview.paletteColors(S, resolved) or colors
          ColorWheel.open(S, {
            title = "C" .. slot .. " · " .. tostring(resolved),
            color = cols[slot] or colors[slot],
            onChange = function(rgb) writeSlot(resolved, slot, rgb) end,
            onApply = function(rgb) writeSlot(resolved, slot, rgb) end,
          })
        else
          writeSlot(resolved, slot, rgbOrOpenWheel)
        end
      end
      if owner and owner.kind and owner.entityId then
        PaletteEdit.request(S, {
          kind = owner.kind,
          entityId = owner.entityId,
          entityLabel = owner.entityLabel or owner.entityId,
          paletteId = focusId,
          assign = function(id)
            if owner.assign then owner.assign(id) end
            p.current = id
            p.focus = id
          end,
          thenFn = go,
        })
      else
        go(focusId)
      end
    end
    for i = 1, 4 do
      local c = colors[i] or { 40, 40, 40 }
      local cur = string.format("%d,%d,%d", c[1] or 0, c[2] or 0, c[3] or 0)
      Kit.text("micro", "C" .. i, prevX, cy2 + 6 * s, PAL.caption)
      local sw = 20 * s
      love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
        (c[3] or 0) / 255, 1)
      love.graphics.rectangle("fill", prevX + 20 * s, cy2 + 3 * s, sw, fieldH - 6 * s,
        3 * s, 3 * s)
      love.graphics.setColor(1, 1, 1, 0.4)
      love.graphics.rectangle("line", prevX + 20 * s, cy2 + 3 * s, sw, fieldH - 6 * s,
        3 * s, 3 * s)
      love.graphics.setColor(1, 1, 1, 1)
      if Kit.press(prevX + 20 * s, cy2 + 3 * s, sw, fieldH - 6 * s) then
        editSlot(i, true)
      end
      local v = Kit.textfield("pal_pick_c" .. i, prevX + 20 * s + sw + 6 * s, cy2,
        prevW - 20 * s - sw - 6 * s, fieldH, cur, "r,g,b")
      if v ~= cur then
        local r, g, b = tostring(v):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        if r then editSlot(i, { tonumber(r), tonumber(g), tonumber(b) }) end
      end
      cy2 = cy2 + fieldH + 4 * s
    end
    if Kit.button(prevX, py + ph - pad - 32 * s, prevW, 30 * s, "Use palette", {
        kind = "primary",
      }) then
      pick(S, focusId)
    end
  else
    Kit.text("micro", "No palette selected", prevX, swY, PAL.faint)
  end
end

return PalettePicker
