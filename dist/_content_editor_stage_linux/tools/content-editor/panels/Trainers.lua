-- Trainers tab: full class data (parties, pic, AI, money) + map headers.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Search = require("Search")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local FormPane = require("FormPane")
local ModIO = require("ModIO")
local RegList = require("RegList")
local Pokemon = require("src.pokemon.Pokemon")
local PAL = Theme.PAL

local DV_KEYS = { "attack", "defense", "speed", "special", "hp" }
local DV_LABELS = { attack = "Atk", defense = "Def", speed = "Spe",
  special = "Spc", hp = "HP" }
local EV_KEYS = { "hp", "attack", "defense", "speed", "special" }
local EV_LABELS = { hp = "HP", attack = "Atk", defense = "Def",
  speed = "Spe", special = "Spc" }

local function copyMoves(moves)
  if type(moves) ~= "table" then return nil end
  local out = {}
  for i = 1, math.min(4, #moves) do
    local id = moves[i]
    if type(id) == "string" and id ~= "" then
      out[#out + 1] = id
    end
  end
  if #out == 0 then return nil end
  return out
end

local function copyStatBlock(src, keys, maxV)
  if type(src) ~= "table" then return nil end
  local out, any = {}, false
  for _, k in ipairs(keys) do
    local n = tonumber(src[k])
    if n ~= nil then
      n = math.floor(n)
      if maxV then n = Theme.clamp(n, 0, maxV) end
      if n < 0 then n = 0 end
      out[k] = n
      any = true
    end
  end
  return any and out or nil
end

local function copyPartySlot(mon)
  local slot = {
    level = mon.level or 5,
    species = mon.species or "PIDGEY",
  }
  slot.moves = copyMoves(mon.moves)
  slot.dvs = copyStatBlock(mon.dvs, DV_KEYS, 15)
  slot.statExp = copyStatBlock(mon.statExp, EV_KEYS, 65535)
  return slot
end

local function deriveHpDv(dvs)
  if type(dvs) ~= "table" then return 0 end
  return (tonumber(dvs.attack) or 0) % 2 * 8
    + (tonumber(dvs.defense) or 0) % 2 * 4
    + (tonumber(dvs.speed) or 0) % 2 * 2
    + (tonumber(dvs.special) or 0) % 2
end

local function normalizeBulkDvs(src, defDvs)
  local out = copyStatBlock(src, DV_KEYS, 15)
  if not out then
    out = {}
    for _, k in ipairs(DV_KEYS) do out[k] = defDvs[k] end
  end
  if out.hp == nil then out.hp = deriveHpDv(out) end
  return out
end

local function normalizeBulkSe(src)
  local out = copyStatBlock(src, EV_KEYS, 65535)
  if not out then
    out = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
  end
  return out
end

-- Apply DVs and/or Stat Exp to every mon in a party (keeps level/species/moves).
local function applyStatsToParty(party, dvs, se)
  if type(party) ~= "table" then return 0 end
  local n = 0
  for mi, mon in ipairs(party) do
    party[mi] = {
      level = mon.level or 5,
      species = mon.species or "PIDGEY",
      moves = copyMoves(mon.moves),
      dvs = dvs and copyStatBlock(dvs, DV_KEYS, 15) or copyStatBlock(mon.dvs, DV_KEYS, 15),
      statExp = se and copyStatBlock(se, EV_KEYS, 65535)
        or copyStatBlock(mon.statExp, EV_KEYS, 65535),
    }
    n = n + 1
  end
  return n
end

-- Vanilla parties store only level+species. Battle uses learnset moves and
-- constants.trainerDvs (fallback 9/8/8/8). Show those as placeholders.
local DEFAULT_TRAINER_DVS = {
  attack = 9, defense = 8, speed = 8, special = 8, hp = 8,
}

-- Mirror BattleState special third-move tables for accurate placeholders.
local LONE_MOVES = {
  OPP_BROCK = { 2, "BIDE" },
  OPP_MISTY = { 2, "BUBBLEBEAM" },
  OPP_LT_SURGE = { 3, "THUNDERBOLT" },
  OPP_ERIKA = { 3, "MEGA_DRAIN" },
  OPP_KOGA = { 4, "TOXIC" },
  OPP_SABRINA = { 4, "PSYWAVE" },
  OPP_BLAINE = { 4, "FIRE_BLAST" },
  OPP_GIOVANNI = { 5, "FISSURE", onlyParty = 3 },
}
local TEAM_MOVES = {
  OPP_LORELEI = "BLIZZARD", OPP_BRUNO = "FISSURE",
  OPP_AGATHA = "TOXIC", OPP_LANCE = "BARRIER",
}
local RIVAL_STARTER_MOVES = {
  VENUSAUR = "MEGA_DRAIN", CHARIZARD = "FIRE_BLAST", BLASTOISE = "BLIZZARD",
}

local function speciesDef(S, speciesId)
  if not speciesId then return nil end
  return (S.project.pokemon and S.project.pokemon[speciesId])
    or (S.data and S.data.pokemon and S.data.pokemon[speciesId])
end

local function defaultTrainerDvs(S)
  local t = S.data and S.data.constants and S.data.constants.trainerDvs
  if type(t) ~= "table" then
    return {
      attack = DEFAULT_TRAINER_DVS.attack,
      defense = DEFAULT_TRAINER_DVS.defense,
      speed = DEFAULT_TRAINER_DVS.speed,
      special = DEFAULT_TRAINER_DVS.special,
      hp = DEFAULT_TRAINER_DVS.hp,
    }
  end
  local out = {
    attack = tonumber(t.attack) or DEFAULT_TRAINER_DVS.attack,
    defense = tonumber(t.defense) or DEFAULT_TRAINER_DVS.defense,
    speed = tonumber(t.speed) or DEFAULT_TRAINER_DVS.speed,
    special = tonumber(t.special) or DEFAULT_TRAINER_DVS.special,
  }
  out.hp = tonumber(t.hp)
  if out.hp == nil then out.hp = deriveHpDv(out) end
  return out
end

local function defaultMovesForMon(S, oppClass, partyIndex, monIndex, mon)
  local def = speciesDef(S, mon.species)
  local moves = {}
  if def then
    local got = Pokemon.movesAtLevel({
      level1Moves = def.level1Moves or {},
      learnset = def.learnset or {},
    }, mon.level or 1)
    for i, id in ipairs(got) do moves[i] = id end
  end
  local function setThird(moveId)
    if not moveId then return end
    local i = math.min(3, #moves + 1)
    moves[i] = moveId
  end
  local lone = LONE_MOVES[oppClass]
  if lone and lone[1] == monIndex
      and (not lone.onlyParty or lone.onlyParty == partyIndex) then
    setThird(lone[2])
  elseif TEAM_MOVES[oppClass] and monIndex == 5 then
    setThird(TEAM_MOVES[oppClass])
  elseif oppClass == "OPP_RIVAL3" then
    if monIndex == 1 then
      setThird("SKY_ATTACK")
    elseif monIndex == 6 and RIVAL_STARTER_MOVES[mon.species] then
      setThird(RIVAL_STARTER_MOVES[mon.species])
    end
  end
  return moves
end

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
      copy.parties[pi][mi] = copyPartySlot(mon)
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
  local trNav = RegList.bindNav(S, ids, {
    selKey = "trainerId", offsetKey = "trainerListOffset", perPage = perPage,
    onSelect = function()
      Kit.blur()
      S.trainerPartyIndex = 1
    end,
  })
  local ry = scrollY
  for i = (S.trainerListOffset or 0) + 1,
      math.min(#ids, (S.trainerListOffset or 0) + perPage) do
    local id = ids[i]
    local rowTr = select(1, getTrainer(S, id))
    local owned = S.project.trainers[id] ~= nil
    if Kit.row(scrollX, ry, rowW, rowH, S.trainerId == id, PAL.red) then
      trNav.activate()
      if S.trainerId ~= id then Kit.blur() end
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

  -- Party tab strip needs the wheel before FormPane steals it for vertical scroll.
  if S.trainerSection == "parties" and (Kit.wheelY or 0) ~= 0 then
    local n = #(tr.parties or {})
    local bw, gap, navW, actW = 56 * s, 4 * s, 28 * s, 148 * s
    local stripW = math.max(40 * s, viewW - actW - navW * 2 - 12 * s)
    local maxOff = math.max(0, n * (bw + gap) - stripW)
    local stripX = viewX + ((maxOff > 0) and (navW + 4 * s) or 0)
    local stripY = viewY - (S.trainerFormScroll or 0) + 20 * s
    if maxOff > 0 and Kit.hit(stripX, stripY, stripW, 28 * s) then
      S.trainerPartyTabScroll = Theme.clamp(
        (S.trainerPartyTabScroll or 0) - Kit.wheelY * (bw + gap) * 2, 0, maxOff)
      Kit.wheelY = 0
    end
  end

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

    -- Scrollable P1..Pn strip; +Party / Del stay pinned on the right.
    local bw, gap = 56 * s, 4 * s
    local navW = 28 * s
    local actW = 148 * s
    local stripW = math.max(40 * s, viewW - actW - navW * 2 - 12 * s)
    local contentW = #tr.parties * (bw + gap)
    local maxOff = math.max(0, contentW - stripW)
    S.trainerPartyTabScroll = Theme.clamp(S.trainerPartyTabScroll or 0, 0, maxOff)

    local navX = viewX
    if maxOff > 0 then
      if Kit.button(navX, fy, navW, fh, "<", {
          kind = "ghost", tooltip = "Scroll party tabs left",
        }) then
        S.trainerPartyTabScroll = Theme.clamp(
          S.trainerPartyTabScroll - (bw + gap) * 3, 0, maxOff)
      end
      navX = navX + navW + 4 * s
    end

    local stripX = navX
    if Kit.hit(stripX, fy, stripW, fh) then
      if Kit.mouseDown then
        if not S._partyTabDrag then
          S._partyTabDrag = {
            x = Kit.mouseX, off = S.trainerPartyTabScroll or 0,
          }
        else
          S.trainerPartyTabScroll = Theme.clamp(
            S._partyTabDrag.off + (S._partyTabDrag.x - Kit.mouseX), 0, maxOff)
        end
      else
        S._partyTabDrag = nil
      end
    else
      S._partyTabDrag = nil
    end

    Kit.pushClip(stripX, fy, stripW, fh)
    local px = stripX - (S.trainerPartyTabScroll or 0)
    for pi = 1, #tr.parties do
      local on = S.trainerPartyIndex == pi
      if Kit.chip(px, fy, bw, fh, "P" .. pi, on, PAL.yellow) then
        S.trainerPartyIndex = pi
        -- Keep the selected tab in view.
        local left = (pi - 1) * (bw + gap)
        local right = left + bw
        if left < S.trainerPartyTabScroll then
          S.trainerPartyTabScroll = left
        elseif right > S.trainerPartyTabScroll + stripW then
          S.trainerPartyTabScroll = math.max(0, right - stripW)
        end
      end
      px = px + bw + gap
    end
    Kit.popClip()

    local ax = stripX + stripW + 8 * s
    if maxOff > 0 then
      if Kit.button(ax, fy, navW, fh, ">", {
          kind = "ghost", tooltip = "Scroll party tabs right",
        }) then
        S.trainerPartyTabScroll = Theme.clamp(
          S.trainerPartyTabScroll + (bw + gap) * 3, 0, maxOff)
      end
      ax = ax + navW + 4 * s
    end
    if #tr.parties < 20 and Kit.button(ax, fy, 70 * s, fh, "+Party",
        { kind = "good" }) then
      tr = mutate()
      tr.parties[#tr.parties + 1] = { { level = 5, species = "PIDGEY" } }
      S.trainerPartyIndex = #tr.parties
      S.trainerPartyTabScroll = math.max(0, #tr.parties * (bw + gap) - stripW)
      App.markDirty()
    end
    if #tr.parties > 1 and Kit.button(ax + 78 * s, fy, 70 * s, fh, "Del P",
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
    local numW = 44 * s
    local defDvs = defaultTrainerDvs(S)

    -- Bulk DVs / Stat Exp for every mon in this party (or all parties).
    do
      S.trainerBulkDvs = S.trainerBulkDvs or normalizeBulkDvs(nil, defDvs)
      S.trainerBulkSe = S.trainerBulkSe or normalizeBulkSe(nil)
      Kit.text("micro", "Bulk DVs / Stat Exp — apply to all mons",
        viewX, fy, PAL.caption)
      fy = fy + 14 * s
      local dvGap = 8 * s
      local dvCell = numW + dvGap + 18 * s
      for di, key in ipairs(DV_KEYS) do
        local lab = DV_LABELS[key]
        local lx = viewX + (di - 1) * dvCell
        Kit.text("micro", lab, lx, fy, PAL.faint)
        local cur = S.trainerBulkDvs[key]
        if cur == nil and key == "hp" then cur = deriveHpDv(S.trainerBulkDvs) end
        local raw = field(App, "tr_bulk_dv_" .. key,
          lx, fy + 12 * s, numW, fh - 4 * s,
          cur ~= nil and tostring(cur) or "", "0")
        S.trainerBulkDvs[key] = Theme.clamp(tonumber(raw) or 0, 0, 15)
      end
      S.trainerBulkDvs.hp = S.trainerBulkDvs.hp or deriveHpDv(S.trainerBulkDvs)
      fy = fy + 12 * s + fh + 4 * s
      local btnW = 120 * s
      if Kit.button(viewX, fy, btnW, 26 * s, "DVs → party", {
          kind = "accent",
          tooltip = "Copy these DVs onto every mon in the current party",
        }) then
        tr = mutate()
        local p = tr.parties[S.trainerPartyIndex]
        local dvs = normalizeBulkDvs(S.trainerBulkDvs, defDvs)
        local n = applyStatsToParty(p, dvs, nil)
        App.markDirty()
        S.status = string.format("Applied DVs to %d mon(s) in party %d",
          n, S.trainerPartyIndex or 1)
      end
      if Kit.button(viewX + btnW + 8 * s, fy, btnW + 24 * s, 26 * s,
          "DVs → all parties", {
            kind = "ghost",
            tooltip = "Copy these DVs onto every mon in every party of this trainer",
          }) then
        tr = mutate()
        local dvs = normalizeBulkDvs(S.trainerBulkDvs, defDvs)
        local n = 0
        for _, p in ipairs(tr.parties or {}) do
          n = n + applyStatsToParty(p, dvs, nil)
        end
        App.markDirty()
        S.status = string.format("Applied DVs to %d mon(s) across all parties", n)
      end
      fy = fy + 32 * s

      local seGap = 8 * s
      local seCell = numW + seGap + 18 * s
      for ei, key in ipairs(EV_KEYS) do
        local lab = EV_LABELS[key]
        local lx = viewX + (ei - 1) * seCell
        Kit.text("micro", lab, lx, fy, PAL.faint)
        local cur = S.trainerBulkSe[key] or 0
        local raw = field(App, "tr_bulk_se_" .. key,
          lx, fy + 12 * s, numW, fh - 4 * s, tostring(cur), "0")
        S.trainerBulkSe[key] = Theme.clamp(tonumber(raw) or 0, 0, 65535)
      end
      fy = fy + 12 * s + fh + 4 * s
      if Kit.button(viewX, fy, btnW, 26 * s, "EVs → party", {
          kind = "accent",
          tooltip = "Copy these Stat Exp values onto every mon in the current party",
        }) then
        tr = mutate()
        local p = tr.parties[S.trainerPartyIndex]
        local se = normalizeBulkSe(S.trainerBulkSe)
        local n = applyStatsToParty(p, nil, se)
        App.markDirty()
        S.status = string.format("Applied Stat Exp to %d mon(s) in party %d",
          n, S.trainerPartyIndex or 1)
      end
      if Kit.button(viewX + btnW + 8 * s, fy, btnW + 24 * s, 26 * s,
          "EVs → all parties", {
            kind = "ghost",
            tooltip = "Copy these Stat Exp values onto every mon in every party",
          }) then
        tr = mutate()
        local se = normalizeBulkSe(S.trainerBulkSe)
        local n = 0
        for _, p in ipairs(tr.parties or {}) do
          n = n + applyStatsToParty(p, nil, se)
        end
        App.markDirty()
        S.status = string.format("Applied Stat Exp to %d mon(s) across all parties", n)
      end
      fy = fy + 36 * s
    end

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
      local rowTop = fy
      local lvl = tonumber(field(App, "tr_lv_" .. mi, mx, fy, 50 * s, fh,
        tostring(mon.level or 5), "5")) or 5
      local sp = field(App, "tr_sp_" .. mi, mx + 60 * s, fy, 160 * s, fh,
        mon.species or "PIDGEY", "PIDGEY"):upper():gsub("%s+", "_")
      if Kit.button(mx + 230 * s, fy, 36 * s, fh, "X", { kind = "danger" })
          and #party > 1 then
        tr = mutate()
        table.remove(tr.parties[S.trainerPartyIndex], mi)
        App.markDirty()
        break
      end
      fy = fy + fh + 4 * s

      local partyIdx = S.trainerPartyIndex or 1
      local defMoves = defaultMovesForMon(S, S.trainerId, partyIdx, mi, mon)
      local defDvs = defaultTrainerDvs(S)
      local hasMoveOverride = mon.moves ~= nil
      local hasDvOverride = mon.dvs ~= nil
      local hasSeOverride = mon.statExp ~= nil

      -- Caption row, then fields on the next line so hints never cover inputs.
      local moveHint = hasMoveOverride and "override" or "level-up default"
      Kit.text("micro", "Moves · " .. moveHint, mx, fy, PAL.caption)
      fy = fy + 14 * s
      local moves = mon.moves or {}
      local typedMoves = {}
      local moveW = math.max(70 * s, math.floor((viewW - (mx - viewX) - 8 * s) / 4))
      for slot = 1, 4 do
        local cur = hasMoveOverride and tostring(moves[slot] or "")
          or tostring(defMoves[slot] or "")
        local v = field(App, "tr_mv_" .. mi .. "_" .. slot,
          mx + (slot - 1) * (moveW + 4 * s), fy, moveW, fh,
          cur, "MOVE"):upper():gsub("%s+", "_")
        if v == "MOVE" then v = "" end
        typedMoves[slot] = v
      end
      local newMoves = {}
      for slot = 1, 4 do
        if typedMoves[slot] ~= "" then
          newMoves[#newMoves + 1] = typedMoves[slot]
        end
      end
      do
        local same = #newMoves == #defMoves
        if same then
          for i = 1, #newMoves do
            if newMoves[i] ~= defMoves[i] then same = false; break end
          end
        end
        -- Keep nil unless the user actually overrides the level-up set.
        if same and not hasMoveOverride then
          newMoves = nil
        elseif #newMoves == 0 and hasMoveOverride then
          newMoves = nil
        elseif same and hasMoveOverride then
          -- Explicitly same as defaults: drop the override.
          newMoves = nil
        end
      end
      fy = fy + fh + 8 * s

      local dvHint = hasDvOverride and "override" or "class default"
      Kit.text("micro", "DVs 0-15 · " .. dvHint, mx, fy, PAL.caption)
      fy = fy + 14 * s
      local dvs = hasDvOverride and (mon.dvs or {}) or defDvs
      local newDvs = {}
      local dvGap = 8 * s
      local dvCell = numW + dvGap + 18 * s
      local hasDv = false
      for di, key in ipairs(DV_KEYS) do
        local lab = DV_LABELS[key]
        local lx = mx + (di - 1) * dvCell
        Kit.text("micro", lab, lx, fy, PAL.faint)
        local cur = dvs[key]
        if cur == nil and key == "hp" then cur = deriveHpDv(dvs) end
        local raw = field(App, "tr_dv_" .. mi .. "_" .. key,
          lx, fy + 12 * s, numW, fh - 4 * s,
          cur ~= nil and tostring(cur) or "", "-")
        if raw ~= "" and raw ~= "-" then
          newDvs[key] = Theme.clamp(tonumber(raw) or 0, 0, 15)
          hasDv = true
        end
      end
      if hasDv then
        if newDvs.hp == nil then newDvs.hp = deriveHpDv(newDvs) end
        local same = true
        for _, key in ipairs(DV_KEYS) do
          if tonumber(newDvs[key] or -1) ~= tonumber(defDvs[key] or -1) then
            same = false; break
          end
        end
        if same then newDvs = nil end
      else
        newDvs = nil
      end
      fy = fy + 12 * s + fh + 8 * s

      local seHint = hasSeOverride and "Gen1 EV override" or "default 0"
      Kit.text("micro", "Stat Exp · " .. seHint, mx, fy, PAL.caption)
      fy = fy + 14 * s
      local se = hasSeOverride and (mon.statExp or {}) or {
        hp = 0, attack = 0, defense = 0, speed = 0, special = 0,
      }
      local newSe = {}
      local hasSe = false
      local seGap = 8 * s
      local seCell = numW + seGap + 18 * s
      for ei, key in ipairs(EV_KEYS) do
        local lab = EV_LABELS[key]
        local lx = mx + (ei - 1) * seCell
        Kit.text("micro", lab, lx, fy, PAL.faint)
        local cur = se[key]
        local raw = field(App, "tr_se_" .. mi .. "_" .. key,
          lx, fy + 12 * s, numW, fh - 4 * s,
          cur ~= nil and tostring(cur) or "0", "0")
        if raw ~= "" and raw ~= "-" then
          newSe[key] = Theme.clamp(tonumber(raw) or 0, 0, 65535)
          hasSe = true
        end
      end
      if hasSe then
        local allZero = true
        for _, key in ipairs(EV_KEYS) do
          if tonumber(newSe[key] or 0) ~= 0 then allZero = false; break end
        end
        if allZero then newSe = nil end
      else
        newSe = nil
      end
      fy = fy + 12 * s + fh + 10 * s

      local function optBlockChanged(oldB, newB, keys)
        local o = copyStatBlock(oldB, keys, nil)
        if o == nil and newB == nil then return false end
        if (o == nil) ~= (newB == nil) then return true end
        for _, k in ipairs(keys) do
          if tonumber(o[k] or 0) ~= tonumber(newB[k] or 0) then return true end
        end
        return false
      end

      local changed = lvl ~= (mon.level or 5) or sp ~= (mon.species or "")
      local oldMoves = copyMoves(mon.moves)
      if (oldMoves == nil) ~= (newMoves == nil) then
        changed = true
      elseif newMoves then
        if #oldMoves ~= #newMoves then
          changed = true
        else
          for i = 1, #newMoves do
            if oldMoves[i] ~= newMoves[i] then changed = true; break end
          end
        end
      end
      if optBlockChanged(mon.dvs, newDvs, DV_KEYS) then changed = true end
      if optBlockChanged(mon.statExp, newSe, EV_KEYS) then changed = true end

      if changed then
        tr = mutate()
        local p = tr.parties[S.trainerPartyIndex]
        p[mi] = {
          level = lvl,
          species = sp,
          moves = newMoves,
          dvs = newDvs,
          statExp = newSe,
        }
      end

      fy = math.max(fy, rowTop + prevSize) + 10 * s
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
      "Beat flags are per map object. Prefer Maps → Objects → Beat flag.",
      viewX, fy, PAL.muted)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 180 * s, 30 * s, "Use on Maps tab",
        { kind = "primary" }) then
      S.tab = "maps"
      S.mapTool = "trainer"
      S.status = "Trainer tool active — click a cell to place "
        .. tostring(S.trainerId)
    end
    fy = fy + 40 * s

    local mapId = S.mapId or S.dialogMapId
    if not mapId then
      Kit.text("micro", "Select a map on the Maps tab to edit placements.",
        viewX, fy, PAL.faint)
    else
      local label = State.mapLabel(S, mapId)
      local mapDef = (S.project.maps and S.project.maps[mapId])
        or (S.data and S.data.maps and S.data.maps[mapId])
      local placements = {}
      for i, obj in ipairs((mapDef and mapDef.objects) or {}) do
        if obj.trainerClass and obj.trainerClass ~= "" then
          placements[#placements + 1] = {
            listI = i,
            idx = obj.index or i,
            class = obj.trainerClass,
            party = obj.trainerParty or 1,
          }
        end
      end
      -- Prefer placements of the selected class; fall back to all on this map.
      local shown = {}
      for _, p in ipairs(placements) do
        if p.class == S.trainerId then shown[#shown + 1] = p end
      end
      if #shown == 0 then shown = placements end

      Kit.text("small", "Placements on " .. tostring(label), viewX, fy, PAL.caption)
      fy = fy + 20 * s
      if #shown == 0 then
        Kit.text("micro", "No trainer objects on this map yet.",
          viewX, fy, PAL.faint)
        fy = fy + 18 * s
      else
        local rowH = 26 * s
        local selIdx = tonumber(S.trainerHeaderIndex)
        local found = false
        for _, p in ipairs(shown) do
          if p.idx == selIdx then found = true; break end
        end
        if not found then
          S.trainerHeaderIndex = shown[1].idx
          selIdx = shown[1].idx
        end
        for _, p in ipairs(shown) do
          local on = selIdx == p.idx
          local lab = string.format("#%d  %s  party %d",
            p.idx, p.class or "?", p.party or 1)
          if Kit.row(viewX, fy, viewW, rowH, on, PAL.red) then
            if selIdx ~= p.idx then Kit.blur() end
            S.trainerHeaderIndex = p.idx
            S.mapObjectIndex = p.listI
            selIdx = p.idx
          end
          Kit.text("micro", Kit.ellipsize("micro", lab, viewW - 12 * s),
            viewX + 8 * s, fy + 6 * s, on and PAL.text or PAL.muted)
          fy = fy + rowH + 3 * s
        end
        fy = fy + 8 * s

        local idx = tonumber(S.trainerHeaderIndex) or shown[1].idx
        local picked = nil
        for _, p in ipairs(shown) do
          if p.idx == idx then picked = p; break end
        end
        picked = picked or shown[1]
        idx = picked.idx
        -- Field ids include map + object index so typing never bleeds.
        local fid = "_" .. tostring(mapId) .. "_" .. tostring(idx)
        local uniq = (mapId or "MAP") .. "_" .. idx
        State.ensureProjectFields(S.project)
        S.project.trainer_headers[label] = S.project.trainer_headers[label] or {}
        local bucket = S.project.trainer_headers[label]

        local function cloneHdr(src)
          local c = {}
          if type(src) == "table" then
            for k, v in pairs(src) do c[k] = v end
          end
          return c
        end

        -- Break accidental shared table refs across object indices.
        local function isolate(i)
          local h = bucket[i]
          if type(h) ~= "table" then return h end
          for other, oh in pairs(bucket) do
            if other ~= i and oh == h then
              bucket[other] = cloneHdr(oh)
            end
          end
          return bucket[i]
        end

        local function ensureHdr()
          local h = bucket[idx]
          if not h then
            h = {
              range = 2,
              battle = "_" .. uniq .. "Battle",
              won = "_" .. uniq .. "Won",
              after = "_" .. uniq .. "After",
              event = State.modFlag(S.project, "BEAT_" .. uniq),
              opponent = picked.class or S.trainerId,
              party = picked.party or 1,
            }
            bucket[idx] = h
            S.project.eventFlags = S.project.eventFlags or {}
            S.project.eventFlags[h.event] = true
          else
            h = isolate(idx)
            bucket[idx] = h
          end
          App.markDirty()
          return h
        end

        local hdr = bucket[idx]
        local draft = hdr or {
          range = 2,
          battle = "_" .. uniq .. "Battle",
          won = "_" .. uniq .. "Won",
          after = "_" .. uniq .. "After",
          event = State.modFlag(S.project, "BEAT_" .. uniq),
          opponent = picked.class or S.trainerId,
          party = picked.party or 1,
        }

        Kit.text("micro",
          "Editing object #" .. tostring(idx) .. " only",
          viewX, fy, PAL.faint)
        fy = fy + 16 * s

        local range = tonumber(field(App, "tr_hdr_range" .. fid, viewX, fy, 50 * s, fh,
          tostring(draft.range or 2), "2")) or 2
        if range ~= (draft.range or 2) then
          draft = ensureHdr(); draft.range = range
        end
        Kit.text("micro", "sight range", viewX + 58 * s, fy + 6 * s, PAL.faint)
        fy = fy + fh + 4 * s

        local partyN = tonumber(field(App, "tr_hdr_party" .. fid, viewX, fy, 50 * s, fh,
          tostring(draft.party or 1), "1")) or 1
        if partyN ~= (draft.party or 1) then
          draft = ensureHdr(); draft.party = partyN
          if mapDef and mapDef.objects and mapDef.objects[picked.listI] then
            mapDef.objects[picked.listI].trainerParty = partyN
          end
        end
        Kit.text("micro", "party #", viewX + 58 * s, fy + 6 * s, PAL.faint)
        fy = fy + fh + 4 * s

        local battle = field(App, "tr_hdr_b" .. fid, viewX, fy, viewW, fh,
          draft.battle or "", "_Battle")
        if battle ~= (draft.battle or "") then
          draft = ensureHdr(); draft.battle = battle
        end
        fy = fy + fh + 4 * s
        local won = field(App, "tr_hdr_w" .. fid, viewX, fy, viewW, fh,
          draft.won or "", "_Won")
        if won ~= (draft.won or "") then
          draft = ensureHdr(); draft.won = won
        end
        fy = fy + fh + 4 * s
        local after = field(App, "tr_hdr_a" .. fid, viewX, fy, viewW, fh,
          draft.after or "", "_After")
        if after ~= (draft.after or "") then
          draft = ensureHdr(); draft.after = after
        end
        fy = fy + fh + 4 * s

        local event = field(App, "tr_hdr_e" .. fid, viewX, fy, viewW, fh,
          draft.event or "", "MOD_BEAT_")
        if event ~= (draft.event or "") then
          draft = ensureHdr()
          local full = State.modFlag(S.project,
            (event ~= "" and event) or ("BEAT_" .. uniq))
          -- Write only this object index (never broadcast to other trainers).
          draft.event = full
          bucket[idx] = draft
          S.project.eventFlags = S.project.eventFlags or {}
          S.project.eventFlags[full] = true
        end
        fy = fy + fh + 8 * s

        if bucket[idx] then
          for _, key in ipairs({ "battle", "won", "after" }) do
            local tid = draft[key]
            if type(tid) == "string" and tid:sub(1, 1) == "_"
                and not S.project.text[tid] then
              S.project.text[tid] = (key == "battle" and "Let's fight!")
                or (key == "won" and "I lost...")
                or "You're strong."
            end
          end
        end

        if Kit.button(viewX, fy, 160 * s, 28 * s, "Open on Maps",
            { kind = "ghost" }) then
          S.tab = "maps"
          S.mapId = mapId
          S.mapSection = "objects"
          S.mapObjectIndex = picked.listI
        end
        fy = fy + 36 * s
      end
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
