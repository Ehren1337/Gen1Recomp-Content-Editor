-- The editor's own settings (not a mod's): kept in the editor's save folder
-- (editor-settings.lua), so mods, updates and the editor folder never touch
-- them. Settings > Theme is the first.
--   theme = "stock" | a Theme.PRESETS id | "custom", themeHue = 0-359 (custom)

local M = {}

M.FILE = "editor-settings.lua"
M.DEFAULTS = { theme = "stock", themeHue = 294 }

local values

local function fs() return love and love.filesystem end

local function serialize(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = { "return {" }
  for _, k in ipairs(keys) do
    local v = t[k]
    if type(k) == "string" and k:match("^[%a_][%w_]*$")
        and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then
      out[#out + 1] = ("  %s = %s,"):format(k, type(v) == "string" and ("%q"):format(v) or tostring(v))
    end
  end
  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end
M.serialize = serialize

--- Read a settings file's text (data only: no code runs).
function M.parse(text)
  if type(text) ~= "string" then return {} end
  local chunk = load(text, "=editor-settings", "t", {})
  if not chunk then return {} end
  local ok, t = pcall(chunk)
  return ok and type(t) == "table" and t or {}
end

function M.load()
  values = {}
  local f = fs()
  local text = f and f.getInfo and f.getInfo(M.FILE) and f.read(M.FILE)
  for k, v in pairs(M.parse(text)) do values[k] = v end
  return values
end

function M.get(key)
  if not values then M.load() end
  local v = values[key]
  if v == nil then return M.DEFAULTS[key] end
  return v
end

function M.set(key, value)
  if not values then M.load() end
  values[key] = value
  local f = fs()
  if f and f.write then pcall(f.write, M.FILE, serialize(values)) end
end

--- Put the saved theme on (call once when the editor starts).
function M.applyTheme()
  local Theme = require("Theme")
  return Theme.apply(M.get("theme"), M.get("themeHue"))
end

return M
