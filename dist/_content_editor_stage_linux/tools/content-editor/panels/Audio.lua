-- AUDIO tab: music, cries, sfx, map_songs overrides.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local ModIO = require("ModIO")
local PAL = Theme.PAL

local Audio = {}

local MODES = {
  { id = "music", label = "Music", tip = "Song registry (mod.content.music)" },
  { id = "cries", label = "Cries", tip = "Species cry overrides" },
  { id = "sfx", label = "SFX", tip = "Sound effect registry" },
  { id = "map_songs", label = "Map songs", tip = "Which song plays on each map" },
}

local function audioRoot(S)
  return S.data and S.data.audio
end

local function projectBucket(S, mode)
  State.ensureProjectFields(S.project)
  S.project.audio = S.project.audio or {}
  if mode == "music" then
    S.project.audio.songs = S.project.audio.songs or {}
    return S.project.audio.songs
  elseif mode == "cries" then
    S.project.audio.cries = S.project.audio.cries or {}
    return S.project.audio.cries
  elseif mode == "sfx" then
    S.project.audio.sfx = S.project.audio.sfx or {}
    return S.project.audio.sfx
  end
  S.project.audio.mapSongs = S.project.audio.mapSongs or {}
  return S.project.audio.mapSongs
end

local function dataBucket(S, mode)
  local a = audioRoot(S)
  if not a then return {} end
  if mode == "music" then return a.songs or {} end
  if mode == "cries" then return a.cries or {} end
  if mode == "sfx" then return a.sfx or {} end
  return a.mapSongs or {}
end

local function resolve(S, mode, id)
  local p = projectBucket(S, mode)
  if p[id] ~= nil then return p[id], true end
  local d = dataBucket(S, mode)
  if d[id] ~= nil then return d[id], false end
  return nil, false
end

local function summarize(rec, mode)
  if mode == "map_songs" then return tostring(rec or "") end
  if type(rec) == "string" then return rec end
  if type(rec) ~= "table" then return "?" end
  if rec.file then return "file " .. tostring(rec.file) end
  if rec.chip then return "chip" end
  if rec.address then return string.format("ROM %s:%s", tostring(rec.bank), tostring(rec.address)) end
  if rec.base then return "base " .. tostring(rec.base) end
  return "record"
end

