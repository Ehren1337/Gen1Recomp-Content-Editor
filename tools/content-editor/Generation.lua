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

-- Manifest `games` tokens for the active authoring target.
-- Gold authoring scaffolds gen1+gen2 so the mod loads on both generations
-- (wiki: omit games ⇒ Gen1-only; gen2 alone won't load on Red/Blue/Yellow).
function Generation.manifestGames(S)
  if Generation.isGen2(S) then
    return { "gen1", "gen2" }
  end
  return { "gen1" }
end

return Generation
