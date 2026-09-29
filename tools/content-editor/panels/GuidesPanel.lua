-- GUIDES tab: step-by-step guides (content in GuidesData.lua, see Guides.lua).
-- A list of guides by topic on the left; the chosen guide's numbered steps
-- on the right, each with "Take me there" when it has a place to go.

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL
local Pane = require("FormPane")
local Guides = require("Guides")

local M = {}

local function wrapped(f, text, width)
  if f and f.getWrap then
    local _, lines = f:getWrap(text, width)
    return math.max(1, #lines)
  end
  return 1
end

-- The list ------------------------------------------------------------------------

local function drawList(S, data, x, y, lw, h, guide)
  local s = Kit.scale
  Kit.card(x, y, lw, h)
  Kit.caption(x + 14 * s, y + 12 * s, "GUIDES")
  local first, view = Pane.begin(S, "guideListScroll", x + 8 * s, y + 40 * s, lw - 16 * s, h - 48 * s)
  local ly = first
  for _, cat in ipairs(data.categories) do
    Kit.text("micro", cat.label:upper(), view.x + 6 * s, ly + 6 * s, PAL.caption or PAL.muted)
    ly = ly + 28 * s
    for _, g in ipairs(Guides.byCategory(cat.id, data.guides)) do
      if Kit.chip(view.x, ly, view.contentW, 28 * s, g.title ~= "" and g.title or "(untitled)", g == guide,
          PAL.green, PAL.steel, g.summary) then
        S.guideId = g.id
        S.guideStepScroll = 0
      end
      ly = ly + 32 * s
    end
    ly = ly + 6 * s
  end
  Pane.finish(S, "guideListScroll", first, ly, view)
end

-- Reading a guide -----------------------------------------------------------------

local function drawGuide(S, App, guide, px, pw, y, h, gen3)
  local s = Kit.scale
  local G = love.graphics
  local f = Kit.fonts and Kit.fonts.small
  local lineH = f and f:getHeight() * 1.25 or 18 * s
  Kit.text("button", guide.title, px, y + 16 * s, PAL.heading)
  local ty = y + 48 * s
  Theme.col(PAL.muted, 1)
  if f then G.setFont(f) end
  G.printf(guide.summary or "", px, ty, pw, "left")
  ty = ty + wrapped(f, guide.summary or "", pw) * lineH + 6 * s
  if guide.gen3 then
    Kit.text("micro", gen3 and "FireRed / LeafGreen" or "FireRed / LeafGreen mods only -- open or make a Gen 3 mod to use this",
      px, ty, gen3 and PAL.faint or PAL.yellow)
    ty = ty + 24 * s
  end
  ty = ty + 6 * s
  Pane.track(S, "guideStepScroll", guide.id)
  local firstS, sv = Pane.begin(S, "guideStepScroll", px, ty, pw + 12 * s, y + h - ty - 12 * s)
  local sy = firstS
  local btnW = 150 * s
  local canGo = not guide.gen3 or gen3
  for i, step in ipairs(guide.steps or {}) do
    local text = step[1] or ""
    local hasGo = step.go and step.go.tab and canGo
    local textW = sv.contentW - 44 * s - (hasGo and (btnW + 16 * s) or 0)
    local n = wrapped(f, text, textW)
    local rowH = math.max(n * lineH, 30 * s)
    Theme.col(PAL.green, 0.16)
    G.circle("fill", px + 14 * s, sy + 14 * s, 14 * s)
    G.setColor(1, 1, 1, 1)
    Kit.text("micro", tostring(i), px + (i >= 10 and 6 or 10) * s, sy + 6 * s, PAL.green)
    Theme.col(PAL.text, 1)
    if f then G.setFont(f) end
    G.printf(text, px + 40 * s, sy + 4 * s, textW, "left")
    G.setColor(1, 1, 1, 1)
    if hasGo and Kit.button(px + sv.contentW - btnW, sy, btnW, 28 * s, "Take me there", {
        kind = "accent", font = "micro", tooltip = "Go to " .. tostring(step.go.tab):upper() }) then
      Guides.go(S, step.go)
    end
    sy = sy + rowH + 16 * s
  end
  Pane.finish(S, "guideStepScroll", firstS, sy, sv)
end

-- The tab -------------------------------------------------------------------------

function M.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local gen3 = require("Generation").isGen3(S)
  local data = Guides.data()
  local guide = Guides.find(S.guideId, data.guides) or data.guides[1]
  S.guideId = guide and guide.id or nil

  local lw = math.min(300 * s, w * 0.34)
  drawList(S, data, x, y, lw, h, guide)

  local gx, gw = x + lw + 16 * s, w - lw - 16 * s
  Kit.card(gx, y, gw, h)
  local px, pw = gx + 20 * s, gw - 40 * s
  if not guide then
    Kit.text("small", "No guides.", px, y + 20 * s, PAL.muted)
    return
  end
  drawGuide(S, App, guide, px, pw, y, h, gen3)
end

return M
