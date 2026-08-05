-- Clipped, pixel-scrolled form body for content-editor detail cards.
-- Keeps long field stacks inside Kit.card instead of painting over chrome.

local Kit = require("Kit")

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
-- and the view rect {x,y,w,h,contentW}.  Lay out widgets with contentW so the
-- scrollbar gutter on the right is not covered.  Call FormPane.finish after.
function FormPane.begin(S, key, x, y, w, h)
  local contentH = S["_" .. key .. "ContentH"] or h
  local needsBar = contentH > h + 1
  local gutter = needsBar and Kit.scrollbarSize() or 0
  local scroll = Kit.scrollPixels(x, y, w, h, S[key] or 0, contentH)
  S[key] = scroll
  Kit.pushClip(x, y, math.max(0, w - gutter), h)
  return y - scroll, {
    x = x, y = y, w = w, h = h,
    contentW = math.max(0, w - gutter),
    gutter = gutter,
  }
end

function FormPane.finish(S, key, contentTop, contentBottom, view)
  local pad = 8
  local contentH = math.max(view.h, (contentBottom - contentTop) + pad)
  S["_" .. key .. "ContentH"] = contentH
  Kit.popClip()
  if contentH > view.h + 1 then
    S[key] = Kit.scrollbarPixels(view.x, view.y, view.w, view.h,
      S[key] or 0, contentH)
  end
end

return FormPane
