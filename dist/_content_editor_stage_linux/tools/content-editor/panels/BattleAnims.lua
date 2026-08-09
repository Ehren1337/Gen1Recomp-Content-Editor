-- Battle Anims tab: moveAnims / subanims / tilesheets from battle_anims.
-- First edit clones into the mod; Save emits battle_anims:patch/register.
-- Also hosts a clone-from picker used by the Moves tab.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local Preview = require("Preview")
local BattleAnimPreview = require("BattleAnimPreview")
local PAL = Theme.PAL

local BattleAnims = {}

local MODES = {
  { id = "moves", label = "Move anims",
    tip = "Per-move battle animation sequences (keyed by move id)" },
  { id = "subanims", label = "Subanims",
    tip = "Shared subanimation frame-block lists" },
  { id = "tilesheets", label = "Tilesheets",
    tip = "Battle animation tile atlases" },
}

local SUBANIM_TYPES = {
  "NORMAL", "HFLIP", "HVFLIP", "COORDFLIP", "ENEMY", "REVERSE",
}

local function deepClone(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do
    if type(val) == "function" then
      -- skip
    elseif type(val) == "table" then
      out[k] = deepClone(val)
    else
      out[k] = val
    end
  end
  return out
end

local function baRoot(S)
  return S.data and S.data.battle_anims or nil
end

local function projectBucket(S)
  State.ensureProjectFields(S.project)
  S.project.battle_anims = S.project.battle_anims or {}
  return S.project.battle_anims
end

local function parseRoute(id)
  local kind, index = tostring(id or ""):match("^(%a+):(%d+)$")
  if kind == "subanim" then return "subanims", tonumber(index) end
  if kind == "tilesheet" then return "tilesheets", tonumber(index) end
  return "moveAnims", id
end

function BattleAnims.resolve(S, id)
  if not id then return nil, false end
  local proj = S.project and S.project.battle_anims
  if proj and proj[id] ~= nil then return proj[id], true end
  local root = baRoot(S)
  if not root then return nil, false end
  local sub, key = parseRoute(id)
  local table_ = root[sub]
  if table_ and table_[key] ~= nil then return table_[key], false end
  return nil, false
end

function BattleAnims.moveAnimIds(S)
  local seen, ids = {}, {}
  local proj = S.project and S.project.battle_anims or {}
  for id in pairs(proj) do
    local sub = parseRoute(id)
    if sub == "moveAnims" then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local root = baRoot(S)
  if root and root.moveAnims then
    for id in pairs(root.moveAnims) do
      if type(id) == "string" and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function listIds(S, mode)
  local proj = projectBucket(S)
  local root = baRoot(S)
  local seen, ids = {}, {}

  local function add(id)
    if not id or seen[id] then return end
    seen[id] = true
    ids[#ids + 1] = id
  end

  if mode == "moves" then
    for id in pairs(proj) do
      if parseRoute(id) == "moveAnims" then add(id) end
    end
    if root and root.moveAnims then
      for id in pairs(root.moveAnims) do
        if type(id) == "string" then add(id) end
      end
    end
  elseif mode == "subanims" then
    for id in pairs(proj) do
      if parseRoute(id) == "subanims" then add(id) end
    end
    if root and root.subanims then
      for index in pairs(root.subanims) do
        add("subanim:" .. tostring(index))
      end
    end
  else -- tilesheets
    for id in pairs(proj) do
      if parseRoute(id) == "tilesheets" then add(id) end
    end
    if root and root.tilesheets then
      for index in pairs(root.tilesheets) do
        add("tilesheet:" .. tostring(index))
      end
    end
  end

  table.sort(ids, function(a, b)
    local _, ka = parseRoute(a)
    local _, kb = parseRoute(b)
    if type(ka) == "number" and type(kb) == "number" then return ka < kb end
    return tostring(a) < tostring(b)
  end)
  return ids
end

local function summarize(id, rec)
  if type(rec) ~= "table" then return "empty" end
  local sub = parseRoute(id)
  if sub == "moveAnims" then
    local n = type(rec.seq) == "table" and #rec.seq or 0
    return n == 0 and "empty seq" or (n .. " row" .. (n == 1 and "" or "s"))
  end
  if sub == "subanims" then
    local n = type(rec.blocks) == "table" and #rec.blocks or 0
    return (rec.type or "?") .. " · " .. n .. " block" .. (n == 1 and "" or "s")
  end
  if sub == "tilesheets" then
    local path = tostring(rec.path or "")
    local short = path:match("([^/\\]+)$") or path
    return string.format("%dx%d · %s tiles · %s",
      tonumber(rec.width) or 0, tonumber(rec.height) or 0,
      tostring(rec.tiles or "?"), short ~= "" and short or "?")
  end
  return "?"
end

local function summarizeSeqRow(row, i)
  if type(row) ~= "table" then return tostring(i) .. ". ?" end
  if row.effect then
    local s = string.format("%d. effect %s", i, tostring(row.effect))
    if row.sound then s = s .. "  sfx=" .. tostring(row.sound) end
    return s
  end
  local s = string.format("%d. sub=%s tile=%s delay=%s",
    i, tostring(row.subanim), tostring(row.tileset), tostring(row.delay))
  if row.sound then s = s .. "  sfx=" .. tostring(row.sound) end
  return s
end

local function cloneIntoProject(S, id, App)
  local proj = projectBucket(S)
  if proj[id] then return proj[id] end
  local base = select(1, BattleAnims.resolve(S, id))
  local copy
  if type(base) == "table" then
    copy = deepClone(base)
  else
    local sub = parseRoute(id)
    if sub == "moveAnims" then
      copy = { seq = {} }
    elseif sub == "subanims" then
      copy = { type = "NORMAL", blocks = {} }
    else
      copy = { path = "", width = 128, height = 64, tiles = 1 }
    end
  end
  copy._isNew = base == nil
  if base ~= nil then copy._isNew = false end
  proj[id] = copy
  if App then App.markDirty() end
  return copy
end

-- Clone a source moveAnim's seq onto targetMoveId in the project.
function BattleAnims.cloneMoveAnim(S, targetMoveId, sourceMoveId, App)
  if not targetMoveId or not sourceMoveId then return nil end
  local src = select(1, BattleAnims.resolve(S, sourceMoveId))
  if type(src) ~= "table" then return nil end
  local proj = projectBucket(S)
  local copy = deepClone(src)
  local root = baRoot(S)
  local hadVanilla = root and root.moveAnims and root.moveAnims[targetMoveId]
  copy._isNew = not hadVanilla
  proj[targetMoveId] = copy
  if App then App.markDirty() end
  return copy
end

-- ---- Clone-from picker (Moves tab + Anims tab) ----

function BattleAnims.isPickerOpen(S)
  return S and S.battleAnimPicker ~= nil
end

function BattleAnims.closePicker(S)
  if not S then return end
  S.battleAnimPicker = nil
  Kit.blur()
  Kit.suppressMouseUntilUp()
end

-- opts: current, title, onPick(sourceId), excludeId?
function BattleAnims.openPicker(S, opts)
  opts = opts or {}
  S.battleAnimPicker = {
    query = "",
    offset = 0,
    opened = true,
    focus = opts.current,
    current = opts.current,
    title = opts.title or "CLONE BATTLE ANIM FROM",
    excludeId = opts.excludeId,
    onPick = opts.onPick,
  }
end

function BattleAnims.pickerKeypressed(S, key)
  if not BattleAnims.isPickerOpen(S) then return false end
  if key == "escape" then
    BattleAnims.closePicker(S)
    return true
  end
  return false
end

function BattleAnims.drawPicker(S, x, y, w, h)
  local p = S and S.battleAnimPicker
  if not p then return end
  local s = Kit.scale
  if p.opened then
    p.opened = nil
    Kit.mouseClicked = false
  end

  Theme.col(PAL.bgBot or PAL.card, 0.72)
  love.graphics.rectangle("fill", x, y, w, h)

  local pw = math.min(w - 24 * s, 520 * s)
  local ph = math.min(h - 24 * s, 460 * s)
  local px = x + (w - pw) / 2
  local py = y + (h - ph) / 2
  if Kit.press(x, y, w, h) and not Kit.hit(px, py, pw, ph) then
    BattleAnims.closePicker(S)
    return
  end

  Kit.card(px, py, pw, ph, 12 * s)
  local pad = 14 * s
  local cx, cy = px + pad, py + pad
  local inner = pw - 2 * pad
  Kit.caption(cx, cy, p.title or "CLONE BATTLE ANIM FROM")
  if Kit.button(px + pw - pad - 30 * s, cy - 2 * s, 30 * s, 26 * s, "x", {
      kind = "ghost", tooltip = "Close (Esc)",
    }) then
    BattleAnims.closePicker(S)
    return
  end
  cy = cy + 22 * s

  local qh = 28 * s
  local q = Kit.textfield("ba_pick_q", cx, cy, inner, qh, p.query or "",
    "search move anims...")
  if q ~= (p.query or "") then
    p.query = q
    p.offset = 0
  end

  local list = BattleAnims.moveAnimIds(S)
  if p.excludeId then
    local filtered = {}
    for _, id in ipairs(list) do
      if id ~= p.excludeId then filtered[#filtered + 1] = id end
    end
    list = filtered
  end
  if (p.query or "") ~= "" then
    local filtered, ql = {}, p.query:lower()
    for _, id in ipairs(list) do
      if id:lower():find(ql, 1, true) then filtered[#filtered + 1] = id end
    end
    list = filtered
  end

  local listY = cy + qh + 8 * s
  local btnH = 32 * s
  local listH = py + ph - pad - listY - btnH - 8 * s
  local rowH = 30 * s
  local perPage = math.max(1, math.floor(listH / (rowH + 3 * s)))
  local innerW = Kit.scrollInnerWidth(inner)
  p.offset = Kit.scroll(cx, listY, inner, listH, p.offset or 0, #list, perPage)

  local function accept(id)
    local cb = p.onPick
    BattleAnims.closePicker(S)
    if cb then cb(id) end
  end

  if #list == 0 then
    Kit.emptyBox(cx, listY, inner, listH, "No move anims match")
  else
    if not p.focus then p.focus = list[(p.offset or 0) + 1] or list[1] end
    local focusOk = false
    for _, id in ipairs(list) do
      if id == p.focus then focusOk = true; break end
    end
    if not focusOk then p.focus = list[(p.offset or 0) + 1] or list[1] end

    local ry = listY
    for i = (p.offset or 0) + 1, math.min(#list, (p.offset or 0) + perPage) do
      local id = list[i]
      local rec = select(1, BattleAnims.resolve(S, id))
      local on = p.focus == id
      if Kit.hover(cx, ry, innerW, rowH) then p.focus = id end
      if Kit.row(cx, ry, innerW, rowH, on, PAL.blue) then
        accept(id)
        return
      end
      Kit.text("mono", Kit.ellipsize("mono", id, math.max(8, innerW * 0.55)),
        cx + 8 * s, ry + 2 * s, PAL.text)
      Kit.text("micro", Kit.ellipsize("micro", summarize(id, rec),
          math.max(8, innerW - 16 * s)),
        cx + 8 * s, ry + 16 * s, PAL.faint)
      ry = ry + rowH + 3 * s
    end
  end
  p.offset = Kit.scrollbar(cx, listY, inner, listH, p.offset or 0, #list, perPage)

  local focusId = p.focus
  if focusId and Kit.button(cx, listY + listH + 4 * s, inner, btnH,
      "Clone " .. Kit.ellipsize("small", focusId, inner - 80 * s), {
        kind = "primary",
        tooltip = "Copy this anim's sequence onto the target move id",
      }) then
    accept(focusId)
  end
end

-- ---- Form helpers ----

local function drawMoveAnimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  local s = Kit.scale
  local proj = projectBucket(S)
  local r = (owned and proj[id]) or rec or { seq = {} }
  local seq = type(r.seq) == "table" and r.seq or {}

  local function ensure()
    if owned then return proj[id] end
    local e = cloneIntoProject(S, id, App)
    owned = true
    return e
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarize(id, r), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Clone from", function(fx, fy_, fw, fh_)
    if Kit.button(fx, fy_, math.min(160 * s, fw), fh_, "Choose…", {
        kind = "accent",
        tooltip = "Replace this anim with a copy of another move's seq",
      }) then
      BattleAnims.openPicker(S, {
        current = id,
        excludeId = id,
        title = "CLONE SEQUENCE FROM",
        onPick = function(srcId)
          local src = select(1, BattleAnims.resolve(S, srcId))
          if type(src) ~= "table" then return end
          local e = ensure()
          e.seq = deepClone(src.seq) or {}
          S.battleAnimRow = 1
          App.markDirty()
        end,
      })
    end
  end)

  -- Row list
  Kit.text("small", "Sequence", viewX, fy + 4 * s, PAL.caption)
  fy = fy + 22 * s
  S.battleAnimRow = S.battleAnimRow or 1
  if S.battleAnimRow > #seq then S.battleAnimRow = math.max(1, #seq) end

  local rowH = 26 * s
  local listH = math.min(8, math.max(3, #seq)) * (rowH + 2 * s) + 4 * s
  Kit.card(viewX, fy, viewW, listH, 8 * s)
  local ry = fy + 4 * s
  local maxShow = math.floor((listH - 4 * s) / (rowH + 2 * s))
  local start = 1
  if #seq > maxShow then
    start = math.max(1, (S.battleAnimRow or 1) - maxShow + 1)
  end
  for i = start, math.min(#seq, start + maxShow - 1) do
    local on = S.battleAnimRow == i
    if Kit.row(viewX + 4 * s, ry, viewW - 8 * s, rowH, on, PAL.blue) then
      S.battleAnimRow = i
    end
    Kit.text("micro", Kit.ellipsize("micro", summarizeSeqRow(seq[i], i),
        viewW - 20 * s),
      viewX + 10 * s, ry + 6 * s, on and PAL.heading or PAL.text)
    ry = ry + rowH + 2 * s
  end
  fy = fy + listH + 8 * s

  local btnW = 72 * s
  if Kit.button(viewX, fy, btnW, fh, "+ Row", { kind = "good" }) then
    local e = ensure()
    e.seq = e.seq or {}
    e.seq[#e.seq + 1] = { subanim = 0, tileset = 0, delay = 1 }
    S.battleAnimRow = #e.seq
    App.markDirty()
  end
  if Kit.button(viewX + btnW + 6 * s, fy, btnW, fh, "+ SE", {
      kind = "ghost", tooltip = "Add special-effect row",
    }) then
    local e = ensure()
    e.seq = e.seq or {}
    e.seq[#e.seq + 1] = { effect = "SE_DELAY_ANIMATION_10" }
    S.battleAnimRow = #e.seq
    App.markDirty()
  end
  if #seq > 0 and Kit.button(viewX + 2 * (btnW + 6 * s), fy, btnW, fh, "Del", {
      kind = "danger",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    table.remove(e.seq, i)
    S.battleAnimRow = math.max(1, math.min(i, #e.seq))
    App.markDirty()
  end
  if #seq > 1 and Kit.button(viewX + 3 * (btnW + 6 * s), fy, btnW, fh, "Up", {
      kind = "ghost",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    if i > 1 then
      e.seq[i], e.seq[i - 1] = e.seq[i - 1], e.seq[i]
      S.battleAnimRow = i - 1
      App.markDirty()
    end
  end
  if #seq > 1 and Kit.button(viewX + 4 * (btnW + 6 * s), fy, btnW, fh, "Down", {
      kind = "ghost",
    }) then
    local e = ensure()
    local i = S.battleAnimRow or 1
    if i < #e.seq then
      e.seq[i], e.seq[i + 1] = e.seq[i + 1], e.seq[i]
      S.battleAnimRow = i + 1
      App.markDirty()
    end
  end
  fy = fy + fh + 12 * s

  -- Selected row editor
  local idx = S.battleAnimRow or 1
  local cur = seq[idx]
  if cur then
    Kit.text("small", "Row " .. idx, viewX, fy + 4 * s, PAL.caption)
    fy = fy + 22 * s

    local isEffect = cur.effect ~= nil
    row("Kind", function(fx, fy_, fw, fh_)
      local label = isEffect and "effect" or "subanim"
      if Kit.button(fx, fy_, 120 * s, fh_, label, { kind = "ghost" }) then
        local e = ensure()
        local row_ = e.seq[idx]
        if not row_ then return end
        if row_.effect then
          e.seq[idx] = { subanim = 0, tileset = 0, delay = 1, sound = row_.sound }
        else
          e.seq[idx] = { effect = "SE_DELAY_ANIMATION_10", sound = row_.sound }
        end
        App.markDirty()
      end
    end)

    -- refresh after possible kind toggle
    r = (owned and proj[id]) or r
    seq = type(r.seq) == "table" and r.seq or {}
    cur = seq[idx]
    if not cur then return fy, owned end
    isEffect = cur.effect ~= nil

    if isEffect then
      row("Effect", function(fx, fy_, fw, fh_)
        local v = RegList.field(App, "ba_eff", fx, fy_, fw, fh_,
          tostring(cur.effect or ""), "SE_...")
        if v ~= tostring(cur.effect or "") then
          ensure().seq[idx].effect = v
        end
      end)
    else
      row("Subanim", function(fx, fy_, fw, fh_)
        local v = RegList.num(App, "ba_sub", fx, fy_, 80 * s, fh_,
          tonumber(cur.subanim) or 0)
        if v ~= (tonumber(cur.subanim) or 0) then
          ensure().seq[idx].subanim = v
        end
      end)
      row("Tileset", function(fx, fy_, fw, fh_)
        local v = RegList.num(App, "ba_tile", fx, fy_, 80 * s, fh_,
          tonumber(cur.tileset) or 0)
        if v ~= (tonumber(cur.tileset) or 0) then
          ensure().seq[idx].tileset = v
        end
      end)
      row("Delay", function(fx, fy_, fw, fh_)
        local v = RegList.num(App, "ba_delay", fx, fy_, 80 * s, fh_,
          tonumber(cur.delay) or 1)
        if v < 1 then v = 1 end
        if v > 63 then v = 63 end
        if v ~= (tonumber(cur.delay) or 1) then
          ensure().seq[idx].delay = v
        end
      end)
    end
    row("Sound", function(fx, fy_, fw, fh_)
      local curS = tostring(cur.sound or "")
      local v = RegList.field(App, "ba_snd", fx, fy_, fw, fh_, curS, "MOVE_ID or empty")
      if v ~= curS then
        local e = ensure().seq[idx]
        if v == "" then e.sound = nil else e.sound = v end
      end
    end)
  else
    Kit.text("micro", "Empty sequence — add a row or clone from another move.",
      viewX, fy, PAL.faint)
    fy = fy + 20 * s
  end

  fy = fy + 8 * s
  fy = BattleAnimPreview.draw(S, id, viewX, fy, viewW, s)

  return fy, owned
end

local function drawSubanimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  local proj = projectBucket(S)
  local r = (owned and proj[id]) or rec or { type = "NORMAL", blocks = {} }
  local s = Kit.scale

  local function ensure()
    if owned then return proj[id] end
    local e = cloneIntoProject(S, id, App)
    owned = true
    return e
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarize(id, r), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Type", function(fx, fy_, fw, fh_)
    local cur = tostring(r.type or "NORMAL")
    if Kit.button(fx, fy_, math.min(160 * s, fw), fh_, cur, { kind = "ghost" }) then
      ensure().type = RegList.cycle(SUBANIM_TYPES, cur)
    end
  end)

  local blocks = type(r.blocks) == "table" and r.blocks or {}
  Kit.text("small", "Blocks (" .. #blocks .. ")", viewX, fy + 4 * s, PAL.caption)
  fy = fy + 22 * s
  for i = 1, math.min(#blocks, 12) do
    local b = blocks[i]
    local line = string.format("%d. block=%s coord=%s mode=%s",
      i, tostring(b.block), tostring(b.coord), tostring(b.mode))
    Kit.text("micro", Kit.ellipsize("micro", line, viewW), viewX, fy, PAL.muted)
    fy = fy + 16 * s
  end
  if #blocks > 12 then
    Kit.text("micro", ("… %d more"):format(#blocks - 12), viewX, fy, PAL.faint)
    fy = fy + 16 * s
  end
  if #blocks == 0 then
    Kit.text("micro", "No frame-block refs (read-only summary for now).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
  end

  return fy, owned
end

local function drawTilesheetForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  local proj = projectBucket(S)
  local r = (owned and proj[id]) or rec or {}
  local s = Kit.scale

  local function ensure()
    if owned then return proj[id] end
    local e = cloneIntoProject(S, id, App)
    owned = true
    return e
  end

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.text("micro", summarize(id, r), viewX, fy, PAL.muted)
  fy = fy + 18 * s

  row("Path", function(fx, fy_, fw, fh_)
    local cur = tostring(r.path or "")
    local v = RegList.field(App, "ba_path", fx, fy_, fw, fh_, cur, "assets/...")
    if v ~= cur then ensure().path = v end
  end)
  row("Width", function(fx, fy_, fw, fh_)
    local cur = tonumber(r.width) or 0
    local v = RegList.num(App, "ba_w", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().width = v end
  end)
  row("Height", function(fx, fy_, fw, fh_)
    local cur = tonumber(r.height) or 0
    local v = RegList.num(App, "ba_h", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().height = v end
  end)
  row("Tiles", function(fx, fy_, fw, fh_)
    local cur = tonumber(r.tiles) or 0
    local v = RegList.num(App, "ba_tiles", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().tiles = v end
  end)

  if r.path and r.path ~= "" then
    fy = fy + Preview.draw(S, r.path, viewX, fy,
      math.min(viewW, 240 * s), math.min(160 * s, 120 * s)) + 8 * s
  end

  return fy, owned
end

function BattleAnims.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  local proj = projectBucket(S)

  local prevMode = S._battleAnimModeDrawn
  local modeY = RegList.modeChips(S, "battleAnimMode", MODES, x, y, s)
  local mode = S.battleAnimMode or "moves"
  if prevMode and prevMode ~= mode then
    S.battleAnimListOffset = 0
    S.battleAnimRow = 1
  end
  S._battleAnimModeDrawn = mode
  local ids = listIds(S, mode)

  local selKey = (mode == "moves" and "battleAnimMoveId")
    or (mode == "subanims" and "battleAnimSubId")
    or "battleAnimSheetId"
  -- Moves tab "Edit" sets battleAnimId; honor it when opening move anims.
  if mode == "moves" and S.battleAnimId and not S.battleAnimMoveId then
    S.battleAnimMoveId = S.battleAnimId
  end
  local title = (mode == "moves" and "MOVE ANIMS")
    or (mode == "subanims" and "SUBANIMS")
    or "TILESHEETS"

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, modeY, w,
    h - (modeY - y), title, ids, {
      queryKey = "battleAnimQuery",
      offsetKey = "battleAnimListOffset",
      selKey = selKey,
      accent = PAL.blue,
      isOwned = function(id) return proj[id] ~= nil end,
      filter = function(id, q)
        local ql = q:lower()
        if id:lower():find(ql, 1, true) then return true end
        local rec = select(1, BattleAnims.resolve(S, id))
        return tostring(summarize(id, rec)):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = mode == "moves" and "+ New move anim" or nil,
      onFooter = mode == "moves" and function()
        local nid = "NEW_MOVE_ANIM"
        local n = 1
        while proj[nid] or (baRoot(S) and baRoot(S).moveAnims
            and baRoot(S).moveAnims[nid]) do
          n = n + 1
          nid = "NEW_MOVE_ANIM_" .. n
        end
        proj[nid] = { seq = {}, _isNew = true }
        S.battleAnimMoveId = nid
        S.battleAnimId = nid
        S.battleAnimRow = 1
        App.markDirty()
      end or nil,
    })

  if not S[selKey] then S[selKey] = shown[1] end
  local id = S[selKey]
  if mode == "moves" then S.battleAnimId = id end
  local rec, owned = BattleAnims.resolve(S, id)
  if not id then
    Kit.emptyBox(formX, listY, formW, listH,
      "No battle anims loaded (Import ROM / Link Recomp)")
    return
  end

  Kit.caption(formX, y, (id or "?") .. (owned and "" or "  (vanilla)"))

  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "battleAnimFormScroll", tostring(id) .. ":" .. mode,
    owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 100 * s
  local fh = 28 * s

  if mode == "moves" then
    fy, owned = drawMoveAnimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  elseif mode == "subanims" then
    fy, owned = drawSubanimForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  else
    fy, owned = drawTilesheetForm(S, App, id, rec, owned, viewX, viewW, fy, fh, labelW)
  end

  if not owned then
    Kit.text("micro", "Edit clones into the mod (Save emits battle_anims patch).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      cloneIntoProject(S, id, App)
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "battleAnimFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    proj[id] = nil
    App.markDirty()
  end
end

return BattleAnims
