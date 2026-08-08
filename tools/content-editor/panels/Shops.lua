-- Shops tab: every text_pointers entry with a mart inventory (Poké Marts).

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local ItemPicker = require("ItemPicker")
local PAL = Theme.PAL

local Shops = {}

local DEFAULT_MART = {
  "POKE_BALL", "POTION", "ANTIDOTE", "PARLYZ_HEAL",
  "BURN_HEAL", "ICE_HEAL", "AWAKENING", "REPEL",
}

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

local function cloneEntry(src)
  local e = {}
  if not src then return e end
  for k, v in pairs(src) do
    if k == "mart" and type(v) == "table" then
      local m = {}
      for i, id in ipairs(v) do m[i] = id end
      e.mart = m
    else
      e[k] = v
    end
  end
  return e
end

-- Collect shops from project + vanilla text_pointers (entries with .mart).
local function collectShops(S)
  local byKey, keys = {}, {}
  local function consider(label, textId, entry, owned)
    if type(entry) ~= "table" or type(entry.mart) ~= "table" then return end
    local key = label .. "/" .. textId
    if byKey[key] and byKey[key].owned then return end
    if not byKey[key] then keys[#keys + 1] = key end
    byKey[key] = {
      key = key,
      label = label,
      textId = textId,
      mart = entry.mart,
      owned = owned and true or false,
      entry = entry,
    }
  end

  local dataPtrs = S.data and S.data.text_pointers or {}
  for label, bucket in pairs(dataPtrs) do
    if type(bucket) == "table" then
      for textId, entry in pairs(bucket) do
        if type(textId) == "string" then
          consider(label, textId, entry, false)
        end
      end
    end
  end

  local projPtrs = S.project and S.project.text_pointers or {}
  for label, bucket in pairs(projPtrs) do
    if type(bucket) == "table" then
      for textId, entry in pairs(bucket) do
        if type(textId) == "string" then
          consider(label, textId, entry, true)
        end
      end
    end
  end

  table.sort(keys)
  return keys, byKey
end

local function ensureShop(S, label, textId, App)
  State.ensureProjectFields(S.project)
  S.project.text_pointers[label] = S.project.text_pointers[label] or {}
  local bucket = S.project.text_pointers[label]
  if not bucket[textId] then
    local base = S.data and S.data.text_pointers and S.data.text_pointers[label]
    bucket[textId] = cloneEntry(base and base[textId])
  end
  local e = bucket[textId]
  if type(e.mart) ~= "table" then
    e.mart = {}
    for i, id in ipairs(DEFAULT_MART) do e.mart[i] = id end
    e.nurse, e.pc, e.cableClub = nil, nil, nil
  end
  if App then App.markDirty() end
  return e
end

function Shops.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  local keys, byKey = collectShops(S)
  local items = allItemIds(S)

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "SHOPS", keys, {
      queryKey = "shopsQuery",
      offsetKey = "shopsListOffset",
      selKey = "shopKey",
      accent = PAL.blue,
      isOwned = function(key)
        local rec = byKey[key]
        return rec and rec.owned
      end,
      searchPh = "search map / TEXT_*...",
      filter = function(key, q)
        local rec = byKey[key]
        local ql = q:lower()
        if key:lower():find(ql, 1, true) then return true end
        if rec and tostring(rec.textId):lower():find(ql, 1, true) then
          return true
        end
        if rec and type(rec.mart) == "table" then
          for _, id in ipairs(rec.mart) do
            if tostring(id):lower():find(ql, 1, true) then return true end
          end
        end
        return false
      end,
      footerLabel = "+ New shop",
      onFooter = function()
        S.shopKey = "__new__"
      end,
    })

  if not S.shopKey and shown[1] then S.shopKey = shown[1] end
  local key = S.shopKey
  local fh = 28 * s

  -- Create flow
  if key == "__new__" then
    Kit.caption(formX, y, "NEW SHOP")
    Kit.card(formX, listY, formW, listH, 12 * s)
    local viewX = formX + 12 * s
    local fy = listY + 16 * s
    local viewW = formW - 24 * s
    Kit.text("micro",
      "Map label is the text_pointers key (e.g. ViridianMart, PewterCity).",
      viewX, fy, PAL.muted)
    fy = fy + 22 * s
    Kit.text("small", "Map label", viewX, fy + 6 * s, PAL.caption)
    S._shopNewLabel = RegList.field(App, "shop_new_lbl", viewX + 100 * s, fy,
      viewW - 100 * s, fh, S._shopNewLabel or "ViridianMart", "ViridianMart")
    fy = fy + fh + 8 * s
    Kit.text("small", "TEXT_*", viewX, fy + 6 * s, PAL.caption)
    S._shopNewText = RegList.field(App, "shop_new_tid", viewX + 100 * s, fy,
      viewW - 100 * s, fh,
      S._shopNewText or "TEXT_VIRIDIANMART_CLERK", "TEXT_*")
      :upper():gsub("%s+", "_")
    fy = fy + fh + 16 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Create", { kind = "good" }) then
      local label = tostring(S._shopNewLabel or ""):gsub("%s+", "")
      local textId = tostring(S._shopNewText or ""):upper():gsub("%s+", "_")
      if label ~= "" and textId ~= "" then
        ensureShop(S, label, textId, App)
        S.shopKey = label .. "/" .. textId
        S.status = "Shop " .. S.shopKey
      else
        S.status = "Need map label and TEXT_*"
      end
    end
    if Kit.button(viewX + 150 * s, fy, 100 * s, fh, "Cancel", { kind = "ghost" }) then
      S.shopKey = shown[1]
    end
    return
  end

  local rec = key and byKey[key]
  if not rec then
    Kit.emptyBox(formX, listY, formW, listH,
      #keys == 0
        and "No shops found (Link Recomp / Import ROM, or + New shop)"
        or "Select a shop")
    return
  end

  Kit.caption(formX, y,
    rec.textId .. (rec.owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "shopsFormScroll", key, rec.owned and 44 * s or 12 * s)
  local contentTop = fy

  Kit.text("micro", rec.label .. " / " .. rec.textId, viewX, fy, PAL.muted)
  fy = fy + 20 * s
  Kit.text("micro",
    string.format("%d item(s)  |  Save patches text_pointers", #(rec.mart or {})),
    viewX, fy, PAL.detail)
  fy = fy + 24 * s

  if not rec.owned then
    Kit.text("micro", "Edit clones this shop into the mod.", viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensureShop(S, rec.label, rec.textId, App)
      keys, byKey = collectShops(S)
      rec = byKey[key]
    end
    fy = fy + fh + 12 * s
  end

  local mart = rec.mart or {}
  Kit.text("micro", "Stock", viewX, fy, PAL.caption)
  fy = fy + 18 * s

  for mi, itemId in ipairs(mart) do
    local slot = mi
    local label = rec.label
    local textId = rec.textId
    ItemPicker.field(S, {
      x = viewX, y = fy, w = viewW - 44 * s, h = fh,
      current = itemId or "POKE_BALL",
      title = "SHOP STOCK",
      onPick = function(id)
        local e = ensureShop(S, label, textId, App)
        e.mart[slot] = id
        App.markDirty()
      end,
    })
    if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
        { kind = "danger", font = "small" }) then
      local e = ensureShop(S, label, textId, App)
      table.remove(e.mart, slot)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end

  if Kit.button(viewX, fy, 120 * s, fh, "+ Add item", { kind = "good" }) then
    local label = rec.label
    local textId = rec.textId
    ensureShop(S, label, textId, App)
    ItemPicker.open(S, {
      current = (#items > 0 and items[1]) or "POKE_BALL",
      title = "ADD SHOP ITEM",
      onPick = function(id)
        local e = ensureShop(S, label, textId, App)
        e.mart[#e.mart + 1] = id
        App.markDirty()
      end,
    })
  end
  fy = fy + fh + 8 * s

  FormPane.finish(S, "shopsFormScroll", contentTop, fy, view)

  if rec.owned and Kit.button(formX + 12 * s, listY + listH - 40 * s,
      140 * s, 32 * s, "Clear shop", {
        kind = "danger",
        tooltip = "Remove mart from this TEXT_* (reverts role to talk)",
      }) then
    local e = ensureShop(S, rec.label, rec.textId, App)
    e.mart = nil
    local empty = true
    for k in pairs(e) do
      if k ~= "mart" then empty = false; break end
    end
    if empty then
      S.project.text_pointers[rec.label][rec.textId] = nil
      if not next(S.project.text_pointers[rec.label]) then
        S.project.text_pointers[rec.label] = nil
      end
    end
    S.shopKey = nil
    App.markDirty()
  end
end

return Shops
