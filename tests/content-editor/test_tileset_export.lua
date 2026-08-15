package.path = "runtime/gen1recomp/?.lua;"
  .. "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;"
  .. "tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
  .. package.path

love = {
  filesystem = {
    getInfo = function() return nil end,
    getSource = function() return "." end,
    read = function() return nil, "unexpected virtual read" end,
  },
}

local ModIO = require("ModIO")
local TilesetExport = require("TilesetExport")
local DataSource = require("DataSource")

local sep = package.config:sub(1, 1)
local root = os.tmpname() .. "_tileset_export"
os.remove(root)
love.filesystem.getSaveDirectory = function() return root end

local function join(a, b)
  return a .. sep .. b
end

local function cleanup()
  os.remove(join(join(join(root, "exports"), "tilesets"), "source_a.png"))
  os.remove(join(root, "source.png"))
  os.remove(join(join(join(join(root, "red"), "data"), "generated"), "pokemon.lua"))
  if sep == "\\" then
    os.execute('rmdir "' .. join(join(root, "exports"), "tilesets") .. '" 2>nul')
    os.execute('rmdir "' .. join(root, "exports") .. '" 2>nul')
    os.execute('rmdir "' .. join(join(join(root, "red"), "data"), "generated") .. '" 2>nul')
    os.execute('rmdir "' .. join(join(root, "red"), "data") .. '" 2>nul')
    os.execute('rmdir "' .. join(root, "red") .. '" 2>nul')
    os.execute('rmdir "' .. root .. '" 2>nul')
  else
    os.execute('rmdir "' .. join(join(root, "exports"), "tilesets") .. '" 2>/dev/null')
    os.execute('rmdir "' .. join(root, "exports") .. '" 2>/dev/null')
    os.execute('rmdir "' .. join(join(join(root, "red"), "data"), "generated") .. '" 2>/dev/null')
    os.execute('rmdir "' .. join(join(root, "red"), "data") .. '" 2>/dev/null')
    os.execute('rmdir "' .. join(root, "red") .. '" 2>/dev/null')
    os.execute('rmdir "' .. root .. '" 2>/dev/null')
  end
end

local ok, err = pcall(function()
  assert(ModIO.ensureDirectory(root))
  assert(ModIO.ensureDirectory(root), "directory creation must be idempotent")
  assert(ModIO.writeText(join(root, "source.png"), "png-bytes"))

  local imported = join(join(join(root, "red"), "data"), "generated")
  assert(ModIO.ensureDirectory(imported))
  assert(ModIO.writeText(join(imported, "pokemon.lua"), "return {}"))
  local dataDir, base = DataSource.validationDataDir({
    version = "red", source = "imported", prefs = {}, repoRoot = "missing",
  })
  assert(dataDir == imported, tostring(dataDir))
  assert(base == "imported")

  local state = { path = root }
  assert(TilesetExport.defaultFolder(state) ==
    join(join(root, "exports"), "tilesets"))
  local source = { id = "SOURCE_A", image = "source.png" }
  local first = TilesetExport.exportSources(state, { source })
  assert(first.ok, table.concat(first.failures, "; "))
  assert(first.count == 1)

  local second = TilesetExport.exportSources(state, { source })
  assert(second.ok, table.concat(second.failures, "; "))
  assert(second.count == 1, "repeat export must overwrite cleanly")

  local body = assert(ModIO.readText(
    join(join(join(root, "exports"), "tilesets"), "source_a.png")))
  assert(body == "png-bytes")
end)

cleanup()
if not ok then error(err) end
print("ok tileset export")
