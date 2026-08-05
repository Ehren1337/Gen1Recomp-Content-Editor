-- AUDIO tab: music, cries, sfx, map_songs overrides + in-editor playback.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local ModIO = require("ModIO")
local PAL = Theme.PAL

local Audio = {}

local MODES = {
  { id = "music", label = "Music", tip = "Song registry (mod.content.music)" },
  { id = "cries", label = "Cries", tip = "Species cry overrides" },
  { id = "sfx", label = "SFX", tip = "Sound effect registry" },
  { id = "map_songs", label = "Map songs", tip = "Which song plays on each map" },
}

-- ---- Playback (file via love.audio; chip/ROM via Music / Sound) ----

local function mergeBucket(base, overlay)
  local out = {}
  for k, v in pairs(base or {}) do out[k] = v end
  for k, v in pairs(overlay or {}) do out[k] = v end
  return out
end

-- Data view with project.audio overlays so engine play sees unsaved edits.
local function previewData(S)
  local base = S.data or {}
  local ba = base.audio or {}
  local pa = (S.project and S.project.audio) or {}
  local audio = {}
  for k, v in pairs(ba) do audio[k] = v end
  audio.songs = mergeBucket(ba.songs, pa.songs)
  audio.cries = mergeBucket(ba.cries, pa.cries)
  audio.sfx = mergeBucket(ba.sfx, pa.sfx)
  audio.mapSongs = mergeBucket(ba.mapSongs, pa.mapSongs)
  return setmetatable({ audio = audio }, { __index = base })
end

local function sourceFromPath(S, path, mode)
  if type(path) ~= "string" or path == "" then return nil, "no file" end
  if not (love and love.audio and love.audio.newSource) then
    return nil, "no audio"
  end
  local resolved, kind = Preview.resolve(S, path)
  if not resolved then return nil, "missing file: " .. path end
  local typ = (mode == "music") and "stream" or "static"
  if kind == "love" then
    local ok, src = pcall(love.audio.newSource, resolved, typ)
    if ok and src then return src end
    return nil, tostring(src)
  end
  -- Absolute / mod disk path: feed bytes through FileData.
  local f, err = io.open(resolved, "rb")
  if not f then return nil, err or "cannot open" end
  local bytes = f:read("*a")
  f:close()
  if not bytes or #bytes == 0 then return nil, "empty file" end
  local name = resolved:match("[^/\\]+$") or "preview.ogg"
  local okFd, fileData = pcall(love.filesystem.newFileData, bytes, name)
  if not okFd or not fileData then return nil, tostring(fileData) end
  local ok, src = pcall(love.audio.newSource, fileData, typ)
  if ok and src then return src end
  return nil, tostring(src)
end

function Audio.stopPreview(S)
  if not S then return end
  local p = S.audioPreview
  if p and p.src then pcall(p.src.stop, p.src) end
  S.audioPreview = nil
  pcall(function() require("src.core.Music").stop() end)
end

function Audio.isPreviewPlaying(S)
  local p = S and S.audioPreview
  if not p then return false end
  if p.src then
    local ok, playing = pcall(p.src.isPlaying, p.src)
    if ok then return playing end
  end
  if p.engine == "music" then
    -- Chip/stream music: treat as playing until Stop (Music has no public current).
    return true
  end
  if p.engine == "sfx" or p.engine == "cry" then
    local ok, Sound = pcall(require, "src.core.Sound")
    if ok and Sound.isPlaying then
      return Sound.isPlaying(p.key)
    end
  end
  return false
end

function Audio.update(S, _dt)
  if not S or not S.audioPreview then return end
  local p = S.audioPreview
  if p.engine == "music" then
    pcall(function()
      require("src.core.Music").update(p.data or S.data)
    end)
  end
  if p.src then
    local ok, playing = pcall(p.src.isPlaying, p.src)
    if ok and not playing then
      S.audioPreview = nil
    end
  elseif p.engine == "sfx" or p.engine == "cry" then
    if not Audio.isPreviewPlaying(S) then
      S.audioPreview = nil
    end
  end
end

local function playFilePreview(S, path, opts)
  opts = opts or {}
  Audio.stopPreview(S)
  local src, err = sourceFromPath(S, path, opts.mode or "sfx")
  if not src then return false, err end
  if opts.loop then pcall(src.setLooping, src, true) end
  if opts.pitch and opts.pitch > 0 then
    -- Cry pitch byte ~128 = 1.0; map roughly like chip cries.
    local rate = opts.pitch / 128
    if rate < 0.25 then rate = 0.25 end
    if rate > 4 then rate = 4 end
    pcall(src.setPitch, src, rate)
  end
  pcall(src.play, src)
  S.audioPreview = {
    kind = "file", path = path, src = src,
    label = opts.label or path,
  }
  return true
