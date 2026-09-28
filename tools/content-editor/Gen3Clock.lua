-- The real time clock for scripts (FireRed / LeafGreen): a game action
-- (special) that reads the clock, so events can tell the time and act on the
-- day and the time.
--
--   special 0xE100 "Read the clock" puts:
--     STR_VAR_1 = the day ("Tuesday"), STR_VAR_2 = the date ("29 September"),
--     STR_VAR_3 = the time ("10:42 PM"), for dialogue ({STR_VAR_1} ...);
--     0x8004 = the day (0 Sunday ... 6 Saturday), 0x8005 = the hour (0-23),
--     0x8006 = the minute, 0x8007 = the part of the day (0 morning, 1 day,
--     2 night), for "if" checks in the script.
--
-- It's the device's clock, like Crystal's. With the Real Time Clock on, its
-- hours for morning / day / night are used, and a pinned test hour too
-- (GFX > Day & night). The engine isn't changed: the action is added to the
-- game's list of specials when the mod loads (main.lua).

local M = {}

M.SPECIAL = 0xE100
M.VARS = { day = 0x8004, hour = 0x8005, minute = 0x8006, part = 0x8007 }
M.DAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
M.MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September",
  "October", "November", "December" }
M.PARTS = { [0] = "morning", [1] = "day", [2] = "night" }

--- What the game needs: the hours for the parts of the day, and the test
-- hour while the Real Time Clock is on.
function M.compile(project)
  local DN = require("Gen3DayNight")
  local s = DN.settings(project)
  return { morning = tonumber(s.morning), day = tonumber(s.day), night = tonumber(s.night),
    testHour = DN.enabled(project) and tonumber(s.testHour) or nil }
end

--- The clock for time `t` (os.date("*t")) and settings `cfg`: the strings
-- and the numbers the action gives the script. Shared with the game side.
M.READ = [=[
function(t, cfg, DAYS, MONTHS)
  local hour, minute = t.hour, t.min
  if cfg.testHour then hour, minute = cfg.testHour, 0 end
  local part = 1
  if hour >= cfg.night or hour < cfg.morning then part = 2 elseif hour < cfg.day then part = 0 end
  local h12 = hour % 12
  if h12 == 0 then h12 = 12 end
  return {
    strings = { DAYS[t.wday], tostring(t.day) .. " " .. MONTHS[t.month],
      ("%d:%02d %s"):format(h12, minute, hour < 12 and "AM" or "PM") },
    day = t.wday - 1, hour = hour, minute = minute, part = part,
  }
end]=]

M.read = assert(load("return " .. M.READ))()

function M.emit(project, encode, out)
  out[#out + 1] = "  local clockCfg=" .. encode(M.compile(project)) .. "\n"
    .. "  local clockRead=" .. M.READ .. "\n"
    .. "  local clockDays=" .. encode(M.DAYS) .. "\n"
    .. "  local clockMonths=" .. encode(M.MONTHS) .. "\n"
    .. ([=[
  -- Real time clock: special %d "Read the clock" (Gen3Clock.lua).
  mod.events:on("game.ready",function()
    local okN,Natives=pcall(require,"src.core.game3.scripting.natives")
    if not okN or type(Natives)~="table" or type(Natives.ALLOW)~="table" then return end
    Natives.ALLOW["special:%d"]=function(ctx,adapters)
      local c=clockRead(os.date("*t"),clockCfg,clockDays,clockMonths)
      for i,s in ipairs(c.strings) do
        if ctx and ctx.stringVars then ctx.stringVars[i]=s end
        if adapters and adapters.setStringVar then pcall(adapters.setStringVar,i,s) end
      end
      -- 0x8004-0x8007 are the script's own (special) variables
      local okV,Flags=pcall(require,"src.core.game3.scripting.flags")
      if okV and Flags.setVar then
        Flags.setVar(nil,ctx,%d,c.day)
        Flags.setVar(nil,ctx,%d,c.hour)
        Flags.setVar(nil,ctx,%d,c.minute)
        Flags.setVar(nil,ctx,%d,c.part)
      end
      return false
    end
  end)
]=]):format(M.SPECIAL, M.SPECIAL, M.VARS.day, M.VARS.hour, M.VARS.minute, M.VARS.part)
end

return M
