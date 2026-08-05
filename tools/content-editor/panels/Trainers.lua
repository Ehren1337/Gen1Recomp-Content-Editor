-- Trainers tab: full class data (parties, pic, AI, money) + map headers.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Search = require("Search")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local FormPane = require("FormPane")
local ModIO = require("ModIO")
local PAL = Theme.PAL

local Trainers = {}

local SECTIONS = {
  { id = "basics", label = "Basics" },
  { id = "parties", label = "Parties" },
  { id = "place", label = "Place" },
}

local function allTrainerIds(S)
  local seen, ids = {}, {}
  for id in pairs((S.project and S.project.trainers) or {}) do
    seen[id] = true; ids[#ids + 1] = id
  end
  if S.data and S.data.trainers then
    for id in pairs(S.data.trainers) do
      if not seen[id] then ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  return ids
end

local function getTrainer(S, id)
  if not id then return nil, false end
  if S.project.trainers[id] then return S.project.trainers[id], true end
  if S.data and S.data.trainers and S.data.trainers[id] then
    return S.data.trainers[id], false
  end
  return nil, false
end

local function deepCloneTrainer(tr, id)
  local copy = {
    id = tr.id or id,
    name = tr.name,
    baseMoney = tr.baseMoney,
    index = tr.index,
    pic = tr.pic,
    basePic = tr.basePic,
    paletteSource = tr.paletteSource,
    source = tr.source,
    aiMods = tr.aiMods and { unpack(tr.aiMods) } or nil,
    aiClass = tr.aiClass,
    battleTheme = tr.battleTheme,
    parties = {},
    _isNew = false,
  }
  for pi, party in ipairs(tr.parties or {}) do
    copy.parties[pi] = {}
    for mi, mon in ipairs(party) do
      copy.parties[pi][mi] = { level = mon.level, species = mon.species }
    end
  end
  return copy
end

local function ensureOwned(S, id, App)
  local tr, owned = getTrainer(S, id)
  if not tr then return nil end
  if owned then return tr end
  local copy = deepCloneTrainer(tr, id)
  S.project.trainers[id] = copy
  if App then App.markDirty() end
  return copy
end

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function parseAiMods(str)
  local mods = {}
  for part in (str .. ","):gmatch("([^,]*),") do
    part = part:match("^%s*(.-)%s*$")
    local n = tonumber(part)
    if n then mods[#mods + 1] = n end
  end
  return mods
end

local function cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

-- Runtime looks up ai_classes[trainer.aiClass or trainer.id].
local function aiClassTable(S)
  if S.data and S.data.ai_classes then return S.data.ai_classes end
  local ok, t = pcall(require, "data.scripts.ai_classes")
  return ok and t or {}
end

local function aiClassIds(S)
  if S._aiClassIds then return S._aiClassIds end
  local ids = {}
  for id in pairs(aiClassTable(S)) do
    if type(id) == "string" and not id:match("^LAYER_") then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  S._aiClassIds = ids
  return ids
end

local function summarizeAi(rec)
  if not rec then return "GenericAI (no items/switch)" end
  local bits = {}
  if rec.uses then bits[#bits + 1] = "uses=" .. tostring(rec.uses) end
  if rec.item then bits[#bits + 1] = tostring(rec.item) end
  if rec.chance then bits[#bits + 1] = "chance=" .. tostring(rec.chance) end
  if rec.onStatus then bits[#bits + 1] = "onStatus" end
  if rec.switch then bits[#bits + 1] = "switch" end
  if rec.hpBelow then bits[#bits + 1] = "hp<1/" .. tostring(rec.hpBelow) end
  if #bits == 0 then return "custom AI record" end
  return table.concat(bits, "  ")
end

local function musicIds(S)
  if S._musicIds then return S._musicIds end
  local ids = { "" } -- empty = engine default
  local songs = S.data and S.data.audio and S.data.audio.songs
  if type(songs) == "table" then
    for id in pairs(songs) do
      if type(id) == "string" then ids[#ids + 1] = id end
    end
  end
  if #ids == 1 then
    for _, id in ipairs({
      "Music_Gym", "Music_TrainerBattle", "Music_MeetMaleTrainer",
      "Music_MeetFemaleTrainer", "Music_MeetEvilTrainer",
      "Music_IndigoPlateau", "Music_FinalBattle",
    }) do
      ids[#ids + 1] = id
    end
  end
  table.sort(ids, function(a, b)
    if a == "" then return true end
    if b == "" then return false end
    return a < b
  end)
  S._musicIds = ids
  return ids
end

function Trainers.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local listW = math.min(220 * s, w * 0.28)
  Kit.caption(x, y, "TRAINERS")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "trainerQuery", x, qy, listW, qh, "search trainers...")
  if qChanged then S.trainerListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allTrainerIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local tr = getTrainer(S, id)
      local name = tr and tostring(tr.name or "") or ""
      if id:lower():find(ql, 1, true) or name:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  if not S.trainerId then S.trainerId = ids[1] end
  local rowH = 28 * s
  local thumb = 22 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 2 * s)))
  local scrollX, scrollY = x + 6 * s, listY + 8 * s
  local scrollW, scrollH = listW - 12 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S.trainerListOffset = Kit.scroll(scrollX, scrollY, scrollW, scrollH,
    S.trainerListOffset or 0, #ids, perPage)
  local ry = scrollY
  for i = (S.trainerListOffset or 0) + 1,
      math.min(#ids, (S.trainerListOffset or 0) + perPage) do
    local id = ids[i]
    local rowTr = select(1, getTrainer(S, id))
    local owned = S.project.trainers[id] ~= nil
    if Kit.row(scrollX, ry, rowW, rowH, S.trainerId == id, PAL.red) then
      S.trainerId = id
      S.trainerPartyIndex = 1
    end
    Preview.draw(S, Preview.trainerPicPath(S, rowTr),
      x + 10 * s, ry + (rowH - thumb) / 2, thumb, thumb,
      Preview.trainerPaletteName(S, rowTr))
    local textX = x + 14 * s + thumb
    Kit.text("micro",
      Kit.ellipsize("micro", id, math.max(8, rowW - (textX - scrollX) - 6 * s)),
      textX, ry + 7 * s, owned and PAL.text or PAL.muted)
    ry = ry + rowH + 2 * s
  end
  S.trainerListOffset = Kit.scrollbar(scrollX, scrollY, scrollW, scrollH,
    S.trainerListOffset or 0, #ids, perPage)

  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New trainer",
      { kind = "good" }) then
    local nid = "OPP_NEW_TRAINER"
    local n = 1
    while S.project.trainers[nid] or (S.data.trainers and S.data.trainers[nid]) do
      n = n + 1
      nid = "OPP_NEW_TRAINER_" .. n
    end
    S.project.trainers[nid] = {
      id = nid, name = "COOLTRAINER", baseMoney = 20, index = 200,
      parties = { { { level = 5, species = "PIDGEY" } } },
      basePic = "OPP_YOUNGSTER",
      aiMods = { 1 },
      _isNew = true,
    }
    S.trainerId = nid
    App.markDirty()
  end

  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s
  local tr, owned = getTrainer(S, S.trainerId)
  if not tr then
    Kit.emptyBox(formX, listY, formW, listH, "No trainers in data")
    return
  end

  local function mutate()
    tr = ensureOwned(S, S.trainerId, App)
    owned = true
    return tr
  end

  Kit.caption(formX, y, (S.trainerId or "?") .. (owned and "" or "  (vanilla)"))
  local secY = y + 22 * s
  local sx = formX
  S.trainerSection = S.trainerSection or "basics"
  for _, sec in ipairs(SECTIONS) do
    local on = S.trainerSection == sec.id
    local bw = Kit.textWidth("micro", sec.label) + 18 * s
    if Kit.chip(sx, secY, bw, 26 * s, sec.label, on, PAL.red) then
      S.trainerSection = sec.id
    end
    sx = sx + bw + 4 * s
  end

  Kit.card(formX, listY, formW, listH, 12 * s)
  local footerH = owned and 44 * s or 12 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, "trainerFormScroll",
    tostring(S.trainerId) .. "|" .. tostring(S.trainerSection))
  local fy, view = FormPane.begin(S, "trainerFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local fh = 28 * s
  local labelW = 100 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 12 * s, fh)
    fy = fy + fh + 8 * s
  end

  if S.trainerSection == "basics" then
    local prevW = 112 * s
    local trPal = Preview.trainerPaletteName(S, tr)
    local picX = viewX + viewW - prevW
    Preview.draw(S, Preview.trainerPicPath(S, tr),
      picX, fy, prevW, prevW, trPal)
    Preview.drawNamedSwatches(S, trPal, picX, fy + prevW + 4 * s, prevW, 12 * s)
    local function openTrPal()
      PalettePicker.open(S, {
        current = tr.paletteSource,
        allowClear = true,
        clearLabel = "(MEWMON default)",
        title = "TRAINER PIC PALETTE",
        onPick = function(id)
          tr = mutate()
          tr.paletteSource = id
          Preview.invalidate()
          App.markDirty()
        end,
      })
    end
    if Kit.press(picX, fy, prevW, prevW + 18 * s) then openTrPal() end
    local textW = viewW - prevW - 16 * s

    row("ID", function(fx, fy_, fw, fh_)
      fw = math.min(fw, textW - labelW)
      local v = field(App, "tr_id", fx, fy_, fw, fh_, tr.id or S.trainerId, "OPP_")
      if v ~= (tr.id or S.trainerId) and v:match("^[%w_]+$")
         and not S.project.trainers[v]
         and not (S.data.trainers and S.data.trainers[v]) then
        tr = mutate()
        S.project.trainers[S.trainerId] = nil
        tr.id = v
        S.project.trainers[v] = tr
        S.trainerId = v
        App.markDirty()
      end
    end)
    row("Name", function(fx, fy_, fw, fh_)
      local v = field(App, "tr_name", fx, fy_, math.min(fw, textW - labelW), fh_,
        tr.name or "", "NAME")
      if v ~= (tr.name or "") then tr = mutate(); tr.name = v end
    end)
    row("Money", function(fx, fy_, fw, fh_)
      local v = tonumber(field(App, "tr_money", fx, fy_, 80 * s, fh_,
        tostring(tr.baseMoney or 20), "20")) or 20
      if v ~= (tr.baseMoney or 20) then tr = mutate(); tr.baseMoney = v end
    end)
    row("Index", function(fx, fy_, fw, fh_)
      local cur = tr.index or 0
      local v = tonumber(field(App, "tr_idx", fx, fy_, 80 * s, fh_,
        tostring(cur), "0")) or 0
      if v ~= cur then tr = mutate(); tr.index = v end
    end)
    row("Base pic", function(fx, fy_, fw, fh_)
      local v = field(App, "tr_base", fx, fy_, math.min(fw, textW - labelW), fh_,
        tr.basePic or "", "OPP_YOUNGSTER")
      if v ~= (tr.basePic or "") then
        tr = mutate()
        tr.basePic = (v ~= "" and v) or nil
      end
    end)
    row("Pic path", function(fx, fy_, fw, fh_)
      local path = tr.pic or ""
      Kit.text("micro", path ~= "" and path or "(from base pic)",
        fx, fy_ + 8 * s, PAL.muted)
      if Kit.button(fx + math.min(fw, textW - labelW) - 90 * s, fy_, 90 * s, fh_,
          "Browse", { kind = "ghost", tooltip = "Import trainer portrait PNG" }) then
        tr = mutate()
        local tid = tr.id or S.trainerId
        App.pickFile("Trainer portrait PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
          function(picked)
            local t = S.project.trainers[tid]
            if not t then return end
          App.importToMod(picked, nil, function(rel)
              t.pic = rel
            end)
          end)
      end
    end)
    row("AI mods", function(fx, fy_, fw, fh_)
      local joined = table.concat(tr.aiMods or {}, ",")
      local v = field(App, "tr_ai", fx, fy_, math.min(fw, textW - labelW), fh_,
        joined, "1,3")
      if v ~= joined then tr = mutate(); tr.aiMods = parseAiMods(v) end
    end)
    -- Effective AI = ai_classes[aiClass or id]; most vanilla trainers leave
    -- aiClass nil and rely on their own id (or GenericAI if unlisted).
    do
      local classes = aiClassTable(S)
      local effective = tr.aiClass or S.trainerId
      local rec = classes[effective]
      local override = tr.aiClass and tr.aiClass ~= ""
      Kit.text("small", "AI class", viewX, fy + 6 * s, PAL.caption)
      local fx = viewX + labelW
      local fw = math.min(viewW - labelW - 12 * s, textW - labelW)
      local label = override and tostring(tr.aiClass)
        or (rec and (tostring(effective) .. " (self)") or "(GenericAI)")
      if Kit.button(fx, fy, fw, fh, Kit.ellipsize("small", label, fw - 8 * s),
          { kind = "ghost" }) then
        local ids = { "" }
        for _, id in ipairs(aiClassIds(S)) do ids[#ids + 1] = id end
        local nextId = cycle(ids, tr.aiClass or "")
        tr = mutate()
        tr.aiClass = (nextId ~= "" and nextId) or nil
        App.markDirty()
      end
      fy = fy + fh + 2 * s
      Kit.text("micro",
        Kit.ellipsize("micro",
          "lookup " .. tostring(effective) .. " — " .. summarizeAi(rec), fw + labelW),
        viewX, fy, PAL.faint)
      fy = fy + 16 * s
    end

    do
      Kit.text("small", "Theme", viewX, fy + 6 * s, PAL.caption)
      local fx = viewX + labelW
      local fw = math.min(viewW - labelW - 12 * s, textW - labelW)
      local cur = tr.battleTheme or ""
      local label = cur ~= "" and cur or "(default music)"
      if Kit.button(fx, fy, math.max(80 * s, fw - 100 * s), fh,
          Kit.ellipsize("small", label, fw - 108 * s), { kind = "ghost" }) then
        local nextId = cycle(musicIds(S), cur)
        tr = mutate()
        tr.battleTheme = (nextId ~= "" and nextId) or nil
        App.markDirty()
      end
      local v = field(App, "tr_theme", fx + fw - 96 * s, fy, 96 * s, fh,
        cur, "Music_...")
      if v ~= cur then
        tr = mutate()
        tr.battleTheme = (v ~= "" and v) or nil
      end
      fy = fy + fh + 8 * s
    end

    do
      Kit.text("small", "Palette", viewX, fy + 6 * s, PAL.caption)
      local fx = viewX + labelW
      local fw = math.min(viewW - labelW - 12 * s, textW - labelW)
      PalettePicker.row(S, {
        x = fx, y = fy, w = fw, h = fh,
        current = tr.paletteSource or "",
        effective = Preview.trainerPaletteName(S, tr),
        emptyLabel = "(MEWMON)",
        clearLabel = "(MEWMON default)",
        allowClear = true,
        title = "TRAINER PIC PALETTE",
        tooltip = "SGB palette for this trainer's battle pic",
        onPick = function(id)
          tr = mutate()
          tr.paletteSource = id
          Preview.invalidate()
          App.markDirty()
        end,
      })
      fy = fy + fh + 2 * s
      local hint = (tr.paletteSource and tr.paletteSource ~= "")
        and ("OBJ / pic palette: " .. tr.paletteSource)
        or "empty = MEWMON battle portrait palette"
      if tr.source and not tr.paletteSource then
        hint = hint .. "  (ROM " .. tostring(tr.source) .. ")"
      end
      Kit.text("micro", Kit.ellipsize("micro", hint, fw + labelW),
        viewX, fy, PAL.faint)
      fy = fy + 16 * s
    end

    Kit.text("micro",
      string.format("%d parties - preview uses pic or basePic",
        #(tr.parties or {})),
      viewX, fy + 4 * s, PAL.faint)
    fy = fy + 28 * s

  elseif S.trainerSection == "parties" then
    tr.parties = tr.parties or { {} }
    S.trainerPartyIndex = S.trainerPartyIndex or 1
    if S.trainerPartyIndex > #tr.parties then
      S.trainerPartyIndex = #tr.parties
    end
    Kit.text("micro", "Each class can have multiple parties (roster variants).",
      viewX, fy, PAL.muted)
    fy = fy + 20 * s

    local px = viewX
    for pi = 1, #tr.parties do
      local on = S.trainerPartyIndex == pi
      local bw = 70 * s
      if Kit.chip(px, fy, bw, fh, "P" .. pi, on, PAL.yellow) then
        S.trainerPartyIndex = pi
      end
      px = px + bw + 4 * s
    end
    if #tr.parties < 20 and Kit.button(px, fy, 70 * s, fh, "+Party",
        { kind = "good" }) then
      tr = mutate()
      tr.parties[#tr.parties + 1] = { { level = 5, species = "PIDGEY" } }
      S.trainerPartyIndex = #tr.parties
      App.markDirty()
    end
    if #tr.parties > 1 and Kit.button(px + 78 * s, fy, 70 * s, fh, "Del P",
        { kind = "danger" }) then
      tr = mutate()
      table.remove(tr.parties, S.trainerPartyIndex)
      S.trainerPartyIndex = math.min(S.trainerPartyIndex, #tr.parties)
      App.markDirty()
    end
    fy = fy + fh + 12 * s

    local party = tr.parties[S.trainerPartyIndex] or {}
    local prevSize = 56 * s
    local slots = math.max(1, #party)
    for mi = 1, slots do
      local mon = party[mi] or { level = 5, species = "PIDGEY" }
      local speciesDef = (S.project.pokemon and S.project.pokemon[mon.species])
        or (S.data and S.data.pokemon and S.data.pokemon[mon.species])
      if speciesDef and speciesDef.spriteFront then
        Preview.draw(S, speciesDef.spriteFront, viewX, fy, prevSize, prevSize,
          Preview.monPaletteName(S, speciesDef, mon.species))
      else
        Preview.draw(S, nil, viewX, fy, prevSize, prevSize)
      end
      local mx = viewX + prevSize + 10 * s
      local lvl = tonumber(field(App, "tr_lv_" .. mi, mx, fy, 50 * s, fh,
        tostring(mon.level or 5), "5")) or 5
      local sp = field(App, "tr_sp_" .. mi, mx + 60 * s, fy, 160 * s, fh,
        mon.species or "PIDGEY", "PIDGEY"):upper():gsub("%s+", "_")
      if lvl ~= (mon.level or 5) or sp ~= (mon.species or "") then
        tr = mutate()
        local p = tr.parties[S.trainerPartyIndex]
        p[mi] = { level = lvl, species = sp }
      end
      if Kit.button(mx + 230 * s, fy, 36 * s, fh, "X", { kind = "danger" })
          and #party > 1 then
        tr = mutate()
        table.remove(tr.parties[S.trainerPartyIndex], mi)
        App.markDirty()
        break
      end
      fy = fy + math.max(fh, prevSize) + 6 * s
    end
    if #party < 6 and Kit.button(viewX, fy, 100 * s, 28 * s, "+ Mon",
        { kind = "accent" }) then
      tr = mutate()
      local p = tr.parties[S.trainerPartyIndex]
      p[#p + 1] = { level = 5, species = "PIDGEY" }
      App.markDirty()
    end

  else -- place
    Kit.text("micro",
      "Use the Maps TRAINER tool to stamp an object with this class.",
      viewX, fy, PAL.muted)
    fy = fy + 24 * s
    if Kit.button(viewX, fy, 180 * s, 30 * s, "Use on Maps tab",
        { kind = "primary" }) then
      S.tab = "maps"
      S.mapTool = "trainer"
      S.status = "Trainer tool active â€” click a cell to place " .. tostring(S.trainerId)
    end
    fy = fy + 44 * s

    local mapId = S.mapId or S.dialogMapId
    if mapId then
      local label = State.mapLabel(S, mapId)
      Kit.text("small", "Header on " .. label, viewX, fy, PAL.caption)
      fy = fy + 22 * s
      S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
      local objIndex = tonumber(S.trainerHeaderIndex) or 1
      S.trainerHeaderIndex = objIndex
      Kit.text("micro", "Object index", viewX, fy, PAL.muted)
      local idxStr = field(App, "tr_hdr_idx", viewX + 100 * s, fy, 50 * s, fh,
        tostring(objIndex), "1")
      S.trainerHeaderIndex = tonumber(idxStr) or 1
      fy = fy + fh + 6 * s
      local hdr = S.project.trainer_headers[label][S.trainerHeaderIndex]
      local draft = hdr or {
        range = 2,
        battle = "_" .. (S.trainerId or "T") .. "Battle",
        won = "_" .. (S.trainerId or "T") .. "Won",
        after = "_" .. (S.trainerId or "T") .. "After",
        event = State.modFlag(S.project, "BEAT_" .. (S.trainerId or "T")),
        opponent = S.trainerId,
        party = 1,
      }
      local function touchHdr()
        S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
        if not S.project.trainer_headers[label][S.trainerHeaderIndex] then
          S.project.trainer_headers[label][S.trainerHeaderIndex] = {
            range = draft.range, battle = draft.battle, won = draft.won,
            after = draft.after, event = draft.event,
            opponent = S.trainerId, party = draft.party,
          }
        end
        hdr = S.project.trainer_headers[label][S.trainerHeaderIndex]
        hdr.opponent = S.trainerId
        App.markDirty()
        return hdr
      end
      local range = tonumber(field(App, "tr_hdr_range", viewX, fy, 50 * s, fh,
        tostring(draft.range or 2), "2")) or 2
      if range ~= (draft.range or 2) then draft = touchHdr(); draft.range = range end
      Kit.text("micro", "sight range", viewX + 58 * s, fy + 6 * s, PAL.faint)
      fy = fy + fh + 4 * s
      local partyN = tonumber(field(App, "tr_hdr_party", viewX, fy, 50 * s, fh,
        tostring(draft.party or 1), "1")) or 1
      if partyN ~= (draft.party or 1) then draft = touchHdr(); draft.party = partyN end
      Kit.text("micro", "party #", viewX + 58 * s, fy + 6 * s, PAL.faint)
      fy = fy + fh + 4 * s
      local battle = field(App, "tr_hdr_b", viewX, fy, viewW, fh,
        draft.battle or "", "_Battle")
      if battle ~= (draft.battle or "") then draft = touchHdr(); draft.battle = battle end
      fy = fy + fh + 4 * s
      local won = field(App, "tr_hdr_w", viewX, fy, viewW, fh,
        draft.won or "", "_Won")
      if won ~= (draft.won or "") then draft = touchHdr(); draft.won = won end
      fy = fy + fh + 4 * s
      local after = field(App, "tr_hdr_a", viewX, fy, viewW, fh,
        draft.after or "", "_After")
      if after ~= (draft.after or "") then draft = touchHdr(); draft.after = after end
      fy = fy + fh + 4 * s
      local event = field(App, "tr_hdr_e", viewX, fy, viewW, fh,
        draft.event or "", "MOD_BEAT_")
      if event ~= (draft.event or "") then draft = touchHdr(); draft.event = event end
      fy = fy + fh + 8 * s
      if S.project.trainer_headers[label]
          and S.project.trainer_headers[label][S.trainerHeaderIndex] then
        for _, key in ipairs({ "battle", "won", "after" }) do
          local tid = draft[key]
          if type(tid) == "string" and tid:sub(1, 1) == "_" and not S.project.text[tid] then
            S.project.text[tid] = (key == "battle" and "Let's fight!")
              or (key == "won" and "I lost...")
              or "You're strong."
          end
        end
      end
    else
      Kit.text("micro", "Select a map on the Maps tab to edit trainer headers.",
        viewX, fy, PAL.faint)
    end
  end

  FormPane.finish(S, "trainerFormScroll", contentTop, fy, view)

  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 28 * s,
      "Revert", { kind = "danger" }) then
    S.project.trainers[S.trainerId] = nil
    App.markDirty()
  end
end

return Trainers
