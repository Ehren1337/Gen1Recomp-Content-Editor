-- Day and night (Gen3DayNight): the time rules, shared by the editor and the
-- game. Pure Lua; Gen3DayNightRuntime inlines this file into a mod, the same
-- way Gen3BlocksRuntime inlines Gen3TileSource.
--
-- Three parts of the day, as in Crystal: morning, day and night, each
-- starting at an hour. Day looks as the game draws it; morning and night
-- multiply every colour by a tint. When a part of the day begins, its tint
-- fades in from the previous one over `blend` minutes.
local Core = {}

Core.PERIODS = { "morning", "day", "night" }

Core.DEFAULTS = {
  morning = 4, day = 10, night = 18, -- Crystal's hours
  blend = 30,                        -- minutes to fade into the next part
  morningTint = "ffe8d0",            -- warm, slightly soft
  nightTint = "7080c8",              -- dark and blue
}

-- Map types that change with the time (Town, City, Route, Ocean route).
-- Indoor maps, caves and the rest look the same all day.
Core.OUTDOOR = { [1] = true, [2] = true, [3] = true, [6] = true }

--- "rrggbb" to three 0..1 numbers, or nil.
function Core.hex(text)
  local r, g, b = tostring(text or ""):lower():match("^#?(%x%x)(%x%x)(%x%x)$")
  if not r then return nil end
  return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function tintOf(s, period)
  if period == "day" then return 1, 1, 1 end
  local r, g, b = Core.hex(s[period .. "Tint"])
  if not r then r, g, b = Core.hex(Core.DEFAULTS[period .. "Tint"]) end
  return r, g, b
end

local function minutesOf(s, period) return (tonumber(s[period]) or Core.DEFAULTS[period]) * 60 end

--- Which part of the day it is at hour:minute.
function Core.period(s, hour, minute)
  local now = (hour % 24) * 60 + (minute or 0)
  local m, d, n = minutesOf(s, "morning"), minutesOf(s, "day"), minutesOf(s, "night")
  if now >= m and now < d then return "morning", now - m end
  if now >= d and now < n then return "day", now - d end
  return "night", (now - n) % 1440
end

--- The colour multiplier at hour:minute (three numbers, 1 = unchanged).
function Core.tintAt(s, hour, minute)
  local period, since = Core.period(s, hour, minute)
  local r, g, b = tintOf(s, period)
  local blend = math.max(0, tonumber(s.blend) or Core.DEFAULTS.blend)
  if blend > 0 and since < blend then
    local previous = period == "morning" and "night" or period == "day" and "morning" or "day"
    local pr, pg, pb = tintOf(s, previous)
    local t = since / blend
    r, g, b = pr + (r - pr) * t, pg + (g - pg) * t, pb + (b - pb) * t
  end
  return r, g, b, period
end

--- One colour (0..255 each) as the game shows it under a tint: the GBA's
-- 5-bit colour, multiplied and rounded back to 5 bits.
function Core.grade(r, g, b, tr, tg, tb)
  local function one(v, t)
    local c = math.floor(v * 31 / 255 + 0.5)
    c = math.floor(c * t + 0.5)
    return math.floor(c * 255 / 31 + 0.5)
  end
  return one(r, tr), one(g, tg), one(b, tb)
end

--- A BGR555 colour as three 5-bit numbers (how lit colours are compared).
function Core.bgr5(v)
  v = (tonumber(v) or 0) % 32768
  return v % 32, math.floor(v / 32) % 32, math.floor(v / 1024) % 32
end

Core.MAX_LIT = 32

-- The same rule on the GPU, for whole screens. A pixel whose 5-bit colour
-- is a lit colour keeps its day colour.
Core.SHADER = [[
extern vec3 tint;
extern vec3 lit[32];
extern float litCount;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 p = Texel(tex, tc);
  vec3 q = floor(p.rgb * 31.0 + 0.5);
  for (int i = 0; i < 32; i++) {
    if (float(i) >= litCount) break;
    vec3 d = abs(q - lit[i]);
    if (d.r + d.g + d.b < 0.5) return p * color;
  }
  return vec4(floor(q * tint + 0.5) / 31.0, p.a) * color;
}
]]

return Core
