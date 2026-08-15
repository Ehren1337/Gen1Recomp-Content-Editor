package.path = "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;"
  .. "tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
  .. package.path

love = {
  filesystem = {
    getInfo = function() return nil end,
    getSource = function() return "." end,
  },
}

local Json = require("src.link.Json")
local ModIO = require("ModIO")

local sep = package.config:sub(1, 1)
local root = os.tmpname() .. "_mapbuilder_manifest"
os.remove(root)

local function join(a, b)
  return a .. sep .. b
end

local function cleanup()
  os.remove(join(root, "manifest.json"))
  if sep == "\\" then
    os.execute('rmdir "' .. root .. '" 2>nul')
  else
    os.execute('rmdir "' .. root .. '" 2>/dev/null')
  end
end

local ok, err = pcall(function()
  assert(ModIO.ensureDirectory(root))
  assert(ModIO.writeText(join(root, "manifest.json"),
    '{"id":"test","permissions":["network"]}'))

  assert(ModIO.setMapBuilderTransform(root, "mapbuilder_transforms.lua"))
  assert(ModIO.setMapBuilderTransform(root, "mapbuilder_transforms.lua"),
    "manifest wiring must be idempotent")

  local body = assert(ModIO.readText(join(root, "manifest.json")))
  local manifest = assert(Json.decode(body))
  assert(manifest.assets_transforms == "mapbuilder_transforms.lua")
  assert(#manifest.permissions == 2)
  assert(manifest.permissions[1] == "network")
  assert(manifest.permissions[2] == "filesystem")

  local changed, reason = ModIO.setMapBuilderTransform(root, "custom.lua")
  assert(changed == false)
  assert(reason:find("unsupported Map Builder transform", 1, true))
end)

cleanup()
if not ok then error(err) end
print("ok mapbuilder manifest")
