-- Shared SGB palette picker modal for Maps / Pokemon / Trainers / GFX.

local Kit = require("Kit")
local Theme = require("Theme")
local Preview = require("Preview")
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

-- opts: current, allowClear, clearLabel, title, onPick(id|nil)
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
  }
end

function PalettePicker.keypressed(S, key)
  if not PalettePicker.isOpen(S) then return false end
  if key == "escape" then
    PalettePicker.close(S)
    return true
  end
  return true
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
        tooltip = opts.tooltip or "Pick an SGB palette",
      }) then
    PalettePicker.open(S, {
      current = cur ~= "" and cur or nil,
      allowClear = opts.allowClear,
      clearLabel = opts.clearLabel or opts.emptyLabel,
      title = opts.title,
      onPick = opts.onPick,
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
  if p.opened then
    p.opened = nil
    Kit.blockClicks = true
  end
  Kit.blockClicks = true

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
    Kit.pushClip(cx, listY, listW, listH)
    local ry = listY
    for i = (p.offset or 0) + 1, math.min(#list, (p.offset or 0) + perPage) do
      local id = list[i]
      local on = p.current == id
      local focused = p.focus == id
      if Kit.hover(cx, ry, listW, rowH) then p.focus = id end
      if Kit.row(cx, ry, listW, rowH, on or focused, PAL.yellow) then
        pick(S, id)
        Kit.popClip()
        return
      end
      Preview.drawNamedSwatches(S, id, cx + 6 * s, ry + (rowH - 14 * s) / 2,
        56 * s, 14 * s)
      local label = Kit.ellipsize("mono", id, listW - 72 * s)
      local owned = S.project and S.project.palettes and S.project.palettes[id]
      Kit.text("mono", label, cx + 68 * s, ry + 9 * s,
        on and PAL.heading or (owned and PAL.text or PAL.muted))
      ry = ry + rowH + 3 * s
    end
    Kit.popClip()
  end
  Kit.scrollbar(cx, listY, listW, listH, p.offset or 0, #list, perPage)

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
    local colors = Preview.paletteColors(S, focusId) or {}
    local cy2 = swY + swH + 12 * s
    for i = 1, 4 do
      local c = colors[i] or { 40, 40, 40 }
      Kit.text("micro", string.format("C%d  %d,%d,%d", i,
          c[1] or 0, c[2] or 0, c[3] or 0),
        prevX, cy2, PAL.muted)
      cy2 = cy2 + 16 * s
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
