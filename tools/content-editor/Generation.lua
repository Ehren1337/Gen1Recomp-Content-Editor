-- Generation helpers for content-editor panels / ModWriter.

local Generation = {}

function Generation.id(S)
  if S and S.version then return S.version end
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.get then return GameVersion.get() end
  return "red"
end

function Generation.num(S)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and GameVersion.generation then
    return GameVersion.generation(Generation.id(S))
  end
  return Generation.id(S) == "gold" and 2 or 1
end

function Generation.isGen2(S)
  return Generation.num(S) == 2
end

-- Manifest `games` tokens for the exact active authoring target. Generated
-- content comes from one selected ROM/cache and may rely on version-specific
-- maps, tilesets, scripts, and constants even within the same generation.
function Generation.manifestGames(S)
  return { Generation.id(S) }
end

return Generation
