-- Items tab: every item + its effect kind/params.  First edit clones into
-- the mod; Save emits items:patch and item_effects/balls as needed.

local Kit = require("Kit")
local Theme = require("Theme")
local Search = require("Search")
local FormPane = require("FormPane")
local Preview = require("Preview")
local PalettePicker = require("PalettePicker")
local PaletteEdit = require("PaletteEdit")
local ModIO = require("ModIO")
local RegList = require("RegList")
local PAL = Theme.PAL

local Items = {}

local TEMPLATES = {
  { id = "none",         label = "None" },
  { id = "heal",         label = "Heal HP" },
  { id = "max_heal",     label = "Max HP" },
  { id = "full_restore", label = "Full restore" },
  { id = "status",       label = "Status" },
  { id = "revive",       label = "Revive" },
  { id = "max_revive",   label = "Max revive" },
  { id = "ball",         label = "Ball" },
  { id = "stone",        label = "Stone" },
  { id = "vitamin",      label = "Vitamin" },
  { id = "rare_candy",   label = "Rare candy" },
  { id = "pp_restore",   label = "PP restore" },
  { id = "pp_up",        label = "PP Up" },
  { id = "x_item",       label = "X item" },
  { id = "machine",      label = "TM/HM" },
  { id = "flute",        label = "Flute" },
  { id = "key",          label = "Key" },
  { id = "custom",       label = "Custom" },
}

local HEAL_AMOUNT = {
  POTION = 20, SUPER_POTION = 50, HYPER_POTION = 200,
  FRESH_WATER = 50, SODA_POP = 60, LEMONADE = 80,
}

local STATUS_HEAL = {
  ANTIDOTE = { "PSN" }, BURN_HEAL = { "BRN" },
  ICE_HEAL = { "FRZ" }, AWAKENING = { "SLP" },
  PARLYZ_HEAL = { "PAR" },
  FULL_HEAL = { "PSN", "BRN", "FRZ", "SLP", "PAR" },
}

local BALL_IDS = {
  MASTER_BALL = true, POKE_BALL = true, GREAT_BALL = true,
  ULTRA_BALL = true, SAFARI_BALL = true,
}

local STONES = {
  FIRE_STONE = true, WATER_STONE = true, THUNDER_STONE = true,
  LEAF_STONE = true, MOON_STONE = true,
}

local VITAMINS = {
  HP_UP = "hp", PROTEIN = "attack", IRON = "defense",
  CARBOS = "speed", CALCIUM = "special",
}

local X_ITEMS = {
  X_ATTACK = "attack", X_DEFEND = "defense", X_SPEED = "speed",
  X_SPECIAL = "special", X_ACCURACY = "accuracy",
}

local STATUSES = { "PSN", "BRN", "FRZ", "SLP", "PAR" }
local VIT_STATS = { "hp", "attack", "defense", "speed", "special" }
local X_STATS = { "attack", "defense", "speed", "special", "accuracy" }

