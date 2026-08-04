-- AI classes tab: per-trainer item use and switching overrides.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local PAL = Theme.PAL

local AiClasses = {}

local NEW_CLASS = {
  kind = "class",
  uses = 0,
  chance = 0,
  switch = false,
  switchChance = 0,
  switchBelow = 0,
  hpBelow = 0,
  onStatus = false,
  item = "",
  _isNew = true,
}

local function dataTable(S)
  if S.data and S.data.ai_classes then return S.data.ai_classes end
  local ok, t = pcall(require, "data.scripts.ai_classes")
  return ok and t or {}
end

local function projectBucket(S)
  State.ensureProjectFields(S.project)
  return S.project.aiClasses
end

local function listIds(S)
  local proj = projectBucket(S)
  local data = dataTable(S)
  local seen, ids = {}, {}
  for id in pairs(proj) do
    seen[id] = true
    ids[#ids + 1] = id
  end
  for id in pairs(data) do
    if type(id) == "string" and not id:match("^LAYER_") and not seen[id] then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

local function resolve(S, id)
  local proj = projectBucket(S)
  if proj[id] ~= nil then return proj[id], true end
  local data = dataTable(S)
  if data[id] ~= nil then return data[id], false end
  return nil, false
end

local function summarize(rec)
  if not rec or type(rec) ~= "table" then return "empty" end
  local bits = {}
  if rec.kind and rec.kind ~= "class" then bits[#bits + 1] = rec.kind end
  if rec.uses and rec.uses ~= 0 then bits[#bits + 1] = "uses=" .. tostring(rec.uses) end
  if rec.item and rec.item ~= "" then bits[#bits + 1] = tostring(rec.item) end
  if rec.chance and rec.chance ~= 0 then bits[#bits + 1] = "chance=" .. tostring(rec.chance) end
  if rec.onStatus then bits[#bits + 1] = "onStatus" end
  if rec.switch then bits[#bits + 1] = "switch" end
  if rec.switchChance and rec.switchChance ~= 0 then
    bits[#bits + 1] = "swChance=" .. tostring(rec.switchChance)
  end
  if rec.switchBelow and rec.switchBelow ~= 0 then
    bits[#bits + 1] = "sw<1/" .. tostring(rec.switchBelow)
  end
  if rec.hpBelow and rec.hpBelow ~= 0 then
    bits[#bits + 1] = "hp<1/" .. tostring(rec.hpBelow)
  end
  if #bits == 0 then return "GenericAI (no items/switch)" end
  return table.concat(bits, "  ")
end

local function cloneRecord(rec)
  if type(rec) ~= "table" then
    local copy = {}
    for k, v in pairs(NEW_CLASS) do copy[k] = v end
    return copy
  end
  local copy = {}
  for k, v in pairs(rec) do
    if type(v) ~= "function" then copy[k] = v end
  end
  copy.kind = copy.kind or "class"
  return copy
end

function AiClasses.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)
  local proj = projectBucket(S)
  local data = dataTable(S)
  local ids = listIds(S)

  local formX, formW, listY, listH, shown = RegList.drawList(S, App, x, y, w, h,
    "AI CLASSES", ids, {
      queryKey = "aiClassQuery",
      offsetKey = "aiClassListOffset",
      selKey = "aiClassId",
      accent = PAL.yellow,
      isOwned = function(id) return proj[id] ~= nil end,
      filter = function(id, q)
        local ql = q:lower()
        if id:lower():find(ql, 1, true) then return true end
        local rec = select(1, resolve(S, id))
        return tostring(summarize(rec)):lower():find(ql, 1, true) ~= nil
      end,
      footerLabel = "+ New",
      onFooter = function()
        local nid = "OPP_NEW_AI"
        local n = 1
        while proj[nid] or data[nid] do
          n = n + 1
          nid = "OPP_NEW_AI_" .. n
        end
        local copy = {}
        for k, v in pairs(NEW_CLASS) do copy[k] = v end
        proj[nid] = copy
        S.aiClassId = nid
        App.markDirty()
      end,
    })

  if not S.aiClassId then S.aiClassId = shown[1] end
  local id = S.aiClassId
  local rec, owned = resolve(S, id)
  if not id then
    Kit.emptyBox(formX, listY, formW, listH, "No AI classes in data")
    return
  end

  Kit.caption(formX, y, (id or "?") .. (owned and "" or "  (vanilla)"))
  local fy, view, viewX, viewW = RegList.beginForm(S, formX, listY, formW, listH,
    "aiClassFormScroll", tostring(id), owned and 44 * s or 12 * s)
  local contentTop = fy
  local labelW = 120 * s
  local fh = 28 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  local function ensure()
    if owned then return proj[id] end
    proj[id] = cloneRecord(rec)
    owned = true
    App.markDirty()
    return proj[id]
  end

  Kit.text("micro", summarize(rec), viewX, fy, PAL.muted)
  fy = fy + 20 * s

  local r = type(rec) == "table" and rec or NEW_CLASS

  row("Kind", function(fx, fy_, fw, fh_)
    local cur = (owned and proj[id].kind) or r.kind or "class"
    if Kit.button(fx, fy_, fw, fh_, Kit.ellipsize("small", cur, fw - 8 * s),
        { kind = "ghost" }) then
      local e = ensure()
      e.kind = RegList.cycle({ "class", "layer", "brain" }, cur)
    end
  end)

  row("Uses", function(fx, fy_, fw, fh_)
    local cur = (owned and proj[id].uses) or r.uses or 0
    local v = RegList.num(App, "ai_uses", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().uses = v end
  end)

  row("Chance", function(fx, fy_, fw, fh_)
    local cur = (owned and proj[id].chance) or r.chance or 0
    local v = RegList.num(App, "ai_chance", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().chance = v end
  end)

  row("Item", function(fx, fy_, fw, fh_)
    local cur = (owned and proj[id].item) or r.item or ""
    local v = RegList.field(App, "ai_item", fx, fy_, fw, fh_, cur, "POTION")
    if v ~= cur then ensure().item = v end
  end)

  row("Switch", function(fx, fy_, fw, fh_)
    local cur = not not ((owned and proj[id].switch) or r.switch)
    if Kit.chip(fx, fy_, 80 * s, fh_, cur and "YES" or "NO", cur, PAL.yellow) then
      ensure().switch = not cur
    end
  end)

  row("Sw chance", function(fx, fy_, fw, fh_)
    local cur = (owned and proj[id].switchChance) or r.switchChance or 0
    local v = RegList.num(App, "ai_swch", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().switchChance = v end
  end)

  row("Sw below", function(fx, fy_, fw, fh_)
    local cur = (owned and proj[id].switchBelow) or r.switchBelow or 0
    local v = RegList.num(App, "ai_swbl", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().switchBelow = v end
  end)

  row("HP below", function(fx, fy_, fw, fh_)
    local cur = (owned and proj[id].hpBelow) or r.hpBelow or 0
    local v = RegList.num(App, "ai_hpbl", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then ensure().hpBelow = v end
  end)

  row("On status", function(fx, fy_, fw, fh_)
    local cur = not not ((owned and proj[id].onStatus) or r.onStatus)
    if Kit.chip(fx, fy_, 80 * s, fh_, cur and "YES" or "NO", cur, PAL.yellow) then
      ensure().onStatus = not cur
    end
  end)

  if not owned then
    Kit.text("micro", "Edit clones into the mod (Save emits ai_classes override).",
      viewX, fy, PAL.faint)
    fy = fy + 18 * s
    if Kit.button(viewX, fy, 140 * s, fh, "Clone to mod", { kind = "accent" }) then
      ensure()
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "aiClassFormScroll", contentTop, fy, view)
  if owned and Kit.button(formX + 12 * s, listY + listH - 40 * s, 120 * s, 32 * s,
      "Revert", { kind = "danger" }) then
    proj[id] = nil
    App.markDirty()
  end
end

return AiClasses
