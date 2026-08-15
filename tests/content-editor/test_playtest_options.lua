package.path = "tools/content-editor/?.lua;" .. package.path

local PlaytestOptions = require("PlaytestOptions")
local options = {
  mods = { old_mod = true },
  modsByVersion = { red = { old_mod = true } },
  activeProfile = "TEST",
  modProfiles = {
    {
      name = "TEST",
      enabled = { old_mod = true },
      enabledByVersion = { red = { old_mod = true } },
    },
  },
}

PlaytestOptions.selectOnly(options, "my_content", "red")
assert(options.mods.my_content == true and options.mods.old_mod == false)
assert(options.modsByVersion.red.my_content == true)
assert(options.modsByVersion.red.old_mod == false)
assert(options.modProfiles[1].enabled.my_content == true)
assert(options.modProfiles[1].enabled.old_mod == false)
assert(options.modProfiles[1].enabledByVersion.red.my_content == true)
assert(options.modProfiles[1].enabledByVersion.red.old_mod == false)

print("ok playtest options")
