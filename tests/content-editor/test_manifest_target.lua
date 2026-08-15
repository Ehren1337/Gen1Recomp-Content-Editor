package.path = "tools/content-editor/?.lua;" .. package.path

love = {
  filesystem = {
    getInfo = function() return nil end,
    getSource = function() return "." end,
  },
}

local Json = require("src.link.Json")
local ModIO = require("ModIO")

local sep = package.config:sub(1, 1)
local root = os.tmpname() .. "_manifest_target"
os.remove(root)
assert(ModIO.ensureDirectory(root))

local function manifest()
  local body = assert(ModIO.readText(root .. sep .. "manifest.json"))
  return assert(Json.decode(body))
end

local ok, err = pcall(function()
  assert(ModIO.writeText(root .. sep .. "manifest.json",
    '{"id":"test","name":"Old","games":["gen1","gen2"],"gen2compat":true}'))

  assert(ModIO.setManifestTarget(root, "red", "Red Project"))
  local red = manifest()
  assert(#red.games == 2 and red.games[1] == "gen1" and red.games[2] == "gen2")
  assert(red.gen2compat == true)
  assert(red.name == "Red Project")

  assert(ModIO.setManifestTarget(root, "gold", "Gold Project"))
  local gold = manifest()
  assert(#gold.games == 2 and gold.games[1] == "gen1" and gold.games[2] == "gen2")
  assert(gold.gen2compat == true)
  assert(gold.name == "Gold Project")
end)

os.remove(root .. sep .. "manifest.json")
if sep == "\\" then
  os.execute('rmdir "' .. root .. '" 2>nul')
else
  os.execute('rmdir "' .. root .. '" 2>/dev/null')
end
if not ok then error(err) end
print("ok manifest target")
