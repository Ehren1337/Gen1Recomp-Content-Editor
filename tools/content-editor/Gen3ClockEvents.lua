-- Clock actions for events (FireRed / LeafGreen): "Read the clock" and
-- "Check the time or day", as used by EVENTS > What happens > Add action.
--
-- Read the clock is special 0xE100 (Gen3Clock.lua). A check is two native
-- steps, compare_var_to_value on one of the clock's numbers (0x8004 day,
-- 0x8005 hour, 0x8007 part of the day) and goto_if to a branch event of its
-- own. The branch shows its dialogue and ends the event; when the check
-- doesn't match, the event carries on below it. Several checks in a row
-- work like "if ... else if ... otherwise".

local M = {}
local C = require("Gen3Clock")
local copy = require("src.mods.Merge").deepCopy

local LT, EQ, GE, NE = 0, 1, 4, 5
local RELATIONS = { [0] = "is less than", [1] = "is", [2] = "is more than", [3] = "is at most",
  [4] = "is at least", [5] = "isn't" }

function M.hour12(h)
  h = tonumber(h) or 0
  local n = h % 12
  if n == 0 then n = 12 end
  return n .. (h % 24 < 12 and " AM" or " PM")
end

-- The checks offered in the picker, in order.
M.CHECKS, M.LABELS = {}, {}
local byId = {}
local function check(id, label, var, cond, value, text)
  local c = { id = id, label = label, var = var, cond = cond, value = value, text = text }
  M.CHECKS[#M.CHECKS + 1] = c
  M.LABELS[id] = label
  byId[id] = c
end
check("morning", "It's morning", C.VARS.part, EQ, 0, "Good morning!")
check("day", "It's day", C.VARS.part, EQ, 1, "Good afternoon!")
check("night", "It's night", C.VARS.part, EQ, 2, "Good evening!")
for n, name in ipairs(C.DAYS) do
  check("day:" .. (n - 1), "It's " .. name, C.VARS.day, EQ, n - 1, "It's " .. name .. " today!")
end
for h = 1, 23 do
  check("before:" .. h, "It's before " .. M.hour12(h), C.VARS.hour, LT, h, "It's still early!")
end
for h = 1, 23 do
  check("from:" .. h, "It's " .. M.hour12(h) .. " or later", C.VARS.hour, GE, h, "It's getting late!")
end
M.IDS = {}
for i, c in ipairs(M.CHECKS) do M.IDS[i] = c.id end

function M.get(id) return byId[id] end

local function field(step, name, n) local v = step[name]; if v == nil then v = step[n] end; return v end

--- The check id for a compare + goto_if pair, if it's one of the picker's.
function M.checkId(var, cond, value)
  for _, c in ipairs(M.CHECKS) do
    if c.var == var and c.cond == cond and c.value == value then return c.id end
  end
end

--- Plain words for a check on the clock's numbers, or nil for other saved values.
function M.describe(var, cond, value)
  var, cond, value = tonumber(var), tonumber(cond), tonumber(value)
  if not (var and cond and value) then return end
  if var == C.VARS.part then
    local part = C.PARTS[value]
    if part and cond == EQ then return "it's " .. part end
    if part and cond == NE then return "it isn't " .. part end
    return "the part of the day (0 morning, 1 day, 2 night) " .. tostring(RELATIONS[cond]) .. " " .. value
  elseif var == C.VARS.hour then
    if cond == LT then return "it's before " .. M.hour12(value) end
    if cond == GE then return "it's " .. M.hour12(value) .. " or later" end
    if cond == EQ then return "it's between " .. M.hour12(value) .. " and " .. M.hour12(value + 1) end
    return "the hour (0-23) " .. tostring(RELATIONS[cond]) .. " " .. value
  elseif var == C.VARS.day then
    local name = C.DAYS[value + 1]
    if name and cond == EQ then return "it's " .. name end
    if name and cond == NE then return "it isn't " .. name end
    return "the day (0 Sunday - 6 Saturday) " .. tostring(RELATIONS[cond]) .. " " .. value
  elseif var == C.VARS.minute then
    return "the minute " .. tostring(RELATIONS[cond]) .. " " .. value
  end
end

--- Whether steps[i] is Read the clock.
function M.isRead(step)
  return type(step) == "table" and step.op == "special" and field(step, "id", 1) == C.SPECIAL
end

--- Where Read the clock goes: after the event's opening lock / face the player.
function M.readIndex(steps)
  local i = 1
  while steps[i] and (steps[i].op == "lock" or steps[i].op == "lockall" or steps[i].op == "faceplayer") do i = i + 1 end
  return i
end

--- Where a new action goes: at the end, but before a closing release and end.
function M.insertIndex(steps)
  local at = #steps + 1
  if steps[at - 1] and (steps[at - 1].op == "end" or steps[at - 1].op == "return") then at = at - 1 end
  if steps[at - 1] and (steps[at - 1].op == "release" or steps[at - 1].op == "releaseall") then at = at - 1 end
  return math.max(at, M.readIndex(steps))
end

--- Add Read the clock near the top of `steps` unless it's already there.
-- Returns true when it was added.
function M.addRead(steps)
  for _, step in ipairs(steps) do if M.isRead(step) then return false end end
  table.insert(steps, M.readIndex(steps), { op = "special", id = C.SPECIAL })
  return true
end

local function scripts(S)
  local p = S.project
  p.gen3 = p.gen3 or {}
  p.gen3.map_scripts = p.gen3.map_scripts or {}
  p.gen3Modes = p.gen3Modes or {}
  p.gen3Modes.map_scripts = p.gen3Modes.map_scripts or {}
  p.text = p.text or {}
  return p.gen3.map_scripts
end

local function catalog(S)
  local ok, c = pcall(function() return require("Gen3").catalog(S.data, "map_scripts") end)
  return ok and c or {}
end

--- An event's steps to edit: the mod's own copy (made from the game's if needed).
function M.steps(S, id)
  local own = scripts(S)
  return copy(own[id] or catalog(S)[id] or { { op = "end" } })
end

function M.newBranchKey(S)
  local own, cat = scripts(S), catalog(S)
  local base = "EditorBranch_" .. tostring(S.project.id):gsub("[^%w_]", "_") .. "_"
  local n = 1
  while own[base .. n] or cat[base .. n] do n = n + 1 end
  return base .. n
end

--- Add Read the clock to event `id`. Returns true if it was added.
function M.addReadTo(S, id)
  local steps = M.steps(S, id)
  local added = M.addRead(steps)
  if added then scripts(S)[id] = steps end
  return added
end

--- Add check `checkId` to event `id`: Read the clock (if missing), then the
-- check, going to a new branch event with `text` (or a default line).
-- Returns the branch event's key.
function M.addCheck(S, id, checkId, text)
  local c = assert(byId[checkId], "Unknown clock check")
  local own = scripts(S)
  local steps = M.steps(S, id)
  M.addRead(steps)
  local key = M.newBranchKey(S)
  local branch = { { op = "message" }, { op = "waitmessage" }, { op = "waitbuttonpress" }, { op = "closemessage" } }
  require("Gen3EventActions").setText(S, branch[1], text or c.text)
  local release
  for _, step in ipairs(steps) do
    if step.op == "lockall" then release = "releaseall" elseif step.op == "lock" and not release then release = "release" end
  end
  if release then branch[#branch + 1] = { op = release } end
  branch[#branch + 1] = { op = "end" }
  own[key] = branch
  S.project.gen3Modes.map_scripts[key] = "register"
  local at = M.insertIndex(steps)
  table.insert(steps, at, { op = "goto_if", cond = c.cond, target = key })
  table.insert(steps, at, { op = "compare_var_to_value", var = c.var, value = c.value })
  own[id] = steps
  return key
end

--- Change the check at steps[index] (compare) / steps[index + 1] (goto_if) of event `id`.
function M.change(S, id, index, checkId)
  local c = assert(byId[checkId], "Unknown clock check")
  local steps = M.steps(S, id)
  local a, b = steps[index], steps[index + 1]
  if not (a and b and a.op == "compare_var_to_value" and b.op == "goto_if") then return false end
  a.var, a.value, a[1], a[2] = c.var, c.value, nil, nil
  b.cond = c.cond
  if b[1] ~= nil then b.target = b.target or b[2]; b[1], b[2] = nil, nil end
  scripts(S)[id] = steps
  return true
end

local function referenced(S, key)
  local found = false
  local function scan(v)
    if found or type(v) ~= "table" then return end
    for k, x in pairs(v) do
      if x == key and (k == "target" or k == "scriptKey" or k == "touchScriptKey" or type(k) == "number") then found = true; return end
      scan(x)
    end
  end
  scan(S.project.gen3.map_scripts)
  scan(S.project.maps)
  return found
end

--- Remove the check at steps[index] of event `id`; its branch event goes too
-- when nothing else uses it. Returns true when removed.
function M.remove(S, id, index)
  local steps = M.steps(S, id)
  local a, b = steps[index], steps[index + 1]
  if not (a and b and a.op == "compare_var_to_value" and b.op == "goto_if") then return false end
  local target = field(b, "target", 2)
  table.remove(steps, index + 1)
  table.remove(steps, index)
  local own = scripts(S)
  own[id] = steps
  if type(target) == "string" and target:match("^EditorBranch_") and own[target] and not referenced(S, target) then
    local branch = own[target]
    own[target] = nil
    S.project.gen3Modes.map_scripts[target] = nil
    for _, step in ipairs(branch) do
      local ptr = step.op == "message" and field(step, "ptr", 1)
      if type(ptr) == "string" and ptr:match("^EditorText_") and not referenced(S, ptr) then S.project.text[ptr] = nil end
    end
  end
  return true
end

M.HINT = "After Read the clock, dialogue can say {STR_VAR_1} (the day, e.g. Tuesday), {STR_VAR_2} (the date, e.g. 29 September) and {STR_VAR_3} (the time, e.g. 10:42 PM)."
M.CHECK_HINT = "When the check matches, the lines under it happen and the event ends there. When it doesn't, the event carries on below. Checks run top to bottom and the first one that matches wins."

return M
