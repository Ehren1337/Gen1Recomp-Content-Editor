-- In-editor UI screen preview (160×144 GB viewport): title drop/cycle,
-- intro splash, theme boxes, fonts/strings/town map/badges/boot cards.
-- Does not instantiate TitleState / IntroMovie (they need a full game).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Preview = require("Preview")
local PAL = Theme.PAL

local UiPreview = {}

local GB_W, GB_H = 160, 144
local CYCLE_FRAMES = 240
local DROP_STEPS = {
  { -4, 16 }, { 3, 4 }, { -3, 4 }, { 2, 2 }, { -2, 2 }, { 1, 2 }, { -1, 2 },
}

-- IntroMovie phase-2 timeline (frames from splash start)
local COPYRIGHT_FRAMES = 180
local STAR_START = 64
local STAR_FRAMES = 40
local FLASH_START = STAR_START + STAR_FRAMES
local FLASH_FRAMES = 30
local WAVES_START = FLASH_START + FLASH_FRAMES
local WAVE_FRAMES = 24
local WAVES_END = WAVES_START + 6 * WAVE_FRAMES
local SPLASH_FRAMES = WAVES_END + 40
local STUDIO_BOX = { w = 128, h = 52, cx = 80, cy = 60 }
local STAR_WAVES = {
  { 40, 56, 80, 112 },
  { 48, 64, 88, 104 },
  { 44, 68, 76, 92 },
  { 52, 84, 100, 108 },
}

local THEME_DEFAULTS = {
  cursor = 0xED, cursorHollow = 0xEC, moreArrow = 0xEE,
  textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 },
  choiceBox = { tx = 14, ty = 7, tw = 6, th = 5 },
}

local BOOT_DEFAULTS = {
  splash = "IntroMovie", title = "TitleState", newGame = "OakSpeech",
}

-- ---- path / field helpers ----

local function pathOf(v)
  if type(v) == "table" then return tostring(v.path or "") end
  if type(v) == "string" then return v end
  return ""
end

local function dataField(S, key)
  return (S.data and S.data.field and S.data.field[key]) or {}
end

local function eff(S, bucket, key)
  local p = S.project and S.project[bucket]
  if p ~= nil and p[key] ~= nil then return p[key] end
  return dataField(S, bucket)[key]
end

local function img(S, path)
  if not path or path == "" then return nil end
  return Preview.image(S, path)
end

local function ensureFont(S)
  if S._uiPreviewFontLoaded then return true end
  if not (S.data and S.data.font) then return false end
  local ok = pcall(function()
    require("src.render.Font").load(S.data)
  end)
  S._uiPreviewFontLoaded = ok
  return ok
end

local function applyTheme(S)
  ensureFont(S)
  local EngTheme = require("src.ui.Theme")
  -- Reset to engine defaults then merge data + project theme.
  EngTheme.cursor = 0xED
  EngTheme.cursorHollow = 0xEC
  EngTheme.moreArrow = 0xEE
  EngTheme.textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 }
  EngTheme.choiceBox = { tx = 14, ty = 7, tw = 6, th = 5 }
  local merged = {}
  local d = dataField(S, "theme")
  local p = (S.project and S.project.theme) or {}
  for k, v in pairs(d) do merged[k] = v end
  for k, v in pairs(p) do
    if type(v) == "table" and type(merged[k]) == "table" then
      local sub = {}
      for sk, sv in pairs(merged[k]) do sub[sk] = sv end
      for sk, sv in pairs(v) do sub[sk] = sv end
      merged[k] = sub
    else
      merged[k] = v
    end
  end
  if next(merged) then
    pcall(function()
      require("src.mods.Merge").deepMerge(EngTheme, merged)
    end)
  end
  return EngTheme
end

local function resolveStr(S, source)
  local p = S.project and S.project.strings and S.project.strings[source]
  if type(p) == "string" and p ~= "" then return p end
  local d = S.data and S.data.strings and S.data.strings[source]
  if type(d) == "string" and d ~= "" then return d end
  return source
end

-- ---- title driver ----

