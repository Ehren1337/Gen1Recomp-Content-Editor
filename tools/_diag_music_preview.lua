-- love . tools/_diag_music_preview.lua  (or: love . --diag-music)
-- One-shot: mount gold cache like the content editor and try chip music.

local function say(...)
  print(...)
  io.stdout:flush()
end

function love.load()
  love.filesystem.setIdentity("pokemon-love2d")
  say("identity", love.filesystem.getIdentity())
  say("save", love.filesystem.getSaveDirectory())

  local GameVersion = require("src.core.GameVersion")
  GameVersion.set("gold")
  say("prefix", GameVersion.cachePrefix())

  local CacheFs = require("src.import.CacheFs")
  pcall(CacheFs.mountVersion, "gold")

  local paths = {
    "assets/generated/audio/programs.bin",
    "gold/assets/generated/audio/programs.bin",
  }
  for _, p in ipairs(paths) do
    local info = love.filesystem.getInfo(p)
    local raw = love.filesystem.read(p)
    say("fs", p, info and info.size or "missing", raw and #raw or "nil")
  end

  local okCf, bytes = pcall(CacheFs.readActive, "assets/generated/audio/programs.bin")
  say("CacheFs.readActive", okCf, type(bytes) == "string" and #bytes or bytes)

  -- Load audio.lua the way Data does when possible
  local audio
  local okA, mod = pcall(require, "data.generated.audio")
  if okA and type(mod) == "table" then
    audio = mod
    say("audio via require", "ok", audio.bankOrder and #audio.bankOrder)
  else
    say("audio require failed", mod)
    local chunk = love.filesystem.read("data/generated/audio.lua")
      or love.filesystem.read("gold/data/generated/audio.lua")
    if chunk then
      audio = assert(load(chunk, "audio.lua"))()
      say("audio via read+load", audio.bankOrder and #audio.bankOrder)
    end
  end
  if not audio then
    say("FATAL: no audio table")
    love.event.quit(1)
    return
  end

  audio.programPrefix = GameVersion.cachePrefix()
  local data = { audio = audio }
  local song = audio.songs and audio.songs.Music_NewBarkTown
  say("song", song and song.bank, song and song.address)

  local ChipSynth = require("src.core.ChipSynth")
  ChipSynth.invalidateBanks()
  local okB, banks = pcall(ChipSynth._loadBanksForTest, data)
  say("loadBanks", okB, okB and "ok" or banks)

  local okE, eng = pcall(ChipSynth.newEngine, data, song, { allowLoops = true })
  say("newEngine", okE, okE and "ok" or eng)

  say("newQueueableSource", type(love.audio.newQueueableSource))

  local ChipAudio = require("src.core.ChipAudio")
  ChipAudio.forceSyncMusic = true
  local src, err = ChipAudio.playMusic(data, song, true)
  say("playMusicSync", src and "src" or "nil", err)

  if not src then
    local src2, err2 = ChipAudio.previewMusic(data, song, 1)
    say("previewMusic1s", src2 and "src" or "nil", err2)
  end

  local Music = require("src.core.Music")
  Music.reload()
  local played, playErr = Music.play(data, "Music_NewBarkTown", true, { reason = "preview" })
  say("Music.play", played, playErr)

  love.event.quit(played and 0 or 2)
end