function Audio.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  local modeY = RegList.modeChips(S, "audioMode", MODES, x, y, s)
  local mode = S.audioMode or "music"
  local proj = projectBucket(S, mode)
  local data = dataBucket(S, mode)
  local ids
  if mode == "map_songs" then
    -- map ids from data.maps + project
    ids = RegList.mergeIds(S.project.maps, S.data and S.data.maps)
    -- also include existing mapSongs keys
    for id in pairs(proj) do
      local found = false
      for _, m in ipairs(ids) do if m == id then found = true; break end end
      if not found then ids[#ids + 1] = id end
    end
    for id in pairs(data) do
      local found = false
      for _, m in ipairs(ids) do if m == id then found = true; break end end
      if not found then ids[#ids + 1] = id end
    end
    table.sort(ids)
  else
    ids = RegList.mergeIds(proj, data)
  end

  local selKey = "audioId_" .. mode
  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w, h - (modeY - y),
    mode:upper():gsub("_", " "), ids, {
      queryKey = "audioQuery",
      offsetKey = "audioListOffset",
      selKey = selKey,
      accent = PAL.blue,
      isOwned = function(id) return proj[id] ~= nil end,
      filter = function(id, q)
        local ql = q:lower()
        if id:lower():find(ql, 1, true) then return true end
        local rec = select(1, resolve(S, mode, id))
        return tostring(summarize(rec, mode)):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = mode == "map_songs" and nil or "+ New",
      onFooter = function()
        local nid = "MOD_" .. mode:upper() .. "_1"
        local n = 1
        while proj[nid] or data[nid] do
          n = n + 1
          nid = "MOD_" .. mode:upper() .. "_" .. n
        end
        if mode == "music" or mode == "sfx" then
          proj[nid] = { file = "assets/" .. nid:lower() .. ".ogg" }
        elseif mode == "cries" then
          proj[nid] = { file = "assets/" .. nid:lower() .. ".ogg", pitch = 128, length = 128 }
        end
        S[selKey] = nid
        App.markDirty()
      end,
    })

  if not S[selKey] then S[selKey] = shown[1] end
  local id = S[selKey]
  local rec, owned = resolve(S, mode, id)
  if not id then
    Kit.emptyBox(formX, listY, formW, listH, "No audio data (import ROM cache for songs/cries)")
    return
  end

  Kit.caption(formX, modeY - 32 * s + 22 * s,
    (id or "?") .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "audioFormScroll", mode .. "|" .. tostring(id), owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 110 * s
  local fh = 28 * s
  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  local function ensure()
    if owned then return proj[id] end
    local copy
    if mode == "map_songs" then
      copy = tostring(rec or "Music_PalletTown")
    elseif type(rec) == "string" then
      copy = { file = rec }
    elseif type(rec) == "table" then
      copy = {}
      for k, v in pairs(rec) do copy[k] = v end
    else
      copy = { file = "assets/sound.ogg" }
    end
    proj[id] = copy
    owned = true
    App.markDirty()
    return copy
  end

  Kit.text("micro", summarize(rec, mode), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  if mode == "map_songs" then
    row("Song id", function(fx, fy_, fw, fh_)
      local cur = tostring((owned and proj[id]) or rec or "")
      local songs = RegList.sortedKeys((audioRoot(S) and audioRoot(S).songs) or {})
      if #songs == 0 then songs = { "Music_PalletTown", "Music_Cities1", "Music_Gym" } end
      -- include project songs
      for sid in pairs(projectBucket(S, "music")) do
        local found = false
        for _, e in ipairs(songs) do if e == sid then found = true; break end end
        if not found then songs[#songs + 1] = sid end
      end
      table.sort(songs)
      if Kit.button(fx, fy_, fw, fh_, Kit.ellipsize("small", cur ~= "" and cur or "(none)", fw - 8 * s),
          { kind = "ghost" }) then
        local nextId = RegList.cycle(songs, cur)
        proj[id] = nextId
        owned = true
        App.markDirty()
      end
    end)
    row("Or type", function(fx, fy_, fw, fh_)
      local cur = tostring((owned and proj[id]) or rec or "")
      local v = RegList.field(App, "au_ms", fx, fy_, fw, fh_, cur, "Music_...")
      if v ~= cur then
        proj[id] = v
        owned = true
      end
    end)
  else
    local r = type(rec) == "table" and rec or {}
    row("File", function(fx, fy_, fw, fh_)
      local path = (owned and type(proj[id]) == "table" and proj[id].file)
        or r.file or (type(rec) == "string" and rec) or ""
      Kit.text("micro", Kit.ellipsize("micro", path ~= "" and path or "(ROM/chip)", fw - 100 * s),
        fx, fy_ + 8 * s, PAL.muted)
      if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Browse", {
          kind = "ghost", tooltip = "Import an audio file into the mod",
        }) then
        ensure()
        local aid, amode = id, mode
        App.pickFile("Audio file", "Audio|*.ogg;*.wav;*.mp3|All|*.*",
          function(picked)
            local bucket = projectBucket(S, amode)
            local e = bucket[aid]
            if type(e) ~= "table" then
              e = { file = "" }
              bucket[aid] = e
            end
            App.importToMod(picked, nil, function(rel)
              e.file = rel
              e.address, e.bank, e.chip = nil, nil, nil
            end)
          end)
      end
    end)
    if mode == "cries" then
      row("Pitch", function(fx, fy_, fw, fh_)
        local e = owned and proj[id] or r
        local cur = (type(e) == "table" and e.pitch) or 128
        local v = RegList.num(App, "au_pitch", fx, fy_, 80 * s, fh_, cur)
        if v ~= cur then
          e = ensure()
          if type(e) == "table" then e.pitch = v end
        end
      end)
      row("Length", function(fx, fy_, fw, fh_)
        local e = owned and proj[id] or r
        local cur = (type(e) == "table" and e.length) or 128
        local v = RegList.num(App, "au_len", fx, fy_, 80 * s, fh_, cur)
        if v ~= cur then
          e = ensure()
          if type(e) == "table" then e.length = v end
        end
      end)
    end
    if not owned then
      Kit.text("micro", "Edit clones into the mod (Save emits audio override).",
        viewX, fy, PAL.faint)
      fy = fy + 18 * s
      if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
        ensure()
      end
      fy = fy + fh + 8 * s
    end
  end

  FormPane.finish(S, "audioFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    proj[id] = nil
    App.markDirty()
  end
end

return Audio
