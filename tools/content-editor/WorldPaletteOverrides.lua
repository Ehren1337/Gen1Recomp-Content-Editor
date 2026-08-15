-- Editor-owned compatibility for ADVANCED Gen 1 tileset palettes.
-- It decorates PaletteFX's exported resolver without modifying the pinned
-- runtime. Exported mods use the same resolver contract from ModWriter.

local WorldPaletteOverrides = {}

local STATE_KEY = "__contentEditorWorldPaletteState"

local function cloneGroups(groups)
  if type(groups) ~= "table" then return nil end
  local out = {}
  for i = 1, 8 do
    local group = groups[i]
    if type(group) == "table" then
      out[i] = {}
      for j = 1, 4 do
        local color = group[j] or { 0, 0, 0 }
        out[i][j] = color.r
          and { color.r, color.g, color.b }
          or { color[1] or 0, color[2] or 0, color[3] or 0 }
      end
    end
  end
  return out
end

local function merge(PaletteFX, base, override, mapId)
  if type(base) ~= "table" or type(override) ~= "table" then return base end
  local out = {}
  for i = 1, 8 do
    local colors = override[i]
    -- Gen1Recomp resolves the town-specific ROOF slot when a map is known.
    -- Preserve that result; an editor override supplies the base roof row.
    if mapId and i == 7 then colors = nil end
    if colors and PaletteFX.darkWorld and PaletteFX.darkWorld()
        and PaletteFX.permute and PaletteFX.DARK_BGP then
      colors = PaletteFX.permute(colors, PaletteFX.DARK_BGP)
    end
    out[i] = colors or base[i]
  end
  return out
end

function WorldPaletteOverrides.install(PaletteFX)
  assert(type(PaletteFX) == "table", "PaletteFX table required")
  local state = PaletteFX[STATE_KEY]
  if state then return state end

  state = { original = assert(PaletteFX.worldGroupColors) }
  PaletteFX[STATE_KEY] = state
  PaletteFX.worldGroupColors = function(data, tileset, mapId, playerCellY)
    local base = state.original(data, tileset, mapId, playerCellY)
    local override = state.groups and state.groups[tileset]
    return merge(PaletteFX, base, override, mapId)
  end
  PaletteFX.vanillaWorldGroupColors = function(tileset)
    return cloneGroups(state.original(nil, tileset, nil, nil))
  end
  PaletteFX.setWorldGroupOverrides = function(groups)
    state.groups = type(groups) == "table" and groups or nil
  end
  return state
end

return WorldPaletteOverrides
