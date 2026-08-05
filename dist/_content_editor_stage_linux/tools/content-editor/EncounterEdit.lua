-- Shared wild-encounter editors (grass/water/fishing) for Maps + Encounters tabs.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Preview = require("Preview")
local PAL = Theme.PAL

local EncounterEdit = {}

EncounterEdit.KINDS = {
  { id = "grass", label = "GRASS" },
  { id = "water", label = "WATER" },
  { id = "super", label = "SUPER" },
  { id = "old", label = "OLD" },
  { id = "good", label = "GOOD" },
}

function EncounterEdit.cloneSlots(slots)
  local out = {}
  for i, slot in ipairs(slots or {}) do
    out[i] = { level = slot.level, species = slot.species }
  end
  return out
end

function EncounterEdit.cloneEncounters(enc)
  if type(enc) ~= "table" then return nil end
  local out = {}
  for _, kind in ipairs({ "grass", "water" }) do
    local band = enc[kind]
    if type(band) == "table" then
      out[kind] = {
        rate = band.rate or 0,
        slots = EncounterEdit.cloneSlots(band.slots),
      }
    end
  end
  return out
end

function EncounterEdit.resolveEncounters(S, mapId, mapDef)
  if mapDef and mapDef.encounters then return mapDef.encounters, true end
  if S.data and S.data.encounters and S.data.encounters[mapId] then
    return S.data.encounters[mapId], false
  end
  return nil, false
end

function EncounterEdit.resolveSuperRod(S, mapId, mapDef)
  if mapDef and mapDef.superRod then return mapDef.superRod, true end
  if S.data and S.data.field and S.data.field.superRod
      and S.data.field.superRod[mapId] then
    return S.data.field.superRod[mapId], false
  end
  return nil, false
end

local function defaultFishing(S)
  local FieldDefaults = require("src.world.FieldDefaults")
  return FieldDefaults.field(S.data, "fishing") or {}
end

function EncounterEdit.resolveOldRod(S)
  State.ensureProjectFields(S.project)
  if S.project.fishing and S.project.fishing.OLD_ROD then
    return S.project.fishing.OLD_ROD, true
  end
  return defaultFishing(S).OLD_ROD, false
end

function EncounterEdit.resolveGoodRod(S)
  State.ensureProjectFields(S.project)
  if S.project.fishing and S.project.fishing.GOOD_ROD then
    return S.project.fishing.GOOD_ROD, true
  end
  return defaultFishing(S).GOOD_ROD, false
end

local function ensureEncounterBand(map, kind)
  map.encounters = map.encounters or {}
  if not map.encounters[kind] then
    map.encounters[kind] = { rate = 0, slots = {} }
  end
  map.encounters[kind].slots = map.encounters[kind].slots or {}
  return map.encounters[kind]
