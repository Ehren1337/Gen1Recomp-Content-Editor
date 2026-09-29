-- Fails when the pinned runtime drops a module or field the editor depends on.
local RUNTIME = "runtime/gen1recomp/"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function moduleSource(name)
  local base = RUNTIME .. name:gsub("%.", "/")
  return read(base .. ".lua") or read(base .. "/init.lua")
end

local failures = {}

-- Referenced but absent on purpose; remove an entry once the editor stops naming it.
local KNOWN_GAPS = {
  -- Gen 2's town map lives inside the Pokegear, so the fitted map "paper" wrap has no target yet.
  ["src.ui.gen2.TownMap"] = true,
}

-- Every runtime module named in editor code must exist.
local files = assert(io.popen('git ls-files "tools/content-editor/*.lua"'))
local checked = {}
for file in files:lines() do
  for name in (read(file) or ""):gmatch("[\"'](src%.[%w_%.]+)[\"']") do
    if name:sub(-1) ~= "." and not checked[name] and not KNOWN_GAPS[name] then
      checked[name] = true
      if not moduleSource(name) then
        failures[#failures + 1] = file .. ": missing runtime module " .. name
      end
    end
  end
end
files:close()

-- Fields and functions that Gen3Native's generated mod code reads, resets or wraps.
-- Keep in sync with Gen3Native.M.source.
local DEFINES = {
  ["src.mods.Runtime"] = { "install", "reset", "call" },
  ["src.import.CacheFs"] = { "read" },
  ["src.core.game3.pokemon"] = { "_icons" },
  ["src.core.game3.dataset"] = { "cache" },
  ["src.core.game3.battle.anim"] = { "_packLoaded", "_pack" },
  ["src.core.game3.trainer_pic"] = { "_front", "_back" },
  ["src.core.game3.items_data"] = { "install" },
  ["src.ui.game3.help_system"] = { "install" },
  ["src.ui.game3.region_map"] = { "_images" },
  ["src.ui.game3.teachy_tv"] = { "reloadAssets" },
  ["src.ui.game3.chrome"] = { "invalidate" },
  ["src.ui.game3.frlg_font"] = { "invalidate" },
  ["src.core.game3.ow_sprites"] = { "install" },
  ["src.core.game3.tileset_native"] = { "install" },
  ["src.core.game3.field_effects"] = { "install" },
  ["src.core.game3.scripting.space"] = { "resolveObjectGraphicsId" },
}
for _, name in ipairs({ "party_chrome", "bag_chrome", "battle_chrome", "battle_transition_chrome",
    "pokedex_chrome", "summary_chrome", "shop_chrome", "naming_chrome" }) do
  DEFINES["src.ui.game3." .. name] = {}
end

local function defines(source, key)
  return source:find("function%s+[%w_%.]*[%.:]" .. key .. "%s*%(")
    or source:find("[%.%s{,]" .. key .. "%s*=[^=]")
end

local names = {}
for name in pairs(DEFINES) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local source = moduleSource(name)
  if not source then
    failures[#failures + 1] = "missing runtime module " .. name
  else
    for _, key in ipairs(DEFINES[name]) do
      if not defines(source, key) then
        failures[#failures + 1] = name .. " no longer defines " .. key
      end
    end
  end
end

if #failures > 0 then error(table.concat(failures, "\n"), 0) end
print("ok runtime internals")
