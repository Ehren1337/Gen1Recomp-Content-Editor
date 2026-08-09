-- Modal HSV color wheel for palette / swatch editing.

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL

local ColorWheel = {}

local wheelCache = {} -- size -> Image

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function rgbToHsv(r, g, b)
  r = (tonumber(r) or 0) / 255
  g = (tonumber(g) or 0) / 255
  b = (tonumber(b) or 0) / 255
  local maxc = math.max(r, g, b)
  local minc = math.min(r, g, b)
  local d = maxc - minc
  local h, s, v = 0, 0, maxc
  if maxc > 0 then s = d / maxc end
  if d > 1e-6 then
    if maxc == r then
      h = (g - b) / d + (g < b and 6 or 0)
    elseif maxc == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h / 6
  end
  return h, s, v
end

local function hsvToRgb(h, s, v)
  h = h % 1
  if h < 0 then h = h + 1 end
  s = clamp(s, 0, 1)
  v = clamp(v, 0, 1)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  local r, g, b
  i = i % 6
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q
  end
  return math.floor(r * 255 + 0.5),
    math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5)
end

local function wheelImage(size)
  size = math.floor(size)
  if size < 32 then size = 32 end
  local cached = wheelCache[size]
  if cached then return cached end
  if not (love and love.image and love.image.newImageData) then return nil end
  local id = love.image.newImageData(size, size)
  local cx = (size - 1) * 0.5
  local R = cx
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local dx, dy = x - cx, y - cx
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist <= R + 0.5 then
        local ang = math.atan2(dy, dx) -- -pi..pi, 0 = east
        local h = (ang / (math.pi * 2))
        if h < 0 then h = h + 1 end
        local sat = clamp(dist / R, 0, 1)
        local rr, gg, bb = hsvToRgb(h, sat, 1)
        local a = 1
        if dist > R - 1 then
          a = clamp(R + 0.5 - dist, 0, 1)
        end
        id:setPixel(x, y, rr / 255, gg / 255, bb / 255, a)
      else
        id:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  cached = love.graphics.newImage(id)
  cached:setFilter("linear", "linear")
  wheelCache[size] = cached
  return cached
end

function ColorWheel.isOpen(S)
  return S and S.colorWheel ~= nil
end

function ColorWheel.close(S)
  if not S then return end
  S.colorWheel = nil
  Kit.blur()
  Kit.suppressMouseUntilUp()
end

-- opts: color={r,g,b}|{r,g,b as array}, title, onChange(rgb), onApply(rgb), onCancel()
function ColorWheel.open(S, opts)
  opts = opts or {}
  local c = opts.color or { 255, 255, 255 }
  local r = tonumber(c.r or c[1]) or 255
  local g = tonumber(c.g or c[2]) or 255
  local b = tonumber(c.b or c[3]) or 255
  r, g, b = clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255)
  local h, s, v = rgbToHsv(r, g, b)
  S.colorWheel = {
    title = opts.title or "COLOR",
    h = h, s = s, v = v,
    r = r, g = g, b = b,
    drag = nil, -- "wheel" | "value"
    opened = true,
    onChange = opts.onChange,
    onApply = opts.onApply,
    onCancel = opts.onCancel,
  }
end

function ColorWheel.keypressed(S, key)
  if not ColorWheel.isOpen(S) then return false end
  if key == "escape" then
    local w = S.colorWheel
    local cb = w and w.onCancel
    ColorWheel.close(S)
    if cb then cb() end
    return true
  end
  if key == "return" or key == "kpenter" then
    local w = S.colorWheel
    if w then
      local rgb = { w.r, w.g, w.b }
      local apply = w.onApply
      ColorWheel.close(S)
      if apply then apply(rgb) end
    end
    return true
  end
  return false
end

local function setRgb(w, r, g, b, notify)
  w.r, w.g, w.b = clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255)
  w.h, w.s, w.v = rgbToHsv(w.r, w.g, w.b)
  if notify and w.onChange then
    w.onChange({ w.r, w.g, w.b })
  end
end

local function setHsv(w, h, s, v, notify)
  w.h, w.s, w.v = h % 1, clamp(s, 0, 1), clamp(v, 0, 1)
  w.r, w.g, w.b = hsvToRgb(w.h, w.s, w.v)
  if notify and w.onChange then
    w.onChange({ w.r, w.g, w.b })
  end
end