local function buildTitle(S)
  local logoPath = pathOf(eff(S, "title", "logo"))
  if logoPath == "" then logoPath = "assets/logo/pokemon_logo.png" end
  local verPath = pathOf(eff(S, "title", "versionRibbon") or eff(S, "title", "version"))
  if verPath == "" then verPath = "assets/generated/title/red_version.png" end
  local layout = eff(S, "title", "layout")
  local yellow = layout == "yellow_pikachu"
  local cycle = eff(S, "title", "cycleSpecies")
  if type(cycle) ~= "table" or #cycle == 0 then
    cycle = yellow and { "PIKACHU" }
      or { "CHARIZARD", "VENUSAUR", "BLASTOISE", "PIKACHU" }
  end
  local pikaPath = pathOf(eff(S, "title", "pikachu"))
  if pikaPath == "" then pikaPath = "assets/generated/title/pikachu.png" end
  local bubblePath = pathOf(eff(S, "title", "pikaBubble"))
  if bubblePath == "" then bubblePath = "assets/generated/title/pika_bubble.png" end

  local st = {
    kind = "title",
    logo = img(S, logoPath),
    version = img(S, verPath),
    player = img(S, "assets/generated/title/player.png"),
    yellow = yellow,
    yellowPikachu = yellow and img(S, pikaPath) or nil,
    yellowBubble = yellow and img(S, bubblePath) or nil,
    eyesHalf = yellow and img(S, "assets/generated/title/eyes_half.png") or nil,
    eyesClosed = yellow and img(S, "assets/generated/title/eyes_closed.png") or nil,
    copyrightText = tostring(eff(S, "title", "copyrightText") or "2026 bois club games"),
    cycleSpecies = cycle,
    cycleIndex = 1,
    sprites = {},
    timer = 0,
    blink = 0,
    slideIn = 0,
    phase = yellow and "drop" or "loop",
    scy = yellow and 0x40 or 0,
    dropStep = 1,
    dropLeft = nil,
    showBubble = not yellow,
    blinkTimer = 0,
    blinkAt = nil,
    data = S.data,
  }
  st.yellowLayout = yellow and st.yellowPikachu ~= nil
  if not st.yellowLayout then
    st.phase = "loop"
    st.showBubble = true
    st.scy = 0
  end
  return st
end

local function titleSprite(st, S)
  local species = st.cycleSpecies[st.cycleIndex]
  local cached = st.sprites[species]
  if cached == nil then
    local path
    local ok, Sprites = pcall(require, "src.pokemon.Sprites")
    if ok and S.data then
      path = select(1, Sprites.path(S.data, species, "front", { kind = "title" }))
    end
    local image = path and img(S, path) or nil
    cached = image or false
    st.sprites[species] = cached
  end
  return cached or nil
end

