-- Shared id-list + form chrome for content-editor registry panels.

local Kit = require("Kit")
local Theme = require("Theme")
local Search = require("Search")
local FormPane = require("FormPane")
local PAL = Theme.PAL

local RegList = {}

function RegList.cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

function RegList.field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

function RegList.num(App, id, x, y, w, h, value)
  local v = RegList.field(App, id, x, y, w, h, tostring(value or 0), "0")
  return tonumber(v) or value or 0
end

function RegList.sortedKeys(t)
  local ids = {}
  for id in pairs(t or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

function RegList.mergeIds(projectTbl, dataTbl)
  local seen, ids = {}, {}
  for id in pairs(projectTbl or {}) do
    seen[id] = true; ids[#ids + 1] = id
  end
  for id in pairs(dataTbl or {}) do
    if not seen[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

-- Draw left list. opts: queryKey, offsetKey, selKey, accent, rowH, filter(id)->bool
-- onSelect(id), footerLabel, onFooter()
-- Returns formX, formW, listY, listH, ids
function RegList.drawList(S, App, x, y, w, h, title, ids, opts)
  opts = opts or {}
  local s = Kit.scale
  local listW = opts.listW or math.min(220 * s, w * 0.28)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s
  Kit.caption(x, y, title)
  local qh = 28 * s
  local qy = y + 22 * s
  local qKey = opts.queryKey or "regQuery"
  local q, qChanged = Search.field(S, qKey, x, qy, listW, qh, opts.searchPh or "search...")
  local offKey = opts.offsetKey or "regListOffset"
  if qChanged then S[offKey] = 0 end
  if q ~= "" and opts.filter then
    local filtered = {}
    for _, id in ipairs(ids) do
      if opts.filter(id, q) then filtered[#filtered + 1] = id end
    end
    ids = filtered
  elseif q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      if id:lower():find(ql, 1, true) then filtered[#filtered + 1] = id end
    end
    ids = filtered
  end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)
  local rowH = opts.rowH or 30 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 4 * s)))
  S[offKey] = Kit.scroll(x + 8 * s, listY + 8 * s, listW - 16 * s, listH - 16 * s,
    S[offKey] or 0, #ids, perPage)
  local selKey = opts.selKey or "regId"
  local accent = opts.accent or PAL.blue
  local ry = listY + 8 * s
  for i = (S[offKey] or 0) + 1, math.min(#ids, (S[offKey] or 0) + perPage) do
    local id = ids[i]
    local owned = opts.isOwned and opts.isOwned(id)
    local rowW = listW - 16 * s
    if Kit.row(x + 8 * s, ry, rowW, rowH, S[selKey] == id, accent) then
      S[selKey] = id
      if opts.onSelect then opts.onSelect(id) end
    end
    Kit.text("mono", Kit.ellipsize("mono", id, rowW - 16 * s),
      x + 16 * s, ry + (rowH - Kit.textHeight("mono")) / 2,
      owned and PAL.text or PAL.muted)
    ry = ry + rowH + 4 * s
  end
  Kit.scrollbar(x + 8 * s, listY + 8 * s, listW - 16 * s, listH - 16 * s,
    S[offKey] or 0, #ids, perPage)
  if opts.footerLabel and Kit.button(x, y + h - 36 * s, listW, 32 * s,
      opts.footerLabel, { kind = "good" }) then
    if opts.onFooter then opts.onFooter() end
  end
  return formX, formW, listY, listH, ids
end

function RegList.beginForm(S, formX, listY, formW, listH, scrollKey, identity, footerH)
  local s = Kit.scale
  footerH = footerH or 12 * s
  local pad = 12 * s
  Kit.card(formX, listY, formW, listH, 12 * s)
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, scrollKey, identity)
  local fy, view = FormPane.begin(S, scrollKey, viewX, viewY, viewW, viewH)
  return fy, view, viewX, viewW
end

function RegList.modeChips(S, key, modes, x, y, s)
  local sx = x
  S[key] = S[key] or modes[1].id
  for _, m in ipairs(modes) do
    local on = S[key] == m.id
    local bw = Kit.textWidth("micro", m.label) + 18 * s
    if Kit.chip(sx, y, bw, 26 * s, m.label, on, PAL.green, nil, m.tip) then
      S[key] = m.id
    end
    sx = sx + bw + 4 * s
  end
  return y + 32 * s
end

return RegList
