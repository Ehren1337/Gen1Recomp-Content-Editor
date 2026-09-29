package.path = "runtime/gen1recomp/?.lua;tools/content-editor/?.lua;tools/content-editor/panels/?.lua;"
  .. package.path

love = {
  filesystem = {
    getInfo = function() return nil end,
    getSource = function() return "." end,
  },
}

-- Headless UI: text fields echo their value unless a test types into them;
-- a button or chip reports one click when its label is queued in `clicks`.
local typed, shown, chips, clicks = {}, {}, {}, {}
local function clicked(label)
  if clicks[label] then clicks[label] = nil; return true end
  return false
end
local function noop() end
local Kit = setmetatable({ scale = 1 }, { __index = function() return noop end })
Kit.textfield = function(id, _, _, _, _, value)
  shown[id] = tostring(value or "")
  local t = typed[id]
  typed[id] = nil
  return t or shown[id]
end
Kit.scroll = function(_, _, _, _, off) return off end
Kit.scrollbar = function(_, _, _, _, off) return off end
Kit.scrollInnerWidth = function(w) return w end
Kit.ellipsize = function(_, s) return s end
Kit.textWidth = function() return 10 end
Kit.button = function(_, _, _, _, label) return clicked(label) end
Kit.row = function() return false end
Kit.chip = function(_, _, _, _, label) chips[label] = true; return clicked(label) end
package.loaded["Kit"] = Kit
package.loaded["Theme"] = { PAL = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) }
package.loaded["FormPane"] = {
  track = noop, finish = noop,
  begin = function() return 0, { contentW = 600, y = 0 } end,
}
package.loaded["RegList"] = { bindNav = function() return { activate = noop } end }

local Json = require("src.link.Json")
local ModIO = require("ModIO")
local stored, written
ModIO.listMods = function() return { "t" } end
ModIO.readManifest = function() return Json.decode(stored), "manifest.json" end
ModIO.writeManifest = function(_, data) written = data; return true end
ModIO.engineVersion = function() return "0.3.0" end

local Manifest = require("Manifest")
local BASE = '"id":"t","name":"T","version":"1.0.0","api":2,"entry":"main.lua"'

local function draw(S) Manifest.draw(S, 0, 0, 1000, 800, { openMod = noop }) end
local function open(fields)
  stored = "{" .. BASE .. (fields and ("," .. fields) or "") .. "}"
  local S = { browseModId = "t" }
  draw(S)
  return S
end

-- asset packs and log_url round trip
local S = open('"games":["red"],"permissions":["network"],"log_url":"https://example.com/log",'
  .. '"required_assets":[{"importer":"gba","pack":"firered","version":"^1.0.0"}],'
  .. '"optional_assets":[{"importer":"gb","pack":"red"}]')
assert(shown.mf_rassets == "gba/firered@^1.0.0", tostring(shown.mf_rassets))
assert(shown.mf_oassets == "gb/red", tostring(shown.mf_oassets))
assert(Manifest.save(S, {}), tostring(S.manifestValidateMsg))
local out = Json.decode(ModIO.encodeManifest(written))
assert(out.required_assets[1].importer == "gba" and out.required_assets[1].version == "^1.0.0")
assert(out.optional_assets[1].pack == "red" and out.optional_assets[1].version == nil)
assert(out.log_url == "https://example.com/log")

-- engine validation still rejects bad input
S = open('"games":["red"]')
S.manifestDraft.log_url = "https://example.com/log"
assert(not Manifest.save(S, {}), "log_url without network permission must fail")
S = open('"games":["red"]')
typed.mf_rassets = "gbafirered"
draw(S)
assert(not Manifest.save(S, {}), "asset pack without importer/pack must fail")

-- keys the tab does not edit survive; managed removals still apply
S = open('"games":["red"],"force_enable_env":"MY_ENV","dependency_sources":{"other":"owner/repo"},'
  .. '"assets_transforms":"t.lua",'
  .. '"required_imports":[{"id":"rom","file":"rom.gb","md5":"0123456789abcdef0123456789abcdef"}]')
S.manifestDraft.assets_transforms = nil
assert(Manifest.save(S, {}), tostring(S.manifestValidateMsg))
assert(written.force_enable_env == "MY_ENV")
assert(written.dependency_sources.other == "owner/repo")
assert(written.required_imports[1].file == "rom.gb")
assert(written.assets_transforms == nil)

-- a manifest without games can be written
S = open()
assert(Manifest.save(S, {}), tostring(S.manifestValidateMsg))
assert(written.games == nil)

-- separators survive while typing
S = open('"games":["red"]')
typed.mf_deps = "mod_a,"
draw(S)
draw(S)
assert(shown.mf_deps == "mod_a,", tostring(shown.mf_deps))
typed.mf_deps = "mod_a, mod_b"
draw(S)
assert(Manifest.save(S, {}), tostring(S.manifestValidateMsg))
assert(written.dependencies[1] == "mod_a" and written.dependencies[2] == "mod_b")

-- imports round trip, toggle, remove and add
local MD5A, MD5B = "0123456789abcdef0123456789abcdef", "fedcba9876543210fedcba9876543210"
S = open('"games":["red"],'
  .. '"required_imports":[{"id":"rom","file":"rom.gb","name":"Red ROM","md5":["' .. MD5A .. '","' .. MD5B .. '"]}],'
  .. '"optional_imports":[{"id":"art","file":"art.gba","md5":"' .. MD5A .. '"}]')
assert(shown.mf_imp_md51 == MD5A .. ", " .. MD5B, tostring(shown.mf_imp_md51))
assert(Manifest.save(S, {}), tostring(S.manifestValidateMsg))
assert(written.required_imports[1].name == "Red ROM" and #written.required_imports[1].md5 == 2)
assert(written.optional_imports[1].file == "art.gba" and written.optional_imports[1].md5 == MD5A)

clicks.required = true
draw(S)
assert(Manifest.save(S, {}), tostring(S.manifestValidateMsg))
assert(written.required_imports == nil and #written.optional_imports == 2)

clicks.x = true
draw(S)
clicks["+ Add import"] = true
draw(S)
typed.mf_imp_id2, typed.mf_imp_file2, typed.mf_imp_md52 = "bios", "bios.bin", MD5B
draw(S)
assert(Manifest.save(S, {}), tostring(S.manifestValidateMsg))
assert(#written.optional_imports == 1 and written.optional_imports[1].id == "art")
assert(written.required_imports[1].id == "bios" and written.required_imports[1].md5 == MD5B)

S = open('"games":["red"]')
clicks["+ Add import"] = true
draw(S)
assert(not Manifest.save(S, {}), "an import without id, file and md5 must fail")

-- every engine permission is offered
local Schema = require("src.mods.Manifest")
for name in pairs(Schema.PERMISSIONS) do
  assert(chips[name], "missing permission chip " .. name)
end

print("ok manifest panel")