local function updateTitle(st)
  if st.yellowLayout then
    if st.phase == "drop" then
      local step = DROP_STEPS[st.dropStep]
      if not step then
        st.phase = "settle"
        st.timer = 0
        return
      end
      if st.dropLeft == nil then st.dropLeft = step[2] end
      st.scy = st.scy + step[1]
      st.dropLeft = st.dropLeft - 1
      if st.dropLeft <= 0 then
        st.dropStep = st.dropStep + 1
        st.dropLeft = nil
      end
    elseif st.phase == "settle" then
      st.timer = st.timer + 1
      if st.timer >= 36 then
        st.showBubble = true
        st.phase = "bubble"
        st.timer = 0
      end
    elseif st.phase == "bubble" then
      st.timer = st.timer + 1
      if st.timer >= 3 then
        st.phase = "loop"
        st.blinkTimer = 0
      end
    else
      local t = st.blinkTimer
      st.blinkTimer = (t + 1) % 256
      if t == 0 or t == 0x80 or t == 0x90 then st.blinkAt = 0 end
      if st.blinkAt then
        st.blinkAt = st.blinkAt + 1
        if st.blinkAt > 9 then st.blinkAt = nil end
      end
    end
    return
  end
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 60
  if st.timer >= CYCLE_FRAMES then
    st.timer = 0
    if #st.cycleSpecies > 1 then
      st.cycleIndex = (st.cycleIndex % #st.cycleSpecies) + 1
    end
    st.slideIn = 20
  end
  if st.slideIn and st.slideIn > 0 then st.slideIn = st.slideIn - 1 end
end

local function drawTitleFrame(st, S)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local scrollY = st.yellowLayout and -(st.scy or 0) or 0
  if st.logo then
    love.graphics.draw(st.logo, 16, 8 + scrollY)
  else
    love.graphics.setColor(0.1, 0.1, 0.15, 1)
    love.graphics.rectangle("fill", 24, 16 + scrollY, 112, 40)
  end
  if st.yellowLayout then
    local dy = scrollY
    if st.yellowBubble and st.showBubble then
      love.graphics.draw(st.yellowBubble, 48, 32 + dy)
    end
    if st.yellowPikachu then
      love.graphics.draw(st.yellowPikachu, 32, 64 + dy)
    end
    local overlay
    if st.blinkAt then
      if st.blinkAt <= 3 or st.blinkAt > 6 then
        overlay = st.eyesHalf
      else
        overlay = st.eyesClosed
      end
    end
    if overlay then love.graphics.draw(overlay, 56, 80 + dy) end
  else
    if st.version then
      local iw, ih = st.version:getDimensions()
      local ok, q = pcall(love.graphics.newQuad, 0, 0, math.min(96, iw), math.min(8, ih), iw, ih)
      if ok and q then
        love.graphics.draw(st.version, q, 56, 64)
      else
        love.graphics.draw(st.version, 56, 64)
      end
    end
    local sprite = titleSprite(st, S)
    if sprite then
      local w, h = sprite:getDimensions()
      local slide = (st.slideIn or 0) * 8
      local x = 40 + math.floor((56 - w) / 2) + slide
      local y = 136 - h
      love.graphics.draw(sprite, x, y)
    end
    if st.player then love.graphics.draw(st.player, 82, 80) end
  end
  if ensureFont(S) then
    love.graphics.setColor(0, 0, 0, 1)
    pcall(require("src.render.Font").draw, st.copyrightText, 1, 136 + scrollY)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- intro driver ----

local function buildIntro(S)
  local intro = {}
  local d = dataField(S, "intro")
  local p = (S.project and S.project.intro) or {}
  for k, v in pairs(d) do intro[k] = v end
  for k, v in pairs(p) do intro[k] = v end
  local studio = {}
  if type(d.studio) == "table" then
    for k, v in pairs(d.studio) do studio[k] = v end
  end
  if type(p.studio) == "table" then
    for k, v in pairs(p.studio) do studio[k] = v end
  end
  local logoPath = pathOf(studio.logo)
  if logoPath == "" then logoPath = "assets/logo/minilogo.png" end
  local studioLogo = img(S, logoPath)
  local studioScale, studioX, studioY = 1, 40, 40
  if studioLogo then
    local iw, ih = studioLogo:getDimensions()
    studioScale = math.min(STUDIO_BOX.w / iw, STUDIO_BOX.h / ih)
    studioX = STUDIO_BOX.cx - iw * studioScale / 2
    studioY = STUDIO_BOX.cy - ih * studioScale / 2
  end
  local function frameImg(bucket, key)
    local e = intro[bucket]
    if type(e) == "table" then return img(S, pathOf(e[key])) end
    return nil
  end
  return {
    kind = "intro",
    skipAll = intro.skip and true or false,
    studio = studio,
    studioLogo = studioLogo,
    studioScale = studioScale,
    studioX = studioX,
    studioY = studioY,
    logo = img(S, pathOf(intro.gamefreakLogo)),
    bigStar = img(S, pathOf(intro.bigStar)),
    smallStar = img(S, pathOf(intro.fallingStar)),
    smallStarBlink = img(S, pathOf(intro.fallingStarBlink)),
    gengarFrames = {
      frameImg("gengar", "frame1"),
      frameImg("gengar", "frame2"),
      frameImg("gengar", "frame3"),
    },
    nidoFrames = {
      frameImg("nidorino", "frame1"),
      frameImg("nidorino", "frame2"),
      frameImg("nidorino", "frame3"),
    },
    phase = 1,
    timer = 0,
    gengarX = 104,
    gengarY = 56,
    nidoX = -8,
    nidoY = 72,
    gengarPose = 1,
    nidoFrame = 1,
    fade = 0,
    fightTick = 0,
  }
end

local function drawBars()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 32)
  love.graphics.rectangle("fill", 0, 112, 160, 32)
  love.graphics.setColor(1, 1, 1, 1)