local function allItemIds(S)
  local seen, ids = {}, {}
  for id in pairs((S.project and S.project.items) or {}) do
    seen[id] = true
    ids[#ids + 1] = id
  end
  if S.data and S.data.items then
    for id in pairs(S.data.items) do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

local function registeredEffects(S)
  local ids = {}
  if S.data and S.data.item_effects then
    for id in pairs(S.data.item_effects) do ids[#ids + 1] = id end
  end
  if S.project and S.project.items then
    for _, it in pairs(S.project.items) do
      if it.effect then ids[#ids + 1] = it.effect end
      if it.effectTemplate and it.effectTemplate ~= "none"
          and it.effectTemplate ~= "ball" and it.effectTemplate ~= "machine" then
        ids[#ids + 1] = it.effect or ((it.id or "ITEM") .. "_EFFECT")
      end
    end
  end
  table.sort(ids)
  local seen, out = {}, {}
  for _, id in ipairs(ids) do
    if not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  return out
end

local function inferTemplate(S, def)
  if not def then return "none" end
  if def.effectTemplate then return def.effectTemplate end
  local id = def.id
  if def.effect then return "custom" end
  if def.machine then return "machine" end
  if def.ball or BALL_IDS[id] or (S.data and S.data.balls and S.data.balls[id]) then
    return "ball"
  end
  if def.keyItem then return "key" end
  if HEAL_AMOUNT[id] then return "heal" end
  if id == "MAX_POTION" then return "max_heal" end
  if id == "FULL_RESTORE" then return "full_restore" end
  if STATUS_HEAL[id] then return "status" end
  if id == "REVIVE" then return "revive" end
  if id == "MAX_REVIVE" then return "max_revive" end
  if STONES[id] then return "stone" end
  if VITAMINS[id] then return "vitamin" end
  if id == "RARE_CANDY" then return "rare_candy" end
  if id == "ETHER" or id == "MAX_ETHER" or id == "ELIXER" or id == "MAX_ELIXER" then
    return "pp_restore"
  end
  if id == "PP_UP" then return "pp_up" end
  if X_ITEMS[id] then return "x_item" end
  if id == "POKE_FLUTE" then return "flute" end
  return "none"
end

local function effectSummary(S, def)
  local tmpl = inferTemplate(S, def)
  if tmpl == "heal" then
    local amt = def.healAmount or HEAL_AMOUNT[def.id] or "?"
    return string.format("heal +%s", amt)
  elseif tmpl == "max_heal" then return "heal full HP"
  elseif tmpl == "full_restore" then return "full HP + status"
  elseif tmpl == "status" then
    local cures = def.statusCures or STATUS_HEAL[def.id] or STATUSES
    return "cure " .. table.concat(cures, "/")
  elseif tmpl == "revive" then return "revive 50% HP"
  elseif tmpl == "max_revive" then return "revive full HP"
  elseif tmpl == "ball" then return "ball"
  elseif tmpl == "stone" then return "evolution stone"
  elseif tmpl == "vitamin" then
    return "vitamin " .. (def.vitaminStat or VITAMINS[def.id] or "?")
  elseif tmpl == "rare_candy" then return "level up"
  elseif tmpl == "pp_restore" then
    local full = def.ppFull or (def.id == "MAX_ETHER" or def.id == "MAX_ELIXER")
    local all = def.ppAllMoves or (def.id == "ELIXER" or def.id == "MAX_ELIXER")
    return (full and "max PP" or "+10 PP") .. (all and " all moves" or " one move")
  elseif tmpl == "pp_up" then return "raise PP max"
  elseif tmpl == "x_item" then
    return "X " .. (def.xStat or X_ITEMS[def.id] or "?")
  elseif tmpl == "machine" then
    local m = def.machine
    return m and string.format("%s %s", m.kind or "TM", m.move or "?") or "TM/HM"
  elseif tmpl == "flute" then return "Poké Flute"
  elseif tmpl == "key" then return "key item"
  elseif tmpl == "custom" then return "effect " .. tostring(def.effect or "?")
  end
  return "data only"
end

local function seedEffectFields(S, copy, def)
  local tmpl = copy.effectTemplate
  local id = def.id
  if tmpl == "heal" then
    copy.healAmount = copy.healAmount or HEAL_AMOUNT[id] or 20
  elseif tmpl == "status" then
    copy.statusCures = copy.statusCures or STATUS_HEAL[id]
      or { "PSN", "BRN", "FRZ", "SLP", "PAR" }
  elseif tmpl == "ball" then
    copy.ball = copy.ball or id
    local ball = S.data and S.data.balls and S.data.balls[id]
    if ball then
      copy.ballRandMax = copy.ballRandMax or ball.randMax or 255
      copy.ballHpFactor = copy.ballHpFactor or ball.hpFactor or 12
      copy.ballWobble = copy.ballWobble or ball.wobbleFactor or 255
      copy.ballAutoCatch = copy.ballAutoCatch
      if copy.ballAutoCatch == nil then copy.ballAutoCatch = ball.autoCatch end
    elseif id == "MASTER_BALL" then
      copy.ballAutoCatch = true
      copy.ballRandMax = copy.ballRandMax or 0
    end
  elseif tmpl == "vitamin" then
    copy.vitaminStat = copy.vitaminStat or VITAMINS[id] or "hp"
  elseif tmpl == "x_item" then
    copy.xStat = copy.xStat or X_ITEMS[id] or "attack"
  elseif tmpl == "pp_restore" then
    if copy.ppFull == nil then
      copy.ppFull = (id == "MAX_ETHER" or id == "MAX_ELIXER")
    end
    if copy.ppAllMoves == nil then
      copy.ppAllMoves = (id == "ELIXER" or id == "MAX_ELIXER")
    end
  elseif tmpl == "machine" and def.machine then
    local m = {}
    for k, v in pairs(def.machine) do m[k] = v end
    copy.machine = copy.machine or m
  elseif tmpl == "custom" then
    copy.effect = copy.effect or def.effect
  end
end

local function deepCloneItem(S, def)
  local copy = {}
  for k, v in pairs(def) do
    if k == "machine" and type(v) == "table" then
      local m = {}
      for mk, mv in pairs(v) do m[mk] = mv end
      copy.machine = m
    elseif k == "icon" and type(v) == "table" then
      local ic = {}
      for ik, iv in pairs(v) do ic[ik] = iv end
      copy.icon = ic
    else
      copy[k] = v
    end
  end
  copy._isNew = false
  -- Keep effectTemplate only if the author already chose one.  Otherwise the
  -- form shows the inferred vanilla effect, and Save stays data-only until
  -- an effect chip/param is edited.
  if not copy.effectTemplate then
    local inferred = inferTemplate(S, def)
    local tmp = { id = def.id, effectTemplate = inferred }
    seedEffectFields(S, tmp, def)
    for k, v in pairs(tmp) do
      if k ~= "effectTemplate" and k ~= "id" and copy[k] == nil then
        copy[k] = v
      end
    end
  else
    seedEffectFields(S, copy, def)
  end
  return copy
end

local function resolveItem(S, id)
  if not id then return nil, false end
  if S.project.items[id] then return S.project.items[id], true end
  if S.data and S.data.items and S.data.items[id] then
    return S.data.items[id], false
  end
  return nil, false
end

local function ensureOwned(S, id)
  local def, owned = resolveItem(S, id)
  if not def then return nil end
  if owned then return def end
  local copy = deepCloneItem(S, def)
  S.project.items[id] = copy
  return copy
end

local function defaultItem(id)
  return {
    id = id,
    name = id,
    price = 300,
    tossable = true,
    effectTemplate = "heal",
    healAmount = 20,
    _isNew = true,
  }
end

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

local function cycle(list, cur)
  local idx = 0
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

local function hasCure(cures, st)
  for _, c in ipairs(cures or {}) do
    if c == st then return true end
  end
  return false
end

local function toggleCure(cures, st)
  local out, found = {}, false
  for _, c in ipairs(cures or {}) do
    if c == st then found = true else out[#out + 1] = c end
  end
  if not found then out[#out + 1] = st end
  return out
end

function Items.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end

  local listW = math.min(240 * s, w * 0.30)
  local formX = x + listW + 16 * s
  local formW = w - listW - 16 * s

  Kit.caption(x, y, "ITEMS")
  local qh = 28 * s
  local qy = y + 22 * s
  local q, qChanged = Search.field(S, "itemQuery", x, qy, listW, qh, "search items...")
  if qChanged then S.itemListOffset = 0 end
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y) - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local ids = allItemIds(S)
  if q ~= "" then
    local filtered, ql = {}, q:lower()
    for _, id in ipairs(ids) do
      local item = S.project.items[id]
        or (S.data.items and S.data.items[id])
      local name = item and tostring(item.name or "") or ""
      local summary = item and effectSummary(S, item) or ""
      if id:lower():find(ql, 1, true)
          or name:lower():find(ql, 1, true)
          or summary:lower():find(ql, 1, true) then
        filtered[#filtered + 1] = id
      end
    end
    ids = filtered
  end
  local rowH = 34 * s
  local thumb = 26 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / (rowH + 4 * s)))
  local scrollX, scrollY = x + 8 * s, listY + 8 * s
  local scrollW, scrollH = listW - 16 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S.itemListOffset = Kit.scroll(scrollX, scrollY, scrollW, scrollH,
    S.itemListOffset or 0, #ids, perPage)
  local itemNav = RegList.bindNav(S, ids, {
    selKey = "itemId", offsetKey = "itemListOffset", perPage = perPage,
  })
  local ry = scrollY
  for i = (S.itemListOffset or 0) + 1,
      math.min(#ids, (S.itemListOffset or 0) + perPage) do
    local id = ids[i]
    local owned = S.project.items[id] ~= nil
    local def = owned and S.project.items[id] or S.data.items[id]
    if Kit.row(scrollX, ry, rowW, rowH, S.itemId == id, PAL.blue) then
      itemNav.activate()
      S.itemId = id
    end
    Preview.drawItemIcon(S, def or { id = id },
      x + 12 * s, ry + (rowH - thumb) / 2, thumb, thumb)
    local textX = x + 16 * s + thumb
    local tw = math.max(40 * s, rowW - (textX - scrollX) - 8 * s)
    Kit.text("mono", Kit.ellipsize("mono", id, tw),
      textX, ry + 2 * s, owned and PAL.text or PAL.muted)
    Kit.text("micro", Kit.ellipsize("micro", effectSummary(S, def or { id = id }), tw),
      textX, ry + 16 * s, PAL.faint)
    ry = ry + rowH + 4 * s
  end
  S.itemListOffset = Kit.scrollbar(scrollX, scrollY, scrollW, scrollH,
    S.itemListOffset or 0, #ids, perPage)

  if Kit.button(x, y + h - 36 * s, listW, 32 * s, "+ New item",
      { kind = "good" }) then
    local nid = "NEW_ITEM"
    local n = 1
    while S.project.items[nid] or (S.data.items and S.data.items[nid]) do
      n = n + 1
      nid = "NEW_ITEM_" .. n
    end
    S.project.items[nid] = defaultItem(nid)
    S.itemId = nid
    App.markDirty()
  end

  local item, owned = resolveItem(S, S.itemId)
  if not item then
    local first = ids[1]
    S.itemId = first
    item, owned = resolveItem(S, first)
  end
  if not item then
    Kit.emptyBox(formX, listY, formW, listH, "No items in data — import a ROM cache")
    return
  end

  local function mutate()
    item = ensureOwned(S, S.itemId)
    owned = true
    return item
  end

  local tmpl = item.effectTemplate or inferTemplate(S, item)

  Kit.caption(formX, y, "EDIT  " .. (item.id or "?") .. (owned and "" or "  (vanilla)"))
  Kit.card(formX, listY, formW, listH, 12 * s)
  local footerH = owned and 44 * s or 12 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH)
  FormPane.track(S, "itemFormScroll", tostring(S.itemId))
  local fy, view = FormPane.begin(S, "itemFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local cardX, cardListY, cardListH = formX, listY, listH
  formX, formW = viewX, viewW  -- form body uses these as the clipped origin
  local labelW = 120 * s
  local fh = 28 * s

  local prevSize = 72 * s
  local itemPal = Preview.itemPaletteName(S, item)
  -- false = skip SGB remap. Avoid `x and false or y` (always yields y in Lua).
  local drawPal = itemPal
  if item.trueColor then drawPal = false end
  local function openItemPal()
    if item.trueColor then return end
    local eid = S.itemId or item.id
    PalettePicker.open(S, {
      current = item.palette,
      allowClear = true,
      clearLabel = "(sprite / MEWMON default)",
      title = "ITEM ICON PALETTE",
      onPick = function(id)
        item = mutate()
        item.palette = id
        Preview.invalidate()
        App.markDirty()
      end,
      owner = {
        kind = "item",
        entityId = eid,
        entityLabel = item.name or eid,
        assign = function(id)
          item = mutate()
          item.palette = id
          Preview.invalidate()
          App.markDirty()
        end,
      },
    })
  end
  Preview.drawItemIcon(S, item, formX + formW - prevSize, fy, prevSize, prevSize, drawPal)
  if Kit.press(formX + formW - prevSize, fy, prevSize, prevSize) then
    openItemPal()
  end
  if item.trueColor then
    Kit.text("micro", "true color",
      formX + formW - prevSize, fy + prevSize + 2 * s, PAL.yellow)
  else
    Preview.drawNamedSwatches(S, itemPal,
      formX + formW - prevSize, fy + prevSize + 2 * s, prevSize, 10 * s)
  end
  Kit.text("micro", "icon", formX + formW - prevSize + 4 * s,
    fy + prevSize + 14 * s, PAL.faint)
  local fieldW = formW - labelW - prevSize - 16 * s
  if fieldW < 140 * s then fieldW = formW - labelW - 8 * s end

  local function row(label, body)
    Kit.text("small", label, formX, fy + 6 * s, PAL.caption)
    body(formX + labelW, fy, fieldW, fh)
    fy = fy + fh + 8 * s
  end

  row("ID", function(fx, fy_, fw, fh_)
    local v = field(App, "it_id", fx, fy_, fw, fh_, item.id, "ITEM_ID")
    if v ~= item.id and v:match("^[%w_]+$")
       and not S.project.items[v]
       and not (S.data.items and S.data.items[v]) then
      item = mutate()
      S.project.items[item.id] = nil
      item.id = v
      S.project.items[v] = item
      S.itemId = v
      App.markDirty()
    end
  end)
  row("Name", function(fx, fy_, fw, fh_)
    local v = field(App, "it_name", fx, fy_, fw, fh_, item.name, "NAME")
    if v ~= (item.name or "") then item = mutate(); item.name = v end
  end)
  row("Price", function(fx, fy_, fw, fh_)
    local v = tonumber(field(App, "it_price", fx, fy_, 100 * s, fh_,
      tostring(item.price or 0), "0")) or 0
    if v ~= (item.price or 0) then item = mutate(); item.price = v end
  end)
  row("Tossable", function(fx, fy_, fw, fh_)
    local on = item.tossable ~= false and not item.keyItem
    if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.green) then
      item = mutate()
      item.tossable = not on
      if item.tossable then item.keyItem = nil end
      App.markDirty()
    end
  end)
  row("Icon PNG", function(fx, fy_, fw, fh_)
    local path = Preview.itemIconPath(S, item) or ""
    local custom = type(item.icon) == "string" or (type(item.icon) == "table" and item.icon.image)
    Kit.text("micro",
      Kit.ellipsize("micro", custom and path or ("default: " .. path), fw - 100 * s),
      fx, fy_ + 8 * s, PAL.muted)
    if Kit.button(fx + fw - 96 * s, fy_, 96 * s, fh_, "Browse", {
        kind = "ghost", tooltip = "Import item icon PNG",
      }) then
      item = mutate()
      local id = item.id
      App.pickFile("Item icon PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          local it = S.project.items[id]
          if not it then return end
          App.importToMod(picked, nil, function(rel)
            it.icon = rel
          end)
        end)
    end
  end)
  row("TrueColor", function(fx, fy_, fw, fh_)
    local on = item.trueColor and true or false
    if Kit.chip(fx, fy_, 80 * s, fh_, on and "YES" or "NO", on, PAL.yellow) then
      item = mutate()
      item.trueColor = not on
      if not item.trueColor then item.trueColor = nil end
      Preview.invalidate()
      App.markDirty()
    end
  end)
  if item.trueColor then
    row("Palette", function(fx, fy_, fw, fh_)
      Kit.text("small", "(ignored — TrueColor)", fx, fy_ + 6 * s, PAL.faint)
    end)
  else
    row("Palette", function(fx, fy_, fw, fh_)
      local eid = S.itemId or item.id
      PalettePicker.row(S, {
        x = fx, y = fy_, w = fw, h = fh_,
        current = item.palette or "",
        effective = Preview.itemPaletteName(S, item),
        emptyLabel = "(default)",
        clearLabel = "(sprite / MEWMON default)",
        allowClear = true,
        title = "ITEM ICON PALETTE",
        tooltip = "SGB palette for this item's icon preview",
        onPick = function(id)
          item = mutate()
          item.palette = id
          Preview.invalidate()
          App.markDirty()
        end,
        owner = {
          kind = "item",
          entityId = eid,
          entityLabel = item.name or eid,
          assign = function(id)
            item = mutate()
            item.palette = id
            Preview.invalidate()
            App.markDirty()
          end,
        },
      })
    end)
    do
      local eid = S.itemId or item.id
      fy = PaletteEdit.drawColorRows(S, {
        kind = "item",
        entityId = eid,
        entityLabel = item.name or eid,
        paletteId = Preview.itemPaletteName(S, item),
        assign = function(id)
          item = mutate()
          item.palette = id
          Preview.invalidate()
          App.markDirty()
        end,
        App = App,
        x = formX, y = fy, labelW = labelW,
        fieldW = formW - labelW - 20 * s, fh = fh,
        fieldPrefix = "it_pal_c",
      })
    end
  end

  Kit.text("small", "Effect", formX, fy + 6 * s, PAL.caption)
  fy = fy + 18 * s
  local tx, ty = formX, fy
  local maxX = formX + formW - 8 * s
  for _, t in ipairs(TEMPLATES) do
    local on = tmpl == t.id
    local bw = Kit.textWidth("micro", t.label) + 16 * s
    if tx + bw > maxX then
      tx = formX
      ty = ty + fh + 4 * s
    end
    if Kit.chip(tx, ty, bw, fh, t.label, on, PAL.yellow) then
      item = mutate()
      item.effectTemplate = t.id
      tmpl = t.id
      seedEffectFields(S, item, item)
      App.markDirty()
    end
    tx = tx + bw + 4 * s
  end
  fy = ty + fh + 10 * s

  Kit.text("micro", "→ " .. effectSummary(S, item), formX, fy, PAL.detail)
  fy = fy + 20 * s

  if tmpl == "heal" then
    local cur = item.healAmount or HEAL_AMOUNT[item.id] or 20
    row("Heal amount", function(fx, fy_, fw, fh_)
      local v = tonumber(field(App, "it_heal", fx, fy_, 100 * s, fh_,
        tostring(cur), "20")) or 20
      if v ~= cur then
        item = mutate()
        item.effectTemplate = "heal"
        item.healAmount = v
      end
    end)
  elseif tmpl == "status" then
    local cures = item.statusCures or STATUS_HEAL[item.id]
      or { "PSN", "BRN", "FRZ", "SLP", "PAR" }
    Kit.text("micro", "Cures", formX, fy + 6 * s, PAL.caption)
    tx = formX + labelW
    for _, st in ipairs(STATUSES) do
      local on = hasCure(cures, st)
      if Kit.chip(tx, fy, 52 * s, fh, st, on, PAL.green) then
        item = mutate()
        item.effectTemplate = "status"
        item.statusCures = toggleCure(item.statusCures or cures, st)
        App.markDirty()
      end
      tx = tx + 56 * s
    end
    fy = fy + fh + 8 * s
  elseif tmpl == "ball" then
    row("randMax", function(fx, fy_, fw, fh_)
      local cur = item.ballRandMax or 255
      local v = tonumber(field(App, "it_br", fx, fy_, 80 * s, fh_,
        tostring(cur), "255")) or 255
      if v ~= cur then
        item = mutate(); item.effectTemplate = "ball"; item.ballRandMax = v
      end
    end)
    row("hpFactor", function(fx, fy_, fw, fh_)
      local cur = item.ballHpFactor or 12
      local v = tonumber(field(App, "it_bh", fx, fy_, 80 * s, fh_,
        tostring(cur), "12")) or 12
      if v ~= cur then
        item = mutate(); item.effectTemplate = "ball"; item.ballHpFactor = v
      end
    end)
    row("wobble", function(fx, fy_, fw, fh_)
      local cur = item.ballWobble or 255
      local v = tonumber(field(App, "it_bw", fx, fy_, 80 * s, fh_,
        tostring(cur), "255")) or 255
      if v ~= cur then
        item = mutate(); item.effectTemplate = "ball"; item.ballWobble = v
      end
    end)
    row("Master?", function(fx, fy_, fw, fh_)
      local on = item.ballAutoCatch and true or false
      if Kit.chip(fx, fy_, 100 * s, fh_, on and "AUTO CATCH" or "ROLL", on, PAL.red) then
        item = mutate()
        item.effectTemplate = "ball"
        item.ballAutoCatch = not on
        App.markDirty()
      end
    end)
  elseif tmpl == "vitamin" then
    row("Stat", function(fx, fy_, fw, fh_)
      local cur = item.vitaminStat or VITAMINS[item.id] or "hp"
      if Kit.button(fx, fy_, 120 * s, fh_, cur, { kind = "accent" }) then
        item = mutate()
        item.effectTemplate = "vitamin"
        item.vitaminStat = cycle(VIT_STATS, cur)
        App.markDirty()
      end
    end)
  elseif tmpl == "x_item" then
    row("Battle stat", function(fx, fy_, fw, fh_)
      local cur = item.xStat or X_ITEMS[item.id] or "attack"
      if Kit.button(fx, fy_, 120 * s, fh_, cur, { kind = "accent" }) then
        item = mutate()
        item.effectTemplate = "x_item"
        item.xStat = cycle(X_STATS, cur)
        App.markDirty()
      end
    end)
  elseif tmpl == "pp_restore" then
    row("Fill", function(fx, fy_, fw, fh_)
      local full = item.ppFull
      if full == nil then
        full = item.id == "MAX_ETHER" or item.id == "MAX_ELIXER"
      end
      if Kit.chip(fx, fy_, 90 * s, fh_, full and "MAX PP" or "+10 PP", full, PAL.blue) then
        item = mutate()
        item.effectTemplate = "pp_restore"
        item.ppFull = not full
        App.markDirty()
      end
    end)
    row("Moves", function(fx, fy_, fw, fh_)
      local all = item.ppAllMoves
      if all == nil then
        all = item.id == "ELIXER" or item.id == "MAX_ELIXER"
      end
      if Kit.chip(fx, fy_, 110 * s, fh_, all and "ALL MOVES" or "ONE MOVE", all, PAL.blue) then
        item = mutate()
        item.effectTemplate = "pp_restore"
        item.ppAllMoves = not all
        App.markDirty()
      end
    end)
  elseif tmpl == "machine" then
    local machine = item.machine or { kind = "TM", move = "MEGA_PUNCH", number = 1 }
    row("Kind", function(fx, fy_, fw, fh_)
      local cur = machine.kind or "TM"
      if Kit.chip(fx, fy_, 70 * s, fh_, cur, true, PAL.yellow) then
        item = mutate()
        item.effectTemplate = "machine"
        item.machine = item.machine or { kind = "TM", move = "MEGA_PUNCH", number = 1 }
        item.machine.kind = (cur == "TM") and "HM" or "TM"
        App.markDirty()
      end
    end)
    row("Move", function(fx, fy_, fw, fh_)
      local v = field(App, "it_tm_move", fx, fy_, fw, fh_,
        machine.move or "", "MEGA_PUNCH")
      v = v:upper():gsub("%s+", "_")
      if v ~= (machine.move or "") then
        item = mutate()
        item.effectTemplate = "machine"
        item.machine = item.machine or {}
        item.machine.move = v
      end
    end)
    row("Number", function(fx, fy_, fw, fh_)
      local cur = machine.number or 1
      local v = tonumber(field(App, "it_tm_n", fx, fy_, 80 * s, fh_,
        tostring(cur), "1")) or 1
      if v ~= cur then
        item = mutate()
        item.effectTemplate = "machine"
        item.machine = item.machine or {}
        item.machine.number = v
      end
    end)
  elseif tmpl == "custom" then
    local effects = registeredEffects(S)
    if #effects == 0 then effects = { (item.id or "ITEM") .. "_EFFECT" } end
    row("Effect id", function(fx, fy_, fw, fh_)
      local cur = item.effect or effects[1]
      local label = #tostring(cur) > 28 and (tostring(cur):sub(1, 26) .. "…") or tostring(cur)
      if Kit.button(fx, fy_, fw, fh_, label, { kind = "accent" }) then
        item = mutate()
        item.effectTemplate = "custom"
        item.effect = cycle(effects, item.effect or effects[1])
        App.markDirty()
      end
    end)
    row("Or type id", function(fx, fy_, fw, fh_)
      local v = field(App, "it_eff", fx, fy_, fw, fh_, item.effect or "", "MY_EFFECT")
      if v ~= (item.effect or "") and v:match("^[%w_]+$") then
        item = mutate()
        item.effectTemplate = "custom"
        item.effect = v
      end
    end)
  elseif tmpl == "max_heal" or tmpl == "full_restore"
      or tmpl == "revive" or tmpl == "max_revive"
      or tmpl == "rare_candy" or tmpl == "pp_up" or tmpl == "flute" then
    Kit.text("micro", "Save installs a mod item_effect that replaces vanilla use.",
      formX, fy, PAL.muted)
    fy = fy + 22 * s
  elseif tmpl == "stone" then
    Kit.text("micro", "Evolution stones keep engine evolution logic unless you switch type.",
      formX, fy, PAL.muted)
    fy = fy + 22 * s
  elseif tmpl == "key" then
    Kit.text("micro", "Key items are not tossed; use prints the item name.",
      formX, fy, PAL.muted)
    fy = fy + 22 * s
  else
    Kit.text("micro", "No use effect override — name/price only. Pick a type above to replace use.",
      formX, fy, PAL.muted)
    fy = fy + 22 * s
  end

  Kit.text("micro",
    "List shows effect summary. First edit clones into the mod (Save = patch + effect).",
    formX, fy + 4 * s, PAL.faint)
  fy = fy + 28 * s
  FormPane.finish(S, "itemFormScroll", contentTop, fy, view)

  if owned and Kit.button(cardX + 12 * s, cardListY + cardListH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    S.project.items[item.id] = nil
    S.itemId = item.id
    App.markDirty()
  end
end

return Items
