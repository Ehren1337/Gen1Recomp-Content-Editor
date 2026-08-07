-- Project tab: create / open mod, overview, boot/constants, validate.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local RegList = require("RegList")
local FormPane = require("FormPane")
local ModIO = require("ModIO")
local DataSource = require("DataSource")
local PAL = Theme.PAL

local Project = {}

local FACINGS = { "up", "down", "left", "right" }

local function dataBoot(S)
  return (S.data and S.data.field and S.data.field.boot) or {}
end

local function dataConstants(S)
  return (S.data and S.data.constants) or {}
end

local function bootField(S, key)
  local b = S.project.boot
  if b and b[key] ~= nil then return b[key] end
  return dataBoot(S)[key]
end

local function lastHealField(S, key)
  local lh = S.project.boot and S.project.boot.lastHeal
  if lh and lh[key] ~= nil then return lh[key] end
  local dlh = dataBoot(S).lastHeal
  return dlh and dlh[key]
end

local function constField(S, key)
  local c = S.project.constants
  if c and c[key] ~= nil then return c[key] end
  return dataConstants(S)[key]
end

local function setBoot(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.boot[key] = val
  App.markDirty()
end

local function setLastHeal(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.boot.lastHeal = S.project.boot.lastHeal or {}
  S.project.boot.lastHeal[key] = val
  App.markDirty()
end

local function setConst(S, key, val, App)
  State.ensureProjectFields(S.project)
  S.project.constants[key] = val
  App.markDirty()
end

local function parseCsvIds(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part ~= "" then out[#out + 1] = part end
  end
  return out
end

local function joinCsvIds(t)
  if type(t) ~= "table" then return "" end
  return table.concat(t, ", ")
end

local function badgeRows(S)
  local c = S.project.constants
  if c and c.badges and #c.badges > 0 then return c.badges end
  local dc = dataConstants(S).badges
  if type(dc) == "table" and #dc > 0 then return dc end
  return {}
end

local function ensureBadges(S, App)
  State.ensureProjectFields(S.project)
  if not S.project.constants.badges or #S.project.constants.badges == 0 then
    local src = dataConstants(S).badges
    S.project.constants.badges = {}
    if type(src) == "table" then
      for i, row in ipairs(src) do
        S.project.constants.badges[i] = {
          id = row.id or "",
          name = row.name or "",
        }
      end
    end
    App.markDirty()
  end
  return S.project.constants.badges
end

-- Prefer MK* ERROR / FAIL lines; tips at the end used to hide the real errors.
local function lastValidateLines(text, n)
  if not text or text == "" then return {} end
  local all, errors, other = {}, {}, {}
  for line in tostring(text):gmatch("[^\r\n]+") do
    all[#all + 1] = line
    local u = line:upper()
    if u:find("ERROR", 1, true) or u:find("FAIL ", 1, true) then
      errors[#errors + 1] = line
    elseif not line:find("optional tip", 1, true) then
      other[#other + 1] = line
    end
  end
  local pick = (#errors > 0) and errors or other
  if #pick == 0 then pick = all end
  if #pick <= n then return pick end
  local out = {}
  for i = 1, n do out[i] = pick[i] end
  return out
end

function Project.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local pad = 16 * s
  local row = y

  Kit.caption(x, row, "MOD PROJECT")
  row = row + 28 * s

  local cardY = row
  local innerX = x + pad
  local innerW = w - 2 * pad
  local cy = cardY + pad

  local mods = ModIO.listMods()
  local btnH = 32 * s
  local chipH = 28 * s
  local chipGap = 8 * s

  local chipRows = 1
  local mx = 0
  for i, mid in ipairs(mods) do
    if i > 12 then break end
    local bw = Kit.textWidth("button", mid) + 24 * s
    if mx > 0 and mx + bw > innerW then
      chipRows = chipRows + 1
      mx = 0
    end
    mx = mx + bw + chipGap
  end
  if #mods == 0 then chipRows = 0 end

  local contentH = pad
    + 14 * s + 6 * s + btnH + 10 * s + 14 * s + 16 * s + 14 * s + 6 * s
  if chipRows > 0 then
    contentH = contentH + chipRows * chipH + (chipRows - 1) * chipGap
  else
    contentH = contentH + 14 * s
  end
  contentH = contentH + pad

  Kit.card(x, cardY, w, contentH, 14 * s)

  Kit.text("small", "New mod id", innerX, cy, PAL.caption)
  cy = cy + 20 * s

  local idW = math.min(280 * s, innerW - 150 * s)
  local idVal = Kit.textfield("new_mod_id", innerX, cy, idW, btnH,
    S.newModId or "my_content", "my_content")
  if idVal ~= S.newModId then S.newModId = idVal end

  if Kit.button(innerX + idW + 10 * s, cy, 140 * s, btnH, "Create",
      { kind = "primary" }) then
    App.createMod(S.newModId)
  end
  cy = cy + btnH + 10 * s

  Kit.text("micro", "Creates mods/<id>/ with manifest, editor_project.lua, main.lua",
    innerX, cy, PAL.muted)
  cy = cy + 14 * s + 16 * s

  Kit.text("small", "Existing mods/", innerX, cy, PAL.caption)
  cy = cy + 20 * s

  if #mods == 0 then
    Kit.text("micro", "(none yet)", innerX, cy, PAL.faint)
  else
    local cx = innerX
    local shown = 0
    for _, mid in ipairs(mods) do
      if shown >= 12 then break end
      local bw = Kit.textWidth("button", mid) + 24 * s
      if cx > innerX and cx + bw > x + w - pad then
        cx = innerX
        cy = cy + chipH + chipGap
      end
      if Kit.button(cx, cy, bw, chipH, mid, { kind = "accent" }) then
        App.openMod(ModIO.modsRoot() .. package.config:sub(1, 1) .. mid)
      end
      cx = cx + bw + chipGap
      shown = shown + 1
    end
  end

  row = cardY + contentH + 20 * s

  Kit.caption(x, row, "GAME DATA")
  row = row + 28 * s
  local src = S.dataSource or "fixtures"
  local prefs = S.dataPrefs or DataSource.loadPrefs()
  local srcLine = DataSource.label(src)
  if prefs.recompRoot and prefs.recompRoot ~= "" then
    srcLine = srcLine .. " — Linked: " .. tostring(prefs.recompRoot)
  end
  Kit.text("small", srcLine, x, row, PAL.text)
  row = row + 22 * s
  Kit.text("micro",
    "Shareable packs ship without a ROM cache. Link your Gen1Recomp folder "
      .. "or Import a ROM (cache stays in the save directory, not this pack). "
      .. "Playtest launches the Linked Recomp folder when one is set.",
    x, row, PAL.muted)
  row = row + 32 * s
  local dsW = 150 * s
  local dsGap = 10 * s
  if Kit.button(x, row, dsW, btnH, "Link Recomp", {
      kind = "primary",
      tooltip = "Use data/generated + assets from an existing Gen1Recomp install",
    }) then
    App.pickFolder("Choose Gen1Recomp folder", function(path)
      App.linkRecompFolder(path)
    end, prefs.recompRoot)
  end
  if Kit.button(x + dsW + dsGap, row, dsW, btnH, "Import ROM", {
      kind = "accent",
      tooltip = "Import a US Red/Blue/Yellow .gb into the save-directory cache",
    }) then
    App.pickFile("Choose Pokemon ROM",
      "Game Boy ROM (*.gb;*.gbc)|*.gb;*.gbc|All (*.*)|*.*",
      function(path) App.importRomFile(path) end)
  end
  if Kit.button(x + 2 * (dsW + dsGap), row, dsW, btnH, "Use fixtures", {
      kind = "ghost",
      tooltip = "ROM-free stub data for authoring without a cache",
    }) then
    App.useFixturesData()
  end
  row = row + btnH + 20 * s

  Kit.caption(x, row, "OVERVIEW")
  row = row + 28 * s

  if not S.project then
    Kit.emptyBox(x, row, w, 120 * s, "No mod open")
    return
  end

  State.ensureProjectFields(S.project)
  local p = S.project
  local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
  end

  local overviewH = 120 * s
  Kit.card(x, row, w, overviewH, 14 * s)
  Kit.text("title", p.name or p.id, x + 20 * s, row + 16 * s, PAL.heading)
  Kit.text("small", string.format(
    "Pokemon %d    Items %d    Maps %d    Tilesets %d",
    count(p.pokemon), count(p.items), count(p.maps), count(p.tilesets)),
    x + 20 * s, row + 56 * s, PAL.text)
  Kit.text("micro",
    "Save writes editor_project.lua + main.lua. MANIFEST / CODE tabs edit files under mods/.",
    x + 20 * s, row + 90 * s, PAL.muted)

  row = row + overviewH + 12 * s

  -- Always above the fold: GAME DATA used to push these into a lower card
  -- that early-returned when the window was too short.
  local fh = 28 * s
  local btnW = 120 * s
  if Kit.button(x, row, btnW, fh, "Validate", {
      kind = "primary",
      tooltip = "Run python tools/modkit.py validate on this mod",
    }) then
    if App.validateMod then App.validateMod()
    else S.status = "Implement App.validateMod() to run modkit validate from the editor" end
  end
  if Kit.button(x + btnW + 10 * s, row, btnW, fh, "Playtest", {
      kind = "accent",
      tooltip = prefs.recompRoot and prefs.recompRoot ~= ""
        and ("Sync mod into Linked Recomp and launch:\n" .. tostring(prefs.recompRoot))
        or "Enable this mod and launch (Link Recomp to playtest the full game)",
    }) then
    if App.playtestMod then App.playtestMod()
    else S.status = "Implement App.playtestMod() to launch a playtest build" end
  end
  row = row + fh + 8 * s
  if S.validateOutput and S.validateOutput ~= "" then
    local lines = lastValidateLines(S.validateOutput, 6)
    for _, line in ipairs(lines) do
      local col = line:upper():find("ERROR", 1, true) and PAL.red
        or line:upper():find("FAIL", 1, true) and PAL.yellow
        or PAL.muted
      Kit.text("micro", Kit.ellipsize("micro", line, w), x, row, col)
      row = row + 14 * s
    end
    row = row + 4 * s
  end

  local lowerH = y + h - row - 8 * s
  if lowerH < 80 * s then return end

  Kit.card(x, row, w, lowerH, 14 * s)
  local scrollPad = 12 * s
  local viewX = x + scrollPad
  local viewY = row + scrollPad
  local viewW = w - 2 * scrollPad
  local viewH = lowerH - 2 * scrollPad
  FormPane.track(S, "projectFormScroll", p.id or "project")
  local fy, view = FormPane.begin(S, "projectFormScroll", viewX, viewY, viewW, viewH)
  viewW = view.contentW or viewW
  local contentTop = fy
  local labelW = 120 * s
  local secGap = 20 * s

  local function row(label, body)
    Kit.text("small", label, viewX, fy + 6 * s, PAL.caption)
    body(viewX + labelW, fy, viewW - labelW - 8 * s, fh)
    fy = fy + fh + 8 * s
  end

  Kit.caption(viewX, fy, "BOOT")
  fy = fy + 24 * s

  row("Start map", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "startMap") or "")
    local v = RegList.field(App, "pr_boot_map", fx, fy_, fw, fh_, cur, "REDS_HOUSE_2F")
    if v ~= cur then setBoot(S, "startMap", v, App) end
  end)

  row("Start X", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startX") or 0
    local v = RegList.num(App, "pr_boot_x", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startX", v, App) end
  end)

  row("Start Y", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startY") or 0
    local v = RegList.num(App, "pr_boot_y", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startY", v, App) end
  end)

  row("Facing", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "startFacing") or "down")
    if Kit.button(fx, fy_, fw, fh_, Kit.ellipsize("small", cur, fw - 8 * s),
        { kind = "ghost" }) then
      setBoot(S, "startFacing", RegList.cycle(FACINGS, cur), App)
    end
  end)

  row("Player", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "playerName") or "")
    local v = RegList.field(App, "pr_boot_pname", fx, fy_, fw, fh_, cur, "RED")
    if v ~= cur then setBoot(S, "playerName", v, App) end
  end)

  row("Rival", function(fx, fy_, fw, fh_)
    local cur = tostring(bootField(S, "rivalName") or "")
    local v = RegList.field(App, "pr_boot_rname", fx, fy_, fw, fh_, cur, "BLUE")
    if v ~= cur then setBoot(S, "rivalName", v, App) end
  end)

  row("Start $", function(fx, fy_, fw, fh_)
    local cur = bootField(S, "startMoney") or 0
    local v = RegList.num(App, "pr_boot_money", fx, fy_, 100 * s, fh_, cur)
    if v ~= cur then setBoot(S, "startMoney", v, App) end
  end)

  row("Last heal map", function(fx, fy_, fw, fh_)
    local cur = tostring(lastHealField(S, "map") or "")
    local v = RegList.field(App, "pr_boot_lhm", fx, fy_, fw, fh_, cur, "REDS_HOUSE_2F")
    if v ~= cur then setLastHeal(S, "map", v, App) end
  end)

  row("Last heal X", function(fx, fy_, fw, fh_)
    local cur = lastHealField(S, "x") or 0
    local v = RegList.num(App, "pr_boot_lhx", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setLastHeal(S, "x", v, App) end
  end)

  row("Last heal Y", function(fx, fy_, fw, fh_)
    local cur = lastHealField(S, "y") or 0
    local v = RegList.num(App, "pr_boot_lhy", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setLastHeal(S, "y", v, App) end
  end)

  fy = fy + secGap
  Kit.caption(viewX, fy, "CONSTANTS")
  fy = fy + 24 * s

  row("Level cap", function(fx, fy_, fw, fh_)
    local cur = constField(S, "levelCap") or 100
    local v = RegList.num(App, "pr_const_lvl", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "levelCap", v, App) end
  end)

  row("Dex size", function(fx, fy_, fw, fh_)
    local cur = constField(S, "dexSize") or 151
    local v = RegList.num(App, "pr_const_dex", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "dexSize", v, App) end
  end)

  row("Dex digits", function(fx, fy_, fw, fh_)
    local cur = constField(S, "dexDigits") or 3
    local v = RegList.num(App, "pr_const_ddig", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "dexDigits", v, App) end
  end)

  row("Party max", function(fx, fy_, fw, fh_)
    local cur = constField(S, "partyMax") or 6
    local v = RegList.num(App, "pr_const_party", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "partyMax", v, App) end
  end)

  row("Bag size", function(fx, fy_, fw, fh_)
    local cur = constField(S, "bagSize") or 20
    local v = RegList.num(App, "pr_const_bag", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "bagSize", v, App) end
  end)

  row("Money cap", function(fx, fy_, fw, fh_)
    local cur = constField(S, "moneyCap") or 999999
    local v = RegList.num(App, "pr_const_money", fx, fy_, 100 * s, fh_, cur)
    if v ~= cur then setConst(S, "moneyCap", v, App) end
  end)

  row("Coin cap", function(fx, fy_, fw, fh_)
    local cur = constField(S, "coinCap") or 9999
    local v = RegList.num(App, "pr_const_coin", fx, fy_, 80 * s, fh_, cur)
    if v ~= cur then setConst(S, "coinCap", v, App) end
  end)

  row("HM moves", function(fx, fy_, fw, fh_)
    local cur = joinCsvIds(constField(S, "hmMoves"))
    local v = RegList.field(App, "pr_const_hm", fx, fy_, fw, fh_, cur, "CUT, FLY, SURF")
    if v ~= cur then setConst(S, "hmMoves", parseCsvIds(v), App) end
  end)

  Kit.text("small", "Badges", viewX, fy + 6 * s, PAL.caption)
  fy = fy + 28 * s
  local badges = badgeRows(S)
  if #badges == 0 then
    Kit.text("micro", "(no badges — add one below)", viewX, fy, PAL.faint)
    fy = fy + 20 * s
  end
  for i = 1, math.max(#badges, 0) do
    local badge = badges[i] or { id = "", name = "" }
    local idCur = tostring(badge.id or "")
    local nameCur = tostring(badge.name or "")
    Kit.text("micro", "#" .. i, viewX, fy + 8 * s, PAL.muted)
    local idV = RegList.field(App, "pr_bdg_id_" .. i, viewX + 28 * s, fy, 140 * s, fh,
      idCur, "BOULDERBADGE")
    local nameV = RegList.field(App, "pr_bdg_nm_" .. i, viewX + 176 * s, fy,
      viewW - 176 * s - 44 * s, fh, nameCur, "Boulder")
    if idV ~= idCur or nameV ~= nameCur then
      local rows = ensureBadges(S, App)
      rows[i] = rows[i] or {}
      rows[i].id = idV
      rows[i].name = nameV
    end
    if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X", { kind = "danger" }) then
      local rows = ensureBadges(S, App)
      table.remove(rows, i)
      App.markDirty()
      break
    end
    fy = fy + fh + 6 * s
  end
  if Kit.button(viewX, fy, 100 * s, fh, "+ Badge", { kind = "good" }) then
    local rows = ensureBadges(S, App)
    rows[#rows + 1] = { id = "NEW_BADGE", name = "Badge" }
    App.markDirty()
  end
  fy = fy + fh + secGap

  Kit.caption(viewX, fy, "TRADES / SHOPS")
  fy = fy + 24 * s
  Kit.text("micro",
    "Use the TRADES and SHOPS tabs to edit in-game trades and mart stock.",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s
  if Kit.button(viewX, fy, 100 * s, fh, "Trades", { kind = "accent" }) then
    S.tab = "trades"
  end
  if Kit.button(viewX + 110 * s, fy, 100 * s, fh, "Shops", { kind = "accent" }) then
    S.tab = "shops"
  end
  fy = fy + fh + secGap

  Kit.caption(viewX, fy, "FLY ORDER")
  fy = fy + 24 * s
  Kit.text("micro",
    "field.flyOrder (Town Map / Fly menu) and landing spots in field.flyWarps.",
    viewX, fy, PAL.muted)
  fy = fy + 20 * s

  local function ensureFlyOrder()
    if type(S.project.flyOrder) == "table" then return S.project.flyOrder end
    local base = (S.data and S.data.field and S.data.field.flyOrder) or {}
    local copy = {}
    for i, mid in ipairs(base) do copy[i] = mid end
    S.project.flyOrder = copy
    if next(S.project.flyWarps or {}) == nil then
      local fw = (S.data and S.data.field and S.data.field.flyWarps) or {}
      S.project.flyWarps = {}
      for mid, spot in pairs(fw) do
        if type(spot) == "table" then
          S.project.flyWarps[mid] = { x = spot.x or 0, y = spot.y or 0 }
        end
      end
    end
    App.markDirty()
    return copy
  end

  if type(S.project.flyOrder) ~= "table" then
    if Kit.button(viewX, fy, 160 * s, fh, "Edit fly order…", { kind = "accent" }) then
      ensureFlyOrder()
    end
    fy = fy + fh + 8 * s
  else
    local order = S.project.flyOrder
    S.project.flyWarps = S.project.flyWarps or {}
    for i, mid in ipairs(order) do
      local midV = RegList.field(App, "pr_fly_" .. i, viewX, fy,
        160 * s, fh, tostring(mid or ""), "PALLET_TOWN"):upper():gsub("%s+", "_")
      if midV ~= mid then
        order[i] = midV
        if S.project.flyWarps[mid] and not S.project.flyWarps[midV] then
          S.project.flyWarps[midV] = S.project.flyWarps[mid]
          S.project.flyWarps[mid] = nil
        end
        App.markDirty()
        mid = midV
      end
      local spot = S.project.flyWarps[mid]
      if not spot then
        local base = S.data and S.data.field and S.data.field.flyWarps
          and S.data.field.flyWarps[mid]
        spot = { x = (base and base.x) or 0, y = (base and base.y) or 0 }
        S.project.flyWarps[mid] = spot
      end
      local xV = tonumber(RegList.num(App, "pr_flyx_" .. i,
        viewX + 170 * s, fy, 50 * s, fh, tonumber(spot.x) or 0)) or 0
      local yV = tonumber(RegList.num(App, "pr_flyy_" .. i,
        viewX + 228 * s, fy, 50 * s, fh, tonumber(spot.y) or 0)) or 0
      if xV ~= (spot.x or 0) or yV ~= (spot.y or 0) then
        spot.x, spot.y = xV, yV
        App.markDirty()
      end
      Kit.text("micro", "land x,y", viewX + 286 * s, fy + 8 * s, PAL.faint)
      if Kit.button(viewX + viewW - 36 * s, fy, 32 * s, fh, "X",
          { kind = "danger" }) then
        S.project.flyWarps[mid] = nil
        table.remove(order, i)
        App.markDirty()
        break
      end
      fy = fy + fh + 6 * s
    end
    if Kit.button(viewX, fy, 120 * s, fh, "+ Fly spot", { kind = "good" }) then
      order[#order + 1] = "NEW_TOWN"
      S.project.flyWarps["NEW_TOWN"] = { x = 0, y = 0 }
      App.markDirty()
    end
    fy = fy + fh + 8 * s
  end

  FormPane.finish(S, "projectFormScroll", contentTop, fy, view)
end

return Project
