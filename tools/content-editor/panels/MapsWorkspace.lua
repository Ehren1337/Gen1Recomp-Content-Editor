-- Maps workspace.

local Kit = require("Kit")
local Theme = require("Theme")
local MapBuilder = require("MapBuilder")
local Maps = require("Maps")
local LayeredMap = require("LayeredMap")

local MapsWorkspace = {}
local PAL = Theme.PAL

local function sortedTilesets(S)
  local seen, ids = {}, {}
  for _, bucket in ipairs({ S.project and S.project.tilesets,
      S.data and S.data.tilesets }) do
    for id in pairs(bucket or {}) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  if #ids == 0 then ids[1] = "OVERWORLD" end
  return ids
end

local function beginNewMap(S)
  local ids = sortedTilesets(S)
  local chosen = ids[1]
  for _, id in ipairs(ids) do
    if id == "OVERWORLD" or id == "TILESET_JOHTO" then chosen = id; break end
  end
  S.mapNewDraft = {
    id = "NEW_MAP", width = "20", height = "18",
    tileset = chosen,
  }
  Kit.blur()
end

local function drawNewMapForm(S, x, y, w, App)
  local d, s = S.mapNewDraft, Kit.scale
  Kit.card(x, y, w, 102 * s, 10 * s)
  local px, py = x + 10 * s, y + 8 * s
  Kit.text("micro", "ID", px, py + 5 * s, PAL.caption)
  d.id = Kit.textfield("maps_new_id", px + 30 * s, py, 190 * s, 24 * s,
    d.id, "MY_NEW_MAP")
  Kit.text("micro", "Size", px + 232 * s, py + 5 * s, PAL.caption)
  d.width = Kit.textfield("maps_new_w", px + 270 * s, py, 46 * s, 24 * s,
    d.width, "20")
  Kit.text("micro", "x", px + 321 * s, py + 5 * s, PAL.muted)
  d.height = Kit.textfield("maps_new_h", px + 334 * s, py, 46 * s, 24 * s,
    d.height, "18")
  Kit.text("micro", "16x16 cells", px + 386 * s, py + 5 * s, PAL.muted)
  py = py + 30 * s
  local ids, selected = sortedTilesets(S), 1
  for i, id in ipairs(ids) do if id == d.tileset then selected = i; break end end
  Kit.text("micro", "Tileset", px, py + 5 * s, PAL.caption)
  if Kit.stepper(px + 54 * s, py, 24 * s, 24 * s, "<") then
    selected = ((selected - 2) % #ids) + 1; d.tileset = ids[selected]
  end
  Kit.textCenter("micro", Kit.ellipsize("micro", d.tileset, 210 * s),
    px + 82 * s, py + 5 * s, 210 * s, PAL.heading)
  if Kit.stepper(px + 296 * s, py, 24 * s, 24 * s, ">") then
    selected = (selected % #ids) + 1; d.tileset = ids[selected]
  end
  local width, height = tonumber(d.width), tonumber(d.height)
  local valid = width and height and width >= 2 and height >= 2
    and width % 2 == 0 and height % 2 == 0
  if Kit.button(x + w - 176 * s, py, 78 * s, 24 * s, "Create", {
      kind = "good", enabled = valid,
      tooltip = "Dimensions must be even 16x16-cell values" }) then
    local created, err = LayeredMap.createMap(
      S, d.id, width, height, d.tileset)
    if created then
      S.mapId, S.builderMapId = created.id, created.id
      S.builderLayer = 1
      S.builderSourceId = LayeredMap.runtimeSourceId(created.baseTileset)
      S.builderSelections = {}
      S._builderFitFor = nil
      App.markDirty()
    end
    if created then
      S.mapNewDraft = nil
      S.builderPane = "layers"
      S.status = "Created layered map " .. created.id
      Kit.blur()
    else
      S.status = "Create map failed: " .. tostring(err)
    end
  end
  if Kit.button(x + w - 90 * s, py, 78 * s, 24 * s, "Cancel",
      { kind = "ghost" }) then S.mapNewDraft = nil; Kit.blur() end
end

function MapsWorkspace.draw(S, x, y, w, h, App)
  S.mapWorkspace = true
  if S.mapSection == "warps" then
    S.mapSection = "basics"
    S.builderPane = "warps"
    S.builderTool = "warp"
  end
  S.builderPane = S.builderPane or "layers"
  local s = Kit.scale
  local barH = 42 * s
  local selected = S.mapId or S.builderMapId
  local isLayered = selected and S.project and S.project.layeredMaps
    and S.project.layeredMaps[selected] ~= nil

  -- Maps are edited as 16x16 cells and compiled to runtime blocks on save.
  if selected and S.project and not isLayered then
    local source, err = LayeredMap.convertMap(S, selected)
    if source then
      isLayered = true
      S.mapId, S.builderMapId = source.id, source.id
      S.builderLayer = 1
      S.builderSourceId = LayeredMap.runtimeSourceId(source.baseTileset)
      S.builderSelections = {}
      S._builderFitFor = nil
      if S._mapsAutoConverted ~= selected then
        S._mapsAutoConverted = selected
        local History = require("History")
        History.resetBaseline(S)
        S.dirty = true
        S._quitArmed = nil
        S.status = "Editing " .. selected .. " on the 16x16 grid"
      end
    elseif S._mapsConvertErrorFor ~= selected then
      S._mapsConvertErrorFor = selected
      S.status = "Cannot prepare " .. selected .. " for 16x16 editing: "
        .. tostring(err)
    end
  end

  Kit.card(x, y, w, barH, 10 * s)
  Kit.text("caption", "MAPS", x + 12 * s, y + 11 * s, PAL.heading)
  local context = isLayered and "16x16 map editor" or "Map preview"
  Kit.text("micro", context, x + 84 * s, y + 15 * s, PAL.muted)
  local world = S.mapViewMode == "world"
  local worldLabel = world and "Back to Editor" or "World View"
  if Kit.button(x + 220 * s, y + 7 * s, 112 * s, 28 * s,
      worldLabel, { kind = world and "accent" or "ghost",
        enabled = selected ~= nil,
        tooltip = world
          and "Return to the map editor"
          or "Show this map with its connected neighbors" }) then
    S.mapViewMode = world and "editor" or "world"
    if S.mapViewMode == "world" then
      S._worldFitKey = nil
    else
      S._worldViewHit = false
    end
  end
  local actionRight = x + w - 12 * s
  if Kit.button(actionRight - 104 * s, y + 7 * s, 104 * s, 28 * s,
      "+ New Map", { kind = "good", enabled = S.project ~= nil,
        tooltip = "Create a layered 16x16 map" }) then
    if S.mapNewDraft then S.mapNewDraft = nil else beginNewMap(S) end
  end
  if Kit.button(actionRight - 212 * s, y + 7 * s, 102 * s, 28 * s,
      "Clear Events", { kind = "ghost", enabled = selected ~= nil,
        tooltip = "Remove objects, signs, transfers, and layered warp endpoints" }) then
    Maps.clearEvents(S, App)
  end
  local owned = selected and S.project and S.project.maps
    and S.project.maps[selected] ~= nil
  if Kit.button(actionRight - 304 * s, y + 7 * s, 86 * s, 28 * s,
      "Delete Map", { kind = "danger", enabled = owned,
        tooltip = "Delete this project-owned map (vanilla maps revert to source)" }) then
    Maps.deleteMap(S, App)
  end

  local formH = S.mapNewDraft and 110 * s or 0
  if S.mapNewDraft then drawNewMapForm(S, x, y + barH + 6 * s, w, App) end
  local bodyY = y + barH + 8 * s + formH
  local bodyH = h - barH - 8 * s - formH
  if selected then
    S.mapId = selected
    S.builderMapId = selected
  end
  MapBuilder.draw(S, x, bodyY, w, bodyH, App)
end

function MapsWorkspace.keypressed(S, key, App)
  if key == "escape" and S.mapNewDraft then
    S.mapNewDraft = nil
    Kit.blur()
    S.status = "New map cancelled"
    return true
  end
  local id = S.mapId or S.builderMapId
  local layered = id and S.project and S.project.layeredMaps
    and S.project.layeredMaps[id]
  if layered then
    return MapBuilder.keypressed and MapBuilder.keypressed(S, key, App)
  end
  if Maps.keypressed then return Maps.keypressed(S, key, App) end
  return false
end

function MapsWorkspace.update(S, dt)
  if Maps.update then Maps.update(S, dt) end
  if MapBuilder.update then MapBuilder.update(S, dt) end
end

function MapsWorkspace.wheelmoved(S, dy, dx)
  if MapBuilder.wheelmoved and MapBuilder.wheelmoved(S, dy, dx) then return true end
  return Maps.wheelmoved and Maps.wheelmoved(S, dy, dx) or false
end

return MapsWorkspace
