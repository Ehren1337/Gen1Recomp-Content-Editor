local PlaytestOptions = {}

local function selectOnly(flags, selectedId)
  flags = flags or {}
  for id in pairs(flags) do flags[id] = false end
  flags[selectedId] = true
  return flags
end

function PlaytestOptions.selectOnly(options, selectedId, version)
  options.mods = selectOnly(options.mods, selectedId)
  options.modsByVersion = options.modsByVersion or {}
  options.modsByVersion[version] = selectOnly(
    options.modsByVersion[version], selectedId)

  local activeName = options.activeProfile or "PROFILE 1"
  for _, profile in ipairs(options.modProfiles or {}) do
    if profile.name == activeName then
      profile.enabled = selectOnly(profile.enabled, selectedId)
      profile.enabledByVersion = profile.enabledByVersion or {}
      profile.enabledByVersion[version] = selectOnly(
        profile.enabledByVersion[version], selectedId)
      break
    end
  end
  return options
end

return PlaytestOptions
