-- Undo/redo for content-editor project mutations.
--
-- Panels mutate during love.draw (immediate-mode UI) and then call
-- App.markDirty().  We keep a baseline snapshot of the project from the end
-- of the previous frame; the first dirty mark in a frame pushes that baseline
-- onto the undo stack.  Rapid edits (typing) coalesce within COALESCE_SEC so
-- one undo step reverts a burst of keystrokes.

local History = {}

local MAX_STACK = 60
local COALESCE_SEC = 0.55

local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, val in pairs(v) do
    out[deepCopy(k, seen)] = deepCopy(val, seen)
  end
  return out
end

local function ensureProject(project)
  local ok, State = pcall(require, "State")
  if ok and State.ensureProjectFields then
    return State.ensureProjectFields(deepCopy(project))
  end
  return deepCopy(project)
end

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

-- Map paint mutates project.maps[id] and aliases it into S.data.maps[id].
-- Restoring only S.project would leave the painted live map on screen and make
-- a second Undo report "Nothing to undo".  Re-bind live data from the project
-- (or the pre-edit vanilla backup) after every history restore.
local function syncLiveMaps(S)
  if not (S and S.data and S.data.maps) then return end
  local projectMaps = (S.project and S.project.maps) or {}
  local backup = S._vanillaMapBackup or {}
  for id, def in pairs(projectMaps) do
    S.data.maps[id] = def
  end
  for id, vanilla in pairs(backup) do
    if not projectMaps[id] then
      S.data.maps[id] = vanilla
    end
  end
end

local function restore(S, snapshot)
  S.project = ensureProject(snapshot)
  S._histBaseline = deepCopy(S.project)
  S._histDirtyFrame = false
  S._histLastPush = nil
  S.dirty = true
  S._mapCenteredFor = nil
  S._mapNeedsRebuild = S.mapId
  syncLiveMaps(S)
  local ok, MapLoader = pcall(require, "src.world.MapLoader")
  if ok and MapLoader and MapLoader.invalidateAll then
    MapLoader.invalidateAll()
  end
end

function History.clear(S)
  if not S then return end
  S.undoStack = {}
  S.redoStack = {}
  S._histBaseline = S.project and deepCopy(S.project) or nil
  S._histDirtyFrame = false
  S._histLastPush = nil
  S._histLastTab = nil
end

function History.beginFrame(S)
  if not S then return end
  S._histDirtyFrame = false
  if S.project and not S._histBaseline then
    S._histBaseline = deepCopy(S.project)
  end
end

function History.noteDirty(S)
  if not (S and S.project) then return end
  if S._histDirtyFrame then return end
  S._histDirtyFrame = true

  local t = now()
  local coalesce = S._histLastPush
    and (t - S._histLastPush) < COALESCE_SEC
    and S._histLastTab == S.tab
    and #(S.undoStack or {}) > 0

  if coalesce then
    S._histLastPush = t
    return
  end

  S.undoStack = S.undoStack or {}
  -- Always copy: the baseline table is replaced later, but nested aliases
  -- must not be shared with the live project after the push.
  S.undoStack[#S.undoStack + 1] = deepCopy(S._histBaseline or S.project)
  while #S.undoStack > MAX_STACK do
    table.remove(S.undoStack, 1)
  end
  S.redoStack = {}
  S._histLastPush = t
  S._histLastTab = S.tab
end

function History.endFrame(S)
  if not (S and S.project) then return end
  if S._histDirtyFrame or not S._histBaseline then
    S._histBaseline = deepCopy(S.project)
  end
end

function History.canUndo(S)
  return S and S.undoStack and #S.undoStack > 0
end

function History.canRedo(S)
  return S and S.redoStack and #S.redoStack > 0
end

function History.undo(S)
  if not History.canUndo(S) then return false end
  S.redoStack = S.redoStack or {}
  S.redoStack[#S.redoStack + 1] = deepCopy(S.project)
  local prev = table.remove(S.undoStack)
  restore(S, prev)
  return true
end

function History.redo(S)
  if not History.canRedo(S) then return false end
  S.undoStack = S.undoStack or {}
  S.undoStack[#S.undoStack + 1] = deepCopy(S.project)
  local nxt = table.remove(S.redoStack)
  restore(S, nxt)
  return true
end

return History
