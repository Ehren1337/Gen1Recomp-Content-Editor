-- Content-editor data source: local cache, linked Gen1Recomp, imported ROM
-- (save-dir), or ROM-free fixtures. Prefs live in the LÖVE save directory so
-- a redistributable editor pack never accumulates Nintendo data.

local Json = require("src.link.Json")
local Data = require("src.core.Data")
local CacheFs = require("src.import.CacheFs")

local DataSource = {}

local PREFS_FILE = "content_editor_data.json"
local SEP = package.config:sub(1, 1)

local mountedRecomp = nil

local function join(a, b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. SEP .. b
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function DataSource.hasLocalCache()
  if love and love.filesystem and love.filesystem.getInfo then
    if love.filesystem.getInfo("data/generated/maps.lua", "file") then
      return true
    end
    if love.filesystem.getInfo("data/generated/constants.lua", "file") then
      return true
    end
  end
  local root = love and love.filesystem and love.filesystem.getSource
    and love.filesystem.getSource()
  if root and root ~= "" then
    return fileExists(join(root, "data" .. SEP .. "generated" .. SEP .. "maps.lua"))
  end
  return false
end

function DataSource.isValidRecompRoot(path)
  if type(path) ~= "string" or path == "" then return false end
  path = path:gsub("[/\\]+$", "")
  local maps = join(path, "data" .. SEP .. "generated" .. SEP .. "maps.lua")
  if not fileExists(maps) then return false end
  -- Prefer a tree that also has generated art, but Lua cache alone is enough
  -- to author; playtest against that install still works.
  return true
end

function DataSource.loadPrefs()
  local raw = love.filesystem.read(PREFS_FILE)
  if type(raw) ~= "string" or raw == "" then
    return { mode = "auto", recompRoot = nil, useGbcPalettes = true }
  end
  local ok, data = pcall(Json.decode, raw)
  if not ok or type(data) ~= "table" then
    return { mode = "auto", recompRoot = nil, useGbcPalettes = true }
  end
  local useGbc = data.useGbcPalettes
  if useGbc == nil then useGbc = true end
  return {
    mode = data.mode or "auto",
    recompRoot = data.recompRoot,
    useGbcPalettes = useGbc and true or false,
  }
end

function DataSource.savePrefs(prefs)
  prefs = prefs or DataSource.loadPrefs()
  local useGbc = prefs.useGbcPalettes
  if useGbc == nil then useGbc = true end
  local body = Json.encode({
    mode = prefs.mode or "auto",
    recompRoot = prefs.recompRoot,
    useGbcPalettes = useGbc and true or false,
  })
  love.filesystem.write(PREFS_FILE, body)
  return prefs
end

function DataSource.unmountLinked()
  if mountedRecomp then
    pcall(CacheFs.unmountExternal, mountedRecomp)
    mountedRecomp = nil
  end
end

function DataSource.mountRecomp(path)
  if not DataSource.isValidRecompRoot(path) then
    return false, "Not a Gen1Recomp folder with data/generated"
  end
  path = path:gsub("[/\\]+$", "")
  DataSource.unmountLinked()
  -- Prepend so linked cache wins over missing local generated files.
  if not CacheFs.mountExternal(path, false) then
    return false, "Could not mount folder (PHYSFS unavailable?)"
  end
  mountedRecomp = path
  return true
end

local function loadFixtures()
  local root = love.filesystem.getSource()
  local fixtures = join(root, "tests" .. SEP .. "fixture_data")
  local getenv = os.getenv
  os.getenv = function(k)
    if k == "POKEPORT_DATA_DIR" then return fixtures end
    return getenv(k)
  end
  local ok, err = pcall(function() Data:load() end)
  os.getenv = getenv
  return ok, err
end

local function hasImportedCache(version)
  version = version or "red"
  local ok, RomImporter = pcall(require, "src.import.RomImporter")
  if ok and RomImporter and RomImporter.isReady then
    return RomImporter.isReady(version)
  end
  return love.filesystem.getInfo("data/generated/maps.lua", "file") ~= nil
end

local function tryLocal()
  if not DataSource.hasLocalCache() then return false end
  return pcall(function() Data:load() end)
end

local function tryRecomp(prefs, version)
  if not prefs.recompRoot then return false, "no linked folder" end
  local mok, merr = DataSource.mountRecomp(prefs.recompRoot)
  if not mok then return false, merr end
  pcall(CacheFs.mountVersion, version)
  local ok, err = pcall(function() Data:load() end)
  if ok then return true end
  DataSource.unmountLinked()
  return false, err
end

local function tryImported(version)
  if not hasImportedCache(version) then return false end
  pcall(CacheFs.mountVersion, version)
  return pcall(function() Data:load() end)
end

-- Resolve and load data. Returns source id: "local"|"recomp"|"imported"|"fixtures"
-- Explicit Project-tab choices (recomp / imported / fixtures) win over auto.
function DataSource.apply(opts)
  opts = opts or {}
  local version = opts.version or "red"
  local prefs = DataSource.loadPrefs()
  if Data._pristineKeys then Data:unloadGenerated() end
  DataSource.unmountLinked()

  local mode = prefs.mode or "auto"

  if mode == "fixtures" then
    local ok, err = loadFixtures()
    if not ok then
      error("content editor fixtures failed:\n" .. tostring(err))
    end
    return "fixtures", prefs,
      "Loaded fixture data (no ROM cache) — Link Recomp or Import ROM for full data"
  end

  if mode == "recomp" then
    local ok = tryRecomp(prefs, version)
    if ok then
      return "recomp", prefs,
        "Linked Gen1Recomp: " .. tostring(prefs.recompRoot)
    end
  elseif mode == "imported" then
    local ok = tryImported(version)
    if ok then
      return "imported", prefs, "Loaded imported ROM cache (save directory)"
    end
  end

  -- auto (or failed explicit mode): local → linked → imported → fixtures
  do
    local ok = tryLocal()
    if ok then
      return "local", prefs, "Loaded local ROM cache (dev / pack data/generated)"
    end
  end
  do
    local ok = tryRecomp(prefs, version)
    if ok then
      return "recomp", prefs,
        "Linked Gen1Recomp: " .. tostring(prefs.recompRoot)
    end
  end
  do
    local ok = tryImported(version)
    if ok then
      return "imported", prefs, "Loaded imported ROM cache (save directory)"
    end
  end

  local ok, err = loadFixtures()
  if not ok then
    error("content editor needs an imported ROM cache, linked Recomp, or fixtures:\n"
      .. tostring(err))
  end
  return "fixtures", prefs,
    "Loaded fixture data (no ROM cache) — Link Recomp or Import ROM for full data"
end

function DataSource.label(source)
  if source == "local" then return "Local cache (data/generated)" end
  if source == "recomp" then return "Linked Gen1Recomp folder" end
  if source == "imported" then return "Imported ROM (save directory)" end
  if source == "fixtures" then return "Fixtures (stub data)" end
  return tostring(source or "?")
end

function DataSource.setMode(mode, recompRoot)
  local prefs = DataSource.loadPrefs()
  prefs.mode = mode or "auto"
  if recompRoot ~= nil then prefs.recompRoot = recompRoot end
  if prefs.mode ~= "recomp" and prefs.mode ~= "auto" then
    -- keep path for later re-link, but mode wins
  end
  DataSource.savePrefs(prefs)
  return prefs
end

function DataSource.linkRecomp(path)
  if not DataSource.isValidRecompRoot(path) then
    return nil, "Folder needs data/generated (import a ROM in Gen1Recomp first)"
  end
  path = path:gsub("[/\\]+$", "")
  local prefs = DataSource.setMode("recomp", path)
  return prefs
end

function DataSource.useFixtures()
  return DataSource.setMode("fixtures", nil)
end

function DataSource.clearToAuto()
  local prefs = DataSource.loadPrefs()
  prefs.mode = "auto"
  DataSource.savePrefs(prefs)
  return prefs
end

-- Remove imported ROM cache trees from the LÖVE save directory only.
-- Never deletes a linked Gen1Recomp install or the game source tree.
-- Returns how many top-level cache roots were removed.
function DataSource.clearImportedCache()
  if not (love and love.filesystem and love.filesystem.getSaveDirectory) then
    return 0
  end
  local saveDir = love.filesystem.getSaveDirectory()
  local function removeTree(path)
    local info = love.filesystem.getInfo(path)
    if not info then return end
    if love.filesystem.getRealDirectory
        and love.filesystem.getRealDirectory(path) ~= saveDir then
      return
    end
    if info.type == "directory" then
      for _, child in ipairs(love.filesystem.getDirectoryItems(path) or {}) do
        removeTree(path .. "/" .. child)
      end
    end
    pcall(love.filesystem.remove, path)
  end
  local GameVersion = require("src.core.GameVersion")
  local cleared = 0
  for _, version in ipairs(GameVersion.ORDER or { "red" }) do
    local prefix = GameVersion.cachePrefix and GameVersion.cachePrefix(version) or ""
    local roots = {
      prefix .. "data/generated",
      prefix .. "assets/generated",
      prefix .. "rom-cache.complete",
    }
    for _, rel in ipairs(roots) do
      if love.filesystem.getInfo(rel) then
        removeTree(rel)
        cleared = cleared + 1
      end
    end
  end
  return cleared
end

function DataSource.mountedRecompRoot()
  return mountedRecomp
end

local function ensureDir(path)
  local sep = SEP
  if sep == "\\" then
    os.execute('mkdir "' .. path .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

local function copyFileRaw(src, dest)
  local inf = io.open(src, "rb")
  if not inf then return false, "cannot read " .. tostring(src) end
  local data = inf:read("*a")
  inf:close()
  local parent = dest:match("^(.*)[/\\][^/\\]+$")
  if parent then ensureDir(parent) end
  local out = io.open(dest, "wb")
  if not out then return false, "cannot write " .. tostring(dest) end
  out:write(data)
  out:close()
  return true
end

local function listDir(path)
  local out = {}
  local platform = (love and love.system and love.system.getOS
    and love.system.getOS()) or ""
  local cmd
  if platform == "Windows" or SEP == "\\" then
    cmd = string.format('cmd /c dir /b "%s"', path)
  else
    cmd = string.format('ls -1 "%s"', path)
  end
  local pipe = io.popen(cmd, "r")
  if not pipe then return out end
  for line in pipe:lines() do
    line = line:gsub("%s+$", "")
    if line ~= "" and line ~= "." and line ~= ".." then
      out[#out + 1] = line
    end
  end
  pipe:close()
  return out
end

local function isDir(path)
  -- Append sep and try opening as file; directories fail io.open for write check.
  local f = io.open(path, "rb")
  if f then
    f:close()
    return false
  end
  -- Directory: dir listing succeeds and path has no trailing file open.
  local platform = (love and love.system and love.system.getOS
    and love.system.getOS()) or ""
  if platform == "Windows" or SEP == "\\" then
    local p = io.popen(string.format(
      'cmd /c if exist "%s\\" (echo DIR) else (echo NO)', path), "r")
    if not p then return false end
    local r = p:read("*l") or ""
    p:close()
    return r:find("DIR") ~= nil
  end
  local p = io.popen(string.format('test -d "%s" && echo DIR', path), "r")
  if not p then return false end
  local r = p:read("*l") or ""
  p:close()
  return r:find("DIR") ~= nil
end

function DataSource.copyTree(src, dest)
  src = src:gsub("[/\\]+$", "")
  dest = dest:gsub("[/\\]+$", "")
  if not isDir(src) then
    return copyFileRaw(src, dest)
  end
  ensureDir(dest)
  for _, name in ipairs(listDir(src)) do
    local from = join(src, name)
    local to = join(dest, name)
    local ok, err = DataSource.copyTree(from, to)
    if not ok then return false, err end
  end
  return true
end

return DataSource
