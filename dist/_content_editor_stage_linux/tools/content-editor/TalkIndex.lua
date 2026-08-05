-- Index of map object/sign TEXT_* bindings and their talk scripts
-- (mod overrides, vanilla MapScripts rows, or plain dialog / engine fallbacks).

local State = require("State")
local ModWriter = require("ModWriter")

local TalkIndex = {}

local scriptsOk = false
local scriptsTried = false

function TalkIndex.ensureScripts()
  if scriptsTried then return scriptsOk end
  scriptsTried = true
  local ok = pcall(require, "data.scripts.init")
  scriptsOk = ok
  return ok
end

local function mapRecord(S, mapId)
  if S.project and S.project.maps and S.project.maps[mapId] then
    return S.project.maps[mapId], true
  end
  if S.data and S.data.maps then return S.data.maps[mapId], false end
  return nil, false
end

local function pointerEntry(S, mapId, textId)
  if not textId then return nil end
  local label = State.mapLabel(S, mapId)
  local proj = S.project and S.project.text_pointers and S.project.text_pointers[label]
  if proj and proj[textId] then return proj[textId], true end
  local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
  return base and base[textId], false
end

local function resolveBody(S, strId)
  if not strId then return "" end
  if S.project and S.project.text and S.project.text[strId] ~= nil then
    return S.project.text[strId]
  end
  if S.data and S.data.text and S.data.text[strId] ~= nil then
    return S.data.text[strId]
  end
  return ""
end

local function findObject(S, mapId, textId)
  local map = mapRecord(S, mapId)
  if not map then return nil, nil end
  for i, obj in ipairs(map.objects or {}) do
    if obj.text == textId then return obj, i end
  end
  for i, sign in ipairs(map.signs or {}) do
    if sign.text == textId then return sign, i end
  end
  return nil, nil
end

local function talkRows(mapId, textId)
  TalkIndex.ensureScripts()
  local ok, MapScripts = pcall(require, "src.script.MapScripts")
  if not ok or not MapScripts then return nil end
  local rows = MapScripts.talkScript(mapId, textId)
  if rows == nil then rows = MapScripts.baseTalk(mapId, textId) end
  return rows
end

local function sourceBadge(S, mapId, textId)
  local key = mapId .. "/" .. textId
  if S.project and S.project.talkScripts and S.project.talkScripts[key] then
    return "mod"
  end
  local rows = talkRows(mapId, textId)
  if type(rows) == "function" then return "lua" end
  if type(rows) == "table" and #rows > 0 then return "script" end
  local obj = findObject(S, mapId, textId)
  if obj then
    if obj.item then return "item" end
    if obj.trainerClass or obj.trainer then return "trainer" end
    if obj.pokemon or obj.species then return "pokemon" end
  end
  local ptr = pointerEntry(S, mapId, textId)
  if ptr then
    if ptr.mart then return "shop" end
    if ptr.nurse then return "nurse" end
    if ptr.pc then return "pc" end
    if ptr.cableClub then return "cable" end
    if ptr.asm then return "asm" end
    if ptr.text then
      local body = resolveBody(S, ptr.text)
      if type(body) == "string" and body ~= "" then return "text" end
    end
  end
  return "empty"
end

