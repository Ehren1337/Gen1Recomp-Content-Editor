-- Content editor app shell.  Launch with `love . --content-editor`.
-- Reuses the save-editor Kit/Theme via the shared require path.

local Data = require("src.core.Data")
local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local ModIO = require("ModIO")
local History = require("History")
local DataSource = require("DataSource")
local PAL = Theme.PAL

local Project = require("Project")
local Manifest = require("Manifest")
local Code = require("Code")
local Pokemon = require("Pokemon")
local Items = require("Items")
local Moves = require("Moves")
local MoveEffects = require("MoveEffects")
local Types = require("Types")
local Maps = require("Maps")
local Dialog = require("Dialog")
local Trainers = require("Trainers")
local Events = require("Events")
local Audio = require("Audio")
local Gfx = require("Gfx")
local AiClasses = require("AiClasses")
local PalettePicker = require("PalettePicker")

local App = {}
local S
local mouseClicked = false
local clickX, clickY
local wheelY = 0

App.dataVersion = nil

local TABS = {
  { id = "project",  label = "PROJECT",
    tip = "Create / open mod, boot & constants, validate / playtest" },
  { id = "manifest", label = "MANIFEST",
    tip = "Edit mods/<id>/manifest.json" },
  { id = "code",     label = "CODE",
    tip = "Browse and edit Lua files under mods/" },
  { id = "maps",     label = "MAPS",
    tip = "Paint blocks, warps, objects, encounters, hidden items" },
  { id = "dialog",   label = "DIALOG",
    tip = "NPC / sign TEXT_* strings and bindings" },
  { id = "trainers", label = "TRAINERS",
    tip = "Trainer classes, parties, and battle headers" },
  { id = "ai",       label = "AI",
    tip = "Trainer AI classes (item use / switching)" },
  { id = "items",    label = "ITEMS",
    tip = "Items and bag effect templates" },
  { id = "pokemon",  label = "POKEMON",
    tip = "Species stats, sprites, icons, learnsets" },
  { id = "moves",    label = "MOVES",
    tip = "Move power, accuracy, effects, advanced flags" },
  { id = "effects",  label = "EFFECTS",
    tip = "Author move_effects from templates" },
  { id = "types",    label = "TYPES",
    tip = "Type chart and matchup multipliers" },
  { id = "audio",    label = "AUDIO",
    tip = "Music, cries, SFX, and map songs" },
  { id = "gfx",      label = "GFX",
    tip = "Palettes, overworld sprites, tilesets" },
  { id = "events",   label = "EVENTS",
    tip = "Talk scripts, flags, and save-flag tester" },
}

local PANELS = {
  project = Project,
  manifest = Manifest,
  code = Code,
  pokemon = Pokemon,
  items = Items,
  moves = Moves,
  effects = MoveEffects,
  types = Types,
  maps = Maps,
  dialog = Dialog,
  trainers = Trainers,
  ai = AiClasses,
  audio = Audio,
  gfx = Gfx,
  events = Events,
}

local function anyDirty(state)
  return state and (state.dirty or state.manifestDirty or state.codeDirty)
end

local function say(msg)
  if S then S.status = tostring(msg) end
end

function App.getState()
  return S
end