function ColorWheel.draw(S, x, y, w, h)
  local state = S and S.colorWheel
  if not state then return end
  local s = Kit.scale
  if state.opened then
    state.opened = nil
    Kit.mouseClicked = false
  end

  Theme.col(PAL.bgBot or PAL.card, 0.78)
  love.graphics.rectangle("fill", x, y, w, h)

  local pw = math.min(w - 24 * s, 420 * s)
  local ph = math.min(h - 24 * s, 460 * s)
  local px = x + (w - pw) / 2
  local py = y + (h - ph) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(px, py, pw, ph) then
    local cb = state.onCancel
    ColorWheel.close(S)
    if cb then cb() end
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, state.title or "COLOR")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    local cb = state.onCancel
    ColorWheel.close(S)
    if cb then cb() end
    return
  end
  cy = cy + 28 * s

  local wheelSize = math.floor(math.min(220 * s, inner - 48 * s))
  local wheelX = cx + (inner - wheelSize - 36 * s) * 0.5
  local wheelY = cy
  local img = wheelImage(wheelSize)
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, wheelX, wheelY, 0, wheelSize / img:getWidth(),
      wheelSize / img:getHeight())
  else
    Theme.col(PAL.cardBody, 1)
    love.graphics.circle("fill", wheelX + wheelSize * 0.5,
      wheelY + wheelSize * 0.5, wheelSize * 0.5)
  end

  -- value slider (right of wheel)
  local barX = wheelX + wheelSize + 12 * s
  local barW = 22 * s
  local barH = wheelSize
  for i = 0, math.floor(barH) - 1 do
    local vv = 1 - (i / math.max(1, barH - 1))
    local rr, gg, bb = hsvToRgb(state.h, state.s, vv)
    love.graphics.setColor(rr / 255, gg / 255, bb / 255, 1)
    love.graphics.rectangle("fill", barX, wheelY + i, barW, 1)
  end
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.rectangle("line", barX, wheelY, barW, barH)

  -- wheel cursor
  local R = wheelSize * 0.5
  local wcx = wheelX + R
  local wcy = wheelY + R
  local ang = state.h * math.pi * 2
  local pxC = wcx + math.cos(ang) * state.s * R
  local pyC = wcy + math.sin(ang) * state.s * R
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("line", pxC, pyC, 6 * s)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.circle("line", pxC, pyC, 7 * s)

  -- value cursor
  local vy = wheelY + (1 - state.v) * barH
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", barX - 3 * s, vy - 2 * s, barW + 6 * s, 4 * s)
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.rectangle("line", barX - 3 * s, vy - 2 * s, barW + 6 * s, 4 * s)

  -- drag / click
  if not Kit.mouseDown then
    state.drag = nil
  elseif state.drag == "wheel" or (not state.drag
      and Kit.hit(wheelX, wheelY, wheelSize, wheelSize)
      and (Kit.mouseClicked or Kit.mouseDown)) then
    local dx = Kit.mouseX - wcx
    local dy = Kit.mouseY - wcy
    local dist = math.sqrt(dx * dx + dy * dy)
    if state.drag == "wheel" or dist <= R + 4 * s then
      state.drag = "wheel"
      local hh = math.atan2(dy, dx) / (math.pi * 2)
      if hh < 0 then hh = hh + 1 end
      setHsv(state, hh, clamp(dist / R, 0, 1), state.v, true)
    end
  elseif state.drag == "value" or (not state.drag
      and Kit.hit(barX - 4 * s, wheelY, barW + 8 * s, barH)
      and (Kit.mouseClicked or Kit.mouseDown)) then
    state.drag = "value"
    local t = clamp((Kit.mouseY - wheelY) / math.max(1, barH), 0, 1)
    setHsv(state, state.h, state.s, 1 - t, true)
  end

  cy = wheelY + wheelSize + 14 * s

  -- preview + RGB
  local prevW = 56 * s
  love.graphics.setColor(state.r / 255, state.g / 255, state.b / 255, 1)
  love.graphics.rectangle("fill", cx, cy, prevW, 36 * s, 6 * s, 6 * s)
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.rectangle("line", cx, cy, prevW, 36 * s, 6 * s, 6 * s)

  local fx = cx + prevW + 10 * s
  local fw = inner - prevW - 10 * s
  local fh = 28 * s
  local cur = string.format("%d,%d,%d", state.r, state.g, state.b)
  Kit.text("micro", "RGB", fx, cy - 2 * s, PAL.caption)
  local v = Kit.textfield("color_wheel_rgb", fx, cy + 12 * s, fw, fh, cur, "r,g,b")
  if v ~= cur and not state.drag then
    local rr, gg, bb = tostring(v):match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if rr then
      setRgb(state, tonumber(rr), tonumber(gg), tonumber(bb), true)
    end
  end
  cy = cy + 54 * s

  local btnW = (inner - 8 * s) * 0.5
  if Kit.button(cx, cy, btnW, 32 * s, "Cancel", { kind = "ghost" }) then
    local cb = state.onCancel
    ColorWheel.close(S)
    if cb then cb() end
    return
  end
  if Kit.button(cx + btnW + 8 * s, cy, btnW, 32 * s, "Apply", { kind = "primary" }) then
    local rgb = { state.r, state.g, state.b }
    local apply = state.onApply
    ColorWheel.close(S)
    if apply then apply(rgb) end
  end
end

return ColorWheel
