-- Tileset image export service.
--
-- This module owns filesystem concerns and returns structured results. UI
-- panels decide how to present those results; they do not perform file I/O.

local ModIO = require("ModIO")
local Preview = require("Preview")

local TilesetExport = {}

local function pathSeparator()
  return package.config:sub(1, 1)
end

local function join(...)
  local sep = pathSeparator()
  local parts = { ... }
  local first = tostring(parts[1] or "")
  local rooted = first:match("^[/\\]") ~= nil
  parts[1] = first:gsub("[/\\]+$", "")
  if parts[1] == "" and rooted then parts[1] = sep end
  for index = 2, #parts do
    parts[index] = tostring(parts[index]):gsub("^[/\\]+", ""):gsub("[/\\]+$", "")
  end
  local joined = table.concat(parts, sep)
  if parts[1] == sep then return joined:sub(2) == "" and sep or joined:sub(2) end
  return joined
end

local function sourceFilename(source)
  return tostring(source.id or source.name or "tileset")
    :lower():gsub("[^a-z0-9_-]", "_") .. ".png"
end

local function sourceBytes(S, source)
  if not (source and source.image) then
    return nil, "tileset source has no image"
  end

  local resolved, kind = Preview.resolve(S, source.image)
  if not resolved then
    return nil, "cannot find " .. tostring(source.image)
  end
  if kind == "disk" then
    return ModIO.readText(resolved)
  end
  return love.filesystem.read(resolved)
end

function TilesetExport.defaultFolder(S)
  if not (S and S.path) then return nil end
  return join(S.path, "exports", "tilesets")
end

function TilesetExport.exportSources(S, sources, folder)
  sources = sources or {}
  folder = folder or TilesetExport.defaultFolder(S)
  local result = { ok = false, count = 0, failures = {}, folder = folder }

  if #sources == 0 then
    result.failures[1] = "no tileset sources"
    return result
  end
  if not folder then
    result.failures[1] = "no mod open"
    return result
  end

  local made, makeError = ModIO.ensureDirectory(folder)
  if not made then
    result.failures[1] = "cannot create export folder: " .. tostring(makeError)
    return result
  end

  for _, source in ipairs(sources) do
    local bytes, readError = sourceBytes(S, source)
    if not bytes then
      result.failures[#result.failures + 1] = string.format(
        "%s: %s", tostring(source and source.id or "unknown"), tostring(readError))
    else
      local destination = join(folder, sourceFilename(source))
      local wrote, writeError = ModIO.writeText(destination, bytes)
      if wrote then
        result.count = result.count + 1
      else
        result.failures[#result.failures + 1] = string.format(
          "%s: %s", tostring(source.id or "unknown"), tostring(writeError))
      end
    end
  end

  result.ok = #result.failures == 0
  return result
end

return TilesetExport