local function refreshModsAndEvents()
  local ModLoader = require("src.mods.Loader")
  local mods = ModLoader.new()
  mods:load(Data)
  S.data = Data
  S.mods = mods
  local okCat, Catalog = pcall(require, "Catalog")
  if okCat and Catalog.scrapeEvents then
    local modRoots = {}
    for _, mod in ipairs(mods:status().loaded or {}) do
      modRoots[#modRoots + 1] = mod.path
    end
    local okEv, events = pcall(Catalog.scrapeEvents,
      "data/scripts", "data/generated/trainer_headers.lua", nil, modRoots)
    S.events = okEv and events or {}
  else
    S.events = {}
  end
end

function App.reloadData(opts)
  opts = opts or {}
  if not S then return false end
  local source, prefs, status = DataSource.apply({
    version = opts.version or S.version or App.dataVersion or "red",
  })
  S.dataSource = source
  S.dataPrefs = prefs
  refreshModsAndEvents()
  say(status or DataSource.label(source))
  return true
end

function App.load(modPath, opts)
  opts = opts or {}
  S = State.new()
  S.version = opts.version
  App.dataVersion = opts.version
  local source, prefs, status = DataSource.apply({ version = opts.version })
  S.dataSource = source
  S.dataPrefs = prefs
  S.status = status
  refreshModsAndEvents()

  if modPath and modPath ~= "" then
    App.openMod(modPath)
  elseif not S.status or S.status == "Open or create a mod to begin" then
    say(status or "Create a mod or Open an existing mods/ folder")
  end
end

function App.linkRecompFolder(path)
  if not path or path == "" then return false end
  local prefs, err = DataSource.linkRecomp(path)
  if not prefs then
    say(err or "Link failed")
    return false
  end
  App.reloadData()
  say("Linked Gen1Recomp: " .. path)
  return true
end

function App.useFixturesData()
  DataSource.useFixtures()
  App.reloadData()
  say("Using fixture stub data (no ROM cache)")
  return true
end

function App.importRomFile(path)
  if not path or path == "" then return false end
  if S and S._romImporter and S._romImporter.workState == "working" then
    say("ROM import already in progress…")
    return false
  end
  local RomImporter = require("src.import.RomImporter")
  local importer = RomImporter.new(function(version)
    DataSource.setMode("imported")
    if S then S._romImporter = nil end
    App.dataVersion = version
    S.version = version
    require("src.core.GameVersion").set(version)
    require("src.import.CacheFs").mountVersion(version)
    App.reloadData({ version = version })
    say("ROM imported (" .. tostring(version) .. ") — cache in save directory")
  end, { launcher = false })
  S._romImporter = importer
  say("Importing ROM…")
  importer:startPath(path)
  if importer.workState == "working" then
    return true
  end
  if importer.notice and importer.notice.text then
    say(importer.notice.text)
  elseif importer.status then
    say(tostring(importer.status))
  end
  S._romImporter = nil
  return false
end

function App.unload()
  if S and S._romImporter then S._romImporter = nil end
  pcall(function() require("DataSource").unmountLinked() end)
  S = nil
  App.dataVersion = nil
  Kit.blur()
  Kit.blockClicks = false
end

function App.openMod(path)
  if not path or path == "" then return false end
  -- strip trailing slash
  path = path:gsub("[/\\]+$", "")
  local project, note = ModIO.load(path)
  if not project then
    say("Open failed: " .. tostring(note))
    return false
  end
  S.path = path
  S.project = State.ensureProjectFields(project)
  S.dirty = false
  S._liveTilesets = nil
  S.browseModId = path:match("[/\\]([^/\\]+)$") or S.browseModId
  S._manifestFor = nil
  S._codeFor = nil
  S.manifestDirty = false
  S.codeDirty = false
  S.pokemonId = next(project.pokemon)
  if not S.pokemonId and S.data and S.data.pokemon then
    local ids = {}
    for id in pairs(S.data.pokemon) do ids[#ids + 1] = id end
    table.sort(ids)
    S.pokemonId = ids[1]
  end
  S.itemId = next(project.items)
  if not S.itemId and S.data and S.data.items then
    local ids = {}
    for id in pairs(S.data.items) do ids[#ids + 1] = id end
    table.sort(ids)
    S.itemId = ids[1]
  end
  S.moveId = next(project.moves)
  if not S.moveId and S.data and S.data.moves then
    local ids = {}
    for id in pairs(S.data.moves) do ids[#ids + 1] = id end
    table.sort(ids)
    S.moveId = ids[1]
  end
  S.typeId = next(project.types)
  if not S.typeId then
    local ok, TypeChart = pcall(require, "src.battle.TypeChart")
    if ok and TypeChart and TypeChart.TYPES then
      local ids = {}
      for id in pairs(TypeChart.TYPES) do ids[#ids + 1] = id end
      table.sort(ids)
      S.typeId = ids[1]
    end
  end
  S.mapId = next(project.maps)
  if not S.mapId and S.data and S.data.maps then
    local ids = {}
    for id in pairs(S.data.maps) do ids[#ids + 1] = id end
    table.sort(ids)
    S.mapId = ids[1]
  end
  S.dialogMapId = S.mapId
  S._mapCenteredFor = nil
  S.trainerId = next(project.trainers)
  S.eventScriptKey = next(project.talkScripts)
  History.clear(S)
  say((note and (note .. " — ") or "") .. "Opened " .. path)
  return true
end

function App.createMod(id)
  id = id or S.newModId
  local path, projectOrErr = ModIO.create(id)
  if not path then
    say("Create failed: " .. tostring(projectOrErr))
    return false
  end
  S.path = path
  S.project = projectOrErr
  S.dirty = false
  S.browseModId = id
  S._manifestFor = nil
  S._codeFor = nil
  S.manifestDirty = false
  S.codeDirty = false
  History.clear(S)
  say("Created " .. path)
  return true
end

function App.save()
  if not S or not S.path or not S.project then
    return say("No mod open")
  end
  local ok, err = ModIO.save(S.path, S.project)
  if ok then
    S.dirty = false
    say("Saved " .. S.path .. " (editor_project.lua + main.lua)")
  else
    say("Save failed: " .. tostring(err))
  end
end

local function repoRoot()
  local src = love.filesystem.getSource()
  if src and src ~= "" then return src end
  return "."
end

local function runShell(cmd)
  local ok, handle = pcall(io.popen, cmd .. " 2>&1")
  if not ok or not handle then
    return false, "shell unavailable: " .. tostring(handle)
  end
  local out = handle:read("*a") or ""
  local okClose, _, code = handle:close()
  local exit = (type(code) == "number" and code)
    or (okClose and 0 or 1)
  return exit == 0, out
end

function App.validateMod()
  if not S or not S.project or not S.project.id then
    return say("No mod open")
  end
  if S.dirty then
    App.save()
  end
  local id = S.project.id
  local root = repoRoot()
  local sep = package.config:sub(1, 1)
  local py = "python"
  local script = root .. sep .. "tools" .. sep .. "modkit.py"
  local cmd = string.format('%s "%s" validate %s --base auto', py, script, id)
  local ok, out = runShell(cmd)
  if (not ok and (out or ""):find("python")) or (out or ""):find("not recognized") then
    ok, out = runShell(string.format('python3 "%s" validate %s --base auto', script, id))
  end
  S.validateOutput = tostring(out or "")
  if ok then
    say("Validate OK — " .. id)
  else
    say("Validate failed — see log on Project tab")
  end
end

local function resolveLoveExe(searchRoots)
  local sep = package.config:sub(1, 1)
  for _, root in ipairs(searchRoots or {}) do
    if root and root ~= "" then
      local candidates = {
        root .. sep .. "love" .. sep .. "love.exe",
        root .. sep .. "love" .. sep .. "love-11.5-win64" .. sep .. "love.exe",
        root .. sep .. "love.exe",
      }
      for _, path in ipairs(candidates) do
        local f = io.open(path, "rb")
        if f then f:close(); return path end
      end
    end
  end
  return "love"
end

function App.playtestMod()
  if not S or not S.project or not S.project.id then
    return say("No mod open")
  end
  if anyDirty(S) then App.save() end
  local id = S.project.id
  local packRoot = repoRoot()
  local sep = package.config:sub(1, 1)
  local launchRoot = packRoot
  local source = S.dataSource or "fixtures"

  if source == "recomp" then
    local recomp = (S.dataPrefs and S.dataPrefs.recompRoot)
      or DataSource.mountedRecompRoot()
    if recomp and DataSource.isValidRecompRoot(recomp) then
      local dest = recomp .. sep .. "mods" .. sep .. id
      local src = S.path or (ModIO.modsRoot() .. sep .. id)
      local okCopy, copyErr = DataSource.copyTree(src, dest)
      if not okCopy then
        return say("Playtest sync failed: " .. tostring(copyErr))
      end
      launchRoot = recomp
    end
  end

  local okEnable, errEnable = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    LauncherMods.setEnabled(id, true)
  end)
  if not okEnable then
    say("Could not enable mod in options: " .. tostring(errEnable))
    return
  end

  local loveExe = resolveLoveExe({ packRoot, launchRoot })
  local cmd
  if sep == "\\" then
    cmd = string.format('start "" "%s" "%s"', loveExe, launchRoot)
  else
    cmd = string.format('"%s" "%s" &', loveExe, launchRoot)
  end
  local ok, err = pcall(os.execute, cmd)
  if not ok then
    return say("Playtest launch failed: " .. tostring(err))
  end
  if source == "fixtures" then
    say("Playtest launched (fixtures — stub data only). Link Recomp or Import ROM for full game.")
  elseif source == "recomp" then
    say("Playtest launched in linked Recomp with mod: " .. id)
  else
    say("Playtest launched with mod enabled: " .. id)
  end
end

function App.markDirty()
  if not S then return end
  History.noteDirty(S)
  S.dirty = true
  S._quitArmed = nil
end

function App.undo()
  if not S then return say("Nothing to undo") end
  if S.tab == "code" and Code.undo and Code.undo(S) then
    return say("Code undo")
  end
  if not S.project then return say("Nothing to undo") end
  if History.undo(S) then
    say("Undo (" .. #(S.undoStack or {}) .. " left)")
  else
    say("Nothing to undo")
  end
end

function App.redo()
  if not S then return say("Nothing to redo") end
  if S.tab == "code" and Code.redo and Code.redo(S) then
    return say("Code redo")
  end
  if not S.project then return say("Nothing to redo") end
  if History.redo(S) then
    say("Redo (" .. #(S.redoStack or {}) .. " left)")
  else
    say("Nothing to redo")
  end
end

function App.close()
  if anyDirty(S) then
    if not S._quitArmed then
      S._quitArmed = true
      say("Unsaved changes — Close again to quit without saving")
      return
    end
  end
  love.event.quit()
end

local function cycleTab(delta)
  local idx = 1
  for i, t in ipairs(TABS) do
    if t.id == S.tab then idx = i; break end
  end
  idx = ((idx - 1 + delta) % #TABS) + 1
  S.tab = TABS[idx].id
  say("Tab: " .. TABS[idx].label)
end

-- Queue a native file dialog.  Must not run inside love.draw: on Windows the
-- PowerShell OpenFileDialog + mid-frame image decode freezes the LOVE window
-- ("Not Responding") after Browse.  Processed once from App.update.
function App.pickFile(title, filter, onPicked)
  if not S then return end
  S._filePick = {
    kind = "file",
    title = title or "Choose a file",
    filter = filter or "All files (*.*)|*.*",
    cb = onPicked,
  }
end

function App.pickFolder(title, onPicked, startPath)
  if not S then return end
  S._filePick = {
    kind = "folder",
    title = title or "Choose a folder",
    startPath = startPath,
    cb = onPicked,
  }
end

-- Sanitize a picked filename for use under mod assets/.
function App.assetBaseName(picked, fallback)
  local base = tostring(picked or ""):match("[^/\\]+$") or fallback or "file.bin"
  base = base:gsub("[^%w%._%-]", "_")
  if base == "" or base == "." or base == ".." then
    base = fallback or "file.bin"
  end
  return base
end

-- Copy a picked file into the open mod's assets/ keeping its real filename
-- (e.g. abrab.png → assets/abrab.png).  destRel is ignored when present as a
-- legacy prefix; the basename of `picked` always wins.
-- onDone(destRel, sourceName) is optional.
function App.importToMod(picked, destRel, onDone)
  if not (S and S.path and picked) then return false end
  local sourceName = App.assetBaseName(picked, "file.bin")
  local rel = "assets/" .. sourceName
  -- Optional explicit destination only if caller passed a full path with ext.
  if type(destRel) == "string" and destRel:match("%.[%w]+$") then
    rel = destRel:match("^assets/") and destRel or ("assets/" .. destRel)
  end
  local sep = package.config:sub(1, 1)
  local dest = S.path .. sep .. rel:gsub("/", sep)
  local ok, err = ModIO.copyFile(picked, dest)
  if not ok then
    say("Copy failed: " .. tostring(err))
    return false
  end
  local Preview = require("Preview")
  if Preview.invalidatePath then
    Preview.invalidatePath(rel)
  else
    Preview.invalidate()
  end
  App.markDirty()
  if onDone then onDone(rel, sourceName) end
  say("Imported " .. sourceName .. " → " .. rel)
  local perr = Preview.lastError and Preview.lastError()
  if perr then say("Imported " .. rel .. " — preview: " .. perr) end
  return true
end

function App.update(dt)
  if not S then return end
  if S._romImporter then
    local imp = S._romImporter
    pcall(function() imp:update(dt or 0) end)
    if imp.status and imp.workState == "working" then
      local pct = imp.progress and math.floor((imp.progress or 0) * 100) or 0
      S.status = string.format("Importing ROM… %s (%d%%)",
        tostring(imp.status), pct)
    end
    if imp.workState ~= "working" and not imp.worker then
      if imp.workState ~= "complete" and S._romImporter == imp then
        local msg = (imp.notice and imp.notice.text) or imp.status
        if msg and tostring(msg) ~= "" then say(tostring(msg)) end
        S._romImporter = nil
      end
    end
  end
  if not S._filePick then return end
  local req = S._filePick
  S._filePick = nil
  local path
  if req.kind == "folder" then
    path = ModIO.chooseFolder(req.title, req.startPath)
  else
    path = ModIO.chooseFile(req.title, req.filter)
  end
  if not path then
    say("Open cancelled / picker unavailable")
    return
  end
  if req.cb then
    local ok, err = pcall(req.cb, path)
    if not ok then
      say("Import failed: " .. tostring(err))
    end
  end
end

function App.draw()
  if not S then return end
  local W, H = love.graphics.getDimensions()
  local s = Kit.layout(W, H)
  local mx, my = love.mouse.getPosition()
  if clickX then mx, my = clickX, clickY end
  Kit.beginFrame(mx, my, mouseClicked, wheelY)
  mouseClicked = false
  clickX, clickY = nil, nil

  Theme.field(W, H)

  -- version rail
  local railH = 6 * s
  Theme.versionRail(0, 0, W, railH)

  local titleY = railH + 10 * s
  local btnH = 32 * s
  Kit.text("title", "CONTENT EDITOR", 20 * s, titleY, PAL.heading)
  local chip = S.path and (S.path:match("[/\\]([^/\\]+)$") or S.path)
    or S.browseModId or "(no mod)"
  if anyDirty(S) then chip = chip .. " *" end
  Kit.text("small", chip, 20 * s, titleY + 28 * s, PAL.muted)

  local bx = W - 20 * s
  local function rbtn(label, kind, fn, enabled, tip)
    local bw = Kit.textWidth("button", label) + 28 * s
    bx = bx - bw - 8 * s
    local opts = { kind = kind, tooltip = tip }
    if enabled == false then opts.enabled = false end
    if Kit.button(bx, titleY, bw, btnH, label, opts) then fn() end
  end
  rbtn("Close", "ghost", function() App.close() end, true,
    "Quit the content editor (Esc)")
  rbtn("Save", "primary", function() App.save() end, true,
    "Write editor_project.lua + main.lua (Ctrl+S)")
  rbtn("Redo", "ghost", function() App.redo() end, History.canRedo(S),
    "Redo (Ctrl+Y)")
  rbtn("Undo", "ghost", function() App.undo() end, History.canUndo(S),
    "Undo last content edit (Ctrl+Z)")
  rbtn("Open", "ghost", function()
    local p = ModIO.chooseModDir()
    if p then App.openMod(p) else say("Open cancelled / picker unavailable") end
  end, true, "Open an existing mods/ folder")

  local tabY = railH + 70 * s
  local tabH = 36 * s
  local tx = 20 * s
  for _, t in ipairs(TABS) do
    local tw = math.max(72 * s, Kit.textWidth("micro", t.label) + 18 * s)
    local on = S.tab == t.id
    if Kit.chip(tx, tabY, tw, tabH, t.label, on, PAL.green, PAL.steel, t.tip) then
      S.tab = t.id
    end
    tx = tx + tw + 6 * s
  end

  local contentY = tabY + tabH + 16 * s
  local contentH = H - contentY - 44 * s
  History.beginFrame(S)
  -- Block underlying panel hits while the shared palette modal is up.
  if PalettePicker.isOpen(S) then Kit.blockClicks = true end
  local panel = PANELS[S.tab]
  if panel and panel.draw then
    panel.draw(S, 20 * s, contentY, W - 40 * s, contentH, App)
  end
  History.endFrame(S)

  -- status bar
  local statusH = 38 * s
  local statusY = H - statusH
  Theme.col(PAL.cardBody, 0.85)
  love.graphics.rectangle("fill", 0, statusY, W, statusH)
  local statusTy = statusY + (statusH - Kit.textHeight("micro")) / 2
  Kit.text("micro", S.status or "", 20 * s, statusTy, PAL.detail)
  Kit.textRight("micro", "Undo Ctrl+Z   Redo Ctrl+Y   Save Ctrl+S   Esc",
    W - 20 * s, statusTy, PAL.faint)

  -- Re-enable hits so the modal itself can receive clicks.
  if PalettePicker.isOpen(S) then
    Kit.blockClicks = false
    PalettePicker.draw(S, 0, 0, W, H)
  end

  Kit.endFrame()
  wheelY = 0
end

function App.keypressed(key)
  if not S then return end
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
  local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  -- undo/redo before Kit steals keystrokes from focused fields
  if ctrl and (key == "z" or key == "y") then
    Kit.blur()
    if key == "y" or (key == "z" and shift) then
      return App.redo()
    end
    return App.undo()
  end
  if Kit.keypressed(key) then return end
  if key == "escape" then
    if PalettePicker.keypressed(S, key) then return end
    if S.tab == "maps" and S.mapTilesetPicker then
      S.mapTilesetPicker = nil
      Kit.blur()
      return
    end
    return App.close()
  end
  if key == "s" and ctrl then
    return App.save()
  end
  if key == "]" or key == "tab" then return cycleTab(1) end
  if key == "[" then return cycleTab(-1) end
  if PalettePicker.isOpen(S) then return end
  if S.tab == "maps" and Maps.keypressed then
    Maps.keypressed(S, key)
  elseif S.tab == "code" and Code.keypressed then
    Code.keypressed(S, key)
  end
end

function App.textinput(text)
  Kit.textinput(text)
end

function App.mousepressed(x, y, button)
  if button == 1 then
    mouseClicked = true
    clickX, clickY = x, y
  end
end

function App.mousereleased() end

function App.wheelmoved(_, y)
  if S and S.tab == "maps" and Maps.wheelmoved and Maps.wheelmoved(S, y) then
    return
  end
  wheelY = wheelY + (y or 0)
end

function App.filedropped(file)
  if not (file and S) then return end
  local path = file.getFilename and file:getFilename() or nil
  if not path then return end
  if path:lower():match("%.tmx$") then
    S.tab = "maps"
    if Maps.importTmx then Maps.importTmx(S, path, App) end
    return
  end
  -- treat as mod folder if it looks like one
  if ModIO.exists(path .. "/manifest.json") or ModIO.exists(path .. "\\manifest.json") then
    App.openMod(path)
  else
    say("Drop a mod folder or a .tmx map")
  end
end

function App.quit()
  if anyDirty(S) and not S._quitArmed then
    S._quitArmed = true
    say("Unsaved changes — quit again to discard")
    return true
  end
  return false
end

return App