end

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function drawSlotRows(S, App, px, py, propW, listBottom, fh, s,
    kindKey, slots, onChange, onDelete, maxSlots)
  Kit.text("micro", "Slots (level, species)", px + 10 * s, py, PAL.caption)
  py = py + 16 * s
  for si = 1, #(slots or {}) do
    if py + fh > listBottom - 36 * s then break end
    local slot = slots[si]
    local speciesDef = (S.project.pokemon and S.project.pokemon[slot.species])
      or (S.data.pokemon and S.data.pokemon[slot.species])
    if speciesDef and speciesDef.spriteFront then
      Preview.draw(S, speciesDef.spriteFront, px + 10 * s, py, 24 * s, 24 * s,
        Preview.monPaletteName(S, speciesDef, slot.species))
    end
    local lx = px + 40 * s
    local lvl = tonumber(field(App, "enc_lv_" .. kindKey .. si, lx, py, 40 * s, fh,
      tostring(slot.level or 1), "1")) or 1
    local spW = math.max(80 * s, propW - (lx - px) - 48 * s - 42 * s - 8 * s)
    local sp = field(App, "enc_sp_" .. kindKey .. si, lx + 48 * s, py, spW, fh,
      slot.species or "PIDGEY", "PIDGEY"):upper():gsub("%s+", "_")
    if lvl ~= (slot.level or 1) or sp ~= (slot.species or "") then
      onChange(si, { level = math.max(1, lvl), species = sp })
    end
    if Kit.button(px + propW - 42 * s, py, 28 * s, fh, "X", { kind = "danger" }) then
      onDelete(si)
      break
    end
    py = py + math.max(fh, 26 * s) + 4 * s
  end
  if #(slots or {}) < (maxSlots or 10) and py + 30 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "+ Slot", { kind = "accent" }) then
      onChange(#(slots or {}) + 1, { level = 5, species = "MAGIKARP" }, true)
    end
    py = py + 32 * s
  end
  return py
end

-- Draw wild encounter editor for a map. mutate() must return an owned map def.
function EncounterEdit.drawWild(S, map, mutate, App, px, py, propW, listBottom, fh, s)
  if not map then
    Kit.text("micro", "Select a map.", px + 10 * s, py, PAL.faint)
    return py + 20 * s
  end
  State.ensureProjectFields(S.project)
  local mapId = map.id or S.mapId
  local enc = EncounterEdit.resolveEncounters(S, mapId, map)
  local superSlots = EncounterEdit.resolveSuperRod(S, mapId, map)

  S.mapEncKind = S.mapEncKind or "grass"
  local sx, sy = px + 10 * s, py
  for _, kind in ipairs(EncounterEdit.KINDS) do
    local on = S.mapEncKind == kind.id
    local bw = Kit.textWidth("micro", kind.label) + 14 * s
    if sx + bw > px + propW - 10 * s then
      sx = px + 10 * s
      sy = sy + fh + 4 * s
    end
    if Kit.chip(sx, sy, bw, fh, kind.label, on, PAL.green) then
      S.mapEncKind = kind.id
    end
    sx = sx + bw + 4 * s
  end
  py = sy + fh + 10 * s

  local kind = S.mapEncKind

  if kind == "grass" or kind == "water" then
    local band = enc and enc[kind]
    if not band then
      Kit.text("micro", "No " .. kind .. " encounters on this map.",
        px + 10 * s, py, PAL.faint)
      py = py + 18 * s
      if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add " .. kind,
          { kind = "good" }) then
        map = mutate()
        local b = ensureEncounterBand(map, kind)
        b.rate = kind == "grass" and 25 or 5
        b.slots = {
          { level = kind == "grass" and 3 or 5,
            species = kind == "grass" and "PIDGEY" or "TENTACOOL" },
        }
        App.markDirty()
      end
      return py + 36 * s
    end

    Kit.text("micro", "Rate (0-255)", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local rate = tonumber(field(App, "enc_rate_" .. kind, px + 10 * s, py, 70 * s, fh,
      tostring(band.rate or 0), "0")) or 0
    if rate ~= (band.rate or 0) then
      map = mutate()
      ensureEncounterBand(map, kind).rate = math.max(0, math.min(255, rate))
    end
    py = py + fh + 8 * s

    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, kind, band.slots,
      function(si, slot, isAdd)
        map = mutate()
        local b = ensureEncounterBand(map, kind)
        if isAdd then b.slots[#b.slots + 1] = slot
        else b.slots[si] = slot end
        App.markDirty()
      end,
      function(si)
        map = mutate()
        table.remove(ensureEncounterBand(map, kind).slots, si)
        App.markDirty()
      end, 10)

    if py + 36 * s <= listBottom then
      if Kit.button(px + 10 * s, py, 100 * s, 28 * s, "Clear " .. kind,
          { kind = "ghost" }) then
        map = mutate()
        if map.encounters then map.encounters[kind] = nil end
        App.markDirty()
      end
      py = py + 36 * s
    end
    return py

  elseif kind == "super" then
    Kit.text("micro", "Super Rod group for this map (field.superRod).",
      px + 10 * s, py, PAL.muted)
    py = py + 18 * s
    if not superSlots then
      Kit.text("micro", "No Super Rod table here.", px + 10 * s, py, PAL.faint)
      py = py + 18 * s
      if Kit.button(px + 10 * s, py, propW - 20 * s, 28 * s, "+ Add Super Rod",
          { kind = "good" }) then
        map = mutate()
        map.superRod = { { level = 15, species = "POLIWAG" } }
        App.markDirty()
      end
      return py + 36 * s
    end
    py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, "super", superSlots,
      function(si, slot, isAdd)
        map = mutate()
        map.superRod = map.superRod or EncounterEdit.cloneSlots(superSlots)
        if isAdd then map.superRod[#map.superRod + 1] = slot
        else map.superRod[si] = slot end
        App.markDirty()
      end,
      function(si)
        map = mutate()
        map.superRod = map.superRod or EncounterEdit.cloneSlots(superSlots)
        table.remove(map.superRod, si)
        App.markDirty()
      end, 10)
    if py + 36 * s <= listBottom then
      if Kit.button(px + 10 * s, py, 110 * s, 28 * s, "Clear Super",
          { kind = "ghost" }) then
        map = mutate()
        map.superRod = {}
        App.markDirty()
      end
      py = py + 36 * s
    end
    return py

  elseif kind == "old" then
    Kit.text("micro", "Old Rod (global -- always hooks this mon).",
      px + 10 * s, py, PAL.muted)
    py = py + 18 * s
    local def = select(1, EncounterEdit.resolveOldRod(S))
      or { always = { species = "MAGIKARP", level = 5 } }
    local always = def.always or { species = "MAGIKARP", level = 5 }
    Kit.text("micro", "Level", px + 10 * s, py, PAL.caption)
    py = py + 14 * s
    local lvl = tonumber(field(App, "enc_old_lv", px + 10 * s, py, 50 * s, fh,
      tostring(always.level or 5), "5")) or 5
    local sp = field(App, "enc_old_sp", px + 70 * s, py, 140 * s, fh,
      always.species or "MAGIKARP", "MAGIKARP"):upper():gsub("%s+", "_")
    if lvl ~= (always.level or 5) or sp ~= (always.species or "") then
      S.project.fishing.OLD_ROD = {
        always = { level = math.max(1, lvl), species = sp },
      }
      App.markDirty()
    end
    py = py + fh + 10 * s
    if S.project.fishing.OLD_ROD
        and Kit.button(px + 10 * s, py, 120 * s, 28 * s, "Revert Old",
          { kind = "danger" }) then
      S.project.fishing.OLD_ROD = nil
      App.markDirty()
    end
    return py + 36 * s
  end

  -- good
  Kit.text("micro", "Good Rod (global pool -- ~1/3 bite).",
    px + 10 * s, py, PAL.muted)
  py = py + 18 * s
  local def = select(1, EncounterEdit.resolveGoodRod(S)) or {
    pool = {
      { species = "GOLDEEN", level = 10 },
      { species = "POLIWAG", level = 10 },
    },
  }
  local pool = def.pool or {}
  py = drawSlotRows(S, App, px, py, propW, listBottom, fh, s, "good", pool,
    function(si, slot, isAdd)
      local cur = EncounterEdit.resolveGoodRod(S)
      local base = (cur and cur.pool)
        and EncounterEdit.cloneSlots(cur.pool)
        or EncounterEdit.cloneSlots(pool)
      if isAdd then base[#base + 1] = slot else base[si] = slot end
      S.project.fishing.GOOD_ROD = { pool = base }
      App.markDirty()
    end,
    function(si)
      local cur = EncounterEdit.resolveGoodRod(S)
      local base = (cur and cur.pool)
        and EncounterEdit.cloneSlots(cur.pool)
        or EncounterEdit.cloneSlots(pool)
      table.remove(base, si)
      S.project.fishing.GOOD_ROD = { pool = base }
      App.markDirty()
    end, 8)
  if S.project.fishing.GOOD_ROD and py + 36 * s <= listBottom then
    if Kit.button(px + 10 * s, py, 120 * s, 28 * s, "Revert Good",
        { kind = "danger" }) then
      S.project.fishing.GOOD_ROD = nil
      App.markDirty()
    end
    py = py + 36 * s
  end
  return py
end

return EncounterEdit
