-- Clipped, pixel-scrolled form body for content-editor detail cards.
-- Keeps long field stacks inside Kit.card instead of painting over chrome.

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL

local FormPane = {}

-- Reset scroll when the edited record / section changes.
function FormPane.track(S, key, identity)
  local mark = "_" .. key .. "For"
  if S[mark] ~= identity then
    S[key] = 0
    S[mark] = identity
  end
end

-- Begin a scroll+clip region.  Returns drawY (top of content, scroll-adjusted)
-- and the view rect {x,y,w,h}.  Call FormPane.finish after drawing.
function FormPane.begin(S, key, x, y, w, h)
  local contentH = S["_" .. key .. "ContentH"] or h
  local scroll = Kit.scrollPixels(x, y, w, h, S[key] or 0, contentH)
  S[key] = scroll
  Kit.pushClip(x, y, w, h)
  return y - scroll, { x = x, y = y, w = w, h = h }
end

function FormPane.finish(S, key, contentTop, contentBottom, view)
  local pad = 8
  local contentH = math.max(view.h, (contentBottom - contentTop) + pad)
  S["_" .. key .. "ContentH"] = contentH
  Kit.popClip()
  -- thin scrollbar when content overflows
  if contentH > view.h + 1 and love and love.graphics then
    local bw = 3
    local bx = view.x + view.w - bw - 1
    Theme.col(PAL.cardBorder, 0.22)
    love.graphics.rectangle("fill", bx, view.y, bw, view.h, bw / 2, bw / 2)
    local th = math.max(18, view.h * view.h / contentH)
    local maxOff = contentH - view.h
    local ty = view.y + (view.h - th) * ((S[key] or 0) / math.max(1, maxOff))
    Theme.col(PAL.blue, 0.55)
    love.graphics.rectangle("fill", bx, ty, bw, th, bw / 2, bw / 2)
  end
end

return FormPane
