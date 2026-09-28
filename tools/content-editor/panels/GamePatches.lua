-- GAME PATCHES tab: switches for features a mod adds on top of the game
-- (nothing in the engine is changed; each one is generated into main.lua).
-- FireRed / LeafGreen: the real time clock (day and night, Gen3DayNight),
-- with its encounter tables as a setting of it.
--
-- Each patch is a title, one line under it and an Off / On switch; what it
-- does in detail opens in a pop-up (Description).

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL

local M = {}

-- A two-way switch: "Off" | "On" (smaller for a sub setting). Returns the
-- new value when clicked.
local function switch(x, y, on, s, small)
  local w, h = (small and 64 or 90) * s, (small and 24 or 34) * s
  local picked
  if Kit.chip(x, y, w, h, "Off", not on, PAL.red, nil, "Turn it off") and on then picked = false end
  if Kit.chip(x + w + 6 * s, y, w, h, "On", on, PAL.green, nil, "Turn it on") and not on then picked = true end
  return picked
end

-- What the pop-ups say ---------------------------------------------------------

local function clockText(S)
  local DN = require("Gen3DayNight")
  local on, cfg = DN.enabled(S.project), DN.settings(S.project)
  local lines = {
    "The game follows the player's own clock, like Crystal. Outdoor maps (Town, City, Route, Ocean route) look like morning, day or night; buildings, caves, battles and menus look the same all day.",
    ("Morning from %d:00, day from %d:00, night from %d:00, with a %d-minute fade (Settings)."):format(
      cfg.morning, cfg.day, cfg.night, cfg.blend),
    ("%d blocks have a night look: lit windows, lamps and signs."):format(#DN.paintedBlocks(S.project)),
    DN.encountersEnabled(S.project) and "Wild encounters change with the time of day (Encounter tables)."
      or "Wild encounters use the all-day lists (Encounter tables is off).",
    "Turning it off keeps every setting and night look for when it's turned on again. Encounter tables go off with it, and on again with it.",
    on and "It is on." or "It is off: the game has no clock.",
  }
  if cfg.testHour then
    lines[#lines + 1] = ("Test hour %d:00 is pinned -- clear it in Settings before you share the mod."):format(cfg.testHour)
  end
  return "Real Time Clock", lines
end

local function encounterText(S)
  local DN = require("Gen3DayNight")
  local lines = {
    ("On: FireRed's own routes and caves (%d Kanto tables) get Pokemon Crystal's morning, day and night lists straight away, as their own lists. Maps added in a mod aren't touched."):format(#DN.crystalTargets(S.project)),
    "Edit them in Encounters (pick a map, then Morning, Day or Night) like any other list. Back to one all-day list or Keep the all-day list at every time takes one table out.",
    "Off: Crystal's lists come back out and every table uses its all-day list. Tables you've edited are kept, and so are lists you made yourself.",
    "It's a setting of the real time clock: off while the clock is off, and on again when the clock is turned on.",
  }
  return "Encounter tables", lines
end

local function wrappedLines(f, text, width)
  if f and f.getWrap then
    local _, wrapped = f:getWrap(text, width)
    return math.max(1, #wrapped)
  end
  return 1
end

-- The pop-up, over the tab: a description, or (for an action) a warning
-- with Cancel and a confirm button.
local function popup(S, App, x, y, w, h)
  local s = Kit.scale
  local confirm = S._gamePatchConfirm and M.confirms[S._gamePatchConfirm]
  local title, lines
  if confirm then title, lines = confirm.title, confirm.lines(S)
  else title, lines = M.describe[S._gamePatchPopup](S) end
  local G = love.graphics
  local f = Kit.fonts and Kit.fonts.small
  local bw = math.min(w - 40 * s, 640 * s)
  local textW = bw - 40 * s
  local lineH = f and f:getHeight() * 1.25 or 18 * s
  local total = 0
  for _, line in ipairs(lines) do total = total + wrappedLines(f, line, textW) * lineH + 8 * s end
  local bh = total + 110 * s
  local bx, by = x + (w - bw) / 2, y + 40 * s
  Theme.col(PAL.bgBot, 0.75)
  G.rectangle("fill", x, y, w, h)
  -- solid underneath: the card itself is see-through
  Theme.col(PAL.bgMid, 1)
  G.rectangle("fill", bx, by, bw, bh, 16 * s, 16 * s)
  Kit.card(bx, by, bw, bh)
  Kit.text("button", title, bx + 20 * s, by + 18 * s, PAL.heading)
  local ty = by + 54 * s
  for i, line in ipairs(lines) do
    Theme.col(confirm and i == 1 and PAL.red or PAL.text, 1)
    if f then G.setFont(f) end
    G.printf(line, bx + 20 * s, ty, textW, "left")
    ty = ty + wrappedLines(f, line, textW) * lineH + 8 * s
  end
  G.setColor(1, 1, 1, 1)
  if confirm then
    if Kit.button(bx + bw - 140 * s, by + bh - 46 * s, 120 * s, 30 * s, "Cancel", { kind = "ghost", font = "micro" })
        or (Kit.mouseClicked and not Kit.hit(bx, by, bw, bh)) then
      S._gamePatchConfirm = nil
    elseif Kit.button(bx + 20 * s, by + bh - 46 * s, 240 * s, 30 * s, confirm.button, { kind = "danger", font = "micro" }) then
      S._gamePatchConfirm = nil
      confirm.run(S, App)
    end
    return
  end
  local close = Kit.button(bx + bw - 140 * s, by + bh - 46 * s, 120 * s, 30 * s, "Close", { kind = "ghost", font = "micro" })
  if close or (Kit.mouseClicked and not Kit.hit(bx, by, bw, bh)) then S._gamePatchPopup = nil end
end

-- The patches ---------------------------------------------------------------
-- Each patch gets its own box. Its sub settings share that box, below a
-- line, with smaller text and switches.

local function cleanText(S)
  local applied = require("Gen3Clean").enabled(S.project)
  return "Clean Project", {
    "Start a mod from scratch. Apply wipes the open project and leaves one blank starter map.",
    "A new game starts on the starter map (PLAYER tab > start map) with no story flags, variables or events.",
    "The intro only asks boy or girl and the player's name: no professor, no rival. The title screen and menu stay.",
    "FireRed's own maps and scripts are hidden and can't be reached in game. MAPS > Import template map brings a FireRed map's layout in under a new name -- never its events or story.",
    "Pokemon, moves, items, types, tilesets, graphics and trainers stay available.",
    applied and "This project is clean." or "Only do this at the start of a project.",
  }
end

M.describe = { clock = clockText, encounters = encounterText, clean = cleanText }

M.confirms = {
  clean = {
    title = "Clean Project -- wipe this project?",
    button = "Wipe and start clean",
    lines = function(S)
      return {
        "This should only be done at the start of a project. All changes made up until this point will be gone.",
        ("Everything in %s -- maps, events, scripts, Pokemon, items, trainers, graphics and settings edits -- is removed, and the mod is saved straight away. It can't be undone."):format(
          tostring((S.project or {}).name or (S.project or {}).id or "this mod")),
        "What's left: one blank starter map, a new game that starts there with no story, and the short intro (boy or girl, and a name).",
      }
    end,
    run = function(S, App)
      local ok, result = pcall(require("Gen3Clean").apply, S)
      if not ok then S.status = "Clean Project failed: " .. tostring(result); return end
      App.markDirty()
      local path = S.path
      if path and App.save() then
        if App.openMod then App.openMod(path) end
        S.status = "Clean Project applied: starting from " .. tostring(result)
      else
        S.status = "Clean Project applied (not saved yet): starting from " .. tostring(result)
      end
      S.tab = "patches"
    end,
  },
}

local function dayNight() return require("Gen3DayNight") end

M.PATCHES = {
  {
    id = "clean", title = "Clean Project", subtitle = "Start from scratch: no story, events or maps (Fire Red, Leaf Green)",
    action = { label = "Apply", confirm = "clean",
      tooltip = "Wipe this project and start clean -- asks first" },
    note = function(S)
      return require("Gen3Clean").enabled(S.project) and "This project is clean" or nil
    end,
  },
  {
    id = "clock", title = "Real Time Clock", subtitle = "Day and night cycles (Fire Red, Leaf Green)",
    isOn = function(S) return dayNight().enabled(S.project) end,
    setOn = function(S, on)
      local changed = dayNight().setEnabled(S.project, on)
      if changed then dayNight().syncCrystalPopulation(S) end -- Encounter tables follow the clock
      return changed
    end,
    status = { on = "Real time clock on", off = "Real time clock off (settings kept)" },
    note = function(S)
      local h = dayNight().settings(S.project).testHour
      return h and ("Test hour %d:00 is pinned"):format(h) or nil
    end,
    settings = { tooltip = "Hours, tints, night looks and the preview (GFX > Day & night)",
      open = function(S) S.tab, S.g3GfxMode = "gfx", "daynight" end },
    subs = {
      {
        id = "encounters", title = "Encounter tables", subtitle = "Pre-configured Day/ night encounters that can be edited",
        isOn = function(S) return dayNight().encountersEnabled(S.project) end,
        setOn = function(S, on)
          if on and not dayNight().enabled(S.project) then
            S.status = "Turn the Real Time Clock on first: Encounter tables come on with it"
            return false
          end
          local changed = dayNight().setEncounters(S.project, on)
          if changed then dayNight().syncCrystalPopulation(S) end
          return changed
        end,
        status = { on = "Encounter tables on: Crystal's lists filled in, ready to edit",
          off = "Encounter tables off: Crystal's lists taken back out, all-day lists used" },
      },
    },
  },
}

local function flip(S, App, patch, picked)
  if picked ~= nil and patch.setOn(S, picked) then
    App.markDirty()
    S.status = picked and patch.status.on or patch.status.off
  end
end

-- One patch's box. Returns the next y.
local function patchCard(S, App, patch, x, y, w)
  local s = Kit.scale
  local colW = 186 * s
  local rx = x + w - colW - 16 * s
  local subs = patch.subs or {}
  local mainH = patch.settings and 132 or 96
  local subH = 62
  local cardH = (mainH + #subs * subH + (#subs > 0 and 10 or 0)) * s
  Kit.card(x, y, w, cardH)
  local cx, cy = x + 18 * s, y + 16 * s
  local on = patch.isOn and patch.isOn(S) or false

  Kit.text("button", patch.title, cx, cy, PAL.heading)
  Kit.text("small", patch.subtitle, cx, cy + 26 * s, PAL.muted)
  local note = patch.note and patch.note(S)
  if note then Kit.text("small", note, cx, cy + 50 * s, patch.action and PAL.green or PAL.yellow) end
  if patch.action then
    if Kit.button(rx, cy, colW, 34 * s, patch.action.label, { kind = "danger", font = "micro",
        tooltip = patch.action.tooltip }) then
      S._gamePatchConfirm = patch.action.confirm
    end
    on = true
  else
    flip(S, App, patch, switch(rx, cy, on, s))
    on = patch.isOn(S)
  end
  if Kit.button(rx, cy + 44 * s, colW, 28 * s, "Description", { kind = "ghost", font = "micro",
      tooltip = "What " .. patch.title .. " does" }) then
    S._gamePatchPopup = patch.id
  end
  if patch.settings and Kit.button(rx, cy + 78 * s, colW, 28 * s, "Settings", { kind = "ghost", font = "micro",
      tooltip = patch.settings.tooltip }) then
    patch.settings.open(S)
  end

  -- sub settings: same box, smaller
  local sy = y + mainH * s
  local subColW = 134 * s
  local srx = x + w - subColW - 16 * s
  for _, sub in ipairs(subs) do
    Theme.col(PAL.cardBorder, 0.3)
    love.graphics.line(cx, sy, x + w - 16 * s, sy)
    love.graphics.setColor(1, 1, 1, 1)
    local ty = sy + 10 * s
    local ex = cx + 18 * s
    Kit.text("small", sub.title, ex, ty, on and PAL.heading or PAL.faint)
    Kit.text("micro", sub.subtitle, ex, ty + 20 * s, on and PAL.muted or PAL.faint)
    flip(S, App, sub, switch(srx, ty, sub.isOn(S), s, true))
    if Kit.button(srx, ty + 28 * s, subColW, 20 * s, "Description", { kind = "ghost", font = "micro",
        tooltip = "What " .. sub.title .. " does" }) then
      S._gamePatchPopup = sub.id
    end
    sy = sy + subH * s
  end
  return y + cardH + 12 * s
end

function M.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local top = y
  Kit.caption(x, y, "GAME PATCHES")
  y = y + 24 * s
  Kit.text("small", "Features this mod adds on top of the game. The game itself isn't changed; each one is written into the mod.",
    x, y, PAL.muted)
  y = y + 32 * s
  local cw = math.min(w, 760 * s)
  if not require("Generation").isGen3(S) or not S.project then
    Kit.emptyBox(x, y, cw, 120 * s, "No game patches for this game yet (FireRed and LeafGreen have the real time clock).")
    return
  end
  -- Encounter tables: Crystal's lists filled in / taken out to match the switch
  if dayNight().syncCrystalPopulation(S) then App.markDirty() end
  -- While a pop-up is open, the cards underneath don't take clicks.
  local open = S._gamePatchPopup ~= nil or S._gamePatchConfirm ~= nil
  local blocked = Kit.blockClicks
  if open then Kit.blockClicks = true end
  for _, patch in ipairs(M.PATCHES) do y = patchCard(S, App, patch, x, y, cw) end
  Kit.blockClicks = blocked
  if open then popup(S, App, x, top, w, h) end
end

return M
