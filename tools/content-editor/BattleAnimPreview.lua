-- In-editor battle move animation preview (AnimPlayer @ 160×144, scaled).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local PAL = Theme.PAL

local BattleAnimPreview = {}

local GB_W, GB_H = 160, 144

local function stripEditor(rec)
  if type(rec) ~= "table" then return rec end
  local out = {}
  for k, v in pairs(rec) do
    if type(k) == "string" and k:sub(1, 1) ~= "_" then
      out[k] = v
    end
  end
  return out
end

local function copyMap(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

-- Merge vanilla battle_anims with project.battle_anims overrides.
function BattleAnimPreview.buildData(S)
  local root = S and S.data and S.data.battle_anims
  if type(root) ~= "table" then return nil end
  local data = {
    moveAnims = copyMap(root.moveAnims),
    subanims = copyMap(root.subanims),
    tilesheets = copyMap(root.tilesheets),
    frameBlocks = root.frameBlocks or {},
    baseCoords = root.baseCoords or {},
  }
  State.ensureProjectFields(S.project)
  for id, rec in pairs(S.project.battle_anims or {}) do
    if type(rec) == "table" then
      local clean = stripEditor(rec)
      local kind, index = tostring(id):match("^(%a+):(%d+)$")
      if kind == "subanim" then
        data.subanims[tonumber(index)] = clean
      elseif kind == "tilesheet" then
        data.tilesheets[tonumber(index)] = clean
      else
        data.moveAnims[id] = clean
      end
    end
  end
  return data
end

function BattleAnimPreview.hasAnim(S, moveId)
  if not moveId then return false end
  local data = BattleAnimPreview.buildData(S)
  local anim = data and data.moveAnims and data.moveAnims[moveId]
  return type(anim) == "table" and type(anim.seq) == "table"
end

function BattleAnimPreview.stop(S)
  if not S then return end
  local p = S.battleAnimPreview
  if p and p.player and p.player.release then
    pcall(p.player.release, p.player)
  end
  S.battleAnimPreview = nil
end

function BattleAnimPreview.isPlaying(S)
  local p = S and S.battleAnimPreview
  return p and p.playing and p.player and not p.player:isDone()
end

function BattleAnimPreview.start(S, moveId, opts)
  opts = opts or {}
  if not (S and moveId) then return false end
  local data = BattleAnimPreview.buildData(S)
  if not data or not data.moveAnims[moveId] then
    S.status = "No battle anim for " .. tostring(moveId)
    return false
  end
  local okAp, AnimPlayer = pcall(require, "src.battle.AnimPlayer")
  if not okAp then
    S.status = "AnimPlayer unavailable"
    return false
  end
  BattleAnimPreview.stop(S)
  local player = AnimPlayer.new(data)
  local attackerIsPlayer = not S.battleAnimPreviewEnemy
  if opts.enemy == true then attackerIsPlayer = false end
  if opts.enemy == false then attackerIsPlayer = true end
  pcall(player.start, player, moveId, attackerIsPlayer, opts)
  if not player.steps or #player.steps == 0 then
    S.status = "Empty anim sequence for " .. tostring(moveId)
    pcall(player.release, player)
    return false
  end
  S.battleAnimPreview = {
    player = player,
    moveId = moveId,
    data = data,
    accum = 0,
    playing = true,
    loop = S.battleAnimPreviewLoop ~= false,
    attackerIsPlayer = attackerIsPlayer,
    flash = 0,
  }
  S.status = "Previewing " .. tostring(moveId)
  return true
end

function BattleAnimPreview.update(S, dt)
  local p = S and S.battleAnimPreview
  if not p or not p.playing or not p.player then return end
  p.accum = (p.accum or 0) + (dt or 0)
  local frames = math.floor(p.accum * 60)
  if frames < 1 then return end
  p.accum = p.accum - frames / 60
  if frames > 5 then frames = 5 end
  for _ = 1, frames do
    if (p.flash or 0) > 0 then p.flash = p.flash - 1 end
    pcall(p.player.update, p.player)
    local ok, fired = pcall(p.player.pollEffects, p.player)
    if ok and type(fired) == "table" then
      for _, ev in ipairs(fired) do
        local eff = tostring(ev.effect or "")
        if eff:find("FLASH", 1, true) or eff == "SE_DARK_SCREEN_FLASH" then
          p.flash = 4
        end
      end
    end
    if p.player:isDone() then
      local loop = S.battleAnimPreviewLoop ~= false
      if loop then
        pcall(p.player.start, p.player, p.moveId, p.attackerIsPlayer)
        if not p.player.steps or #p.player.steps == 0 then
          p.playing = false
          break
        end
      else
        p.playing = false
        break
      end
    end
  end
end

-- Draw controls + scaled GB viewport. Returns y below the widget.
function BattleAnimPreview.draw(S, moveId, x, y, w, s)
  s = s or Kit.scale
  local fh = 28 * s
  Kit.text("small", "Animation preview", x, y, PAL.caption)
  y = y + 18 * s

  local p = S.battleAnimPreview
  if p and p.moveId ~= moveId then
    BattleAnimPreview.stop(S)
    p = nil
  end
  local active = p and p.moveId == moveId
  local playing = active and p.playing

  if Kit.chip(x, y, 72 * s, fh, playing and "STOP" or "PLAY",
      playing, PAL.green) then
    if playing then
      BattleAnimPreview.stop(S)
      S.status = "Anim preview stopped"
    else
      BattleAnimPreview.start(S, moveId)
    end
    p = S.battleAnimPreview
    active = p and p.moveId == moveId
    playing = active and p.playing
  end

  local loop = S.battleAnimPreviewLoop ~= false
  if Kit.chip(x + 80 * s, y, 72 * s, fh, loop and "LOOP" or "ONCE",
      loop, PAL.blue) then
    S.battleAnimPreviewLoop = not loop
    if active and p then p.loop = S.battleAnimPreviewLoop ~= false end
  end

  local enemy = S.battleAnimPreviewEnemy and true or false
  if Kit.chip(x + 160 * s, y, 100 * s, fh, enemy and "ENEMY" or "PLAYER",
      enemy, PAL.yellow, nil, "Attacker side (transforms subanims)") then
    S.battleAnimPreviewEnemy = not enemy
    if active and playing then
      BattleAnimPreview.start(S, moveId)
      p = S.battleAnimPreview
      active = p and p.moveId == moveId
    end
  end

  y = y + fh + 8 * s

  local maxScale = math.max(1, math.floor((w - 8 * s) / GB_W))
  local scale = math.min(maxScale, math.max(2, math.floor(2 * s)))
  local vw, vh = GB_W * scale, GB_H * scale

  Theme.col(PAL.cardBody or PAL.card, 1)
  love.graphics.rectangle("fill", x, y, vw + 8 * s, vh + 8 * s, 8 * s, 8 * s)

  local vx, vy = x + 4 * s, y + 4 * s
  Kit.pushClip(vx, vy, vw, vh)
  love.graphics.push()
  love.graphics.translate(vx, vy)
  love.graphics.scale(scale, scale)

  -- Simple battle stage (not full HUD — just anchors for OAM).
  love.graphics.setColor(0.18, 0.28, 0.22, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  love.graphics.setColor(0.22, 0.38, 0.28, 1)
  love.graphics.rectangle("fill", 0, 88, GB_W, 56)
  -- Enemy / player pic stand-ins
  love.graphics.setColor(0.75, 0.35, 0.32, 1)
  love.graphics.rectangle("fill", 96, 8, 56, 56)
  love.graphics.setColor(0.32, 0.42, 0.78, 1)
  love.graphics.rectangle("fill", 8, 64, 56, 56)

  if active and p and p.player then
    love.graphics.setColor(1, 1, 1, 1)
    pcall(p.player.draw, p.player)
    if (p.flash or 0) > 0 then
      love.graphics.setColor(1, 1, 1, 0.55)
      love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    end
  else
    love.graphics.setColor(1, 1, 1, 0.35)
  end

  love.graphics.pop()
  Kit.popClip()

  local info
  if not BattleAnimPreview.hasAnim(S, moveId) then
    info = "no anim data for this move"
  elseif active and p then
    local step = p.player and p.player.stepIndex or 0
    local total = p.player and p.player.steps and #p.player.steps or 0
    info = string.format("%s · step %d/%d%s",
      tostring(moveId), step, total, playing and "" or " · done")
  else
    info = "Press PLAY · needs ROM battle_anims + tilesheets"
  end
  Kit.text("micro", Kit.ellipsize("micro", info, w), x, y + vh + 12 * s, PAL.muted)

  return y + vh + 28 * s
end

return BattleAnimPreview