end

local function playEngineMusic(S, songId)
  Audio.stopPreview(S)
  local data = previewData(S)
  local ok, err = pcall(function()
    local Music = require("src.core.Music")
    Music.reload()
    Music.play(data, songId, true, { reason = "preview" })
  end)
  if not ok then return false, err end
  S.audioPreview = {
    engine = "music", id = songId, data = data, label = songId,
  }
  return true
end

local function playEngineSfx(S, name)
  Audio.stopPreview(S)
  local data = previewData(S)
  local ok, Sound = pcall(require, "src.core.Sound")
  if not ok then return false, Sound end
  pcall(Sound.invalidate, name)
  local src = Sound.play(data, name)
  if not src then return false, "could not play SFX (chip/file missing?)" end
  S.audioPreview = {
    engine = "sfx", key = name, label = name,
  }
  return true
end

local function playEngineCry(S, species)
  Audio.stopPreview(S)
  local data = previewData(S)
  local ok, Sound = pcall(require, "src.core.Sound")
  if not ok then return false, Sound end
  local key = "cry:" .. tostring(species)
  pcall(Sound.invalidate, key)
  local src = Sound.playCry(data, species)
  if not src then return false, "could not play cry (chip/file missing?)" end
  S.audioPreview = {
    engine = "cry", key = key, label = species,
  }
  return true
end

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

function Audio.playPreview(S, mode, id)
  if not (S and id) then return false end
  State.ensureProjectFields(S.project)
  local rec = select(1, resolve(S, mode, id))
  local ok, err

  if mode == "map_songs" then
    local songId = tostring((S.project.audio.mapSongs and S.project.audio.mapSongs[id])
      or rec or "")
    if songId == "" then return false, "no song id" end
    local songRec = select(1, resolve(S, "music", songId))
    if type(songRec) == "table" and type(songRec.file) == "string" then
      ok, err = playFilePreview(S, songRec.file, {
        mode = "music", loop = true, label = songId,
      })
    else
      ok, err = playEngineMusic(S, songId)
    end
  elseif mode == "music" then
    if type(rec) == "table" and type(rec.file) == "string" and rec.file ~= "" then
      ok, err = playFilePreview(S, rec.file, {
        mode = "music", loop = true, label = id,
      })
    else
      ok, err = playEngineMusic(S, id)
    end
  elseif mode == "sfx" then
    if type(rec) == "table" and type(rec.file) == "string" and rec.file ~= "" then
      ok, err = playFilePreview(S, rec.file, { mode = "sfx", label = id })
    elseif type(rec) == "string" then
      ok, err = playFilePreview(S, rec, { mode = "sfx", label = id })
    else
      ok, err = playEngineSfx(S, id)
    end
  elseif mode == "cries" then
    if type(rec) == "table" and type(rec.file) == "string" and rec.file ~= "" then
      ok, err = playFilePreview(S, rec.file, {
        mode = "sfx", label = id,
        pitch = tonumber(rec.pitch) or 128,
      })
    else
      ok, err = playEngineCry(S, id)
    end
  else
    return false, "unknown mode"
  end

  if not ok and S then
    S.status = "Audio: " .. tostring(err or "play failed")
  elseif ok and S then
    local label = (S.audioPreview and S.audioPreview.label) or id
    S.status = "Playing " .. tostring(label)
  end
  return ok, err
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

  do
    local playing = Audio.isPreviewPlaying(S)
    local label = playing and (S.audioPreview and S.audioPreview.label) or nil
    local bw = 88 * s
    if Kit.button(viewX, fy, bw, fh, playing and "Stop" or "Play", {
        kind = playing and "danger" or "primary",
        tooltip = playing and "Stop preview" or "Preview this audio",
      }) then
      if playing then
        Audio.stopPreview(S)
        S.status = "Audio stopped"
      else
        Audio.playPreview(S, mode, id)
      end
    end
    if playing and label then
      Kit.text("micro", "♪ " .. Kit.ellipsize("micro", tostring(label), viewW - bw - 16 * s),
        viewX + bw + 10 * s, fy + 8 * s, PAL.green)
    else
      Kit.text("micro", "file / chip preview",
        viewX + bw + 10 * s, fy + 8 * s, PAL.faint)
    end
    fy = fy + fh + 10 * s
  end

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
