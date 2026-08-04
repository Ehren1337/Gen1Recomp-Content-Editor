-- Immediate-mode widget kit for the save editor, drawn in the launcher's
-- visual language (see Theme.lua and SaveEditor.dc.html).
--
-- Call Kit.beginFrame(mx, my, clicked, wheel) once per love.draw() before any
-- widget and Kit.endFrame() after the last one; widgets read the frame's mouse
-- state to decide hover / click, and endFrame retires the text-input queue so a
-- keystroke is never applied twice.  The wheel notches accumulated since the
-- last frame arrive the same way and are retired the same way: an unclaimed
-- notch dies with the frame rather than scrolling something later (#595).
--
-- Hit testing is a plain rect with no z-order, so panels must draw
-- overlapping controls in dispatch order and every target is >= 26px tall
-- (rule 6 of the design spec) -- that sizing is the whole accessibility story
-- here.

local Theme = require("Theme")
local PAL = Theme.PAL

local Kit = {}
Kit.mouseX, Kit.mouseY = 0, 0
Kit.mouseClicked = false  -- left button pressed this frame
Kit.wheelY = 0            -- wheel notches queued since the last frame (#595)
Kit.focus = nil           -- id of the text field receiving keystrokes
Kit.caret = 0             -- byte offset of caret within the focused field
Kit.selAnchor = nil       -- selection anchor byte offset (nil = no selection)
Kit.fieldScroll = 0       -- horizontal pixel scroll for the focused field
Kit.time = 0
Kit.fonts = {}
Kit.scale = 1

local G = love and love.graphics or nil
local edits = {}          -- queued textinput / key edits since the last frame
local kbField = nil       -- id of the field the OS soft keyboard is raised for
local focusFor = nil      -- field id that currently owns caret state

-- Mobile LOVE only delivers love.textinput while setTextInput(true) is
-- active, and that call is what raises the Android/iOS soft keyboard; the
-- rect keeps the focused field visible above it.  Desktop has text input on
-- by default and the launcher hosting this editor depends on that -- the
-- launcher's own fields (slot rename #205, mod index prompt, find search)
-- follow the same rule since #578: arm on open, lower only on mobile -- so
-- neither side ever turns desktop text input off, since setTextInput is
-- global SDL state, not per-widget (#529).
local function mobile()
  local osName = love and love.system and love.system.getOS
    and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

local function syncSoftKeyboard(id, x, y, w, h)
  if not (love and love.keyboard and love.keyboard.setTextInput) then return end
  if id then
    if kbField ~= id then
      kbField = id
      love.keyboard.setTextInput(true, math.floor(x), math.floor(y),
        math.ceil(w), math.ceil(h))
    end
  elseif kbField then
    kbField = nil
    if mobile() then love.keyboard.setTextInput(false) end
  end
end

local function canPrintf()
  return G and type(G.printf) == "function"
end

-- Hover tip delay (seconds) before a tooltip appears.
local TOOLTIP_DELAY = 0.45

function Kit.beginFrame(mx, my, clicked, wheel)
  Kit.mouseX, Kit.mouseY = mx, my
  Kit.mouseClicked = clicked
  Kit.wheelY = wheel or 0
  -- Held-button state is polled, not evented: the editor is hosted both
  -- standalone and inside the launcher, and neither routes mousereleased
  -- here.  Touch drag scrolling (#715) rides this poll, so it works in both
  -- hosts without new plumbing.  The stub has no love.mouse.isDown; a frame
  -- without it simply has no drags.
  local down = false
  if love and love.mouse and love.mouse.isDown then
    down = love.mouse.isDown(1) and true or false
  end
  Kit.mouseDown = down
  if not down then Kit._drag = nil end
  Kit.resetClip()
  if love and love.timer and love.timer.getTime then
    Kit.time = love.timer.getTime()
  end
  -- Last widget to call offerTooltip while hovered wins (draw order ≈ z).
  Kit._tipOffer = nil
end

-- Register a hover tip for the current frame.  Drawn in endFrame after a short
-- dwell so tips do not flash while the pointer crosses chrome.
function Kit.offerTooltip(x, y, w, h, text)
  if not text or text == "" then return end
  if Kit.blockClicks then return end
  if not Kit.hit(x, y, w, h) then return end
  Kit._tipOffer = tostring(text)
end

-- Retire this frame's keystrokes.  Anything typed while no field had focus is
-- dropped here rather than replayed into the next field that gets clicked.
-- A wheel notch no list claimed retires with them, for the same reason.
-- Tooltip paint runs at the end so it sits above every panel widget.
function Kit.endFrame()
  for i = #edits, 1, -1 do edits[i] = nil end
  Kit.wheelY = 0

  local tip = Kit._tipOffer
  local now = Kit.time or 0
  if tip then
    if Kit._tipText ~= tip then
      Kit._tipText = tip
      Kit._tipSince = now
    end
    if now - (Kit._tipSince or now) >= TOOLTIP_DELAY and not Kit.mouseDown then
      Kit.drawTooltip(tip, Kit.mouseX, Kit.mouseY)
    end
  else
    Kit._tipText = nil
    Kit._tipSince = nil
  end
  Kit._tipOffer = nil
end

-- Rebuild the font set when the window size changes.  `s` matched the
-- launcher's height/768 scale alone until #497: a phone in portrait
-- (720x1560) is TALLER than the desktop reference and barely half as wide, so
-- a height-only scale drew a 1.6x desktop layout into a 720px window and every
-- right-aligned cluster in the chrome landed on top of the block to its left.
--
-- The #497 answer was to shrink the whole layout down to fit the width
-- (floor 0.62), which #715 showed is its own failure: a small window got a
-- complete but unreadably tiny desktop layout, and the panels still assumed
-- their columns fit.  Shrink-to-fit is gone.  The scale now never dips below
-- 0.9, so text and the 26px tap targets stay readable everywhere, and a
-- narrow window is answered by REFLOW instead: every panel compares its real
-- pixel width against what its columns need (Party/Boxes/Items stack their
-- cards, Dex/Events drop grid columns, the chrome wraps its button row) and
-- whatever no longer fits vertically scrolls through Kit.scroll /
-- Kit.scrollPixels.  The width term survives only to keep a portrait phone
-- from inflating to the 1.6 cap its height alone would buy: 640 real px is
-- the narrowest the single-row chrome fits at scale 1.  Desktop sizes
-- (width >= 640 * height / 768) still land on the height term, so they stay
-- pixel-identical to before.
function Kit.layout(width, height)
  local s = Theme.clamp(math.min(width / 640, height / 768), 0.9, 1.6)
  local key = ("%dx%d"):format(width, height)
  if Kit._fontKey ~= key then
    Kit._fontKey = key
    Kit.fonts = Theme.fonts(s)
  end
  Kit.scale = s
  return s
end

-- ------------------------------------------------------------ input plumbing
-- App forwards love.textinput / love.keypressed here so Kit.textfield can be a
-- real editable field.  Events arrive before draw, so they queue and the
-- focused field drains them while it renders.
function Kit.textinput(text)
  if not Kit.focus then return false end
  if type(text) ~= "string" or text == "" then return true end
  -- Ignore raw newlines from IME / paste; fields are single-line.
  if text == "\n" or text == "\r" then return true end
  edits[#edits + 1] = text
  return true
end

local function ctrlDown()
  return love and love.keyboard and (
    love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui"))
end

local function shiftDown()
  return love and love.keyboard and (
    love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift"))
end

-- Returns true when the key was consumed by the focused field, so App can
-- leave its own shortcuts alone while the user is typing.
function Kit.keypressed(key)
  if not Kit.focus then return false end
  if key == "backspace" then
    edits[#edits + 1] = "\b"
    return true
  elseif key == "delete" then
    edits[#edits + 1] = "\x7f"
    return true
  elseif key == "left" then
    edits[#edits + 1] = { "left", shiftDown() }
    return true
  elseif key == "right" then
    edits[#edits + 1] = { "right", shiftDown() }
    return true
  elseif key == "home" then
    edits[#edits + 1] = { "home", shiftDown() }
    return true
  elseif key == "end" then
    edits[#edits + 1] = { "end", shiftDown() }
    return true
  elseif key == "a" and ctrlDown() then
    edits[#edits + 1] = "select_all"
    return true
  elseif key == "return" or key == "kpenter" or key == "escape" then
    edits[#edits + 1] = "\r"
    return true
  end
  -- other keys fall through to App while a field is hot
  return false
end

function Kit.blur()
  Kit.focus = nil
  Kit.caret = 0
  Kit.selAnchor = nil
  Kit.fieldScroll = 0
  focusFor = nil
  syncSoftKeyboard(nil)  -- the soft keyboard follows focus down too (#529)
end

-- ------------------------------------------------------------- hit testing
-- A widget inside a scrolled clip region can sit at coordinates outside the
-- visible rect (#715: stacked panels scroll in pixels), so the active clip
-- bounds the hit: what the user cannot see cannot take the tap.
function Kit.hit(x, y, w, h)
  local c = Kit._clipRect
  if c and not (Kit.mouseX >= c.x and Kit.mouseX <= c.x + c.w
      and Kit.mouseY >= c.y and Kit.mouseY <= c.y + c.h) then
    return false
  end
  return Kit.mouseX >= x and Kit.mouseX <= x + w
     and Kit.mouseY >= y and Kit.mouseY <= y + h
end

-- ------------------------------------------------------------ layout audit
-- #715 reflow tests: when a test sets Kit.audit to a table, every control
-- that could take a click this frame appends its rect (plus the clip that
-- bounds it), so a window-size sweep can assert that no two controls
-- overlap and none escapes the window.  Shielded widgets are skipped: under
-- a modal they cannot take the tap, and the modal legitimately covers them.
Kit.audit = nil

local function audit(class, x, y, w, h, label)
  local a = Kit.audit
  if not a or Kit.blockClicks then return end
  local c = Kit._clipRect
  a[#a + 1] = { class = class, x = x, y = y, w = w, h = h,
    label = tostring(label or ""),
    clip = c and { x = c.x, y = c.y, w = c.w, h = c.h } or nil }
end

function Kit.hover(x, y, w, h)
  return Kit.hit(x, y, w, h)
end

-- Kit hit-tests without a z-order, so an overlay cannot just be drawn last:
-- every widget underneath it would still take the same click.  A modal raises
-- this shield over the layers it covers (App.draw does it around the chrome
-- and the panel while the species picker is up) and lowers it for its own
-- layer (#541).
Kit.blockClicks = false

function Kit.press(x, y, w, h)
  if Kit.blockClicks then return false end
  return Kit.mouseClicked and Kit.hit(x, y, w, h)
end

-- ------------------------------------------------------------------- text
local function font(name)
  return Kit.fonts[name] or Kit.fonts.small
end

function Kit.text(name, str, x, y, c, a)
  if not G then return 0 end
  local f = font(name)
  if not f then return 0 end
  G.setFont(f)
  Theme.col(c or PAL.text, a or 1)
  G.print(tostring(str), x, y)
  return f:getWidth(tostring(str))
end

function Kit.textRight(name, str, x2, y, c, a)
  local f = font(name)
  if not f then return end
  Kit.text(name, str, x2 - f:getWidth(tostring(str)), y, c, a)
end

function Kit.textCenter(name, str, x, y, w, c, a)
  if not G then return end
  local f = font(name)
  if not f then return end
  G.setFont(f)
  Theme.col(c or PAL.text, a or 1)
  if canPrintf() then
    G.printf(tostring(str), x, y, w, "center")
  else
    G.print(tostring(str), x + (w - f:getWidth(tostring(str))) / 2, y)
  end
end

function Kit.textHeight(name)
  local f = font(name)
  return f and f:getHeight() or 12
end

-- Floating hover tip near the pointer (called from endFrame after dwell).
function Kit.drawTooltip(text, mx, my)
  if not (G and text and text ~= "") then return end
  local s = Kit.scale
  local padX, padY = 10 * s, 6 * s
  local maxW = 280 * s
  local lines = {}
  local body = tostring(text)
  if Kit.textWidth("micro", body) <= maxW then
    lines[1] = body
  else
    local word, line = "", ""
    local function flushWord()
      if word == "" then return end
      local trial = (line == "") and word or (line .. " " .. word)
      if Kit.textWidth("micro", trial) > maxW and line ~= "" then
        lines[#lines + 1] = line
        line = word
      else
        line = trial
      end
      word = ""
    end
    for i = 1, #body do
      local ch = body:sub(i, i)
      if ch == "\n" then
        flushWord()
        lines[#lines + 1] = line
        line = ""
      elseif ch == " " then
        flushWord()
      else
        word = word .. ch
      end
    end
    flushWord()
    if line ~= "" then lines[#lines + 1] = line end
  end
  if #lines == 0 then return end
  local tw = 0
  for _, ln in ipairs(lines) do
    tw = math.max(tw, Kit.textWidth("micro", ln))
  end
  local lineH = Kit.textHeight("micro")
  local bw = tw + 2 * padX
  local bh = #lines * lineH + 2 * padY
  local W, H = G.getDimensions()
  local bx = (mx or 0) + 14 * s
  local by = (my or 0) + 18 * s
  if bx + bw > W - 8 * s then bx = (mx or 0) - bw - 8 * s end
  if by + bh > H - 8 * s then by = (my or 0) - bh - 10 * s end
  if bx < 8 * s then bx = 8 * s end
  if by < 8 * s then by = 8 * s end
  local r = 8 * s
  Theme.col(PAL.cardBody or PAL.rowBg, 0.96)
  G.rectangle("fill", bx, by, bw, bh, r, r)
  Theme.stroke(bx, by, bw, bh, r, PAL.cardBorder, 0.7, 1)
  for i, ln in ipairs(lines) do
    Kit.text("micro", ln, bx + padX, by + padY + (i - 1) * lineH, PAL.heading)
  end
end

function Kit.textWidth(name, str)
  local f = font(name)
  return f and f:getWidth(tostring(str)) or 0
end

function Kit.ellipsize(name, str, maxW)
  return Theme.ellipsize(font(name), str, maxW)
end

-- 12px / 2px-tracked uppercase section caption -- the design's one and only
-- section header.  Returns the caption's height so callers can stack below.
function Kit.caption(x, y, str, c)
  if not G then return Kit.textHeight("caption") end
  local f = font("caption")
  if not f then return 12 end
  G.setFont(f)
  Theme.col(c or PAL.caption, 1)
  Theme.spaced(f, str, x, y, 2 * Kit.scale)
  return f:getHeight()
end

function Kit.captionWidth(str)
  return Theme.spacedWidth(font("caption"), str, 2 * Kit.scale)
end

-- --------------------------------------------------------------- surfaces
function Kit.card(x, y, w, h, r)
  Theme.card(x, y, w, h, r or 16 * Kit.scale)
end

-- A list row.  `selected` rings it in the accent colour (green for "this is
-- the thing you are editing", blue for "this is the thing you are browsing")
-- instead of filling it, so sprites and HP colours stay readable.  Returns
-- true when the row was clicked this frame.
function Kit.row(x, y, w, h, selected, accent, r)
  r = r or 12 * Kit.scale
  audit("row", x, y, w, h, "row")
  if not G then return Kit.press(x, y, w, h) end
  accent = accent or PAL.green
  if selected then Theme.glow(x, y, w, h, r, accent, 0.45) end
  Theme.row(x, y, w, h, r, 0.6)
  if selected then
    Theme.stroke(x, y, w, h, r, accent, 0.85, 1.5 * Kit.scale)
  end
  return Kit.press(x, y, w, h)
end

function Kit.meter(x, y, w, h, pct, c)
  Theme.meter(x, y, w, h, pct, c)
end

-- Dashed empty-state box with a centred hint.
function Kit.emptyBox(x, y, w, h, message)
  if not G then return end
  Theme.col(PAL.cardBorder, 0.4)
  if G.setLineWidth then G.setLineWidth(math.max(1, 1 * Kit.scale)) end
  Theme.dashed(x, y, w, h, 12 * Kit.scale, 7 * Kit.scale, 5 * Kit.scale)
  if G.setLineWidth then G.setLineWidth(1) end
  local f = font("button")
  if not f then return end
  Kit.textCenter("button", message, x + 12 * Kit.scale,
    y + h / 2 - f:getHeight() / 2, w - 24 * Kit.scale, PAL.muted)
end

-- --------------------------------------------------------------- buttons
-- Button kinds, straight out of the spec's colour semantics:
--   primary  green gradient  -- the single "commit this" control (Save)
--   ghost    glassy white    -- neutral verbs (Reload, Open, Add)
--   accent   blue tint       -- steppers, pagers, in-panel navigation
--   good     green tint      -- safe helpers (Full heal, max a DV)
--   danger   red tint        -- destructive verbs, always two-click
--   disabled steel           -- never hidden, always explained in the status bar
local KINDS = {
  primary  = { fillTop = PAL.green, fillBot = PAL.greenDark, aTop = 1, aBot = 1,
               ink = PAL.greenInk, border = nil, glow = PAL.green },
  ghost    = { fillTop = { 255, 255, 255 }, fillBot = { 255, 255, 255 },
               aTop = 0.14, aBot = 0.03, ink = PAL.heading,
               border = { 255, 255, 255 }, borderA = 0.18 },
  accent   = { flat = PAL.blue, flatA = 0.14, ink = PAL.blueInk,
               border = PAL.cardBorder, borderA = 0.35 },
  good     = { flat = PAL.green, flatA = 0.1, ink = PAL.green,
               border = PAL.green, borderA = 0.45 },
  danger   = { flat = PAL.red, flatA = 0.12, ink = PAL.redSoft,
               border = PAL.red, borderA = 0.45 },
  disabled = { flat = { 120, 132, 158 }, flatA = 0.22, ink = PAL.steel,
               border = PAL.steel, borderA = 0.3 },
}

-- opts: { kind, font, enabled, align, radius, glow, tooltip }
-- Returns true when clicked (never when disabled).
function Kit.button(x, y, w, h, label, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  -- disabled buttons audit too: rule 3 keeps them visible, so they still
  -- must not paint over a neighbour (#715)
  audit("control", x, y, w, h, label)
  local kind = KINDS[enabled and (opts.kind or "ghost") or "disabled"]
  local r = opts.radius or 10 * Kit.scale
  local hot = enabled and Kit.hover(x, y, w, h)
  if opts.tooltip then Kit.offerTooltip(x, y, w, h, opts.tooltip) end

  if G then
    if opts.glow and enabled then
      Theme.glow(x, y, w, h, r, kind.glow or PAL.green, opts.glow)
    end
    if kind.flat then
      Theme.col(kind.flat, kind.flatA * (hot and 1.6 or 1))
      G.rectangle("fill", x, y, w, h, r, r)
    else
      Theme.gradRounded(x, y, w, h, r, kind.fillTop, kind.fillBot,
        kind.aTop * (hot and 1.4 or 1), kind.aBot * (hot and 1.6 or 1))
    end
    if kind.border then
      Theme.stroke(x, y, w, h, r, kind.border, kind.borderA * (hot and 1.5 or 1), 1)
    end
    local f = font(opts.font or "button")
    if f then
      G.setFont(f)
      Theme.col(kind.ink, 1)
      -- Default vector fonts leave extra gap under the baseline inside
      -- getHeight(), so geometric centering reads high on short bars.
      local ty = y + (h - f:getHeight()) / 2 + 1 * Kit.scale
      if opts.align == "left" then
        G.print(label, x + 10 * Kit.scale, ty)
      elseif canPrintf() then
        G.printf(label, x, ty, w, "center")
      else
        G.print(label, x + (w - f:getWidth(label)) / 2, ty)
      end
    end
  end
  return enabled and Kit.press(x, y, w, h) or false
end

-- A small square control: the +/- steppers, the arrow cyclers, the row ✕.
function Kit.stepper(x, y, w, h, glyph, opts)
  opts = opts or {}
  opts.kind = opts.kind or "accent"
  opts.font = opts.font or "small"
  opts.radius = opts.radius or 6 * Kit.scale
  return Kit.button(x, y, w, h, glyph, opts)
end

-- A pill toggle (badges, dex SEEN/OWN, event sub-tabs).  `on` colours it;
-- returns true when clicked.  Optional 9th arg is a hover tooltip string.
function Kit.chip(x, y, w, h, label, on, onColor, offColor, tip)
  audit("control", x, y, w, h, label)
  local c = on and (onColor or PAL.green) or (offColor or PAL.steel)
  if tip then Kit.offerTooltip(x, y, w, h, tip) end
  if G then
    local r = 6 * Kit.scale
    Theme.col(c, on and 0.16 or 0.06)
    G.rectangle("fill", x, y, w, h, r, r)
    Theme.stroke(x, y, w, h, r, PAL.cardBorder, Kit.hover(x, y, w, h) and 0.5 or 0.28, 1)
    Kit.textCenter("micro", label, x,
      y + (h - Kit.textHeight("micro")) / 2 + 1 * Kit.scale, w,
      c, on and 1 or 0.75)
  end
  return Kit.press(x, y, w, h)
end

-- Checkbox row: a 20px box plus a mono label, the Events grid's unit.
-- Returns (newChecked, changed) so callers can write true/nil on a flip.
function Kit.checkbox(x, y, w, h, checked, label, labelColor)
  local clicked = Kit.row(x, y, w, h, false, nil, 9 * Kit.scale)
  local box = 20 * Kit.scale
  local bx, by = x + 12 * Kit.scale, y + (h - box) / 2
  if G then
    Theme.col(checked and PAL.green or PAL.rowBg, checked and 1 or 0.9)
    G.rectangle("fill", bx, by, box, box, 5 * Kit.scale, 5 * Kit.scale)
    Theme.stroke(bx, by, box, box, 5 * Kit.scale, PAL.cardBorder, 0.4, 1)
    if checked then
      Kit.textCenter("small", "X", bx, by + (box - Kit.textHeight("small")) / 2,
        box, PAL.greenInk)
    end
    local lx = bx + box + 12 * Kit.scale
    Kit.text("mono", Kit.ellipsize("mono", label, x + w - lx - 10 * Kit.scale), lx,
      y + (h - Kit.textHeight("mono")) / 2, labelColor or (checked and PAL.text or PAL.muted))
  end
  if clicked then return not checked, true end
  return checked, false
end

-- Single-line fields must not paint LOVE's multi-line print below the bar
-- (script dialog often stores "line1\nline2").
local function flatOneLine(s)
  s = tostring(s or ""):gsub("\r\n", "\n")
  s = s:gsub("[\n\r\f\v]", " / ")
  s = s:gsub(" +/ +", " / ")
  return s
end

-- 1-based byte index after the codepoint that starts at i.
local function utf8NextIndex(s, i)
  if i > #s then return #s + 1 end
  local b = s:byte(i)
  if not b then return i end
  local len = 1
  if b >= 0xF0 then len = 4
  elseif b >= 0xE0 then len = 3
  elseif b >= 0xC0 then len = 2 end
  if i + len - 1 > #s then len = 1 end
  return i + len
end

-- Caret is a byte offset 0..#s (text:sub(1, caret) is left of the caret).
local function caretLeft(s, caret)
  if caret <= 0 then return 0 end
  local i = caret
  while i > 1 do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then break end
    i = i - 1
  end
  return i - 1
end

local function caretRight(s, caret)
  if caret >= #s then return #s end
  return utf8NextIndex(s, caret + 1) - 1
end

-- Byte offset (0..#s) of the caret nearest to pixel x within string s.
local function caretAtX(f, s, x)
  if not f or s == "" or x <= 0 then return 0 end
  local best, bestDist = 0, math.abs(x)
  local caret = 0
  while caret <= #s do
    local w = f:getWidth(s:sub(1, caret))
    local dist = math.abs(w - x)
    if dist < bestDist then best, bestDist = caret, dist end
    if caret >= #s then break end
    caret = caretRight(s, caret)
  end
  return best
end

local function selRange()
  local a, c = Kit.selAnchor, Kit.caret or 0
  if a == nil then return c, c end
  if a < c then return a, c end
  return c, a
end

-- --------------------------------------------------------------- text field
-- Single-line editable field with click-to-caret, arrows, and selection.
-- App routes love.textinput / love.keypressed in via Kit.textinput /
-- Kit.keypressed.  Returns the (possibly edited) value; the caller stores it.
function Kit.textfield(id, x, y, w, h, value, placeholder)
  audit("control", x, y, w, h, id)
  local original = tostring(value or "")
  local text = flatOneLine(original)
  local f = font("mono")
  local pad = 10 * Kit.scale
  local textX = x + pad
  local textW = math.max(0, w - 2 * pad)

  if Kit.press(x, y, w, h) then
    Kit.focus = id
    if focusFor ~= id then
      focusFor = id
      Kit.fieldScroll = 0
    end
    local rel = (Kit.mouseX - textX) + (Kit.fieldScroll or 0)
    Kit.caret = caretAtX(f, text, rel)
    Kit.selAnchor = Kit.caret
  end

  local focused = (Kit.focus == id)
  if focused then
    if focusFor ~= id then
      focusFor = id
      Kit.caret = #text
      Kit.selAnchor = nil
      Kit.fieldScroll = 0
    end
    Kit.caret = Theme.clamp(Kit.caret or #text, 0, #text)
    -- Drag to select while the button is held inside the field.
    if Kit.mouseDown and Kit.hit(x, y, w, h) and not Kit.mouseClicked then
      local rel = (Kit.mouseX - textX) + (Kit.fieldScroll or 0)
      Kit.caret = caretAtX(f, text, rel)
      if Kit.selAnchor == nil then Kit.selAnchor = Kit.caret end
    end

    syncSoftKeyboard(id, x, y, w, h)

    local function clearSel() Kit.selAnchor = nil end
    local function hasSel()
      return Kit.selAnchor ~= nil and Kit.selAnchor ~= (Kit.caret or 0)
    end
    local function moveCaret(to, keepSel)
      to = Theme.clamp(to, 0, #text)
      if keepSel then
        if Kit.selAnchor == nil then Kit.selAnchor = Kit.caret end
      else
        clearSel()
      end
      Kit.caret = to
    end
    local function deleteSel()
      local a, b = selRange()
      if a == b then return false end
      text = text:sub(1, a) .. text:sub(b + 1)
      Kit.caret = a
      clearSel()
      return true
    end

    for _, e in ipairs(edits) do
      if type(e) == "table" then
        local op, keep = e[1], e[2]
        if op == "left" then
          if hasSel() and not keep then
            local a = selRange()
            moveCaret(a, false)
          else
            moveCaret(caretLeft(text, Kit.caret or 0), keep)
          end
        elseif op == "right" then
          if hasSel() and not keep then
            local _, b = selRange()
            moveCaret(b, false)
          else
            moveCaret(caretRight(text, Kit.caret or 0), keep)
          end
        elseif op == "home" then
          moveCaret(0, keep)
        elseif op == "end" then
          moveCaret(#text, keep)
        end
      elseif e == "\b" then
        if not deleteSel() then
          local c = Kit.caret or 0
          if c > 0 then
            local p = caretLeft(text, c)
            text = text:sub(1, p) .. text:sub(c + 1)
            Kit.caret = p
          end
        end
      elseif e == "\x7f" then
        if not deleteSel() then
          local c = Kit.caret or 0
          if c < #text then
            local n = caretRight(text, c)
            text = text:sub(1, c) .. text:sub(n + 1)
          end
        end
      elseif e == "\r" then
        Kit.blur()
        focused = false
      elseif e == "select_all" then
        Kit.selAnchor = 0
        Kit.caret = #text
      elseif type(e) == "string" then
        deleteSel()
        local c = Kit.caret or 0
        text = text:sub(1, c) .. e .. text:sub(c + 1)
        Kit.caret = c + #e
        clearSel()
      end
    end
  end

  if G then
    local r = 8 * Kit.scale
    Theme.col(PAL.rowBg, 0.7)
    G.rectangle("fill", x, y, w, h, r, r)
    Theme.stroke(x, y, w, h, r, focused and PAL.blue or PAL.cardBorder,
      focused and 0.8 or 0.3, focused and 1.5 * Kit.scale or 1)
    local ty = y + (h - Kit.textHeight("mono")) / 2 + 1 * Kit.scale
    Kit.pushClip(x + 1, y + 1, math.max(0, w - 2), math.max(0, h - 2))
    if text == "" and not focused then
      Kit.text("mono", placeholder or "", textX, ty, PAL.faint)
    elseif focused and f then
      local caret = Theme.clamp(Kit.caret or #text, 0, #text)
      local caretPx = f:getWidth(text:sub(1, caret))
      local scroll = Kit.fieldScroll or 0
      if caretPx - scroll > textW - 2 then
        scroll = caretPx - textW + 2
      elseif caretPx - scroll < 0 then
        scroll = caretPx
      end
      scroll = math.max(0, scroll)
      Kit.fieldScroll = scroll
      local drawX = textX - scroll

      local a, b = selRange()
      if a ~= b then
        local x0 = drawX + f:getWidth(text:sub(1, a))
        local x1 = drawX + f:getWidth(text:sub(1, b))
        Theme.col(PAL.blue, 0.35)
        G.rectangle("fill", x0, ty - 1, math.max(1, x1 - x0),
          Kit.textHeight("mono") + 2)
      end
      Kit.text("mono", text, drawX, ty, PAL.heading)
      if (Kit.time % 1) < 0.55 then
        Theme.col(PAL.blue, 1)
        G.rectangle("fill", drawX + caretPx, ty, math.max(1, Kit.scale),
          Kit.textHeight("mono"))
      end
    else
      -- Unfocused: show the end of long values (paths, flags).
      local shown = Theme.ellipsizeLeft(f, text, textW)
      Kit.text("mono", shown, textX, ty, PAL.heading)
    end
    Kit.popClip()
  end

  -- Preserve original newlines until the user actually edits the flat view.
  if text == flatOneLine(original) then
    return original
  end
  return text
end

-- ------------------------------------------------------------------ pager
-- Prev / Next / "1-12 of 151".  Drawn even when there is a single page, so a
-- list is never silently truncated (rule 5 of the design spec).  Returns the
-- new offset.
function Kit.pager(x, y, w, offset, total, perPage)
  local h = 30 * Kit.scale
  local bw = 74 * Kit.scale
  local maxOffset = math.max(0, total - perPage)
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.button(x, y, bw, h, "Prev", { kind = "accent", font = "small",
      enabled = offset > 0, radius = 8 * Kit.scale }) then
    offset = math.max(0, offset - perPage)
  end
  if Kit.button(x + bw + 10 * Kit.scale, y, bw, h, "Next", { kind = "accent",
      font = "small", enabled = offset < maxOffset, radius = 8 * Kit.scale }) then
    offset = math.min(maxOffset, offset + perPage)
  end
  local shown = math.min(perPage, math.max(0, total - offset))
  local label = ("%d-%d of %d"):format(total > 0 and offset + 1 or 0,
    offset + shown, total)
  -- the counter clips to the width the caller granted: a panel parking a
  -- button on the pager line passes a reduced w and the text yields instead
  -- of running underneath it (#715)
  local labelX = x + 2 * bw + 20 * Kit.scale
  Kit.text("mono", Kit.ellipsize("mono", label, math.max(0, x + w - labelX)),
    labelX, y + (h - Kit.textHeight("mono")) / 2, PAL.caption)
  return offset, h
end

-- ----------------------------------------------------------------- scroll
-- Mouse wheel over a list body (#595): same offset contract as Kit.pager, so
-- a list can carry both and stay on one page counter.  Three rules, all of
-- them consequences of Kit having no z-order:
--   * only the list the pointer is inside takes the notch,
--   * the notch is consumed, so two stacked lists cannot both eat it,
--   * Kit.blockClicks shields it exactly as it shields Kit.press, or the
--     panel under an open species picker would scroll through the modal.
local SCROLL_ROWS = 3

-- `step` is optional and exists for grids: a 4-column dex page must move in
-- multiples of 4 or the columns shear.  Lists leave it nil and keep the old
-- behaviour bit for bit (wheel notch = 3 rows, drag = 1 row per row height).
function Kit.scroll(x, y, w, h, offset, total, perPage, step)
  local maxOffset = math.max(0, (total or 0) - (perPage or 0))
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.blockClicks then return offset end

  -- Touch drag (#715): a phone has no wheel and the pagers are small
  -- targets, so a held pointer dragging vertically over the list body
  -- scrolls it.  The drag is keyed to the rect it started in and follows the
  -- pointer even once it leaves, like every native scroll view; the press
  -- frame itself still dispatches as a click, which is the pre-existing
  -- press-on-down contract, so a tap keeps selecting rows.
  local dragStep = math.max(1, step or 1)
  if Kit.mouseDown and maxOffset > 0 and h > 0 and (perPage or 0) > 0 then
    local key = math.floor(x) .. ":" .. math.floor(y)
    local d = Kit._drag
    if not d and Kit.hit(x, y, w, h) then
      Kit._drag = { key = key, startY = Kit.mouseY, base = offset }
    elseif d and d.key == key then
      local visRows = math.max(1, math.floor(perPage / dragStep))
      local rowPx = math.max(1, h / visRows)
      local moved = math.floor((d.startY - Kit.mouseY) / rowPx + 0.5) * dragStep
      offset = Theme.clamp(d.base + moved, 0, maxOffset)
    end
  end

  if (Kit.wheelY or 0) == 0 then return offset end
  if not Kit.hit(x, y, w, h) then return offset end
  -- LOVE reports wheel-up as positive y; up moves the window toward the top
  -- of the list, which is a smaller offset.
  local rows = step or math.max(1, math.min(SCROLL_ROWS, perPage or SCROLL_ROWS))
  local notch = (Kit.wheelY > 0) and -rows or rows
  Kit.wheelY = 0
  return Theme.clamp(offset + notch, 0, maxOffset)
end

-- Pixel-unit sibling of Kit.scroll for a whole stacked card column (#715
-- reflow): `offset` is a pixel offset into `contentH` pixels of laid-out
-- content shown through an `h`-pixel viewport.  Same three rules as
-- Kit.scroll (pointer-inside only, notch consumed, shielded by
-- Kit.blockClicks), same drag contract (a tap still dispatches as a click).
-- Call it AFTER the content so any inner Kit.scroll list gets first claim on
-- a wheel notch or drag that lands over it.
function Kit.scrollPixels(x, y, w, h, offset, contentH)
  local maxOffset = math.max(0, (contentH or 0) - math.max(0, h))
  offset = Theme.clamp(offset or 0, 0, maxOffset)
  if Kit.blockClicks then return offset end

  if Kit.mouseDown and maxOffset > 0 and h > 0 then
    local key = "px:" .. math.floor(x) .. ":" .. math.floor(y)
    local d = Kit._drag
    if not d and Kit.hit(x, y, w, h) then
      Kit._drag = { key = key, startY = Kit.mouseY, base = offset }
    elseif d and d.key == key then
      offset = Theme.clamp(d.base + (d.startY - Kit.mouseY), 0, maxOffset)
    end
  end

  if (Kit.wheelY or 0) == 0 then return offset end
  if not Kit.hit(x, y, w, h) then return offset end
  local notch = 48 * Kit.scale
  local delta = (Kit.wheelY > 0) and -notch or notch
  Kit.wheelY = 0
  return Theme.clamp(offset + delta, 0, maxOffset)
end

-- Thin overlay scrollbar along the right edge of a list body, drawn after
-- the rows so it stays visible.  Pure indicator (the drag above and the
-- pager are the controls): on a phone the old layout looked "stuck" because
-- nothing said the list continued past the fold (#715).
function Kit.scrollbar(x, y, w, h, offset, total, perPage)
  if not G then return end
  total, perPage = total or 0, perPage or 0
  if total <= perPage or h <= 0 or perPage <= 0 then return end
  local bw = 3 * Kit.scale
  local bx = x + w - bw
  Theme.col(PAL.cardBorder, 0.22)
  G.rectangle("fill", bx, y, bw, h, bw / 2, bw / 2)
  local maxOffset = total - perPage
  local th = math.max(18 * Kit.scale, h * perPage / total)
  local ty = y + (h - th) * (Theme.clamp(offset or 0, 0, maxOffset) / maxOffset)
  Theme.col(PAL.blue, 0.55)
  G.rectangle("fill", bx, ty, bw, th, bw / 2, bw / 2)
end

-- Clip drawing to a rect (list bodies, scrolled cards).  A stack since #715:
-- a stacked panel scrolls its whole column inside one clip and the lists
-- inside it push their own, so pushes nest by intersecting with the rect
-- above and a pop restores that rect rather than clearing the scissor.  The
-- tracked rect also bounds Kit.hit, so a widget scrolled out of view is
-- inert instead of taking taps aimed at whatever is drawn where it left.
-- Under the headless stub the scissor is a no-op but the rect tracking (and
-- so the hit fencing) still runs.
local clipStack = {}

local function applyClip(rect)
  Kit._clipRect = rect
  if not (G and G.setScissor) then return end
  if not rect then
    G.setScissor()
  elseif rect.w <= 0 or rect.h <= 0 then
    -- A compact mobile viewport can leave a panel with no room for a list.
    -- LÖVE rejects negative scissor dimensions, so treat an exhausted clip
    -- region as empty instead of passing invalid geometry through to it.
    G.setScissor(0, 0, 0, 0)
  else
    G.setScissor(math.floor(rect.x), math.floor(rect.y),
      math.ceil(rect.w), math.ceil(rect.h))
  end
end

function Kit.pushClip(x, y, w, h)
  local prev = clipStack[#clipStack]
  local x2, y2 = x + math.max(0, w), y + math.max(0, h)
  if prev then
    x, y = math.max(x, prev.x), math.max(y, prev.y)
    x2 = math.min(x2, prev.x + prev.w)
    y2 = math.min(y2, prev.y + prev.h)
  end
  local rect = { x = x, y = y, w = math.max(0, x2 - x), h = math.max(0, y2 - y) }
  clipStack[#clipStack + 1] = rect
  applyClip(rect)
end

function Kit.popClip()
  clipStack[#clipStack] = nil
  applyClip(clipStack[#clipStack])
end

-- A pcall-ed draw that raised mid-clip must not leak the stack into later
-- frames (every hit test would stay fenced to the dead rect), so the frame
-- boundary clears it.
function Kit.resetClip()
  for i = #clipStack, 1, -1 do clipStack[i] = nil end
  applyClip(nil)
end

return Kit