-- Collect every talk-capable pin for a map: objects, signs, text_pointers,
-- vanilla talk keys, and mod talkScripts.
function TalkIndex.collect(S, mapId)
  if not mapId or mapId == "" then return {} end
  local entries, seen = {}, {}

  local function add(textId, kind, label, index)
    if not textId or textId == "" or seen[textId] then return end
    seen[textId] = true
    local src = sourceBadge(S, mapId, textId)
    entries[#entries + 1] = {
      key = mapId .. "/" .. textId,
      mapId = mapId,
      textId = textId,
      kind = kind,
      index = index,
      label = label or textId,
      source = src,
      attached = src ~= "empty",
    }
  end

  local map = mapRecord(S, mapId)
  if map then
    for i, obj in ipairs(map.objects or {}) do
      local tid = obj.text or ("TEXT_" .. mapId .. "_OBJ" .. i)
      add(tid, "object", string.format("NPC #%d %s", obj.index or i, obj.sprite or ""), i)
    end
    for i, sign in ipairs(map.signs or {}) do
      local tid = sign.text or ("TEXT_" .. mapId .. "_SIGN" .. i)
      add(tid, "sign", string.format("Sign #%d", i), i)
    end
  end

  local label = State.mapLabel(S, mapId)
  local function addPtrTable(ptrs)
    if not ptrs then return end
    local ids = {}
    for textId in pairs(ptrs) do ids[#ids + 1] = textId end
    table.sort(ids)
    for _, textId in ipairs(ids) do
      local entry = ptrs[textId]
      add(textId, "pointer", (entry and entry.label) or textId, nil)
    end
  end
  addPtrTable(S.data and S.data.text_pointers and S.data.text_pointers[label])
  addPtrTable(S.project and S.project.text_pointers and S.project.text_pointers[label])

  TalkIndex.ensureScripts()
  local ok, MapScripts = pcall(require, "src.script.MapScripts")
  if ok and MapScripts then
    local view = MapScripts.get(mapId)
    if view and view.talk then
      local ids = {}
      for textId in pairs(view.talk) do ids[#ids + 1] = textId end
      table.sort(ids)
      for _, textId in ipairs(ids) do
        add(textId, "script", textId, nil)
      end
    end
  end

  if S.project and S.project.talkScripts then
    local prefix = mapId .. "/"
    for key, script in pairs(S.project.talkScripts) do
      if key:sub(1, #prefix) == prefix then
        local tid = script.textId or key:sub(#prefix + 1)
        add(tid, "mod", tid, nil)
      end
    end
  end

  table.sort(entries, function(a, b)
    local ao = a.kind == "object" and 0 or a.kind == "sign" and 1 or 2
    local bo = b.kind == "object" and 0 or b.kind == "sign" and 1 or 2
    if ao ~= bo then return ao < bo end
    if (a.index or 0) ~= (b.index or 0) then
      return (a.index or 0) < (b.index or 0)
    end
    return a.textId < b.textId
  end)
  return entries
end

function TalkIndex.allMapIds(S)
  local seen, ids = {}, {}
  local function add(id)
    if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
  end
  if S.project then
    for id in pairs(S.project.maps or {}) do add(id) end
    for key in pairs(S.project.talkScripts or {}) do
      add(key:match("^([^/]+)/"))
    end
  end
  if S.data and S.data.maps then
    for id in pairs(S.data.maps) do add(id) end
  end
  TalkIndex.ensureScripts()
  local ok, MapScripts = pcall(require, "src.script.MapScripts")
  if ok and MapScripts then
    -- Prefer maps that actually have objects or scripts; still include all
    -- data maps so empty indoor maps stay browsable.
  end
  table.sort(ids)
  return ids
end

-- Build editor steps for a TEXT_* (does not write the project).
function TalkIndex.resolveSteps(S, mapId, textId)
  local key = mapId .. "/" .. textId
  local owned = S.project and S.project.talkScripts and S.project.talkScripts[key]
  if owned and type(owned.steps) == "table" then
    return owned.steps, { owned = true, source = "mod" }
  end

  local rows = talkRows(mapId, textId)
  if type(rows) == "function" then
    return {
      { kind = "raw", note = "Lua function handler (edit in Code / data/scripts)" },
    }, { owned = false, source = "lua", readOnly = true }
  end
  if type(rows) == "table" and #rows > 0 then
    return ModWriter.rowsToSteps(rows), {
      owned = false, source = "script", readOnly = true, rowCount = #rows,
    }
  end

  local obj = findObject(S, mapId, textId)
  if obj and obj.item then
    return {
      { kind = "raw", note = "Engine item-ball: " .. tostring(obj.item) },
    }, { owned = false, source = "item", readOnly = true }
  end
  if obj and (obj.trainerClass or obj.trainer) then
    return {
      {
        kind = "raw",
        note = "Engine trainer: " .. tostring(obj.trainerClass or obj.trainer)
          .. " party " .. tostring(obj.trainerParty or 1),
      },
    }, { owned = false, source = "trainer", readOnly = true }
  end
  if obj and (obj.pokemon or obj.species) then
    return {
      {
        kind = "raw",
        note = "Engine gift/static: " .. tostring(obj.pokemon or obj.species),
      },
    }, { owned = false, source = "pokemon", readOnly = true }
  end

  local ptr = pointerEntry(S, mapId, textId)
  if ptr and ptr.asm then
    return {
      { kind = "raw", note = "ASM/engine text (ported script may live under data/scripts)" },
    }, { owned = false, source = "asm", readOnly = true }
  end
  if ptr and (ptr.mart or ptr.nurse or ptr.pc or ptr.cableClub) then
    local role = ptr.mart and "shop" or ptr.nurse and "nurse" or ptr.pc and "pc" or "cable"
    return {
      { kind = "raw", note = "Engine " .. role .. " interaction" },
    }, { owned = false, source = role, readOnly = true }
  end
  if ptr and ptr.text then
    local body = resolveBody(S, ptr.text)
    if type(body) == "string" and body ~= "" then
      return {
        { kind = "show_text", text = body },
      }, { owned = false, source = "text", readOnly = true }
    end
  end

  return {}, { owned = false, source = "empty", readOnly = true }
end

-- Copy current resolved steps into project.talkScripts (mod override on Save).
function TalkIndex.cloneToProject(S, mapId, textId)
  State.ensureProjectFields(S.project)
  local key = mapId .. "/" .. textId
  if S.project.talkScripts[key] then return S.project.talkScripts[key] end
  local steps, meta = TalkIndex.resolveSteps(S, mapId, textId)
  local copy = {}
  for i, step in ipairs(steps or {}) do
    local sc = {}
    for k, v in pairs(step) do sc[k] = v end
    copy[i] = sc
  end
  if #copy == 0 then
    copy[1] = { kind = "show_text", text = "Hello!" }
  end
  local script = {
    mapId = mapId,
    textId = textId,
    steps = copy,
    _fromVanilla = meta and meta.source == "script" or nil,
  }
  S.project.talkScripts[key] = script
  return script
end

function TalkIndex.sourceLabel(src)
  local labels = {
    mod = "MOD",
    script = "SCRIPT",
    lua = "LUA",
    text = "TEXT",
    asm = "ASM",
    item = "ITEM",
    trainer = "TRAINER",
    pokemon = "MON",
    shop = "SHOP",
    nurse = "NURSE",
    pc = "PC",
    cable = "CABLE",
    empty = "—",
  }
  return labels[src] or tostring(src or "?")
end

return TalkIndex
