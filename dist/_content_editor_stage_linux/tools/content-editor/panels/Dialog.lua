-- Dialog tab: browse every TEXT_* / string for a map (vanilla + project),
-- edit bodies, emit text:override + text_pointers:patch on Save.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Search = require("Search")
local PAL = Theme.PAL

local Dialog = {}

-- Truncate on UTF-8 codepoint boundaries (byte sub() splits POKeMON / etc).
local function utf8Prefix(s, maxBytes)
  s = tostring(s or "")
  if #s <= maxBytes then return s end
  local i, n = 1, #s
  local last = 1
  while i <= n and i <= maxBytes do
    last = i
    local b = s:byte(i)
    local len = 1
    if b >= 0xF0 then len = 4
    elseif b >= 0xE0 then len = 3
    elseif b >= 0xC0 then len = 2
    end
    if i + len - 1 > n then len = 1 end
    if i + len - 1 > maxBytes then break end
    i = i + len
    last = i
  end
  return s:sub(1, last - 1)
end

local function allMapIds(S)
  local seen, ids = {}, {}
  if S.project then
    for id in pairs(S.project.maps or {}) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  if S.data and S.data.maps then
    for id in pairs(S.data.maps) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  return ids
end

local function mapRecord(S, mapId)
  if S.project and S.project.maps and S.project.maps[mapId] then
    return S.project.maps[mapId], true
  end
  if S.data and S.data.maps then return S.data.maps[mapId], false end
  return nil, false
end

local function pointerTable(S, label)
  local proj = S.project and S.project.text_pointers and S.project.text_pointers[label]
  local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
  return proj, base
end

-- Resolve TEXT_* -> string id (_FooText) using project override, then vanilla.
local function resolveStringId(S, mapId, textId)
  if not textId then return nil end
  local label = State.mapLabel(S, mapId)
  local proj, base = pointerTable(S, label)
  if proj and proj[textId] and proj[textId].text then
    return proj[textId].text, label, true
  end
  if base and base[textId] and base[textId].text then
    return base[textId].text, label, false
  end
  -- invented binding for brand-new pins
  local invented = "_" .. textId:gsub("^TEXT_", "")
  return invented, label, false
end

local function resolveBody(S, strId)
  if not strId then return "" end
  if S.project.text and S.project.text[strId] ~= nil then
    return S.project.text[strId], true
  end
  if S.data and S.data.text and S.data.text[strId] ~= nil then
    return S.data.text[strId], false
  end
  return "", false
end

