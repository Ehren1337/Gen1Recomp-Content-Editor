-- Content-editor session state.  The project table is the source of truth;
-- main.lua is regenerated from it on Save.

local State = {}

function State.new()
  return {
    data = nil,          -- loaded Data (ROM cache + other mods)
    version = nil,
    tab = "project",
    status = "Open or create a mod to begin",
    dirty = false,
    path = nil,          -- absolute mod directory
    project = nil,       -- structured editor project
    -- selection ids per tab
    pokemonId = nil,
    pokemonSection = "basics",
    itemId = nil,
    moveId = nil,
    moveEffectId = nil,
    moveEffectListOffset = 0,
    typeId = nil,
    mapId = nil,
    dialogMapId = nil,
    dialogTextId = nil,
    dialogMapOffset = 0,
    dialogPinOffset = 0,
    trainerId = nil,
    eventScriptKey = nil,  -- "MAP/TEXT_*"
    eventsMode = "scripts", -- scripts | saveflags
    -- map editor tool state
    paintBlock = 1,
    mapTool = "paint",   -- paint | erase | pick | select | warp | object | sign | trainer
    mapZoom = 2,
    mapCamX = 0,
    mapCamY = 0,
    mapListOffset = 0,
    pokemonListOffset = 0,
    itemListOffset = 0,
    moveListOffset = 0,
    typeListOffset = 0,
    typeMatchOffset = 0,
    scrollY = 0,
    newModId = "my_content",
    importReport = nil,
    -- save-flag tester
    testSave = nil,
    testSavePath = nil,
    flagFilter = "",
  }
end

function State.blankProject(id, name)
  return {
    id = id,
    name = name or id,
    profile = "content",
    pokemon = {},   -- id -> record
    items = {},     -- id -> record (+ effectTemplate fields)
    moves = {},     -- id -> record
    moveEffects = {}, -- id -> template draft (emitted as move_effects)
    types = {},     -- id -> { name, category }
    type_matchups = {}, -- "ATK>DEF" -> multiplier (x10)
    maps = {},      -- id -> record (+ encounters)
    tilesets = {},  -- id -> record (imported or custom)
    text = {},      -- _LABEL -> string
    text_pointers = {}, -- mapLabel -> TEXT_* -> { text = "_LABEL" }
    trainers = {},  -- OPP_* -> record
    trainer_headers = {}, -- mapLabel -> { [objIndex] = header }
    map_scripts = {}, -- mapId -> { talk = { TEXT_* = scriptRows } }
    eventFlags = {}, -- shortName -> true (emitted as MOD_<id>_SHORT)
    talkScripts = {}, -- "MAP/TEXT_*" -> { mapId, textId, steps = {...} }
    fishing = {},   -- OLD_ROD / GOOD_ROD overrides (field.fishing)
    hiddenItems = {}, -- mapId -> { { x, y, item }, ... } (field.hiddenItems)
    badgeGates = {},  -- mapId -> gate record (field.badgeGates)
    boot = {},        -- field.boot overrides
    constants = {},   -- constants patches (levelCap, badges, …)
    audio = {},       -- songs/cries/sfx/mapSongs
    palettes = {},    -- id -> colors
    sprites = {},     -- overworld sprite defs
    aiClasses = {},   -- trainer AI class records
    battle_anims = {}, -- registry ids: MOVE / subanim:N / tilesheet:N
    playerSprites = {}, -- field.playerSprites slot -> sprite id
    playerPics = {},    -- field.playerPics slot -> image path
    title = {},         -- field.title (logo, music, copyright, …)
    intro = {},         -- field.intro (studio splash, skip, …)
    theme = {},         -- field.theme (textBox / choiceBox / cursors)
    font = {},          -- font page overrides
    strings = {},       -- engine Strings() overrides (source -> text)
    townMap = {},       -- field.townMap
    -- Oak's Lab ball remap: vanillaSpecies -> { species, level }
    starterRemap = {},
    nextMapIndex = 1000,
  }
end

function State.ensureProjectFields(project)
  if not project then return project end
  project.pokemon = project.pokemon or {}
  project.items = project.items or {}
  project.moves = project.moves or {}
  project.moveEffects = project.moveEffects or {}
  project.types = project.types or {}
  project.type_matchups = project.type_matchups or {}
  project.maps = project.maps or {}
  project.tilesets = project.tilesets or {}
  project.text = project.text or {}
  project.text_pointers = project.text_pointers or {}
  project.trainers = project.trainers or {}
  project.trainer_headers = project.trainer_headers or {}
  project.map_scripts = project.map_scripts or {}
  project.eventFlags = project.eventFlags or {}
  project.talkScripts = project.talkScripts or {}
  project.fishing = project.fishing or {}
  project.boot = project.boot or {}
  project.constants = project.constants or {}
  project.audio = project.audio or {}
  project.palettes = project.palettes or {}
  project.sprites = project.sprites or {}
  project.aiClasses = project.aiClasses or {}
  project.battle_anims = project.battle_anims or {}
  project.playerSprites = project.playerSprites or {}
  project.playerPics = project.playerPics or {}
  project.title = project.title or {}
  project.intro = project.intro or {}
  project.theme = project.theme or {}
  project.font = project.font or {}
  project.strings = project.strings or {}
  project.townMap = project.townMap or {}
  project.hiddenItems = project.hiddenItems or {}
  project.badgeGates = project.badgeGates or {}
  project.starterRemap = project.starterRemap or {}
  project.nextMapIndex = project.nextMapIndex or 1000
  return project
end

function State.mapLabel(S, mapId)
  if not mapId then return nil end
  local proj = S.project and S.project.maps and S.project.maps[mapId]
  if proj and proj.label and proj.label ~= "" then return proj.label end
  local base = S.data and S.data.maps and S.data.maps[mapId]
  if base and base.label then return base.label end
  -- fallback: CamelCase from id
  return (mapId:lower():gsub("_(%w)", function(c) return c:upper() end)
    :gsub("^%w", string.upper))
end

function State.modFlag(project, shortName)
  shortName = tostring(shortName or "FLAG"):upper():gsub("%W+", "_")
  -- Pass through vanilla EVENT_* and already-qualified MOD_* names.
  if shortName:match("^EVENT_") or shortName:match("^MOD_") then
    return shortName
  end
  local prefix = "MOD_" .. (project.id or "MOD"):upper():gsub("%W+", "_") .. "_"
  return prefix .. shortName
end

return State
