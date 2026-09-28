-- Day and night (Gen3DayNight, Gen3DayNightCore, Gen3DayNightRuntime). Plain
-- LuaJIT, no LOVE; lamp colours use the game's own cache. Run from the
-- repository root:
--   POKEPORT_RECOMP=<runtime checkout> POKEPORT_GEN3_CACHE=<folder holding
--   data/generated/gba> luajit tests/content-editor/test_gen3_daynight.lua
local RUNTIME = assert(os.getenv("POKEPORT_RECOMP"), "Set POKEPORT_RECOMP")
local CACHE = assert(os.getenv("POKEPORT_GEN3_CACHE"), "Set POKEPORT_GEN3_CACHE")
package.path = "tools/content-editor/?.lua;tools/save-editor/?.lua;" .. RUNTIME .. "/?.lua;"
  .. RUNTIME .. "/?/init.lua;" .. package.path

local Core = require("Gen3DayNightCore")
local DN = require("Gen3DayNight")

local function read(rel)
  local f = io.open(CACHE .. "/" .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function fresh() return { project = {}, data = { _gen3Read = read, _g3Packs = {} } } end

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

run("parts of the day follow Crystal's hours", function()
  local s = DN.settings({})
  assert(Core.period(s, 3, 59) == "night" and Core.period(s, 4, 0) == "morning")
  assert(Core.period(s, 9, 59) == "morning" and Core.period(s, 10, 0) == "day")
  assert(Core.period(s, 17, 59) == "day" and Core.period(s, 18, 0) == "night")
  assert(Core.period(s, 0, 0) == "night" and Core.period(s, 23, 59) == "night")
end)

run("a new part of the day fades in from the last", function()
  local s = DN.settings({})
  local nr, ng, nb = Core.hex(s.nightTint)
  local mr, mg, mb = Core.hex(s.morningTint)
  local r, g, b = Core.tintAt(s, 4, 0) -- the fade starts at night's colours
  assert(near(r, nr) and near(g, ng) and near(b, nb))
  r = Core.tintAt(s, 4, 15)
  assert(near(r, (nr + mr) / 2), "halfway")
  r, g, b = Core.tintAt(s, 4, 30)
  assert(near(r, mr) and near(g, mg) and near(b, mb))
  r, g, b = Core.tintAt(s, 12, 0)
  assert(r == 1 and g == 1 and b == 1, "day is untouched")
  r = Core.tintAt(s, 18, 0)
  assert(near(r, 1), "night fades in from day")
  r, g, b = Core.tintAt(s, 23, 0)
  assert(near(r, nr) and near(g, ng) and near(b, nb))
  s.blend = 0
  r = Core.tintAt(s, 4, 0)
  assert(near(r, mr), "no fade")
end)

run("grading works in the GBA's 5-bit colours", function()
  assert(select(1, Core.grade(255, 255, 255, 1, 1, 1)) == 255)
  local r, g, b = Core.grade(255, 255, 255, 0.5, 0.5, 0.5)
  assert(r == math.floor(math.floor(31 * 0.5 + 0.5) * 255 / 31 + 0.5) and r == g and g == b)
  assert(select(1, Core.grade(0, 0, 0, 0.3, 0.3, 0.3)) == 0)
  local a, bb, c = Core.bgr5(0x7FFF)
  assert(a == 31 and bb == 31 and c == 31)
  a, bb, c = Core.bgr5(1 + 2 * 32 + 3 * 1024)
  assert(a == 1 and bb == 2 and c == 3)
end)

run("settings keep only what differs; lit colours toggle", function()
  local p = {}
  assert(DN.setEnabled(p, true) and DN.enabled(p))
  assert(DN.set(p, "night", 19) and p.gen3DayNight.night == 19)
  assert(DN.set(p, "night", 18) and p.gen3DayNight.night == nil, "default removes it")
  assert(DN.setLit(p, "pallet_outdoor", 3, 7, true))
  assert(not DN.setLit(p, "pallet_outdoor", 3, 7, true), "already lit")
  assert(not DN.setLit(p, "pallet_outdoor", 3, 0, true), "colour 0 is see-through")
  assert(DN.isLit(p, "pallet_outdoor", 3, 7) and not DN.isLit(p, "pallet_outdoor", 3, 8))
  DN.setLit(p, "viridian_outdoor", 1, 2, true)
  local list = DN.litList(p)
  assert(#list == 2 and list[1].pair == "pallet_outdoor" and list[2].pair == "viridian_outdoor")
  assert(DN.setLit(p, "pallet_outdoor", 3, 7, false) and DN.setLit(p, "viridian_outdoor", 1, 2, false))
  assert(p.gen3DayNight.lit == nil)
  DN.setEnabled(p, false)
  DN.clearAllNightLooks(p) -- the default night looks it started with
  assert(p.gen3DayNight == nil, "nothing left")
end)

run("compile: nothing when off; hours, looks, test hour and lit colours when on", function()
  local p = {}
  assert(DN.compile(p) == nil)
  DN.setEnabled(p, true)
  DN.set(p, "testHour", 21)
  DN.setLit(p, "pallet_outdoor", 3, 7, true)
  local d = DN.compile(p)
  assert(d.morning == 4 and d.day == 10 and d.night == 18 and d.blend == 30 and d.testHour == 21)
  assert(d.nightTint == Core.DEFAULTS.nightTint and #d.lit == 1 and d.lit[1][1] == "pallet_outdoor"
    and d.lit[1][2] == 3 and d.lit[1][3] == 7)
  DN.validate(p)
end)

run("validation rejects bad settings", function()
  local function bad(t) return not pcall(DN.validate, { gen3DayNight = t }) end
  assert(bad({ enabled = true, morning = 12, day = 10 }), "order")
  assert(bad({ night = 25 }) and bad({ blend = -1 }) and bad({ nightTint = "blue" }) and bad({ testHour = 30 }))
  local many = { enabled = true, lit = { p = {} } }
  for i = 1, 33 do many.lit.p[(i % 13) .. "/" .. (i % 15 + 1) .. ""] = true end
  local n = 0
  for _ in pairs(many.lit.p) do n = n + 1 end
  if n > Core.MAX_LIT then assert(bad(many), "too many lit colours") end
  assert(not bad({ enabled = true }))
end)

run("the game side compiles as mod source", function()
  local Runtime = require("Gen3DayNightRuntime")
  love = love or {}
  love.filesystem = love.filesystem or {}
  local realRead = love.filesystem.read
  love.filesystem.read = function(path) local f = io.open(path, "rb"); local s = f and f:read("*a"); if f then f:close() end return s end
  local p = {}
  DN.setEnabled(p, true)
  DN.setLit(p, "pallet_outdoor", 3, 7, true)
  local src = Runtime(DN.compile(p), require("ModWriter").encodeLua)
  love.filesystem.read = realRead
  assert(src:find("editor.gen3.daynight.world", 1, true))
  assert(not src:find("package.loaded", 1, true), "mods have no package")
  assert(loadstring("return function(mod) " .. src .. " end"), "doesn't compile")
end)

run("map types decide which maps change", function()
  local S = fresh()
  S.project.maps = { A = { mapType = 3 }, B = { mapType = 8 }, C = { mapType = 4 }, D = { mapType = 1 }, E = {} }
  assert(DN.isOutdoorMap(S, "A") and DN.isOutdoorMap(S, "D"))
  assert(not DN.isOutdoorMap(S, "B") and not DN.isOutdoorMap(S, "C"))
end)

run("night paint: pixels get their own night colour, and back", function()
  local p = {}
  assert(DN.setNightPixels(p, "pallet_outdoor", 42, { 1, 2, 17 }, "F8E080"))
  local px = DN.nightPixels(p, "pallet_outdoor", 42)
  assert(px[1] == "f8e080" and px[2] == "f8e080" and px[17] == "f8e080" and px[3] == nil)
  assert(not DN.setNightPixels(p, "pallet_outdoor", 42, { 1 }, "f8e080"), "no change")
  assert(not DN.setNightPixels(p, "pallet_outdoor", 42, { 5 }, "yellow"), "bad colour")
  DN.setNightPixels(p, "pallet_outdoor", 42, { 2 }, "ffffff")
  local rec = p.gen3DayNight.paint.pallet_outdoor["42"]
  assert(#rec.px == 256 and #rec.cols == 2)
  assert(DN.hasNightPixels(p, "pallet_outdoor", 42) and #DN.paintedBlocks(p) == 1)
  DN.setEnabled(p, true)
  local d = DN.compile(p)
  assert(#d.paint == 1 and d.paint[1][1] == "pallet_outdoor" and d.paint[1][2] == 42 and d.paint[1][3] == rec.px)
  DN.validate(p)
  assert(DN.setNightPixels(p, "pallet_outdoor", 42, { 1, 2, 17 }, nil))
  assert(p.gen3DayNight.paint == nil, "cleared blocks leave nothing behind")
end)

run("night paint: a block holds up to 35 night colours", function()
  local p = {}
  for i = 1, DN.MAX_NIGHT_COLOURS do assert(DN.setNightPixels(p, "x", 1, { i }, ("%06x"):format(i))) end
  assert(not DN.setNightPixels(p, "x", 1, { 200 }, "123456"), "one too many")
  assert(not pcall(DN.validate, { gen3DayNight = { paint = { x = { ["1"] = { px = "!", cols = {} } } } } }))
end)

run("night paint: the day picture of a block", function()
  local S = fresh()
  local day = assert(DN.dayPixels(S, "pallet_outdoor", 1))
  local n = 0
  for i = 1, 256 do if day[i] then n = n + 1 end end
  assert(n == 256, "a ground block is solid")
end)

run("an example window finds the other windows, not blue roofs", function()
  local S = fresh()
  -- Pallet Town's window block, lit the way Pashley lit it
  local day = assert(DN.dayPixels(S, "pallet_outdoor", 665))
  local map = { ["63a5de"] = "ffded6", ["73bdf7"] = "fff784", ["9cd6ff"] = "ffd642", ["ceb56b"] = "ff8400" }
  local groups = {}
  for i = 1, 256 do
    local c = day[i]
    local h = c and ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
    if h and map[h] then groups[map[h]] = groups[map[h]] or {}; table.insert(groups[map[h]], i) end
  end
  for colour, list in pairs(groups) do DN.setNightPixels(S.project, "pallet_outdoor", 665, list, colour) end
  local rule = assert(DN.learn(S, "pallet_outdoor", 665))
  assert(rule.map["73bdf7"] == "fff784" and rule.frame["424a6b"])
  local found = assert(DN.findSimilar(S, "pallet_outdoor", 665, { "pallet_outdoor" }))
  local mids = {}
  for _, f in ipairs(found) do mids[#mids + 1] = f.mid end
  table.sort(mids)
  assert(table.concat(mids, ",") == "666,667,673,674", table.concat(mids, ","))
  -- Viridian: its windows, but none of its many blue roof blocks
  local v = DN.findSimilar(S, "pallet_outdoor", 665, { "viridian_outdoor" })
  local vm = {}
  for _, f in ipairs(v) do vm[f.mid] = true end
  assert(vm[6] and vm[667] and not vm[40] and not vm[41] and not vm[430], "roofs lit or windows missed")
  assert(DN.applySimilar(S.project, found[1]))
  assert(DN.hasNightPixels(S.project, "pallet_outdoor", found[1].mid))
end)

run("a missed window, lit like the example, teaches the search", function()
  local S = fresh()
  local day = assert(DN.dayPixels(S, "pallet_outdoor", 665))
  local map = { ["63a5de"] = "ffded6", ["73bdf7"] = "fff784", ["9cd6ff"] = "ffd642", ["ceb56b"] = "ff8400" }
  local function hexAt(d, i)
    local c = d[i]
    return c and ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
  end
  for i = 1, 256 do local h = hexAt(day, i); if map[h] then DN.setNightPixels(S.project, "pallet_outdoor", 665, { i }, map[h]) end end
  -- block 666 by hand: select its glass pixels, light like 665
  local d2 = assert(DN.dayPixels(S, "pallet_outdoor", 666))
  local sel = {}
  for i = 1, 256 do if map[hexAt(d2, i) or ""] then sel[#sel + 1] = i end end
  assert(DN.lightLikeExample(S, "pallet_outdoor", 666, sel, "pallet_outdoor", 665) == #sel)
  local n2 = DN.nightPixels(S.project, "pallet_outdoor", 666)
  for _, i in ipairs(sel) do assert(n2[i] == map[hexAt(d2, i)], "same colours, same gradient") end
  -- both examples teach the same kind of window: one rule
  assert(#DN.rules(S, DN.paintedBlocks(S.project)) == 1)
  local normal = DN.findSimilarTo(S, DN.paintedBlocks(S.project), { "viridian_outdoor" })
  local loose = DN.findSimilarTo(S, DN.paintedBlocks(S.project), { "viridian_outdoor" }, DN.LOOSE)
  assert(#loose >= #normal and #normal > 0)
  -- a different window: brightest colour gets the brightest night colour
  local p = {}
  S.project.gen3DayNight.paint = S.project.gen3DayNight.paint
  local n = DN.lightLikeExample(S, "viridian_outdoor", 40, { 1, 2, 3 }, "pallet_outdoor", 665)
  assert(n and n <= 3)
end)

run("a night look is removed from one block, or from every block", function()
  local S = fresh()
  local function drawn(pair, mid, count)
    local day, out = assert(DN.dayPixels(S, pair, mid)), {}
    for i = 1, 256 do if day[i] and #out < count then out[#out + 1] = i end end
    return out
  end
  local map = { ["63a5de"] = "ffded6", ["73bdf7"] = "fff784", ["9cd6ff"] = "ffd642", ["ceb56b"] = "ff8400" }
  local d665 = assert(DN.dayPixels(S, "pallet_outdoor", 665))
  for i = 1, 256 do
    local c = d665[i]
    local h = c and ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
    if h and map[h] then DN.setNightPixels(S.project, "pallet_outdoor", 665, { i }, map[h]) end
  end
  DN.setNightPixels(S.project, "pallet_outdoor", 666, { 3 }, "ff8400")
  DN.setNightPixels(S.project, "viridian_outdoor", 40, { 4 }, "ffffff")
  -- likeExample only works the colours out; nothing is written
  local out, n = DN.likeExample(S, "pallet_outdoor", 667, drawn("pallet_outdoor", 667, 2), "pallet_outdoor", 665)
  assert(out and n == 2 and not DN.hasNightPixels(S.project, "pallet_outdoor", 667))
  assert(DN.clearNightLook(S.project, "pallet_outdoor", 665))
  assert(not DN.hasNightPixels(S.project, "pallet_outdoor", 665))
  assert(DN.hasNightPixels(S.project, "pallet_outdoor", 666))
  assert(not DN.clearNightLook(S.project, "pallet_outdoor", 665), "nothing left to remove")
  assert(DN.clearAllNightLooks(S.project) == 2)
  assert(#DN.paintedBlocks(S.project) == 0)
  assert(S.project.gen3DayNight == nil, "nothing left behind in the project")
  assert(DN.clearAllNightLooks(S.project) == 0)
end)

run("turning day and night on starts from the default night looks", function()
  local looks, total = DN.defaultLooks(), 0
  for pair, set in pairs(looks) do
    for mid, rec in pairs(set) do
      total = total + 1
      assert(#rec.px == 256 and #rec.cols > 0, pair .. " " .. mid)
      for _, c in ipairs(rec.cols) do assert(Core.hex(c), c) end
    end
  end
  assert(total > 400, "defaults loaded: " .. total)
  local S = fresh()
  assert(DN.setEnabled(S.project, true))
  assert(#DN.paintedBlocks(S.project) == total and DN.missingDefaultLooks(S.project) == 0)
  -- the defaults are copies: editing the project leaves them alone
  local pair, set = next(looks)
  local mid, rec = next(set)
  local before = rec.px
  assert(DN.clearNightLook(S.project, pair, mid))
  assert(rec.px == before and DN.missingDefaultLooks(S.project) == 1)
  -- off and on again with looks of its own: nothing is added
  DN.setEnabled(S.project, false)
  DN.setEnabled(S.project, true)
  assert(DN.missingDefaultLooks(S.project) == 1)
  -- a block drawn differently keeps its own look
  DN.setNightPixels(S.project, pair, mid, { 1 }, "123456")
  local otherPair, otherMid = "pallet_outdoor", next(looks.pallet_outdoor)
  if otherPair == pair and otherMid == mid then otherMid = next(looks.pallet_outdoor, otherMid) end
  DN.clearNightLook(S.project, otherPair, otherMid)
  assert(DN.addDefaultLooks(S.project) == 1)
  assert(DN.nightPixels(S.project, pair, mid)[1] == "123456")
  -- the game gets them
  local data = assert(DN.compile(S.project))
  assert(#data.paint == total)
end)

run("wild encounters by time of day: stored, compiled, removed", function()
  local p = {}
  local area = { rate = 25, slots = { { species = "HOOTHOOT", minLevel = 2, maxLevel = 4 } } }
  assert(DN.setTimeArea(p, "FR_ROUTE_1", "night", "land", area))
  area.slots[1].species = "PIDGEY"
  assert(DN.timeArea(p, "FR_ROUTE_1", "night", "land").slots[1].species == "HOOTHOOT", "stored as a copy")
  assert(DN.timeArea(p, "FR_ROUTE_1", "day", "land") == nil)
  assert(not DN.setTimeArea(p, "FR_ROUTE_1", "evening", "land", area), "only morning, day, night")
  assert(not DN.setTimeArea(p, "FR_ROUTE_1", "night", "grass2", area), "only known kinds")
  DN.setTimeArea(p, "FR_ROUTE_1", "morning", "water", area)
  assert(#DN.timeTables(p) == 2 and DN.timeTables(p)[1].period == "morning")
  assert(DN.settings(p).encounters == nil, "not a setting")
  DN.validate(p)
  assert(DN.compile(p) == nil, "nothing for the game while day and night is off")
  DN.setEnabled(p, true)
  local data = assert(DN.compile(p))
  assert(data.encounters.FR_ROUTE_1.night.land.slots[1].species == "HOOTHOOT")
  assert(data.encounters.FR_ROUTE_1.morning.water.rate == 25)
  assert(DN.setTimeArea(p, "FR_ROUTE_1", "night", "land", nil))
  assert(DN.setTimeArea(p, "FR_ROUTE_1", "morning", "water", nil))
  assert(p.gen3DayNight.encounters == nil, "tidied away")
  -- lists come as a set: morning, day and night, and the all-day list is off
  local allDay = { rate = 21, slots = { { species = "PIDGEY", minLevel = 2, maxLevel = 5 } } }
  assert(not DN.hasTimeLists(p, "FR_ROUTE_2", "land"))
  assert(DN.startTimeLists(p, "FR_ROUTE_2", "land", allDay) == 3)
  assert(DN.hasTimeLists(p, "FR_ROUTE_2", "land") and not DN.hasTimeLists(p, "FR_ROUTE_2", "water"))
  DN.timeArea(p, "FR_ROUTE_2", "night", "land").slots[1].species = "HOOTHOOT"
  assert(DN.startTimeLists(p, "FR_ROUTE_2", "land", allDay) == 0, "keeps lists it has")
  assert(DN.timeArea(p, "FR_ROUTE_2", "night", "land").slots[1].species == "HOOTHOOT")
  assert(DN.timeArea(p, "FR_ROUTE_2", "morning", "land").slots[1].species == "PIDGEY")
  assert(DN.clearTimeLists(p, "FR_ROUTE_2", "land") and not DN.hasTimeLists(p, "FR_ROUTE_2", "land"))
  p.gen3DayNight.encounters = { X = { night = { land = { slots = { { species = "A" } } } } } }
  assert(not pcall(DN.validate, p), "slots need levels")
end)

run("Crystal's encounters: slots, targets, compile, your own lists first", function()
  local C = require("Gen3CrystalEncounters")
  -- the twelve FireRed slots keep Crystal's chances
  local fr = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
  local sum = {}
  for i, k in ipairs(DN.CRYSTAL_SLOTS) do sum[k] = (sum[k] or 0) + fr[i] end
  local crystal = { 30, 30, 20, 10, 5, 4, 1 }
  for k = 1, 7 do assert(sum[k] == crystal[k], "slot " .. k) end
  local area = DN.crystalArea(C.maps.ROUTE_2.night, 10)
  assert(#area.slots == 12 and area.rate == 10 and area.slots[1].minLevel == area.slots[1].maxLevel)
  -- targets: FireRed's Kanto tables, and maps added in the editor
  local p = { maps = { FR_JOHTO_ROUTE_29 = {}, FR_TOHJO_FALLS = {}, FR_MY_TOWN = {} } }
  local ids = {}
  for _, e in ipairs(DN.crystalTargets(p)) do ids[e.id] = e end
  assert(ids.FR_ROUTE_1 and ids.FR_ROUTE_1.crystal == "ROUTE_1")
  assert(ids.FR_MT_MOON_B2F and ids.FR_ROUTE_21_SOUTH)
  assert(not ids.FR_JOHTO_ROUTE_29 and not ids.FR_TOHJO_FALLS and not ids.FR_MY_TOWN, "maps added in a mod aren't touched")
  -- Encounter tables: on unless turned off; off, nothing time-based is compiled
  DN.setEnabled(p, true)
  assert(DN.encountersEnabled(p) and DN.compile(p).crystal ~= nil, "on with the clock")
  local data = DN.compile(p)
  assert(data.crystal.FR_ROUTE_1.night.land.rate == nil, "FireRed tables keep their rate")
  assert(data.crystal.FR_JOHTO_ROUTE_29 == nil and data.crystal.FR_TOHJO_FALLS == nil)
  assert(data.crystal.FR_ROUTE_1.morning.land.slots[1].species == C.maps.ROUTE_1.morning[1][2])
  DN.startTimeLists(p, "FR_ROUTE_2", "land", { rate = 20, slots = { { species = "PIDGEY", minLevel = 2, maxLevel = 2 } } })
  assert(next(DN.compile(p).encounters))
  assert(DN.setEncounters(p, false) and DN.settings(p).encountersOff == nil)
  data = DN.compile(p)
  assert(data.crystal == nil and next(data.encounters) == nil and data.allDay == nil, "off: all-day lists everywhere")
  assert(DN.hasTimeLists(p, "FR_ROUTE_2", "land"), "your lists are kept while off")
  assert(DN.setEncounters(p, true) and next(DN.compile(p).encounters))
  -- one table kept on its all-day list, the rest still change
  assert(DN.setAllDay(p, "FR_ROUTE_2", "land", true) and DN.isAllDay(p, "FR_ROUTE_2", "land"))
  data = DN.compile(p)
  assert(data.allDay.FR_ROUTE_2.land and data.crystal.FR_ROUTE_1 and data.encounters.FR_ROUTE_2)
  assert(#DN.allDayList(p) == 1)
  assert(DN.setAllDay(p, "FR_ROUTE_2", "land", false) and p.gen3DayNight.allDay == nil)
end)

run("Encounter tables follow the clock; Crystal's lists filled in as your own, taken out when off", function()
  local p = {}
  local S = { project = p, data = {} }
  assert(not DN.encountersEnabled(p), "off while the clock is off")
  assert(not DN.setEncounters(p, true), "the clock comes first")
  assert(DN.setEnabled(p, true) and DN.encountersEnabled(p), "on with the clock")
  assert(DN.syncCrystalPopulation(S))
  local route1 = DN.timeArea(p, "FR_ROUTE_1", "night", "land")
  assert(route1 and #route1.slots == 12 and route1.rate == 21, "filled in as a real list")
  assert(DN.isCrystalFilled(p, "FR_ROUTE_1") and not DN.syncCrystalPopulation(S), "in sync")
  assert(DN.compile(p).crystal.FR_ROUTE_1 == nil, "filled-in tables use their own lists")
  -- edit one, clear one, make one of your own
  DN.timeArea(p, "FR_ROUTE_2", "day", "land").slots[1].species = "PIKACHU"
  assert(DN.clearTimeLists(p, "FR_ROUTE_3", "land"))
  assert(not DN.syncCrystalPopulation(S) and not DN.hasTimeLists(p, "FR_ROUTE_3", "land"), "cleared stays cleared")
  assert(DN.compile(p).crystal.FR_ROUTE_3 == nil, "cleared: all-day list in game")
  DN.startTimeLists(p, "FR_ROUTE_1", "water", { rate = 5, slots = { { species = "TENTACOOL", minLevel = 5, maxLevel = 5 } } })
  -- off: Crystal's come back out; edited and your own stay
  assert(DN.setEncounters(p, false) and DN.syncCrystalPopulation(S))
  assert(not DN.hasTimeLists(p, "FR_ROUTE_1", "land"), "Crystal's list gone")
  assert(DN.timeArea(p, "FR_ROUTE_2", "day", "land").slots[1].species == "PIKACHU", "edited table kept")
  assert(DN.hasTimeLists(p, "FR_ROUTE_1", "water"), "your own list kept")
  assert(p.gen3DayNight.crystalFilled == nil)
  -- clock off turns them off; clock on brings them back
  assert(DN.setEncounters(p, true) and DN.syncCrystalPopulation(S) and DN.hasTimeLists(p, "FR_ROUTE_3", "land"))
  assert(DN.setEnabled(p, false) and not DN.encountersEnabled(p) and DN.syncCrystalPopulation(S))
  assert(not DN.hasTimeLists(p, "FR_ROUTE_1", "land"))
  assert(DN.setEncounters(p, false) == false, "already off with the clock")
  assert(DN.setEnabled(p, true) and DN.encountersEnabled(p) and DN.syncCrystalPopulation(S))
  assert(DN.hasTimeLists(p, "FR_ROUTE_1", "land"))
  DN.validate(p)
end)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