local function collectPins(S, mapId)
  local map = mapRecord(S, mapId)
  local pins, seen = {}, {}
  local function add(kind, index, textId, label, x, y)
    if not textId or seen[textId] then return end
    seen[textId] = true
    local strId = select(1, resolveStringId(S, mapId, textId))
    local body = select(1, resolveBody(S, strId))
    if type(body) ~= "string" then body = "" end
    local preview = body:gsub("\n", " "):gsub("\f", " / "):gsub("\v", " ")
    if #preview > 40 then preview = utf8Prefix(preview, 38) .. "..." end
    pins[#pins + 1] = {
      kind = kind, index = index, textId = textId,
      label = label, x = x, y = y,
      strId = strId, preview = preview,
    }
  end

  if map then
    for i, obj in ipairs(map.objects or {}) do
      add("object", i,
        obj.text or ("TEXT_" .. mapId .. "_OBJ" .. i),
        string.format("NPC #%d %s", obj.index or i, obj.sprite or ""),
        obj.x, obj.y)
    end
    for i, sign in ipairs(map.signs or {}) do
      add("sign", i,
        sign.text or ("TEXT_" .. mapId .. "_SIGN" .. i),
        string.format("Sign #%d", i),
        sign.x, sign.y)
    end
  end

  -- every TEXT_* registered for this map label (trainers, scripts, unused, ...)
  local label = State.mapLabel(S, mapId)
  local proj, base = pointerTable(S, label)
  local function addPtrTable(ptrs)
    if not ptrs then return end
    local ids = {}
    for textId in pairs(ptrs) do ids[#ids + 1] = textId end
    table.sort(ids)
    for _, textId in ipairs(ids) do
      local entry = ptrs[textId]
      local hint = (entry and entry.label) or textId
      add("pointer", nil, textId, hint, nil, nil)
    end
  end
  addPtrTable(base)
  addPtrTable(proj)

  return pins
end

local function ensureOwnedMap(S, mapId)
  local map, owned = mapRecord(S, mapId)
  if not map or owned then return map end
  local copy = {}
  for k, v in pairs(map) do copy[k] = v end
  copy.objects = {}
  for i, o in ipairs(map.objects or {}) do
    local oc = {}
    for k, v in pairs(o) do oc[k] = v end
    copy.objects[i] = oc
  end
  copy.signs = {}
  for i, s in ipairs(map.signs or {}) do
    local sc = {}
    for k, v in pairs(s) do sc[k] = v end
    copy.signs[i] = sc
  end
  copy._isNew = false
  S.project.maps[mapId] = copy
  return copy
end

-- Bind project pointer + text on first real edit (not on mere selection).
local function ensureEditable(S, mapId, textId, App)
  State.ensureProjectFields(S.project)
  local strId, label = resolveStringId(S, mapId, textId)
  S.project.text_pointers[label] = S.project.text_pointers[label] or {}
  if not S.project.text_pointers[label][textId] then
    local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
    local src = base and base[textId]
    local copy = {
      text = (src and src.text) or strId,
      label = src and src.label or nil,
      asm = src and src.asm or nil,
      nurse = src and src.nurse or nil,
      pc = src and src.pc or nil,
      cableClub = src and src.cableClub or nil,
    }
    if src and type(src.mart) == "table" then
      copy.mart = {}
      for i, id in ipairs(src.mart) do copy.mart[i] = id end
    end
    S.project.text_pointers[label][textId] = copy
  end
  if S.project.text[strId] == nil then
    local body = select(1, resolveBody(S, strId))
    S.project.text[strId] = body
  end
  local map = ensureOwnedMap(S, mapId)
  if map then
    for _, pin in ipairs(collectPins(S, mapId)) do
      if pin.textId == textId then
        if pin.kind == "object" and map.objects[pin.index] then
          map.objects[pin.index].text = textId
        elseif pin.kind == "sign" and map.signs[pin.index] then
          map.signs[pin.index].text = textId
        end
      end
    end
  end
  App.markDirty()
  return strId
end

function Dialog.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local col1 = math.min(200 * s, w * 0.22)
  local col2 = math.min(260 * s, w * 0.30)
  local col3 = w - col1 - col2 - 24 * s

  -- maps
  Kit.caption(x, y, "MAP")
  local qh = 28 * s
  local qy = y + 22 * s
  local mapQ, mapQCh = Search.field(S, "dialogMapQuery", x, qy, col1, qh, "search maps...")
  if mapQCh then S.dialogMapOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = math.max(40 * s, h - (listY - y))
  Kit.card(x, listY, col1, listH, 12 * s)
  local maps = Search.filterIds(allMapIds(S), mapQ)
  if not S.dialogMapId then S.dialogMapId = S.mapId or maps[1] end
  local rowH = 26 * s
  local perMap = math.max(1, math.floor((listH - 16 * s) / (rowH + 2 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = col1 - 12 * s
  local mapScrollH = listH - 16 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.dialogMapOffset = Kit.scroll(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.dialogMapOffset or 0, #maps, perMap)
  local ry = listY + 8 * s
  for i = (S.dialogMapOffset or 0) + 1,
      math.min(#maps, (S.dialogMapOffset or 0) + perMap) do
    local id = maps[i]
    if Kit.row(mapScrollX, ry, mapRowW, rowH, S.dialogMapId == id, PAL.blue) then
      S.dialogMapId = id
      S.dialogTextId = nil
      S.dialogPinOffset = 0
    end
    local textMax = math.max(8, mapRowW - 12 * s)
    Kit.pushClip(mapScrollX, ry, mapRowW, rowH)
    Kit.text("micro", Kit.ellipsize("micro", id, textMax),
      mapScrollX + 6 * s, ry + 6 * s, PAL.text)
    Kit.popClip()
    ry = ry + rowH + 2 * s
  end
  S.dialogMapOffset = Kit.scrollbar(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.dialogMapOffset or 0, #maps, perMap)

  -- pins / all TEXT_* for map
  local px = x + col1 + 12 * s
  Kit.caption(px, y, "DIALOG")
  local pinQ, pinQCh = Search.field(S, "dialogPinQuery", px, qy, col2, qh, "search dialog...")
  if pinQCh then S.dialogPinOffset = 0 end
  Kit.card(px, listY, col2, listH, 12 * s)
  local pins = Search.filterItems(collectPins(S, S.dialogMapId), pinQ, function(p)
    return table.concat({
      p.textId or "", p.label or "", p.preview or "", p.strId or "",
    }, " ")
  end)
  local pinRowH = 34 * s
  local perPin = math.max(1, math.floor((listH - 16 * s) / (pinRowH + 4 * s)))
  local pinScrollX = px + 6 * s
  local pinScrollW = col2 - 12 * s
  local pinRowW = Kit.scrollInnerWidth(pinScrollW)
  S.dialogPinOffset = Kit.scroll(pinScrollX, listY + 8 * s, pinScrollW,
    mapScrollH, S.dialogPinOffset or 0, #pins, perPin)
  ry = listY + 8 * s
  for i = (S.dialogPinOffset or 0) + 1,
      math.min(#pins, (S.dialogPinOffset or 0) + perPin) do
    local pin = pins[i]
    local on = S.dialogTextId == pin.textId
    if Kit.row(pinScrollX, ry, pinRowW, pinRowH, on, PAL.green) then
      S.dialogTextId = pin.textId
      -- selection only -- do not clone / invent Hello!
    end
    local tw = pinRowW - 12 * s
    Kit.text("micro", Kit.ellipsize("micro", tostring(pin.label or ""), tw),
      px + 12 * s, ry + 2 * s, PAL.text)
    local sub = pin.preview ~= "" and pin.preview or pin.textId
    Kit.text("micro", Kit.ellipsize("micro", tostring(sub or ""), tw),
      px + 12 * s, ry + 16 * s, PAL.faint)
    ry = ry + pinRowH + 4 * s
  end
  S.dialogPinOffset = Kit.scrollbar(pinScrollX, listY + 8 * s, pinScrollW,
    mapScrollH, S.dialogPinOffset or 0, #pins, perPin)
  if #pins == 0 then
    Kit.text("micro", "No dialog on this map",
      px + 12 * s, listY + 16 * s, PAL.muted)
  end

  -- editor
  local ex = px + col2 + 12 * s
  Kit.caption(ex, y, "TEXT")
  Kit.card(ex, listY, col3, listH, 12 * s)
  if not S.dialogTextId then
    Kit.emptyBox(ex + 8 * s, listY + 8 * s, col3 - 16 * s, listH - 16 * s,
      "Select a dialog entry")
    return
  end

  local strId, label = resolveStringId(S, S.dialogMapId, S.dialogTextId)
  local body, ownedText = resolveBody(S, strId)
  if type(body) ~= "string" then body = "" end
  Kit.text("small", tostring(S.dialogTextId or ""), ex + 12 * s, listY + 12 * s, PAL.caption)
  Kit.text("micro", string.format("%s  |  %s%s",
      tostring(strId), tostring(label), ownedText and "" or "  (vanilla)"),
    ex + 12 * s, listY + 32 * s, PAL.faint)

  Kit.text("micro", "Use \\n for new line, \\f for page break, {PLAYER} for name",
    ex + 12 * s, listY + 52 * s, PAL.muted)
  local display = body:gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\v", "\\v")
  local fieldW = math.max(40 * s, col3 - 24 * s)
  local edited = Kit.textfield("dlg_body", ex + 12 * s, listY + 72 * s,
    fieldW, 36 * s, display, "(empty)")
  if edited then
    local decoded = edited:gsub("\\n", "\n"):gsub("\\f", "\f"):gsub("\\v", "\v")
    if decoded ~= body then
      strId = ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
      S.project.text[strId] = decoded
      App.markDirty()
      body = decoded
      ownedText = true
    end
  end

  -- multi-line preview
  local previewY = listY + 120 * s
  local previewH = math.max(40 * s, math.min(120 * s, listH - 200 * s))
  Theme.col(PAL.bgBot or PAL.card, 1)
  love.graphics.rectangle("fill", ex + 12 * s, previewY, fieldW, previewH, 8 * s, 8 * s)
  love.graphics.setColor(1, 1, 1, 1)
  local py = previewY + 8 * s
  for line in (body .. "\n"):gmatch("(.-)\n") do
    if py + 14 * s > previewY + previewH - 8 * s then
      Kit.text("micro", "...", ex + 20 * s, py, PAL.faint)
      break
    end
    local shown = line:gsub("\f", "[page]"):gsub("\v", " ")
    Kit.text("mono", utf8Prefix(shown, 48), ex + 20 * s, py, PAL.detail)
    py = py + 14 * s
  end

  local by = previewY + previewH + 12 * s
  if Kit.button(ex + 12 * s, by, 160 * s, 30 * s, "Insert {PLAYER}",
      { kind = "accent" }) then
    strId = ensureEditable(S, S.dialogMapId, S.dialogTextId, App)
    S.project.text[strId] = (S.project.text[strId] or body or "") .. "{PLAYER}"
    App.markDirty()
  end
  if Kit.button(ex + 184 * s, by, 140 * s, 30 * s, "Open in Events",
      { kind = "ghost" }) then
    -- Browse only — do not invent a Hello! stub that would override vanilla.
    S.tab = "events"
    S.eventsMode = "scripts"
    S.eventMapId = S.dialogMapId
    S.eventScriptKey = (S.dialogMapId or "") .. "/" .. (S.dialogTextId or "")
  end
  if ownedText and Kit.button(ex + 12 * s, by + 38 * s, 120 * s, 28 * s, "Revert",
      { kind = "danger" }) then
    if strId then S.project.text[strId] = nil end
    local lbl = State.mapLabel(S, S.dialogMapId)
    if S.project.text_pointers[lbl] then
      S.project.text_pointers[lbl][S.dialogTextId] = nil
      if not next(S.project.text_pointers[lbl]) then
        S.project.text_pointers[lbl] = nil
      end
    end
    App.markDirty()
  end

  Kit.text("micro",
    "Shows vanilla dialog. First edit clones into the mod (Save = text:override).",
    ex + 12 * s, listY + listH - 28 * s, PAL.faint)
end

return Dialog
