package.path = "runtime/gen1recomp/?.lua;" .. package.path

package.preload["src.mods.Runtime"] = function()
  return {
    wants = function() return false end,
    emit = function() end,
  }
end

local StateStack = require("src.core.StateStack")
local stack = setmetatable({}, { __index = StateStack })
stack:init()

local exited = {}
stack:push({ exit = function() exited[#exited + 1] = "first" end })
stack:push({ exit = function() exited[#exited + 1] = "second" end })
stack:clear()

assert(#stack.states == 0, "clear must remove every state")
assert(exited[1] == "second" and exited[2] == "first",
  "clear must preserve pop order and exit lifecycle")

-- Clearing an empty stack is intentionally safe and idempotent.
stack:clear()
assert(#stack.states == 0)

print("ok state stack clear")