end

local function updateIntro(st)
  if st.skipAll then
    st.phase = 2
    st.timer = STAR_START
    st.skipAll = false
  end
  st.timer = st.timer + 1
  if st.phase == 1 then
    if st.timer >= COPYRIGHT_FRAMES then
      st.phase = 2
      st.timer = 0
    end
  elseif st.phase == 2 then
    if st.timer >= SPLASH_FRAMES then
      st.phase = 3
      st.timer = 0
      st.gengarX, st.gengarY = 104, 56
      st.nidoX, st.nidoY = -8, 72
      st.gengarPose, st.nidoFrame = 1, 1
      st.fade = 0
      st.fightTick = 0
    end
  else
    -- Simplified fight scroll: gengar left / nido right, then fade.
    st.fightTick = st.fightTick + 1
    if st.fightTick < 80 then
      if st.fightTick % 2 == 0 then
        st.gengarX = st.gengarX - 2
        st.nidoX = st.nidoX + 2
      end
    elseif st.fightTick < 140 then
      st.nidoFrame = 1 + math.floor((st.fightTick / 10) % 3)
      st.gengarPose = 1 + math.floor((st.fightTick / 16) % 3)
    else
      st.fade = math.min(1, (st.fightTick - 140) / 24)
      if st.fightTick >= 170 then
        st.done = true
      end
    end
  end
end

