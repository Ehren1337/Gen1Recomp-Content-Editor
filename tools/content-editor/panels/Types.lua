-- Types tab: browse/create types and edit matchup multipliers (x10 Gen1).

local Kit = require("Kit")
local Theme = require("Theme")
local Search = require("Search")
local TypeIds = require("TypeIds")
local State = require("State")
local FormPane = require("FormPane")
local PAL = Theme.PAL

local Types = {}

local MULTS = { 0, 5, 10, 20 }  -- immune / not very / neutral / super

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function typeRecord(S, id)
  if S.project.types and S.project.types[id] then
    return S.project.types[id], true
  end
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  if ok and TypeChart and TypeChart.TYPES and TypeChart.TYPES[id] then
    return TypeChart.TYPES[id], false
  end
  if S.data and S.data.type_chart and S.data.type_chart.types
      and S.data.type_chart.types[id] then
    return S.data.type_chart.types[id], false
  end
  return { name = id, category = "physical" }, false
end

local function ensureType(S, id, App)
  State.ensureProjectFields(S.project)
  if S.project.types[id] then return S.project.types[id] end
  local base = select(1, typeRecord(S, id))
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  local isVanilla = ok and TypeChart.TYPES and TypeChart.TYPES[id]
  S.project.types[id] = {
    id = id,
    name = base.name or id,
    category = base.category or "special",
    _isNew = not isVanilla,
  }
  App.markDirty()
  return S.project.types[id]
end

local function matchupKey(atk, def)
  return atk .. ">" .. def
end

local function getMultiplier(S, atk, def)
  local key = matchupKey(atk, def)
  if S.project.type_matchups and S.project.type_matchups[key] ~= nil then
    return S.project.type_matchups[key], true
  end
  if S.data and S.data.type_chart and S.data.type_chart.matchups then
    for _, row in ipairs(S.data.type_chart.matchups) do
      if row.attacker == atk and row.defender == def then
        return row.multiplier, false
      end
    end
  end
  return 10, false  -- Gen1 default neutral
end

local function setMultiplier(S, atk, def, mult, App)
  State.ensureProjectFields(S.project)
  S.project.type_matchups = S.project.type_matchups or {}
  S.project.type_matchups[matchupKey(atk, def)] = mult
  App.markDirty()
end

