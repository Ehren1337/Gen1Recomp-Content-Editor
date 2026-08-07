-- Trades tab: field.trades (in-game trade NPCs). Index is 1-based for the
-- Events "In-game trade" step.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local PAL = Theme.PAL

local Trades = {}

local function baseTrades(S)
  local t = S.data and S.data.field and S.data.field.trades
  return type(t) == "table" and t or {}
end

local function cloneBase(S)
  local copy = {}
  for i, t in ipairs(baseTrades(S)) do
    if type(t) == "table" then
      copy[i] = {
        give = t.give,
        get = t.get,
        dialogset = t.dialogset or 1,
        nickname = t.nickname,
      }
    end
  end
  return copy
end

local function ensureTrades(S, App)
  State.ensureProjectFields(S.project)
  if type(S.project.trades) ~= "table" then
    S.project.trades = cloneBase(S)
    if App then App.markDirty() end
  end
  return S.project.trades
end

local function tradeList(S)
  if type(S.project.trades) == "table" then return S.project.trades, true end
  -- Read-only view of vanilla; ensureTrades() clones before any write.
  return baseTrades(S), false
end

local function summarize(t)
  if type(t) ~= "table" then return "?" end
  local give = t.give or "?"
  local get = t.get or "?"
  local nick = t.nickname and (" (" .. t.nickname .. ")") or ""
  return give .. " -> " .. get .. nick
end

function Trades.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local trades, owned = tradeList(S)
  local ids = {}
  for i = 1, #trades do ids[i] = tostring(i) end

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "IN-GAME TRADES", ids, {
      queryKey = "tradesQuery",
      offsetKey = "tradesListOffset",
      selKey = "tradeIndexStr",
      accent = PAL.green,
      isOwned = function() return owned end,
      searchPh = "search give/get...",
      filter = function(id, q)
        local t = trades[tonumber(id)]
        local ql = q:lower()
        return tostring(id):find(ql, 1, true)
          or summarize(t):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = "+ Trade",
      onFooter = function()
        local list = ensureTrades(S, App)
        list[#list + 1] = {
          give = "ABRA", get = "MR_MIME", dialogset = 1, nickname = "MARCEL",
        }
        S.tradeIndexStr = tostring(#list)
        App.markDirty()
      end,
    })

  if not S.tradeIndexStr and shown[1] then S.tradeIndexStr = shown[1] end
  local idx = tonumber(S.tradeIndexStr)
  if not idx or not trades[idx] then
    Kit.emptyBox(formX, listY, formW, listH,
      #trades == 0
        and "No trades (Link Recomp / Import ROM for vanilla, or + Trade)"
        or "Select a trade")
    return
  end

  local t = trades[idx]
  Kit.caption(formX, y,
    string.format("#%d%s", idx, owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "tradesFormScroll", tostring(idx), owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s

  local function ensure()
    if owned then return S.project.trades[idx] end
    local list = ensureTrades(S, App)
    owned = true
    trades = list
    t = list[idx]
    return t
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro",
    "Events step \"In-game trade\" uses this 1-based index + a done flag.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s
  Kit.text("micro", summarize(t), viewX, fy, PAL.detail)
  fy = fy + 22 * s

  row("Wants (give)", function(fx, fy_, fw, fh_)
    local cur = tostring(t.give or "")
    local v = RegList.field(App, "trd_give", fx, fy_, fw, fh_, cur, "ABRA")
      :upper():gsub("%s+", "_")
    if v ~= cur then ensure().give = v end
  end)

  row("Offers (get)", function(fx, fy_, fw, fh_)
    local cur = tostring(t.get or "")
    local v = RegList.field(App, "trd_get", fx, fy_, fw, fh_, cur, "MR_MIME")
      :upper():gsub("%s+", "_")
    if v ~= cur then ensure().get = v end
  end)

  row("Nickname", function(fx, fy_, fw, fh_)
    local cur = tostring(t.nickname or "")
    local v = RegList.field(App, "trd_nick", fx, fy_, fw, fh_, cur, "MARCEL")
    if v ~= cur then ensure().nickname = v end
  end)

  row("Dialog set", function(fx, fy_, fw, fh_)
    local cur = tonumber(t.dialogset) or 1
    local v = RegList.num(App, "trd_ds", fx, fy_, 60 * s, fh_, cur)
    v = Theme.clamp(math.floor(v), 1, 3)
    if v ~= cur then ensure().dialogset = v end
    Kit.text("micro", "1-3 (WannaTrade text family)",
      fx + 70 * s, fy_ + 8 * s, PAL.faint)
  end)

  if not owned then
    Kit.text("micro", "First edit clones the full trades table into the mod.",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensure()
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "tradesFormScroll", contentTop, fy, view)

  if owned then
    if Kit.button(formX + 12 * s, listY + listH - 40 * s, 100 * s, 32 * s,
        "Delete", { kind = "danger" }) then
      table.remove(S.project.trades, idx)
      S.tradeIndexStr = S.project.trades[idx] and tostring(idx)
        or (S.project.trades[idx - 1] and tostring(idx - 1)) or nil
      App.markDirty()
    end
    if Kit.button(formX + 120 * s, listY + listH - 40 * s, 120 * s, 32 * s,
        "Revert all", {
          kind = "ghost",
          tooltip = "Drop mod trades table (back to vanilla on next open)",
        }) then
      S.project.trades = nil
      S.tradeIndexStr = nil
      App.markDirty()
    end
  end
end

return Trades
