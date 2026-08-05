-- Pokemon tab: full species editing (stats, learnset, evolutions, tmhm, dex).

local Kit = require("Kit")
local Theme = require("Theme")
local ModIO = require("ModIO")
local Search = require("Search")
local TypeIds = require("TypeIds")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local FormPane = require("FormPane")
local PAL = Theme.PAL

local Pokemon = {}

local GROWTH = { "MEDIUM_FAST", "MEDIUM_SLOW", "FAST", "SLOW" }
local EVO_METHODS = { "LEVEL", "ITEM", "TRADE" }
local ICON_NAMES = {
  "", "MON", "BALL", "HELIX", "FAIRY", "BIRD", "WATER",
  "BUG", "GRASS", "SNAKE", "QUADRUPED", "PIKACHU",
}
local SECTIONS = {
  { id = "basics", label = "Basics" },
  { id = "learnset", label = "Learnset" },
  { id = "evolutions", label = "Evos" },
  { id = "tmhm", label = "TM/HM" },
  { id = "dex", label = "Dex" },
}

local function cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

local function iconNameOf(mon)
  local entry = mon and mon.icon
  if type(entry) == "string" then return entry end
  return ""
end

local function allSpeciesIds(S)
  local seen, ids = {}, {}
  for id in pairs((S.project and S.project.pokemon) or {}) do
    seen[id] = true
    ids[#ids + 1] = id
  end
  if S.data and S.data.pokemon then
    for id in pairs(S.data.pokemon) do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function deepCloneMon(def)
  local copy = {}
  for k, v in pairs(def) do
    if k == "types" or k == "level1Moves" or k == "tmhm" then
      local a = {}
      for i = 1, #(v or {}) do a[i] = v[i] end
      copy[k] = a
    elseif k == "baseStats" and type(v) == "table" then
      local s = {}
      for sk, sv in pairs(v) do s[sk] = sv end
      copy.baseStats = s
    elseif k == "learnset" and type(v) == "table" then
      local a = {}
      for i, row in ipairs(v) do
        if type(row) == "table" then
          local r = {}
          for rk, rv in pairs(row) do r[rk] = rv end
          a[i] = r
        else
          a[i] = row
        end
      end
      copy.learnset = a
    elseif k == "evolutions" and type(v) == "table" then
      local a = {}
      for i, row in ipairs(v) do
        if type(row) == "table" then
          local r = {}
          for rk, rv in pairs(row) do r[rk] = rv end
          a[i] = r
        else
          a[i] = row
        end
      end
      copy.evolutions = a
    elseif k == "dexEntry" and type(v) == "table" then
      local d = {}
      for dk, dv in pairs(v) do d[dk] = dv end
      copy.dexEntry = d
    else
      copy[k] = v
    end
  end
  copy._isNew = false
  return copy
end

local function resolveMon(S, id)
  if not id then return nil, false end
  if S.project.pokemon[id] then return S.project.pokemon[id], true end
  if S.data and S.data.pokemon and S.data.pokemon[id] then
    return S.data.pokemon[id], false
  end
  return nil, false
end

local function ensureOwned(S, id)
  local def, owned = resolveMon(S, id)
  if not def then return nil end
  if owned then return def end
  local copy = deepCloneMon(def)
  S.project.pokemon[id] = copy
  return copy
end

local function defaultMon(id)
  return {
    id = id,
    name = id,
    dex = 1,
    types = { "NORMAL" },
    baseStats = { hp = 50, attack = 50, defense = 50, speed = 50, special = 50 },
    catchRate = 190,
    baseExp = 64,
    growthRate = "MEDIUM_FAST",
    level1Moves = { "TACKLE" },
    learnset = {},
    evolutions = {},
    tmhm = {},
    spriteFront = "",
    spriteBack = "",
    frontSize = 5,
    dexEntry = { kind = "???", heightFt = 1, heightIn = 0, weight = 10, text = "" },
    _isNew = true,
  }
end

local function field(S, App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function numField(S, App, id, x, y, w, h, value)
  local v = field(S, App, id, x, y, w, h, tostring(value or 0), "0")
  return tonumber(v) or value or 0
end

local function parseMoveList(str)
  local moves = {}
  for part in (str .. ","):gmatch("([^,]*),") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then moves[#moves + 1] = part:upper():gsub("%s+", "_") end
  end
  return moves
end

local function drawBasics(S, mon, mutate, App, formX, fy, formW, labelW, fh, s)
  local prevSize = 96 * s
  local iconSize = 40 * s
  local gap = 10 * s
  local previewBottom = fy + prevSize + 30 * s
  local iconX = formX + formW - prevSize * 2 - gap - iconSize - gap
  local palName = Preview.monPaletteName(S, mon, S.pokemonId)
  local function openMonPal()
    PalettePicker.open(S, {
      current = mon.palette,
      allowClear = true,
      clearLabel = "(pack default / MEWMON)",
      title = "POKEMON SPRITE / ICON PALETTE",
      onPick = function(id)
        mon = mutate()
        mon.palette = id
        Preview.invalidate()
        App.markDirty()
      end,
    })
  end
  Preview.drawPokemonIcon(S, mon, iconX, fy, iconSize, iconSize, S.pokemonId, palName)
  if Kit.press(iconX, fy, iconSize, iconSize) then openMonPal() end
  local frontX = formX + formW - prevSize * 2 - gap
  Preview.draw(S, mon.spriteFront, frontX, fy, prevSize, prevSize, palName)
  Preview.draw(S, mon.spriteBack, formX + formW - prevSize, fy, prevSize, prevSize, palName)
  if Kit.press(frontX, fy, prevSize * 2 + gap, prevSize) then openMonPal() end
  Preview.drawNamedSwatches(S, palName, frontX, fy + prevSize + 2 * s,
    prevSize * 2 + gap, 10 * s)
  if Kit.press(frontX, fy + prevSize + 2 * s, prevSize * 2 + gap, 12 * s) then
    openMonPal()
  end
  Kit.text("micro", "icon", iconX + 4 * s, fy + iconSize + 2 * s, PAL.faint)
  Kit.text("micro", "front", frontX + 4 * s, fy + prevSize + 14 * s, PAL.faint)
  Kit.text("micro", "back", formX + formW - prevSize + 4 * s,
    fy + prevSize + 14 * s, PAL.faint)

  local fieldW = formW - labelW - prevSize * 2 - gap - iconSize - gap - 24 * s
  if fieldW < 160 * s then fieldW = formW - labelW - 20 * s end
  local function row(label, body)
    Kit.text("small", label, formX, fy + 6 * s, PAL.caption)
    body(formX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end

  row("ID", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_id", fx, fy_, fw, fh_, mon.id, "SPECIES_ID")
    if v ~= mon.id and v:match("^[%w_]+$")
       and not S.project.pokemon[v]
       and not (S.data.pokemon and S.data.pokemon[v]) then
      mon = mutate()
      S.project.pokemon[mon.id] = nil
      mon.id = v
      S.project.pokemon[v] = mon
      S.pokemonId = v
      App.markDirty()
    end
  end)
  row("Name", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_name", fx, fy_, fw, fh_, mon.name, "NAME")
    if v ~= (mon.name or "") then mon = mutate(); mon.name = v end
  end)
  row("Dex #", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_dex", fx, fy_, 80 * s, fh_, mon.dex)
    if v ~= mon.dex then mon = mutate(); mon.dex = v end
  end)
  row("Index", function(fx, fy_, fw, fh_)
    local cur = mon.index or 0
    local v = numField(S, App, "pk_idx", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then mon = mutate(); mon.index = v end
  end)

  Kit.text("small", "Types", formX, fy + 6 * s, PAL.caption)
  local tx = formX + labelW
  mon.types = mon.types or { "NORMAL" }
  for i = 1, 2 do
    local cur = mon.types[i] or (i == 1 and "NORMAL" or "")
    local bw = 120 * s
    local label = (cur ~= "" and cur) or "(none)"
    if Kit.button(tx, fy, bw, fh, label, { kind = "accent" }) then
      mon = mutate()
      mon.types = mon.types or { "NORMAL" }
      if i == 1 then
        mon.types[1] = TypeIds.cycle(S, mon.types[1])
      else
        mon.types[2] = TypeIds.cycle(S, mon.types[2], true)
      end
      App.markDirty()
    end
    tx = tx + bw + 8 * s
  end
  fy = fy + fh + 8 * s

  Kit.text("small", "Stats", formX, fy + 6 * s, PAL.caption)
  mon.baseStats = mon.baseStats or {}
  local sx = formX + labelW
  for _, key in ipairs({ "hp", "attack", "defense", "speed", "special" }) do
    local sw = 70 * s
    Kit.text("micro", key:sub(1, 3):upper(), sx, fy - 2 * s, PAL.faint)
    local cur = mon.baseStats[key] or 50
    local v = numField(S, App, "pk_st_" .. key, sx, fy + 12 * s, sw, fh, cur)
    if v ~= cur then
      mon = mutate()
      mon.baseStats = mon.baseStats or {}
      mon.baseStats[key] = math.max(1, math.min(255, v))
    end
    sx = sx + sw + 6 * s
  end
  fy = fy + fh + 28 * s

  row("Catch", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_catch", fx, fy_, 80 * s, fh_, mon.catchRate)
    if v ~= mon.catchRate then mon = mutate(); mon.catchRate = v end
  end)
  row("Base Exp", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_exp", fx, fy_, 80 * s, fh_, mon.baseExp)
    if v ~= mon.baseExp then mon = mutate(); mon.baseExp = v end
  end)
  row("Growth", function(fx, fy_, fw, fh_)
    if Kit.button(fx, fy_, 160 * s, fh_, mon.growthRate or "MEDIUM_FAST",
        { kind = "accent" }) then
      mon = mutate()
      local idx = 1
      for i, g in ipairs(GROWTH) do
        if g == mon.growthRate then idx = i; break end
      end
      mon.growthRate = GROWTH[(idx % #GROWTH) + 1]
      App.markDirty()
    end
  end)
  row("Front size", function(fx, fy_, fw, fh_)
    local cur = mon.frontSize or 5
    local v = numField(S, App, "pk_fs", fx, fy_, 60 * s, fh_, cur)
    v = math.max(1, math.min(7, v))
    if v ~= cur then mon = mutate(); mon.frontSize = v end
  end)
  row("Scale front", function(fx, fy_, fw, fh_)
    local cur = mon.battleScaleFront
    local shown = (cur ~= nil) and tostring(cur) or ""
    local v = field(S, App, "pk_scf", fx, fy_, 80 * s, fh_, shown, "1.0")
    if v ~= shown then
      mon = mutate()
      if v == "" then mon.battleScaleFront = nil
      else
        local n = tonumber(v)
        if n then mon.battleScaleFront = math.max(0.25, math.min(4, n)) end
      end
    end
  end)
  row("Scale back", function(fx, fy_, fw, fh_)
    local cur = mon.battleScaleBack
    local shown = (cur ~= nil) and tostring(cur) or ""
    local v = field(S, App, "pk_scb", fx, fy_, 80 * s, fh_, shown, "2.0")
    if v ~= shown then
      mon = mutate()
      if v == "" then mon.battleScaleBack = nil
      else
        local n = tonumber(v)
        if n then mon.battleScaleBack = math.max(0.25, math.min(4, n)) end
      end
    end
  end)
  row("TrueColor", function(fx, fy_, fw, fh_)
    local on = mon.trueColor and true or false
    if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
      mon = mutate()
      mon.trueColor = not on
      if not mon.trueColor then mon.trueColor = nil end
      App.markDirty()
    end
  end)
  row("L1 moves", function(fx, fy_, fw, fh_)
    local joined = table.concat(mon.level1Moves or {}, ",")
    local v = field(S, App, "pk_l1", fx, fy_, fw, fh_, joined, "TACKLE,GROWL")
    if v ~= joined then mon = mutate(); mon.level1Moves = parseMoveList(v) end
  end)
  row("Cry", function(fx, fy_, fw, fh_)
    local cur = mon.cry or ""
    local cries = {}
    if S.project and S.project.audio and S.project.audio.cries then
      for id in pairs(S.project.audio.cries) do cries[#cries + 1] = id end
    end
    if S.data and S.data.audio and S.data.audio.cries then
      local seen = {}
      for _, id in ipairs(cries) do seen[id] = true end
      for id in pairs(S.data.audio.cries) do
        if not seen[id] then cries[#cries + 1] = id end
      end
    end
    table.sort(cries)
    local bw = math.max(80 * s, fw - 88 * s)
    if Kit.button(fx, fy_, bw, fh_,
        Kit.ellipsize("small", cur ~= "" and cur or "(species)", bw - 8 * s),
        { kind = "ghost" }) and #cries > 0 then
      mon = mutate()
      mon.cry = cycle(cries, cur)
      if mon.cry == "" then mon.cry = nil end
      App.markDirty()
    end
    local typed = field(S, App, "pk_cry", fx + bw + 6 * s, fy_,
      math.max(60 * s, fw - bw - 6 * s), fh_, cur, "CRY_ID")
    if typed ~= cur then
      mon = mutate()
      mon.cry = (typed ~= "" and typed) or nil
    end
  end)
  row("Palette", function(fx, fy_, fw, fh_)
    PalettePicker.row(S, {
      x = fx, y = fy_, w = fw, h = fh_,
      current = mon.palette or "",
      effective = Preview.monPaletteName(S, mon, S.pokemonId),
      emptyLabel = "(pack default)",
      clearLabel = "(pack default / MEWMON)",
      allowClear = true,
      title = "POKEMON SPRITE / ICON PALETTE",
      tooltip = "SGB palette for battle sprites and icon preview",
      onPick = function(id)
        mon = mutate()
        mon.palette = id
        Preview.invalidate()
        App.markDirty()
      end,
    })
  end)
  row("Icon", function(fx, fy_, fw, fh_)
    local _, resolvedName = Preview.pokemonIcon(S, mon, S.pokemonId)
    local cur = iconNameOf(mon)
    local label
    if type(mon.icon) == "table" and mon.icon.image then
      label = "custom"
    elseif cur ~= "" then
      label = cur
    else
      label = (resolvedName and (resolvedName .. " (dex)") or "(default)")
    end
    if Kit.button(fx, fy_, math.max(80 * s, fw - 100 * s), fh_,
        Kit.ellipsize("small", label, fw - 108 * s), { kind = "ghost" }) then
      local nextName = cycle(ICON_NAMES, cur)
      mon = mutate()
      if nextName == "" then
        mon.icon = nil
      else
        mon.icon = nextName
      end
      Preview.invalidate()
      App.markDirty()
    end
    if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "PNG", {
        kind = "ghost", tooltip = "Import a custom party icon PNG",
      }) then
      mon = mutate()
      local id = mon.id
      App.pickFile("Party icon PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          local m = S.project.pokemon[id]
          if not m then return end
          App.importToMod(picked, nil, function(rel)
            m.icon = { image = rel, frames = 2 }
          end)
        end)
    end
  end)
  row("Front PNG", function(fx, fy_, fw, fh_)
    local path = mon.spriteFront or ""
    Kit.text("micro", path ~= "" and path or "(none)", fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 90 * s, fy_, 90 * s, fh_, "Browse", {
        kind = "ghost",
        tooltip = "Copies abrab.png → assets/abrab.png (keeps your filename)",
      }) then
      mon = mutate()
      local id = mon.id
      App.pickFile("Front sprite PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          local m = S.project.pokemon[id]
          if not m then return end
          App.importToMod(picked, nil, function(rel)
            m.spriteFront = rel
          end)
        end)
    end
  end)
  row("Back PNG", function(fx, fy_, fw, fh_)
    local path = mon.spriteBack or ""
    Kit.text("micro", path ~= "" and path or "(none)", fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 90 * s, fy_, 90 * s, fh_, "Browse", {
        kind = "ghost",
        tooltip = "Copies your file into assets/ with the same name",
      }) then
      mon = mutate()
      local id = mon.id
      App.pickFile("Back sprite PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          local m = S.project.pokemon[id]
          if not m then return end
          App.importToMod(picked, nil, function(rel)
            m.spriteBack = rel
          end)
        end)
    end
  end)
  return math.max(fy, previewBottom), mon
end

local function drawLearnset(S, mon, mutate, App, formX, fy, formW, fh, s)
  Kit.text("micro", "Level-up moves (level, move id). Add rows below.",
    formX, fy, PAL.muted)
  fy = fy + 20 * s
  mon.learnset = mon.learnset or {}
  for i, row in ipairs(mon.learnset) do
    local lvl = row.level or 1
    local mv = row.move or "TACKLE"
    local vLvl = numField(S, App, "pk_ls_l_" .. i, formX, fy, 60 * s, fh, lvl)
    local vMv = field(S, App, "pk_ls_m_" .. i, formX + 70 * s, fy,
      formW - 160 * s, fh, mv, "MOVE")
    vMv = vMv:upper():gsub("%s+", "_")
    if vLvl ~= lvl or vMv ~= mv then
      mon = mutate()
      mon.learnset[i] = { level = math.max(1, math.min(100, vLvl)), move = vMv }
    end
    if Kit.button(formX + formW - 70 * s, fy, 60 * s, fh, "Del",
        { kind = "danger" }) then
      mon = mutate()
      table.remove(mon.learnset, i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(formX, fy, 140 * s, fh, "+ Learn row", { kind = "good" }) then
    mon = mutate()
    mon.learnset = mon.learnset or {}
    mon.learnset[#mon.learnset + 1] = { level = 10, move = "TACKLE" }
    App.markDirty()
  end
  return fy + fh + 8 * s, mon
end

local function drawEvolutions(S, mon, mutate, App, formX, fy, formW, fh, s)
  Kit.text("micro", "Methods: LEVEL (needs level), ITEM (needs item id), TRADE.",
    formX, fy, PAL.muted)
  fy = fy + 20 * s
  mon.evolutions = mon.evolutions or {}
  for i, evo in ipairs(mon.evolutions) do
    if Kit.button(formX, fy, 90 * s, fh, evo.method or "LEVEL",
        { kind = "accent" }) then
      mon = mutate()
      local idx = 1
      for mi, m in ipairs(EVO_METHODS) do
        if m == evo.method then idx = mi; break end
      end
      mon.evolutions[i].method = EVO_METHODS[(idx % #EVO_METHODS) + 1]
      App.markDirty()
    end
    local species = field(S, App, "pk_ev_sp_" .. i, formX + 100 * s, fy,
      140 * s, fh, evo.species or "", "SPECIES")
    species = species:upper():gsub("%s+", "_")
    if species ~= (evo.species or "") then
      mon = mutate(); mon.evolutions[i].species = species
    end
    if (evo.method or "LEVEL") == "LEVEL" then
      local lvl = numField(S, App, "pk_ev_lv_" .. i, formX + 250 * s, fy,
        60 * s, fh, evo.level or 16)
      if lvl ~= (evo.level or 16) then
        mon = mutate(); mon.evolutions[i].level = lvl
      end
    elseif evo.method == "ITEM" then
      local item = field(S, App, "pk_ev_it_" .. i, formX + 250 * s, fy,
        120 * s, fh, evo.item or "", "STONE")
      item = item:upper():gsub("%s+", "_")
      if item ~= (evo.item or "") then
        mon = mutate(); mon.evolutions[i].item = item
      end
    end
    if Kit.button(formX + formW - 70 * s, fy, 60 * s, fh, "Del",
        { kind = "danger" }) then
      mon = mutate()
      table.remove(mon.evolutions, i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(formX, fy, 140 * s, fh, "+ Evolution", { kind = "good" }) then
    mon = mutate()
    mon.evolutions = mon.evolutions or {}
    mon.evolutions[#mon.evolutions + 1] = {
      method = "LEVEL", level = 16, species = "ABRA",
    }
    App.markDirty()
  end
  return fy + fh + 8 * s, mon
end

local function drawTmhm(S, mon, mutate, App, formX, fy, formW, fh, s)
  Kit.text("micro", "Comma-separated move ids this species can learn via TM/HM.",
    formX, fy, PAL.muted)
  fy = fy + 20 * s
  local joined = table.concat(mon.tmhm or {}, ",")
  local v = field(S, App, "pk_tmhm", formX, fy, formW - 20 * s, fh, joined,
    "MEGA_PUNCH,TOXIC,…")
  if v ~= joined then
    mon = mutate()
    mon.tmhm = parseMoveList(v)
  end
  fy = fy + fh + 12 * s
  Kit.text("micro", string.format("%d TM/HM moves", #(mon.tmhm or {})),
    formX, fy, PAL.faint)
  return fy + 24 * s, mon
end

local function drawDex(S, mon, mutate, App, formX, fy, formW, labelW, fh, s)
  mon.dexEntry = mon.dexEntry or {}
  local de = mon.dexEntry
  local fieldW = formW - labelW - 20 * s
  local function row(label, body)
    Kit.text("small", label, formX, fy + 6 * s, PAL.caption)
    body(formX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end
  row("Kind", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_dk", fx, fy_, fw, fh_, de.kind or "", "MOUSE")
    if v ~= (de.kind or "") then mon = mutate(); mon.dexEntry.kind = v end
  end)
  row("Height ft/in", function(fx, fy_, fw, fh_)
    local ft = numField(S, App, "pk_dft", fx, fy_, 50 * s, fh_, de.heightFt or 0)
    local inch = numField(S, App, "pk_din", fx + 60 * s, fy_, 50 * s, fh_,
      de.heightIn or 0)
    if ft ~= (de.heightFt or 0) or inch ~= (de.heightIn or 0) then
      mon = mutate()
      mon.dexEntry.heightFt = ft
      mon.dexEntry.heightIn = math.max(0, math.min(11, inch))
    end
  end)
  row("Weight", function(fx, fy_, fw, fh_)
    local v = numField(S, App, "pk_dw", fx, fy_, 80 * s, fh_, de.weight or 0)
    if v ~= (de.weight or 0) then mon = mutate(); mon.dexEntry.weight = v end
  end)
  row("Text id", function(fx, fy_, fw, fh_)
    local v = field(S, App, "pk_dt", fx, fy_, fw, fh_, de.text or "", "_FooDexEntry")
    if v ~= (de.text or "") then
      mon = mutate()
      mon.dexEntry.text = v
    end
  end)
  row("Dex body", function(fx, fy_, fw, fh_)
    -- editable override stored on project.text when text id is set
    local tid = de.text
    local body = ""
    if tid and S.project.text and S.project.text[tid] then
      body = S.project.text[tid]
    elseif tid and S.data and S.data.text then
      body = S.data.text[tid] or ""
    end
    local shown = body:gsub("\n", "\\n"):gsub("\f", "\\f")
    local v = field(S, App, "pk_dbody", fx, fy_, fw, fh_, shown, "Dex text…")
    local decoded = v:gsub("\\n", "\n"):gsub("\\f", "\f")
    if tid and tid ~= "" and decoded ~= body then
      mon = mutate()
      if not mon.dexEntry.text or mon.dexEntry.text == "" then
        mon.dexEntry.text = "_" .. mon.id:sub(1, 1)
          .. mon.id:sub(2):lower():gsub("_(%w)", function(c) return c:upper() end)
          .. "DexEntry"
      end
      S.project.text[mon.dexEntry.text] = decoded
      App.markDirty()
    end
  end)
  return fy, mon
end

function Pokemon.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end

  local listW = math.min(220 * s, w * 0.28)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s

  Kit.caption(x, y, "SPECIES")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "pokemonQuery", x, qy, listW, qh, "search species...")
  if qChanged then S.pokemonListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allSpeciesIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local mon = S.project.pokemon[id]
        or (S.data.pokemon and S.data.pokemon[id])
      local name = mon and tostring(mon.name or "") or ""
      if id:lower():find(ql, 1, true) or name:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  local rowH = 30 * s
  local thumb = 24 * s
  local listInnerX, listInnerY = x + 8 * s, listY + 8 * s
  local listInnerW, listInnerH = listW - 16 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(listInnerW)
  local perPage = math.max(1, math.floor(listInnerH / (rowH + 4 * s)))
  S.pokemonListOffset = Kit.scroll(listInnerX, listInnerY, listInnerW, listInnerH,
    S.pokemonListOffset or 0, #ids, perPage)
  Kit.pushClip(listInnerX, listInnerY, rowW, listInnerH)
  local ry = listInnerY
  for i = (S.pokemonListOffset or 0) + 1,
      math.min(#ids, (S.pokemonListOffset or 0) + perPage) do
    local id = ids[i]
    local rowMon = S.project.pokemon[id]
      or (S.data.pokemon and S.data.pokemon[id])
    local owned = S.project.pokemon[id] ~= nil
    if Kit.row(listInnerX, ry, rowW, rowH, S.pokemonId == id, PAL.green) then
      S.pokemonId = id
    end
    Preview.drawPokemonIcon(S, rowMon, listInnerX + 4 * s,
      ry + (rowH - thumb) / 2, thumb, thumb, id)
    local textX = listInnerX + 8 * s + thumb
    Kit.text("mono", Kit.ellipsize("mono", id, rowW - (textX - listInnerX) - 4 * s),
      textX, ry + 7 * s, owned and PAL.text or PAL.muted)
    ry = ry + rowH + 4 * s
  end
  Kit.popClip()
  Kit.scrollbar(listInnerX, listInnerY, listInnerW, listInnerH,
    S.pokemonListOffset or 0, #ids, perPage)

  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New species",
      { kind = "good" }) then
    local nid = "NEW_MON"
    local n = 1
    while S.project.pokemon[nid] or (S.data.pokemon and S.data.pokemon[nid]) do
      n = n + 1
      nid = "NEW_MON_" .. n
    end
    S.project.pokemon[nid] = defaultMon(nid)
    S.pokemonId = nid
    App.markDirty()
  end

  local mon, owned = resolveMon(S, S.pokemonId)
  if not mon then
    local first = ids[1]
    S.pokemonId = first
    mon, owned = resolveMon(S, first)
  end
  if not mon then
    Kit.emptyBox(formX, listY, formW, listH, "No species in data — import a ROM cache")
    return
  end

  local function mutate()
    mon = ensureOwned(S, S.pokemonId)
    owned = true
    return mon
  end

  Kit.caption(formX, y, "EDIT  " .. (mon.id or "?") .. (owned and "" or "  (vanilla)"))
  local secY = y + 22 * s
  local sx = formX
  S.pokemonSection = S.pokemonSection or "basics"
  for _, sec in ipairs(SECTIONS) do
    local on = S.pokemonSection == sec.id
    local bw = Kit.textWidth("micro", sec.label) + 18 * s
    if Kit.chip(sx, secY, bw, 26 * s, sec.label, on, PAL.green) then
      S.pokemonSection = sec.id
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
  FormPane.track(S, "pokemonFormScroll",
    tostring(S.pokemonId) .. "|" .. tostring(S.pokemonSection))
  local fy, view = FormPane.begin(S, "pokemonFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local labelW = 110 * s
  local fh = 30 * s

  if S.pokemonSection == "basics" then
    fy, mon = drawBasics(S, mon, mutate, App, viewX, fy, viewW, labelW, fh, s)
  elseif S.pokemonSection == "learnset" then
    fy, mon = drawLearnset(S, mon, mutate, App, viewX, fy, viewW, fh, s)
  elseif S.pokemonSection == "evolutions" then
    fy, mon = drawEvolutions(S, mon, mutate, App, viewX, fy, viewW, fh, s)
  elseif S.pokemonSection == "tmhm" then
    fy, mon = drawTmhm(S, mon, mutate, App, viewX, fy, viewW, fh, s)
  elseif S.pokemonSection == "dex" then
    fy, mon = drawDex(S, mon, mutate, App, viewX, fy, viewW, labelW, fh, s)
  end
  FormPane.finish(S, "pokemonFormScroll", contentTop, fy, view)

  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    S.project.pokemon[mon.id] = nil
    S.pokemonId = mon.id
    App.markDirty()
  end
end

return Pokemon