function Types.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local listW = math.min(200 * s, w * 0.24)
  Kit.caption(x, y, "TYPES")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qCh = Search.field(S, "typeQuery", x, qy, listW, qh, "search types...")
  if qCh then S.typeListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = TypeIds.list(S)
  if q ~= "" then ids = Search.filterIds(ids, q) end
  if not S.typeId then S.typeId = ids[1] end

  local rowH = 28 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 3 * s)))
  S.typeListOffset = Kit.scroll(x + 6 * s, listY + 8 * s, listW - 12 * s,
    listH - 16 * s, S.typeListOffset or 0, #ids, perPage)
  local ry = listY + 8 * s
  for i = (S.typeListOffset or 0) + 1,
      math.min(#ids, (S.typeListOffset or 0) + perPage) do
    local id = ids[i]
    local owned = S.project.types[id] ~= nil
    local rowW = listW - 12 * s
    if Kit.row(x + 6 * s, ry, rowW, rowH, S.typeId == id, PAL.yellow) then
      S.typeId = id
      S.typeMatchOffset = 0
    end
    Kit.text("mono", Kit.ellipsize("mono", id, rowW - 12 * s),
      x + 12 * s, ry + 6 * s, owned and PAL.text or PAL.muted)
    ry = ry + rowH + 3 * s
  end
  Kit.scrollbar(x + 6 * s, listY + 8 * s, listW - 12 * s, listH - 16 * s,
    S.typeListOffset or 0, #ids, perPage)

  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New type",
      { kind = "good" }) then
    local nid = "NEW_TYPE"
    local n = 1
    local all = TypeIds.list(S)
    local used = {}
    for _, id in ipairs(all) do used[id] = true end
    while used[nid] do n = n + 1; nid = "NEW_TYPE_" .. n end
    S.project.types[nid] = {
      id = nid, name = nid, category = "special", _isNew = true,
    }
    S.typeId = nid
    App.markDirty()
  end

  local formX = x + listW + 12 * s
  local formW = w - listW - 12 * s
  local id = S.typeId
  if not id then
    Kit.emptyBox(formX, listY, formW, listH, "No types")
    return
  end
  local rec, owned = typeRecord(S, id)
  Kit.caption(formX, y, id .. (owned and "" or "  (vanilla)"))
  Kit.card(formX, listY, formW, listH, 12 * s)
  local footerH = owned and 44 * s or 12 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, "typeFormScroll", tostring(id))
  local fy, view = FormPane.begin(S, "typeFormScroll", viewX, viewY, viewW, viewH)
  local contentTop = fy
  local fh = 28 * s
  local labelW = 110 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 12 * s, fh)
    fy = fy + fh + 8 * s
  end

  row("ID", function(fx, fy_, fw, fh_)
    local v = field(App, "ty_id", fx, fy_, fw, fh_, id, "TYPE_ID")
    if v ~= id and v:match("^[%w_]+$") and not (S.project.types and S.project.types[v]) then
      local taken = false
      for _, t in ipairs(TypeIds.list(S)) do if t == v then taken = true; break end end
      if not taken or owned then
        local r = ensureType(S, id, App)
        S.project.types[id] = nil
        r.id = v
        S.project.types[v] = r
        -- rewrite matchup keys
        local nm = {}
        for key, mult in pairs(S.project.type_matchups or {}) do
          local a, d = key:match("^([^>]+)>([^>]+)$")
          if a == id then a = v end
          if d == id then d = v end
          nm[a .. ">" .. d] = mult
        end
        S.project.type_matchups = nm
        S.typeId = v
        id = v
        App.markDirty()
      end
    end
  end)
  row("Name", function(fx, fy_, fw, fh_)
    local cur = rec.name or id
    local v = field(App, "ty_name", fx, fy_, fw, fh_, cur, "NAME")
    if v ~= cur then
      rec = ensureType(S, id, App)
      rec.name = v
    end
  end)
  row("Category", function(fx, fy_, fw, fh_)
    local cur = rec.category or "special"
    if Kit.chip(fx, fy_, 120 * s, fh_, cur:upper(), true, PAL.blue) then
      rec = ensureType(S, id, App)
      rec.category = (cur == "physical") and "special" or "physical"
      App.markDirty()
    end
  end)

  Kit.text("micro",
    "Matchups use Gen1 x10 multipliers: 0 immune, 5 NVE, 10 neutral, 20 SE.",
    viewX, fy, PAL.muted)
  fy = fy + 22 * s
  Kit.caption(viewX, fy, "AS ATTACKER vs...")
  fy = fy + 22 * s

  local others = TypeIds.list(S)
  local mRowH = 26 * s
  for _, def in ipairs(others) do
    local mult, custom = getMultiplier(S, id, def)
    Kit.text("mono", def, viewX + 4 * s, fy + 5 * s, custom and PAL.text or PAL.muted)
    local bx = viewX + viewW - (#MULTS * 52 * s)
    for _, m in ipairs(MULTS) do
      local on = mult == m
      local label = (m == 0 and "0") or (m == 5 and "0.5") or (m == 10 and "1x") or "2x"
      if Kit.chip(bx, fy, 48 * s, mRowH, label, on, PAL.green) then
        setMultiplier(S, id, def, m, App)
      end
      bx = bx + 52 * s
    end
    fy = fy + mRowH + 3 * s
  end
  FormPane.finish(S, "typeFormScroll", contentTop, fy, view)

  if owned and Kit.button(formX + 12 * s, listY + listH - 36 * s, 120 * s, 28 * s,
      "Revert type", { kind = "danger" }) then
    S.project.types[id] = nil
    -- drop matchups involving this type that were only for a new type
    if rec._isNew then
      local nm = {}
      for key, mult in pairs(S.project.type_matchups or {}) do
        local a, d = key:match("^([^>]+)>([^>]+)$")
        if a ~= id and d ~= id then nm[key] = mult end
      end
      S.project.type_matchups = nm
      S.typeId = TypeIds.list(S)[1]
    end
    App.markDirty()
  end
end

return Types