local function drawIntroFrame(st, S)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  if st.phase == 1 then
    love.graphics.setColor(0, 0, 0, 1)
    local credit = tostring(st.studio.credit or "bois club")
    if ensureFont(S) then
      local Font = require("src.render.Font")
      pcall(Font.draw, "2026", (160 - 4 * 8) / 2, 48)
      pcall(Font.draw, credit, math.max(0, (160 - #credit * 8) / 2), 64)
    else
      love.graphics.print(credit, 40, 64)
    end
  elseif st.phase == 2 then
    local t = st.timer
    if t >= STAR_START then
      local flashing = t >= FLASH_START and t < FLASH_START + FLASH_FRAMES
      local dim = flashing and math.floor((t - FLASH_START) / 5) % 2 == 0
      love.graphics.setColor(1, 1, 1, dim and 0.35 or 1)
      if st.studioLogo then
        love.graphics.draw(st.studioLogo, st.studioX, st.studioY,
          0, st.studioScale, st.studioScale)
      elseif st.logo then
        love.graphics.draw(st.logo, 72, 56)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    if t >= STAR_START and t < FLASH_START then
      local n = t - STAR_START + 1
      local sx, sy = 152 - 4 * n, -16 + 4 * n
      if st.bigStar then
        love.graphics.draw(st.bigStar, sx, sy)
      else
        love.graphics.setColor(0.2, 0.2, 0.25, 1)
        love.graphics.rectangle("fill", sx + 6, sy + 6, 4, 4)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
    if t >= WAVES_START then
      local substep = math.floor((math.min(t, WAVES_END) - WAVES_START) / 3)
      local blink = substep % 2 == 0
      for w, xs in ipairs(STAR_WAVES) do
        local spawn = (w - 1) * 8
        if substep >= spawn then
          local y = 88 + (substep - spawn)
          if y < 144 then
            local starImg = blink and st.smallStar
              or (st.smallStarBlink or st.smallStar)
            for _, x in ipairs(xs) do
              if starImg then
                love.graphics.draw(starImg, x, y)
              else
                love.graphics.setColor(0.15, 0.15, 0.2, 1)
                love.graphics.rectangle("fill", x + 3, y + 1, 2, 2)
                love.graphics.setColor(1, 1, 1, 1)
              end
            end
          end
        end
      end
    end
    drawBars()
  else
    local nido = st.nidoFrames[st.nidoFrame]
    local gengar = st.gengarFrames[st.gengarPose]
    if nido then love.graphics.draw(nido, st.nidoX, st.nidoY) end
    if gengar then love.graphics.draw(gengar, st.gengarX, st.gengarY) end
    if not nido and not gengar then
      love.graphics.setColor(0.45, 0.25, 0.55, 1)
      love.graphics.rectangle("fill", st.gengarX, st.gengarY, 56, 56)
      love.graphics.setColor(0.75, 0.35, 0.4, 1)
      love.graphics.rectangle("fill", st.nidoX, st.nidoY, 48, 48)
    end
    drawBars()
    if st.fade > 0 then
      love.graphics.setColor(1, 1, 1, math.min(1, st.fade))
      love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- theme / fonts / strings / townmap / badges / boot ----

local function buildTheme(S)
  local eng = applyTheme(S)
  return {
    kind = "theme",
    eng = eng,
    blink = 0,
    timer = 0,
  }
end

local function updateTheme(st)
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 40
end

local function drawThemeFrame(st, S)
  love.graphics.setColor(0.55, 0.7, 0.45, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local eng = st.eng or applyTheme(S)
  local tb = eng.textBox or THEME_DEFAULTS.textBox
  local cb = eng.choiceBox or THEME_DEFAULTS.choiceBox
  if ensureFont(S) then
    local Font = require("src.render.Font")
    love.graphics.setColor(1, 1, 1, 1)
    pcall(Font.drawBox, tb.tx, tb.ty, tb.tw, tb.th)
    pcall(Font.drawBox, cb.tx, cb.ty, cb.tw, cb.th)
    love.graphics.setColor(0, 0, 0, 1)
    pcall(Font.draw, resolveStr(S, "YES"), (cb.tx + 2) * 8, (cb.ty + 1) * 8)
    pcall(Font.draw, resolveStr(S, "NO"), (cb.tx + 2) * 8, (cb.ty + 3) * 8)
    pcall(Font.draw, "Hello!", (tb.tx + 1) * 8, (tb.ty + 2) * 8)
    local cursor = eng.cursor or THEME_DEFAULTS.cursor
    local hollow = eng.cursorHollow or THEME_DEFAULTS.cursorHollow
    local code = (st.blink < 20) and cursor or hollow
    pcall(Font.drawCode, code, (cb.tx + 1) * 8, (cb.ty + 1) * 8)
  else
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("line", tb.tx * 8, tb.ty * 8, tb.tw * 8, tb.th * 8)
    love.graphics.setColor(1, 0.8, 0.3, 0.9)
    love.graphics.rectangle("line", cb.tx * 8, cb.ty * 8, cb.tw * 8, cb.th * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function buildFonts(S)
  local pages = (S.data and S.data.font and S.data.font.pages) or {}
  local proj = (S.project and S.project.font) or {}
  local id = S.uiFontId
  local rec = (id and proj[id]) or (id and pages[id]) or nil
  if not rec then
    for k, v in pairs(proj) do id, rec = k, v; break end
  end
  if not rec then
    for k, v in pairs(pages) do id, rec = k, v; break end
  end
  return {
    kind = "fonts",
    id = id,
    image = rec and img(S, rec.image) or nil,
    scroll = 0,
    timer = 0,
  }
end

local function updateFonts(st)
  st.timer = st.timer + 1
  if st.image then
    local ih = st.image:getHeight()
    if ih > GB_H then
      st.scroll = (st.timer / 2) % (ih - GB_H + 1)
    end
  end
end

local function drawFontsFrame(st)
  love.graphics.setColor(0.08, 0.1, 0.16, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  if st.image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(st.image, 0, -math.floor(st.scroll or 0))
  else
    love.graphics.setColor(1, 1, 1, 0.4)
  end
end

local function buildStrings(S)
  return {
    kind = "strings",
    items = {
      resolveStr(S, "CONTINUE"),
      resolveStr(S, "NEW GAME"),
      resolveStr(S, "OPTION"),
      resolveStr(S, "YES"),
      resolveStr(S, "NO"),
    },
    cursor = 1,
    blink = 0,
    timer = 0,
  }
end

local function updateStrings(st)
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 40
  if st.timer % 90 == 0 then
    st.cursor = (st.cursor % #st.items) + 1
  end
end

local function drawStringsFrame(st, S)
  love.graphics.setColor(0.55, 0.7, 0.45, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  applyTheme(S)
  if ensureFont(S) then
    local Font = require("src.render.Font")
    local EngTheme = require("src.ui.Theme")
    pcall(Font.drawBox, 0, 0, 13, #st.items * 2 + 2)
    love.graphics.setColor(0, 0, 0, 1)
    for i, label in ipairs(st.items) do
      local y = (i * 2) * 8
      pcall(Font.draw, label, 16, y)
      if i == st.cursor and st.blink < 20 then
        pcall(Font.drawCode, EngTheme.cursor or 0xED, 8, y)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function buildTownMap(S)
  local tm = {}
  local d = dataField(S, "townMap")
  local p = (S.project and S.project.townMap) or {}
  for k, v in pairs(d) do tm[k] = v end
  for k, v in pairs(p) do tm[k] = v end
  local locs = {}
  local src = tm.locations or {}
  for id, e in pairs(src) do
    if type(e) == "table" then
      locs[#locs + 1] = {
        id = id, x = e.x or 0, y = e.y or 0,
        name = e.name or id,
      }
    end
  end
  table.sort(locs, function(a, b) return a.id < b.id end)
  return {
    kind = "townmap",
    bg = img(S, pathOf(tm.background)) or img(S, "assets/generated/town_map.png"),
    locs = locs,
    grid = tm.gridPixelSize or 8,
    index = 1,
    blink = 0,
    timer = 0,
  }
end

local function updateTownMap(st)
  st.timer = st.timer + 1
  st.blink = (st.blink + 1) % 30
  if #st.locs > 0 and st.timer % 60 == 0 then
    st.index = (st.index % #st.locs) + 1
  end
end

local function drawTownMapFrame(st, S)
  love.graphics.setColor(0.75, 0.85, 0.65, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  if st.bg then
    love.graphics.setColor(1, 1, 1, 1)
    local iw, ih = st.bg:getDimensions()
    local sx = GB_W / iw
    local sy = GB_H / ih
    love.graphics.draw(st.bg, 0, 0, 0, sx, sy)
  end
  local loc = st.locs[st.index]
  if loc and st.blink < 15 then
    local g = st.grid or 8
    love.graphics.setColor(1, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", loc.x * g, loc.y * g, g, g)
  end
  if loc and ensureFont(S) then
    love.graphics.setColor(0, 0, 0, 1)
    pcall(require("src.render.Font").draw, tostring(loc.name), 8, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function buildBadges(S)
  local rows = (S.project and S.project.constants and S.project.constants.badges)
    or (S.data and S.data.constants and S.data.constants.badges) or {}
  local badges = {}
  for i, b in ipairs(rows) do
    badges[i] = {
      id = b.id or ("#" .. i),
      name = b.name or "",
      icon = img(S, pathOf(b.icon)),
    }
  end
  return { kind = "badges", badges = badges, timer = 0, highlight = 1 }
end

local function updateBadges(st)
  st.timer = st.timer + 1
  if #st.badges > 0 and st.timer % 45 == 0 then
    st.highlight = (st.highlight % #st.badges) + 1
  end
end

local function drawBadgesFrame(st, S)
  love.graphics.setColor(0.9, 0.9, 0.85, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local n = #st.badges
  if n == 0 then return end
  local cols = 4
  local cell = 32
  for i, b in ipairs(st.badges) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = 16 + col * cell
    local y = 24 + row * cell
    if i == st.highlight then
      love.graphics.setColor(1, 0.85, 0.2, 1)
      love.graphics.rectangle("line", x - 2, y - 2, cell - 4, cell - 4)
    end
    love.graphics.setColor(1, 1, 1, 1)
    if b.icon then
      local iw, ih = b.icon:getDimensions()
      local sc = math.min(24 / iw, 24 / ih)
      love.graphics.draw(b.icon, x, y, 0, sc, sc)
    else
      love.graphics.setColor(0.6, 0.55, 0.35, 1)
      love.graphics.rectangle("fill", x + 4, y + 4, 16, 16)
    end
  end
  local cur = st.badges[st.highlight]
  if cur and ensureFont(S) then
    love.graphics.setColor(0, 0, 0, 1)
    pcall(require("src.render.Font").draw, tostring(cur.name or cur.id), 8, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function bootScreen(S, key)
  local boot = S.project and S.project.boot
  if boot and type(boot.screens) == "table" and boot.screens[key] then
    return boot.screens[key]
  end
  local d = dataField(S, "boot")
  if type(d.screens) == "table" and d.screens[key] then
    return d.screens[key]
  end
  return BOOT_DEFAULTS[key]
end

local function buildBoot(S)
  return {
    kind = "boot",
    steps = {
      { key = "splash", id = bootScreen(S, "splash") },
      { key = "title", id = bootScreen(S, "title") },
      { key = "newGame", id = bootScreen(S, "newGame") },
    },
    index = 1,
    timer = 0,
    fade = 0,
    cycles = 0,
  }
end

local function updateBoot(st)
  st.timer = st.timer + 1
  local phase = st.timer % 90
  st.fade = phase < 12 and (phase / 12)
    or (phase > 78 and ((90 - phase) / 12) or 1)
  if phase == 0 and st.timer > 0 then
    if st.index >= #st.steps then
      st.cycles = (st.cycles or 0) + 1
      st.index = 1
    else
      st.index = st.index + 1
    end
  end
end

local function drawBootFrame(st, S)
  love.graphics.setColor(0.08, 0.1, 0.18, 1)
  love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
  local step = st.steps[st.index]
  love.graphics.setColor(1, 1, 1, st.fade or 1)
  if ensureFont(S) then
    local Font = require("src.render.Font")
    local label = tostring(step and step.key or "?")
    local id = tostring(step and step.id or "?")
    pcall(Font.draw, "BOOT", 64, 40)
    pcall(Font.draw, label, math.max(0, (160 - #label * 8) / 2), 64)
    pcall(Font.draw, id, math.max(0, (160 - #id * 8) / 2), 88)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---- public API ----

local BUILDERS = {
  title = buildTitle,
  intro = buildIntro,
  theme = buildTheme,
  fonts = buildFonts,
  strings = buildStrings,
  townmap = buildTownMap,
  badges = buildBadges,
  boot = buildBoot,
}

local UPDATERS = {
  title = updateTitle,
  intro = updateIntro,
  theme = updateTheme,
  fonts = updateFonts,
  strings = updateStrings,
  townmap = updateTownMap,
  badges = updateBadges,
  boot = updateBoot,
}

local DRAWERS = {
  title = drawTitleFrame,
  intro = drawIntroFrame,
  theme = drawThemeFrame,
  fonts = drawFontsFrame,
  strings = drawStringsFrame,
  townmap = drawTownMapFrame,
  badges = drawBadgesFrame,
  boot = drawBootFrame,
}

function UiPreview.stop(S)
  if S then S.uiPreview = nil end
end

function UiPreview.isPlaying(S)
  local p = S and S.uiPreview
  return p and p.playing and true or false
end

function UiPreview.begin(S, mode)
  if not S or not mode then return false end
  local builder = BUILDERS[mode]
  if not builder then
    S.status = "No UI preview for " .. tostring(mode)
    return false
  end
  State.ensureProjectFields(S.project)
  local ok, st = pcall(builder, S)
  if not ok or type(st) ~= "table" then
    S.status = "UI preview build failed: " .. tostring(st)
    return false
  end
  S.uiPreview = {
    mode = mode,
    state = st,
    playing = true,
    accum = 0,
    loop = S.uiPreviewLoop ~= false,
  }
  S.status = "Previewing UI · " .. mode
  return true
end

function UiPreview.rebuild(S)
  local p = S and S.uiPreview
  if not p or not p.mode then return end
  local playing = p.playing
  UiPreview.begin(S, p.mode)
  if S.uiPreview then S.uiPreview.playing = playing end
end

local function sequenceDone(mode, st)
  if mode == "intro" then return st.done == true end
  if mode == "title" and st.yellowLayout then
    return st.phase == "loop" and (st.blinkTimer or 0) >= 200
  end
  if mode == "boot" then
    return (st.cycles or 0) >= 1
  end
  -- Continuous previews (theme/fonts/strings/townmap/badges/RB title): never "done"
  return false
end

function UiPreview.update(S, dt)
  local p = S and S.uiPreview
  if not p or not p.playing or not p.state then return end
  -- Rebuild theme/strings/fonts/badges when selection changes while playing.
  if p.mode == "fonts" and p.state.id ~= S.uiFontId then
    UiPreview.begin(S, "fonts")
    p = S.uiPreview
    if not p then return end
  end
  p.accum = (p.accum or 0) + (dt or 0)
  local frames = math.floor(p.accum * 60)
  if frames < 1 then return end
  p.accum = p.accum - frames / 60
  if frames > 5 then frames = 5 end
  local updater = UPDATERS[p.mode]
  local loop = S.uiPreviewLoop ~= false
  for _ = 1, frames do
    if updater then updater(p.state) end
    if not loop and sequenceDone(p.mode, p.state) then
      p.playing = false
      break
    elseif loop and sequenceDone(p.mode, p.state) then
      -- Restart long sequences
      if p.mode == "intro" or p.mode == "title" or p.mode == "boot" then
        local ok, st = pcall(BUILDERS[p.mode], S)
        if ok and type(st) == "table" then p.state = st end
      end
    end
  end
end

-- Draw Play/Stop + scaled GB viewport. Returns y below the widget.
function UiPreview.draw(S, mode, x, y, w, s)
  s = s or Kit.scale
  local fh = 28 * s
  Kit.text("small", "UI preview", x, y, PAL.caption)
  y = y + 18 * s

  local p = S.uiPreview
  if p and p.mode ~= mode then
    UiPreview.stop(S)
    p = nil
  end
  local active = p and p.mode == mode
  local playing = active and p.playing

  if Kit.chip(x, y, 72 * s, fh, playing and "STOP" or "PLAY",
      playing, PAL.green) then
    if playing then
      UiPreview.stop(S)
      S.status = "UI preview stopped"
    else
      UiPreview.begin(S, mode)
    end
    p = S.uiPreview
    active = p and p.mode == mode
    playing = active and p.playing
  end

  local loop = S.uiPreviewLoop ~= false
  if Kit.chip(x + 80 * s, y, 72 * s, fh, loop and "LOOP" or "ONCE",
      loop, PAL.blue) then
    S.uiPreviewLoop = not loop
    if active and p then p.loop = S.uiPreviewLoop ~= false end
  end

  if Kit.chip(x + 160 * s, y, 88 * s, fh, "RELOAD", false, PAL.yellow,
      nil, "Rebuild preview from current fields") then
    UiPreview.begin(S, mode)
    p = S.uiPreview
    active = p and p.mode == mode
    playing = active and p and p.playing
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

  if active and p and p.state then
    local drawer = DRAWERS[mode]
    if drawer then
      love.graphics.setColor(1, 1, 1, 1)
      pcall(drawer, p.state, S)
    end
  else
    love.graphics.setColor(0.12, 0.14, 0.22, 1)
    love.graphics.rectangle("fill", 0, 0, GB_W, GB_H)
    love.graphics.setColor(1, 1, 1, 0.35)
  end

  love.graphics.pop()
  Kit.popClip()

  local tips = {
    title = "logo drop / species cycle · PLAY to animate",
    intro = "copyright → studio splash → fight stub",
    theme = "textBox / choiceBox + blinking cursor",
    fonts = "scroll selected font sheet",
    strings = "menu labels with string overrides",
    townmap = "background + blinking location cursor",
    badges = "badge icons · highlight cycles",
    boot = "splash → title → newGame screen ids",
  }
  local info = tips[mode] or mode
  if active and p and p.state then
    if mode == "title" and p.state.phase then
      info = string.format("title · %s", tostring(p.state.phase))
    elseif mode == "intro" then
      info = string.format("intro · phase %d", tonumber(p.state.phase) or 0)
    elseif mode == "boot" and p.state.steps then
      local step = p.state.steps[p.state.index]
      info = string.format("boot · %s = %s",
        tostring(step and step.key), tostring(step and step.id))
    end
  end
  Kit.text("micro", Kit.ellipsize("micro", info, w), x, y + vh + 12 * s, PAL.muted)
  return y + vh + 28 * s
end

return UiPreview
