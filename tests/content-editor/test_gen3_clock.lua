-- Real time clock for scripts (Gen3Clock.lua): what "Read the clock" gives.
-- Plain LuaJIT, no LOVE. Run from the repository root:
--   luajit tests/content-editor/test_gen3_clock.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local C = require("Gen3Clock")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local cfg = { morning = 4, day = 10, night = 18 }
local function at(wday, day, month, hour, min, extra)
  local c = {}
  for k, v in pairs(cfg) do c[k] = v end
  for k, v in pairs(extra or {}) do c[k] = v end
  return C.read({ wday = wday, day = day, month = month, hour = hour, min = min }, c, C.DAYS, C.MONTHS)
end

run("day, date and time as words", function()
  local c = at(3, 29, 9, 22, 7)
  assert(c.strings[1] == "Tuesday" and c.strings[2] == "29 September" and c.strings[3] == "10:07 PM")
  assert(c.day == 2 and c.hour == 22 and c.minute == 7 and c.part == 2)
end)

run("12-hour clock and the parts of the day", function()
  assert(at(1, 1, 1, 0, 5).strings[3] == "12:05 AM" and at(1, 1, 1, 0, 5).part == 2)
  assert(at(1, 1, 1, 4, 0).part == 0, "morning from 4")
  assert(at(1, 1, 1, 9, 59).part == 0 and at(1, 1, 1, 10, 0).part == 1, "day from 10")
  assert(at(1, 1, 1, 12, 0).strings[3] == "12:00 PM")
  assert(at(1, 1, 1, 17, 59).part == 1 and at(1, 1, 1, 18, 0).part == 2, "night from 18")
end)

run("a pinned test hour is used", function()
  local c = at(7, 31, 12, 9, 30, { testHour = 21 })
  assert(c.hour == 21 and c.minute == 0 and c.strings[3] == "9:00 PM" and c.part == 2 and c.strings[1] == "Saturday")
end)

run("it's in the editor's list of game actions", function()
  package.path = "tools/content-editor/?.lua;" .. package.path
  local L = require("Gen3ActionLanguage")
  assert(L.specials[C.SPECIAL]:find("clock") and L.specialHelp[C.SPECIAL]:find("STR_VAR_3"))
end)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
