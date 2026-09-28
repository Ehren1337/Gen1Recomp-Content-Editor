-- Clock actions for events (Gen3ClockEvents.lua): Read the clock and the
-- time / day checks the event window's Add action... menu adds.
-- Plain LuaJIT, no LOVE. Run from the repository root:
--   luajit tests/content-editor/test_gen3_clock_events.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = deepCopy(x) end
  return o
end
package.loaded["src.mods.Merge"] = { deepCopy = deepCopy }
package.loaded["Gen3"] = { catalog = function() return { g3_vanilla = { { op = "end" } } } end }
package.loaded["Gen3EventActions"] = { setText = function(S, step, text)
  local n = 1
  while S.project.text["EditorText_t_" .. n] do n = n + 1 end
  S.project.text["EditorText_t_" .. n] = text
  step.ptr = "EditorText_t_" .. n
end }
local CE = require("Gen3ClockEvents")
local C = require("Gen3Clock")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

local TALK = { { op = "lock" }, { op = "faceplayer" }, { op = "message", ptr = "Main" }, { op = "waitmessage" },
  { op = "waitbuttonpress" }, { op = "closemessage" }, { op = "release" }, { op = "end" } }
local function session()
  return { project = { id = "t", text = {}, gen3 = { map_scripts = { Talk = deepCopy(TALK) } },
    gen3Modes = { map_scripts = { Talk = "register" } }, maps = { M = { objects = { { scriptKey = "Talk" } } } } }, data = {} }
end
local function ops(steps) local o = {}; for i, s in ipairs(steps) do o[i] = s.op end; return table.concat(o, " ") end

run("the picker's checks", function()
  assert(CE.LABELS.night == "It's night" and CE.LABELS["day:2"] == "It's Tuesday")
  assert(CE.LABELS["before:6"] == "It's before 6 AM" and CE.LABELS["from:18"] == "It's 6 PM or later")
  assert(CE.LABELS["before:12"] == "It's before 12 PM" and CE.hour12(0) == "12 AM")
  assert(#CE.IDS == 3 + 7 + 23 + 23)
  local c = CE.get("before:6")
  assert(c.var == C.VARS.hour and c.cond == 0 and c.value == 6)
  assert(CE.checkId(C.VARS.part, 1, 2) == "night" and CE.checkId(0x4000, 1, 2) == nil)
end)

run("plain words for checks", function()
  assert(CE.describe(C.VARS.part, 1, 0) == "it's morning")
  assert(CE.describe(C.VARS.part, 5, 2) == "it isn't night")
  assert(CE.describe(C.VARS.hour, 0, 6) == "it's before 6 AM")
  assert(CE.describe(C.VARS.hour, 4, 18) == "it's 6 PM or later")
  assert(CE.describe(C.VARS.day, 1, 2) == "it's Tuesday")
  assert(CE.describe(0x4050, 1, 2) == nil, "other saved values keep the old wording")
end)

run("Read the clock goes after lock / face the player, once", function()
  local S = session()
  assert(CE.addReadTo(S, "Talk"))
  assert(ops(S.project.gen3.map_scripts.Talk) == "lock faceplayer special message waitmessage waitbuttonpress closemessage release end")
  assert(S.project.gen3.map_scripts.Talk[3].id == C.SPECIAL)
  assert(not CE.addReadTo(S, "Talk"), "not added twice")
end)

run("checks build if / else if / otherwise before the release", function()
  local S = session()
  local night = CE.addCheck(S, "Talk", "night", "Sleepy!")
  local day = CE.addCheck(S, "Talk", "day")
  local early = CE.addCheck(S, "Talk", "before:6")
  local steps = S.project.gen3.map_scripts.Talk
  assert(ops(steps) == "lock faceplayer special message waitmessage waitbuttonpress closemessage "
    .. "compare_var_to_value goto_if compare_var_to_value goto_if compare_var_to_value goto_if release end", ops(steps))
  assert(steps[8].var == C.VARS.part and steps[8].value == 2 and steps[9].cond == 1 and steps[9].target == night)
  assert(steps[12].var == C.VARS.hour and steps[12].value == 6 and steps[13].cond == 0 and steps[13].target == early)
  local branch = S.project.gen3.map_scripts[night]
  assert(ops(branch) == "message waitmessage waitbuttonpress closemessage release end", ops(branch))
  assert(S.project.text[branch[1].ptr] == "Sleepy!")
  assert(S.project.text[S.project.gen3.map_scripts[day][1].ptr] == "Good afternoon!")
  assert(S.project.gen3Modes.map_scripts[night] == "register")
  assert(night:match("^EditorBranch_t_%d+$") and night ~= day and day ~= early)
  -- a new action (the morning line) goes after the checks, before the release
  assert(CE.insertIndex(steps) == 14)
end)

run("a check on the game's own event copies it into the mod", function()
  local S = session()
  CE.addCheck(S, "g3_vanilla", "day:2")
  assert(ops(S.project.gen3.map_scripts.g3_vanilla) == "special compare_var_to_value goto_if end")
  local branch = S.project.gen3.map_scripts[S.project.gen3.map_scripts.g3_vanilla[3].target]
  assert(ops(branch) == "message waitmessage waitbuttonpress closemessage end", "no release without a lock")
end)

run("change and remove a check", function()
  local S = session()
  local night = CE.addCheck(S, "Talk", "night")
  local steps = S.project.gen3.map_scripts.Talk
  local at = 8
  assert(CE.change(S, "Talk", at, "from:20"))
  steps = S.project.gen3.map_scripts.Talk
  assert(steps[at].var == C.VARS.hour and steps[at].value == 20 and steps[at + 1].cond == 4 and steps[at + 1].target == night)
  local ptr = S.project.gen3.map_scripts[night][1].ptr
  assert(not CE.change(S, "Talk", 3, "night"), "only on a check")
  assert(CE.remove(S, "Talk", at))
  assert(ops(S.project.gen3.map_scripts.Talk) == "lock faceplayer special message waitmessage waitbuttonpress closemessage release end")
  assert(S.project.gen3.map_scripts[night] == nil and S.project.gen3Modes.map_scripts[night] == nil)
  assert(S.project.text[ptr] == nil, "its line goes too")
end)

run("a branch something else uses is kept", function()
  local S = session()
  local night = CE.addCheck(S, "Talk", "night")
  S.project.maps.M.objects[2] = { scriptKey = night }
  assert(CE.remove(S, "Talk", 8))
  assert(S.project.gen3.map_scripts[night] ~= nil)
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
