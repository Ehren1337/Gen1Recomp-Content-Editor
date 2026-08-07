-- Events tab: talk-script step builder, Oak starter remap, save-flag tester.
-- SCRIPTS browses every map object/sign TEXT_* plus vanilla MapScripts rows.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local SaveIO = require("SaveIO")
local Search = require("Search")
local FormPane = require("FormPane")
local TalkIndex = require("TalkIndex")
local ModWriter = require("ModWriter")
local RegList = require("RegList")
local PAL = Theme.PAL

local Events = {}

local STEP_KINDS = {
  { id = "show_text", label = "Show text" },
  { id = "show_image", label = "Show image" },
  { id = "ask", label = "Ask yes/no" },
  { id = "label", label = "Label" },
  { id = "jump", label = "Jump to label" },
  { id = "jump_if_yes", label = "Jump if yes" },
  { id = "jump_if_no", label = "Jump if no" },
  { id = "face_player", label = "Face player" },
  { id = "give_item", label = "Give item" },
  { id = "take_item", label = "Take item" },
  { id = "check_item_skip", label = "Skip if has item" },
  { id = "check_item_missing", label = "Skip if no item" },
  { id = "give_pokemon", label = "Give pokemon" },
  { id = "give_starter", label = "Give starter" },
  { id = "oneshot_gift", label = "One-shot item" },
  { id = "oneshot_pokemon", label = "One-shot pokemon" },
  { id = "set_flag", label = "Set flag" },
  { id = "clear_flag", label = "Clear flag" },
  { id = "check_flag_skip", label = "Skip if flag set" },
  { id = "check_flag_missing", label = "Skip if flag clear" },
  { id = "heal_party", label = "Heal party" },
  { id = "give_money", label = "Give money" },
  { id = "warp", label = "Warp" },
  { id = "wild_battle", label = "Wild battle" },
  { id = "trainer_battle", label = "Trainer battle" },
  { id = "oneshot_trainer", label = "One-shot trainer" },
  { id = "set_field", label = "Set save field" },
  { id = "trade", label = "In-game trade" },
  { id = "raw", label = "Engine cmd" },
}

local OAK_BALLS = {
  { from = "CHARMANDER", label = "Left ball (Charmander)" },
  { from = "SQUIRTLE", label = "Middle ball (Squirtle)" },
  { from = "BULBASAUR", label = "Right ball (Bulbasaur)" },
}

-- Footer quick-add buttons (kind = Kit button style).
local function shortcutDefs(S)
  return {
    { label = "+ Text", kind = "good",
      tip = "Show this NPC's Dialog TEXT_* (or a literal)",
      make = function()
        local key = S.eventScriptKey or ""
        local tid = key:match("/(.+)$")
        return { kind = "show_text", text = tid or "..." }
      end },
    { label = "+ Ask", kind = "accent",
      tip = "Yes/No prompt (skips rest on NO by default)",
      make = function()
        local key = S.eventScriptKey or ""
        local tid = key:match("/(.+)$")
        return { kind = "ask", text = tid or "OK?", skipOnNo = true }
      end },
    { label = "+ Image", kind = "accent",
      tip = "Framed PNG (PicBox); Browse to import",
      make = function()
        return { kind = "show_image", path = "assets/pic.png", text = "" }
      end },
    { label = "+ Face", kind = "ghost",
      tip = "NPC faces the player",
      make = function() return { kind = "face_player" } end },
    { label = "+ Engine", kind = "ghost",
      tip = "Raw ScriptRunner row (check_flag, hide_object, play_sound, …)",
      make = function()
        return {
          kind = "raw",
          note = "check_flag EVENT_FLAG",
          row = { "check_flag", "EVENT_FLAG" },
        }
      end },
    { label = "+ Item", kind = "accent",
      tip = "Give an item",
      make = function()
        return { kind = "give_item", item = "POTION", count = 1 }
      end },
    { label = "+ Take item", kind = "ghost",
      tip = "Remove an item from the bag",
      make = function()
        return { kind = "take_item", item = "POTION", count = 1 }
      end },
    { label = "+ Check item", kind = "ghost",
      tip = "Skip remaining steps if the item is missing",
      make = function()
        return { kind = "check_item_missing", item = "POTION" }
      end },
    { label = "+ Pokemon", kind = "accent",
      tip = "Give a Pokémon (nickname prompt)",
      make = function()
        return { kind = "give_pokemon", species = "EEVEE", level = 25 }
      end },
    { label = "+ Starter", kind = "accent",
      tip = "Give starter + EVENT_GOT_STARTER (+ chose flag)",
      make = function()
        return {
          kind = "give_starter", species = "BULBASAUR", level = 5,
          choseFlag = "EVENT_CHOSE_BULBASAUR", rivalStarter = 1,
        }
      end },
    { label = "+ Set flag", kind = "ghost",
      tip = "Set a save/event flag",
      make = function() return { kind = "set_flag", flag = "DONE" } end },
    { label = "+ Clear flag", kind = "ghost",
      tip = "Clear a save/event flag",
      make = function() return { kind = "clear_flag", flag = "DONE" } end },
    { label = "+ If flag", kind = "ghost",
      tip = "Skip rest if flag is already set",
      make = function()
        return { kind = "check_flag_skip", flag = "DONE" }
      end },
    { label = "+ If no flag", kind = "ghost",
      tip = "Skip rest if flag is clear",
      make = function()
        return { kind = "check_flag_missing", flag = "DONE" }
      end },
    { label = "+ Label", kind = "ghost",
      tip = "Named jump target",
      make = function() return { kind = "label", name = "label" } end },
    { label = "+ Jump", kind = "ghost",
      tip = "Jump to a label",
      make = function() return { kind = "jump", name = "end" } end },
    { label = "+ Heal", kind = "ghost",
      tip = "Heal the party",
      make = function() return { kind = "heal_party" } end },
    { label = "+ Money", kind = "ghost",
      tip = "Give money",
      make = function() return { kind = "give_money", amount = 500 } end },
    { label = "+ Warp", kind = "ghost",
      tip = "Warp the player to a map cell",
      make = function()
        return {
          kind = "warp", map = "PALLET_TOWN", x = 5, y = 6, facing = "down",
        }
      end },
    { label = "+ Wild", kind = "accent",
      tip = "Start a wild battle",
      make = function()
        return { kind = "wild_battle", species = "PIDGEY", level = 5 }
      end },
    { label = "+ Trainer", kind = "accent",
      tip = "Trainer battle (no oneshot flag)",
      make = function()
        return {
          kind = "trainer_battle",
          trainer = S.trainerId or "OPP_YOUNGSTER", party = 1,
        }
      end },
    { label = "1-shot item", kind = "ghost",
      tip = "Give an item once (flag-gated)",
      make = function()
        return {
          kind = "oneshot_gift", text = "Here, take this!",
          after = "I already gave you one.", item = "POTION", flag = "DONE",
        }
      end },
    { label = "1-shot mon", kind = "ghost",
      tip = "Give a Pokémon once (flag-gated)",
      make = function()
        return {
          kind = "oneshot_pokemon", text = "Here! Take this POKeMON!",
          after = "I already gave you one.", species = "EEVEE", level = 25,
          flag = "GOT_MON",
        }
      end },
    { label = "1-shot fight", kind = "accent",
      tip = "One-shot trainer battle with before/after text",
      make = function()
        return {
          kind = "oneshot_trainer",
          text = "Let's fight!", won = "I lost...", after = "You're strong.",
          trainer = S.trainerId or "OPP_YOUNGSTER", party = 1,
          flag = "BEAT_TRAINER",
        }
      end },
    { label = "+ Trade", kind = "accent",
      tip = "In-game trade (field.trades index + done flag)",
      make = function()
        return { kind = "trade", index = 1, flag = "TRADED" }
      end },
  }
end

local function stepLabel(kind)
  for _, k in ipairs(STEP_KINDS) do
    if k.id == kind then return k.label end
  end
  return kind or "?"
end

local function cycleKind(kind)
  local idx = 1
  for i, k in ipairs(STEP_KINDS) do
    if k.id == kind then idx = i; break end
  end
  return STEP_KINDS[(idx % #STEP_KINDS) + 1].id
end

local function parseKey(key)
  if not key then return nil, nil end
  return key:match("^([^/]+)/(.+)$")
end

-- Create an empty mod script (only for "+ Empty script").
local function ensureEmptyScript(S, key)
  State.ensureProjectFields(S.project)
  local mapId, textId = parseKey(key)
  if not mapId then return nil end
  local script = S.project.talkScripts[key]
  if not script then
    -- Default show_text to this pin's TEXT_* so Dialog bodies connect.
    script = {
      mapId = mapId,
      textId = textId,
      steps = { { kind = "show_text", text = textId or "Hello!" } },
    }
    S.project.talkScripts[key] = script
  end
  return script
end

local function sourceColor(src)
  if src == "mod" then return PAL.green end
  if src == "script" or src == "lua" then return PAL.yellow end
  if src == "text" then return PAL.blue end
  if src == "item" or src == "trainer" or src == "pokemon" then return PAL.blue end
  return PAL.faint
end

local function field(App, id, x, y, w, h, value, ph)
  local v = Kit.textfield(id, x, y, w, h, value, ph)
  if v ~= tostring(value or "") then App.markDirty() end
  return v
end

-- Fit an id into a row: ellipsize by font metrics, then hard-cut if still wide.
-- Collapse script newlines so LOVE never paints a second line under the bar.
local function fitIn(fontName, text, maxW)
  text = tostring(text or "")
    :gsub("\r\n", "\n"):gsub("[\n\r\f\v]", " / "):gsub(" +/ +", " / ")
  if maxW <= 0 then return "" end
  local shown = Kit.ellipsize(fontName, text, maxW)
  if Kit.textWidth(fontName, shown) > maxW + 0.5 then
    local unit = math.max(1, Kit.textWidth(fontName, "W"))
    local n = math.max(0, math.floor(maxW / unit) - 3)
    shown = (n > 0 and text:sub(1, n) or "") .. "..."
  end
  return shown
end

-- Resolve TEXT_* / _FooText to a string-table id for project.text lookup.
local function resolveStringIdForText(S, value, mapId)
  if type(value) ~= "string" or value == "" then return nil end
  if value:find("[%s\\]") then return nil end
  if S.project and S.project.text and S.project.text[value] ~= nil then
    return value
  end
  if S.data and S.data.text and S.data.text[value] ~= nil then
    return value
  end
  if value:match("^TEXT_") then
    local mid = mapId or S.eventMapId or S.dialogMapId
    if mid then
      local label = State.mapLabel(S, mid)
      local function from(ptrs)
        local e = ptrs and label and ptrs[label] and ptrs[label][value]
        if type(e) == "table" and type(e.text) == "string" then return e.text end
      end
      return from(S.project and S.project.text_pointers)
        or from(S.data and S.data.text_pointers)
        or ("_" .. value:gsub("^TEXT_", ""))
    end
  end
  if value:match("^_[%w_]+") then return value end
  return nil
end

local function resolveTextBody(S, strId)
  if not strId then return "" end
  if S.project and S.project.text and S.project.text[strId] ~= nil then
    return tostring(S.project.text[strId])
  end
  if S.data and S.data.text and S.data.text[strId] ~= nil then
    return tostring(S.data.text[strId])
  end
  return ""
end

local function encodeTextBody(body)
  return tostring(body or ""):gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\v", "\\v")
end

local function decodeTextBody(display)
  return tostring(display or "")
    :gsub("\\n", "\n"):gsub("\\f", "\f"):gsub("\\v", "\v"):gsub("\\/", "/")
end

-- Edit show_text / ask: TEXT_* / _FooText edit project.text; literals decode \n.
local function drawDialogTextFields(S, App, step, i, fx, fw, fh, s, row)
  local y = row()
  local value = step.text or ""
  local mapId = S.eventMapId or select(1, parseKey(S.eventScriptKey))
  local strId = resolveStringIdForText(S, value, mapId)
  if strId then
    local body = resolveTextBody(S, strId)
    local display = encodeTextBody(body)
    local edited = field(App, "ev_tbody_" .. i, fx, y, fw, fh, display,
      "dialog text (\\n = line, \\f = page)")
    if edited ~= display then
      State.ensureProjectFields(S.project)
      S.project.text[strId] = decodeTextBody(edited)
      if value:match("^TEXT_") and mapId then
        local label = State.mapLabel(S, mapId)
        if label then
          S.project.text_pointers[label] = S.project.text_pointers[label] or {}
          local ptr = S.project.text_pointers[label][value]
          if type(ptr) ~= "table" then
            S.project.text_pointers[label][value] = { text = strId }
          elseif not ptr.text then
            ptr.text = strId
          end
        end
      end
    end
    local yKey = row()
    Kit.text("micro", "key", fx, yKey + 8 * s, PAL.faint)
    step.text = field(App, "ev_t_" .. i, fx + 34 * s, yKey, fw - 34 * s, fh,
      value, "TEXT_* or _FooText")
  else
    local display = encodeTextBody(value)
    local edited = field(App, "ev_t_" .. i, fx, y, fw, fh, display,
      "literal (\\n = line, \\f = page)")
    if edited ~= display then
      step.text = decodeTextBody(edited)
    end
  end
end

local function previewDialogText(S, value, maxW)
  local mapId = S.eventMapId or select(1, parseKey(S.eventScriptKey))
  local strId = resolveStringIdForText(S, value, mapId)
  if strId then
    local body = resolveTextBody(S, strId)
    if body ~= "" then
      return fitIn("micro", body, maxW)
    end
  end
  return fitIn("micro", value or "", maxW)
end

local function drawStepFields(S, App, step, i, kind, fx, fy, fw, fh, s)
  local used = 0
  local function row()
    used = used + 1
    return fy + (used - 1) * (fh + 4 * s)
  end

  if kind == "show_text" or kind == "ask" then
    drawDialogTextFields(S, App, step, i, fx, fw, fh, s, row)
    if kind == "ask" then
      local y2 = row()
      local on = step.skipOnNo ~= false
      if Kit.chip(fx, y2, 160 * s, fh, on and "Skip on NO" or "Keep on NO",
          on, PAL.yellow) then
        step.skipOnNo = on and false or true
        App.markDirty()
      end
    end
  elseif kind == "show_image" then
    local y = row()
    local browseW = 90 * s
    local pathW = math.max(80 * s, fw - browseW - 6 * s)
    step.path = field(App, "ev_img_" .. i, fx, y, pathW, fh,
      step.path or step.image or "", "assets/pic.png")
    if Kit.button(fx + pathW + 6 * s, y, browseW, fh, "Browse",
        { kind = "ghost", font = "small",
          tooltip = "Import a PNG into the mod and use it here" }) then
      App.pickFile("Image PNG", "PNG (*.png)|*.png|All (*.*)|*.*",
        function(picked)
          if not picked or picked == "" then return end
          App.importToMod(picked, nil, function(rel)
            step.path = rel
            App.markDirty()
            S.status = "Image set to " .. tostring(rel)
          end)
        end)
    end
    local y2 = row()
    step.text = field(App, "ev_imgt_" .. i, fx, y2, fw, fh,
      step.text or "", "optional caption after close")
  elseif kind == "set_flag" or kind == "clear_flag"
      or kind == "check_flag_skip" or kind == "check_flag_missing" then
    local y = row()
    step.flag = field(App, "ev_f_" .. i, fx, y, 160 * s, fh,
      step.flag or "STARTED", "STARTED or EVENT_*")
    local full = State.modFlag(S.project, step.flag)
    S.project.eventFlags[full] = true
    Kit.text("micro", full, fx + 170 * s, y + 8 * s, PAL.faint)
  elseif kind == "give_item" or kind == "take_item"
      or kind == "check_item_skip" or kind == "check_item_missing" then
    local y = row()
    step.item = field(App, "ev_i_" .. i, fx, y, 140 * s, fh,
      step.item or "POTION", "POTION"):upper():gsub("%s+", "_")
    if kind == "give_item" or kind == "take_item" then
      step.count = tonumber(field(App, "ev_c_" .. i, fx + 150 * s, y, 50 * s, fh,
        tostring(step.count or 1), "1")) or 1
    end
  elseif kind == "give_pokemon" or kind == "give_starter"
      or kind == "oneshot_pokemon" or kind == "wild_battle" then
    local y = row()
    step.species = field(App, "ev_sp_" .. i, fx, y, 140 * s, fh,
      step.species or (kind == "wild_battle" and "PIDGEY" or "PIKACHU"),
      "SPECIES"):upper():gsub("%s+", "_")
    step.level = tonumber(field(App, "ev_lv_" .. i, fx + 150 * s, y, 50 * s, fh,
      tostring(step.level or 5), "5")) or 5
    if kind ~= "wild_battle" then
      local y2 = row()
      local nick = step.skipNickname and true or false
      if Kit.chip(fx, y2, 140 * s, fh, nick and "No nickname" or "Ask nickname",
          nick, PAL.blue) then
        step.skipNickname = (not nick) or nil
        App.markDirty()
      end
    end
    if kind == "give_starter" then
      local y3 = row()
      step.choseFlag = field(App, "ev_cf_" .. i, fx, y3, 160 * s, fh,
        step.choseFlag or "EVENT_CHOSE_BULBASAUR", "EVENT_CHOSE_*")
      step.rivalStarter = tonumber(field(App, "ev_rs_" .. i,
        fx + 170 * s, y3, 40 * s, fh,
        tostring(step.rivalStarter or 1), "1")) or 1
      Kit.text("micro", "rival 1-3", fx + 220 * s, y3 + 8 * s, PAL.faint)
    end
    if kind == "oneshot_pokemon" then
      local y3 = row()
      step.text = field(App, "ev_ot_" .. i, fx, y3, fw, fh,
        step.text or "Here! Take this POKeMON!", "intro")
      local y4 = row()
      step.after = field(App, "ev_oa_" .. i, fx, y4, fw - 140 * s, fh,
        step.after or "I already gave you one.", "after")
      step.flag = field(App, "ev_of_" .. i, fx + fw - 130 * s, y4, 120 * s, fh,
        step.flag or "GOT_MON", "GOT_MON")
      S.project.eventFlags[State.modFlag(S.project, step.flag)] = true
    end
  elseif kind == "oneshot_gift" then
    local y = row()
    step.text = field(App, "ev_gt_" .. i, fx, y, fw, fh,
      step.text or "Here, take this!", "intro")
    local y2 = row()
    step.item = field(App, "ev_gi_" .. i, fx, y2, 120 * s, fh,
      step.item or "POTION", "POTION"):upper():gsub("%s+", "_")
    step.count = tonumber(field(App, "ev_gc_" .. i, fx + 130 * s, y2, 40 * s, fh,
      tostring(step.count or 1), "1")) or 1
    step.flag = field(App, "ev_gf_" .. i, fx + 180 * s, y2, 100 * s, fh,
      step.flag or "DONE", "DONE")
    S.project.eventFlags[State.modFlag(S.project, step.flag)] = true
    local y3 = row()
    step.after = field(App, "ev_ga_" .. i, fx, y3, fw, fh,
      step.after or "I already gave you one.", "after text")
  elseif kind == "give_money" then
    local y = row()
    step.amount = tonumber(field(App, "ev_m_" .. i, fx, y, 100 * s, fh,
      tostring(step.amount or 500), "500")) or 500
  elseif kind == "warp" then
    local y = row()
    step.map = field(App, "ev_wm_" .. i, fx, y, 140 * s, fh,
      step.map or "PALLET_TOWN", "MAP"):upper():gsub("%s+", "_")
    step.x = tonumber(field(App, "ev_wx_" .. i, fx + 150 * s, y, 40 * s, fh,
      tostring(step.x or 0), "0")) or 0
    step.y = tonumber(field(App, "ev_wy_" .. i, fx + 200 * s, y, 40 * s, fh,
      tostring(step.y or 0), "0")) or 0
    step.facing = field(App, "ev_wf_" .. i, fx + 250 * s, y, 70 * s, fh,
      step.facing or "down", "down")
  elseif kind == "trainer_battle" or kind == "oneshot_trainer" then
    local y = row()
    step.trainer = field(App, "ev_tr_" .. i, fx, y, 160 * s, fh,
      step.trainer or "OPP_BUG_CATCHER", "OPP_*"):upper():gsub("%s+", "_")
    step.party = tonumber(field(App, "ev_tp_" .. i, fx + 170 * s, y, 40 * s, fh,
      tostring(step.party or 1), "1")) or 1
    if kind == "oneshot_trainer" then
      local y2 = row()
      step.text = field(App, "ev_tb_" .. i, fx, y2, fw, fh,
        step.text or "Let's fight!", "before battle")
      local y3 = row()
      step.won = field(App, "ev_tw_" .. i, fx, y3, fw - 140 * s, fh,
        step.won or "I lost...", "on win")
      step.flag = field(App, "ev_tf_" .. i, fx + fw - 130 * s, y3, 120 * s, fh,
        step.flag or "BEAT_TRAINER", "BEAT_*")
      S.project.eventFlags[State.modFlag(S.project, step.flag)] = true
      local y4 = row()
      step.after = field(App, "ev_ta_" .. i, fx, y4, fw, fh,
        step.after or "You're strong.", "after defeated")
    end
  elseif kind == "set_field" then
    local y = row()
    step.field = field(App, "ev_sf_" .. i, fx, y, 140 * s, fh,
      step.field or "mod:value", "mod:key or rivalStarter")
    step.value = field(App, "ev_sv_" .. i, fx + 150 * s, y, 100 * s, fh,
      tostring(step.value or ""), "value")
    if Kit.button(fx + 260 * s, y, 70 * s, fh,
        step.valueType or "str", { kind = "ghost" }) then
      local order = { "str", "number", "bool" }
      local idx = 1
      for oi, o in ipairs(order) do
        if o == (step.valueType or "str") then idx = oi; break end
      end
      step.valueType = order[(idx % #order) + 1]
      App.markDirty()
    end
  elseif kind == "trade" then
    local y = row()
    step.index = tonumber(field(App, "ev_trd_" .. i, fx, y, 50 * s, fh,
      tostring(step.index or 1), "1")) or 1
    Kit.text("micro", "trade #", fx + 56 * s, y + 8 * s, PAL.faint)
    step.flag = field(App, "ev_trdf_" .. i, fx + 110 * s, y, 140 * s, fh,
      step.flag or "TRADED", "TRADED")
    local full = State.modFlag(S.project, step.flag)
    S.project.eventFlags[full] = true
    Kit.text("micro", full, fx + 260 * s, y + 8 * s, PAL.faint)
  elseif kind == "raw" then
    local y = row()
    if not step.note or step.note == "" then
      if type(step.row) == "table" then
        step.note = ModWriter.formatEngineLine(step.row)
      else
        step.note = "check_flag EVENT_FLAG"
      end
    end
    local prev = step.note
    step.note = field(App, "ev_raw_" .. i, fx, y, fw, fh,
      step.note, "verb arg1 arg2 …")
    if step.note ~= prev then
      step.row = ModWriter.parseEngineLine(step.note)
    end
  elseif kind == "label" then
    local y = row()
    step.name = field(App, "ev_lbl_" .. i, fx, y, fw, fh,
      step.name or step.label or "", "label_name")
  elseif kind == "jump" or kind == "jump_if_yes" or kind == "jump_if_no" then
    local y = row()
    step.name = field(App, "ev_jmp_" .. i, fx, y, fw, fh,
      step.name or step.label or "", "target_label")
  elseif kind == "face_player" or kind == "heal_party" then
    Kit.text("micro", "(no params)", fx, row() + 8 * s, PAL.faint)
  end

  return used
end

local function drawScripts(S, x, y, w, h, App)
  local s = Kit.scale
  TalkIndex.ensureScripts()
  State.ensureProjectFields(S.project)

  local mapColW = math.min(160 * s, w * 0.18)
  local listW = math.min(260 * s, w * 0.32)
  local qh = 28 * s
  local qy = y + 22 * s
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y)

  -- Map picker (same idea as Dialog): every object on the map is listed.
  Kit.caption(x, y, "MAP")
  local mapQ, mapQCh = Search.field(S, "eventMapQuery", x, qy, mapColW, qh, "maps...")
  if mapQCh then S.eventMapOffset = 0 end
  Kit.card(x, listY, mapColW, listH, 12 * s)
  local maps = Search.filterIds(TalkIndex.allMapIds(S), mapQ)
  if not S.eventMapId then
    S.eventMapId = S.dialogMapId or S.mapId or maps[1]
  end
  local mapRowH = 26 * s
  local perMap = math.max(1, math.floor((listH - 16 * s) / (mapRowH + 2 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = mapColW - 12 * s
  local mapScrollH = listH - 16 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.eventMapOffset = Kit.scroll(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.eventMapOffset or 0, #maps, perMap)
  local mapNav = RegList.bindNav(S, maps, {
    selKey = "eventMapId", offsetKey = "eventMapOffset", perPage = perMap,
    onSelect = function()
      S.eventScriptKey = nil
      S.eventScriptOffset = 0
    end,
  })
  local ry = listY + 8 * s
  for i = (S.eventMapOffset or 0) + 1,
      math.min(#maps, (S.eventMapOffset or 0) + perMap) do
    local id = maps[i]
    if Kit.row(mapScrollX, ry, mapRowW, mapRowH, S.eventMapId == id, PAL.blue) then
      mapNav.activate()
      S.eventMapId = id
      S.eventScriptKey = nil
      S.eventScriptOffset = 0
    end
    Kit.pushClip(mapScrollX, ry, mapRowW, mapRowH)
    Kit.text("micro", fitIn("micro", id, math.max(8, mapRowW - 12 * s)),
      mapScrollX + 6 * s, ry + 6 * s, PAL.text)
    Kit.popClip()
    ry = ry + mapRowH + 2 * s
  end
  S.eventMapOffset = Kit.scrollbar(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.eventMapOffset or 0, #maps, perMap)

  -- Object / TEXT_* events for the map
  local pinX = x + mapColW + 10 * s
  Kit.caption(pinX, y, "OBJECT EVENTS")
  local q, qChanged = Search.field(S, "eventScriptQuery", pinX, qy, listW, qh,
    "search events...")
  if qChanged then S.eventScriptOffset = 0 end
  Kit.card(pinX, listY, listW, listH, 12 * s)

  local entries = TalkIndex.collect(S, S.eventMapId)
  entries = Search.filterItems(entries, q, function(e)
    return table.concat({
      e.textId or "", e.label or "", e.source or "", e.key or "",
    }, " ")
  end)

  local rowH = 34 * s
  local footerBtns = 70 * s
  local perPage = math.max(1, math.floor((listH - footerBtns - 16 * s) / (rowH + 3 * s)))
  local pinScrollX = pinX + 6 * s
  local pinScrollW = listW - 12 * s
  local pinScrollH = listH - footerBtns - 16 * s
  local pinRowW = Kit.scrollInnerWidth(pinScrollW)
  S.eventScriptOffset = Kit.scroll(pinScrollX, listY + 8 * s, pinScrollW,
    pinScrollH, S.eventScriptOffset or 0, #entries, perPage)
  local entryKeys = {}
  for i, e in ipairs(entries) do entryKeys[i] = e.key end
  local eventNav = RegList.bindNav(S, entryKeys, {
    selKey = "eventScriptKey", offsetKey = "eventScriptOffset", perPage = perPage,
  })
  ry = listY + 8 * s
  for i = (S.eventScriptOffset or 0) + 1,
      math.min(#entries, (S.eventScriptOffset or 0) + perPage) do
    local e = entries[i]
    if Kit.row(pinScrollX, ry, pinRowW, rowH, S.eventScriptKey == e.key, PAL.yellow) then
      eventNav.activate()
      S.eventScriptKey = e.key
      -- Selection only — do not invent a Hello! stub.
    end
    local badge = TalkIndex.sourceLabel(e.source)
    local badgeW = Kit.textWidth("micro", badge) + 10 * s
    Kit.pushClip(pinScrollX, ry, pinRowW, rowH)
    Kit.text("micro",
      fitIn("micro", e.textId, math.max(8, pinRowW - badgeW - 16 * s)),
      pinScrollX + 6 * s, ry + 4 * s, PAL.text)
    Kit.text("micro", fitIn("micro", e.label, math.max(8, pinRowW - 12 * s)),
      pinScrollX + 6 * s, ry + 18 * s, PAL.faint)
    Kit.text("micro", badge, pinScrollX + pinRowW - badgeW, ry + 4 * s,
      sourceColor(e.source))
    Kit.popClip()
    ry = ry + rowH + 3 * s
  end
  S.eventScriptOffset = Kit.scrollbar(pinScrollX, listY + 8 * s, pinScrollW,
    pinScrollH, S.eventScriptOffset or 0, #entries, perPage)

  if Kit.button(pinX + 8 * s, listY + listH - 70 * s, listW - 16 * s, 28 * s,
      "From Dialog selection", { kind = "accent" }) then
    if S.dialogMapId and S.dialogTextId then
      S.eventMapId = S.dialogMapId
      S.eventScriptKey = S.dialogMapId .. "/" .. S.dialogTextId
    else
      S.status = "Pick a map NPC/sign on the Dialog tab first"
    end
  end
  if Kit.button(pinX + 8 * s, listY + listH - 36 * s, listW - 16 * s, 28 * s,
      "+ Empty script", { kind = "good" }) then
    local mapId = S.eventMapId or S.mapId or S.dialogMapId or "NEW_MAP"
    local textId = "TEXT_" .. mapId .. "_NPC1"
    local key = mapId .. "/" .. textId
    ensureEmptyScript(S, key)
    S.eventMapId = mapId
    S.eventScriptKey = key
    App.markDirty()
  end

  local formX = pinX + listW + 12 * s
  local formW = w - (formX - x)
  Kit.caption(formX, y, "STEPS")
  Kit.card(formX, listY, formW, listH, 12 * s)

  if not S.eventScriptKey then
    Kit.emptyBox(formX + 8 * s, listY + 8 * s, formW - 16 * s, listH - 16 * s,
      "Select a map object — badges: SCRIPT (vanilla), TEXT, ITEM, MOD…")
    return
  end

  local mapId, textId = parseKey(S.eventScriptKey)
  if not mapId then
    Kit.emptyBox(formX + 8 * s, listY + 8 * s, formW - 16 * s, listH - 16 * s,
      "Invalid event key")
    return
  end

  local owned = S.project.talkScripts[S.eventScriptKey]
  local steps, meta = TalkIndex.resolveSteps(S, mapId, textId)
  local readOnly = not owned
  -- Shortcut grid needs ~4 rows when editing; clone button is a single row.
  local footerH = readOnly and 40 * s or 120 * s
  local pad = 12 * s
  local viewX = formX + pad
  local viewY = listY + pad + 36 * s
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH - 36 * s)

  Kit.text("micro", fitIn("micro", S.eventScriptKey, formW - 24 * s),
    formX + 12 * s, listY + 10 * s, PAL.faint)
  local src = (meta and meta.source) or (owned and "mod") or "?"
  Kit.text("micro",
    readOnly
      and ("Vanilla / engine (" .. TalkIndex.sourceLabel(src)
        .. ") — Clone to mod to override on Save")
      or "Mod override (emitted on Save)",
    formX + 12 * s, listY + 22 * s, readOnly and PAL.yellow or PAL.green)

  FormPane.track(S, "eventFormScroll", S.eventScriptKey .. (readOnly and ":v" or ":m"))
  local fy, view = FormPane.begin(S, "eventFormScroll", viewX, viewY, viewW, viewH)
  local contentTop = fy
  local fh = 28 * s
  local kindW = 150 * s
  local innerW = view.contentW or view.w

  if #steps == 0 then
    Kit.text("small", "No script rows for this object.", viewX, fy, PAL.muted)
    fy = fy + 24 * s
  end

  for i, step in ipairs(steps) do
    local kind = step.kind or "show_text"
    if readOnly then
      Kit.text("micro", stepLabel(kind), viewX, fy + 8 * s, PAL.caption)
      if kind == "raw" then
        Kit.text("micro", fitIn("micro", step.note or "", innerW - kindW - 8 * s),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.muted)
      elseif kind == "show_image" then
        local line = tostring(step.path or step.image or "")
        if step.text and step.text ~= "" then
          line = line .. "  ·  " .. tostring(step.text)
        end
        Kit.text("micro", fitIn("micro", line, innerW - kindW - 8 * s),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.text)
      elseif kind == "show_text" or kind == "ask" then
        Kit.text("micro",
          previewDialogText(S, step.text, innerW - kindW - 8 * s),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.text)
      elseif kind == "label" or kind == "jump" or kind == "jump_if_yes"
          or kind == "jump_if_no" then
        Kit.text("micro", fitIn("micro", step.name or step.label or "",
            innerW - kindW - 8 * s),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.text)
      elseif kind == "set_flag" or kind == "clear_flag"
          or kind == "check_flag_skip" or kind == "check_flag_missing" then
        Kit.text("micro", tostring(step.flag or ""),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.text)
      elseif kind == "give_item" or kind == "take_item"
          or kind == "check_item_skip" or kind == "check_item_missing" then
        Kit.text("micro",
          tostring(step.item or "") .. " x" .. tostring(step.count or 1),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.text)
      elseif kind == "give_pokemon" or kind == "give_starter"
          or kind == "oneshot_pokemon" or kind == "wild_battle" then
        Kit.text("micro",
          tostring(step.species or "") .. " Lv" .. tostring(step.level or 5),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.text)
      else
        Kit.text("micro", stepLabel(kind),
          viewX + kindW + 8 * s, fy + 8 * s, PAL.faint)
      end
      fy = fy + fh + 6 * s
    else
      local script = owned
      if Kit.button(viewX, fy, kindW, fh, stepLabel(kind),
          { kind = "accent", font = "small",
            tooltip = kind == "raw"
              and "Engine cmd — edit the line, or click to change step type"
              or "Click to change step type" }) then
        local nextKind = cycleKind(kind)
        step.kind = nextKind
        if nextKind == "raw" and (not step.note or step.note == "") then
          step.note = "check_flag EVENT_FLAG"
          step.row = { "check_flag", "EVENT_FLAG" }
        end
        App.markDirty()
      end
      local rowsN = drawStepFields(S, App, step, i, step.kind or kind,
        viewX + kindW + 8 * s, fy, innerW - kindW - 48 * s, fh, s)
      local blockH = math.max(1, rowsN) * (fh + 4 * s)
      if Kit.button(viewX + innerW - 32 * s, fy, 28 * s, fh, "X",
          { kind = "danger", font = "small" }) then
        table.remove(script.steps, i)
        App.markDirty()
      end
      fy = fy + blockH + 8 * s
    end
  end

  FormPane.finish(S, "eventFormScroll", contentTop, fy, view)

  if readOnly then
    local by = listY + listH - 34 * s
    if Kit.button(formX + 12 * s, by, 180 * s, 28 * s, "Clone to mod",
        { kind = "good", font = "small" }) then
      TalkIndex.cloneToProject(S, mapId, textId)
      App.markDirty()
      S.status = "Cloned " .. S.eventScriptKey .. " into mod (Save to emit override)"
    end
    return
  end

  local script = owned
  local shortcuts = shortcutDefs(S)
  local bh = 26 * s
  local gap = 4 * s
  local bx = formX + 12 * s
  local by = listY + listH - footerH + 6 * s
  local maxX = formX + formW - 12 * s
  for _, sc in ipairs(shortcuts) do
    local bw = Kit.textWidth("small", sc.label) + 16 * s
    if bx + bw > maxX then
      bx = formX + 12 * s
      by = by + bh + gap
    end
    if Kit.button(bx, by, bw, bh, sc.label,
        { kind = sc.kind or "ghost", font = "small", tooltip = sc.tip }) then
      script.steps = script.steps or {}
      script.steps[#script.steps + 1] = sc.make()
      App.markDirty()
    end
    bx = bx + bw + gap
  end
end

local function drawStarters(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  Kit.caption(x, y, "OAK LAB STARTERS")
  local listY = y + 28 * s
  Kit.text("micro",
    "Remap the three Oak's Lab balls. Save emits pokemon.before_give (like example_mew_starter).",
    x, listY, PAL.muted)
  listY = listY + 22 * s

  Kit.card(x, listY, w, h - (listY - y), 12 * s)
  local fy = listY + 16 * s
  local fh = 30 * s
  local remap = S.project.starterRemap

  for _, ball in ipairs(OAK_BALLS) do
    local cur = remap[ball.from]
    local sp = (type(cur) == "table" and cur.species)
      or (type(cur) == "string" and cur)
      or ball.from
    local lv = (type(cur) == "table" and tonumber(cur.level)) or 5

    Kit.text("small", ball.label, x + 20 * s, fy + 6 * s, PAL.caption)
    fy = fy + 22 * s
    Kit.text("micro", "becomes", x + 20 * s, fy + 8 * s, PAL.faint)
    local nsp = field(App, "st_sp_" .. ball.from, x + 90 * s, fy, 160 * s, fh,
      sp, ball.from):upper():gsub("%s+", "_")
    local nlv = tonumber(field(App, "st_lv_" .. ball.from, x + 260 * s, fy, 50 * s, fh,
      tostring(lv), "5")) or 5
    if nsp ~= sp or nlv ~= lv then
      remap[ball.from] = { species = nsp, level = nlv }
      App.markDirty()
    elseif nsp == ball.from and nlv == 5 then
      -- keep explicit identity optional; leave stored if user set it
    end
    if Kit.button(x + 330 * s, fy, 70 * s, fh, "Reset", { kind = "ghost" }) then
      remap[ball.from] = nil
      App.markDirty()
    end
    fy = fy + fh + 16 * s
  end

  Kit.text("micro",
    "Custom gifts on any NPC: Events > Scripts > + Pokemon / Give starter / One-shot pokemon.",
    x + 20 * s, fy, PAL.faint)
end

local function scrapeFlags(S)
  local names = {}
  local seen = {}
  local function add(n)
    if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
  end
  for n in pairs(S.project.eventFlags or {}) do add(n) end
  local function scrapeSteps(steps)
    for _, step in ipairs(steps or {}) do
      if step.flag then add(State.modFlag(S.project, step.flag)) end
      if step.choseFlag then add(State.modFlag(S.project, step.choseFlag)) end
    end
  end
  for _, script in pairs(S.project.talkScripts or {}) do
    scrapeSteps(script.steps)
  end
  for _, hooks in pairs(S.project.mapHooks or {}) do
    if type(hooks) == "table" then
      if hooks.onEnter then scrapeSteps(hooks.onEnter.steps) end
      if hooks.onVictory then scrapeSteps(hooks.onVictory.steps) end
      for _, cell in ipairs(hooks.onStepCells or {}) do
        scrapeSteps(cell.steps)
      end
      for _, scr in pairs(hooks.scripts or {}) do
        scrapeSteps(scr.steps)
      end
    end
  end
  if S.events then
    for _, n in ipairs(S.events) do add(n) end
  end
  table.sort(names)
  return names
end

local function drawSaveFlags(S, x, y, w, h, App)
  local s = Kit.scale
  Kit.caption(x, y, "TEST SAVE FLAGS")
  local listY = y + 28 * s
  Kit.text("micro",
    "Toggles flags on a real save for playtesting. This does not author content.",
    x, listY, PAL.muted)
  listY = listY + 22 * s

  if Kit.button(x, listY, 140 * s, 30 * s, "Open save...", { kind = "accent" }) then
    local path = SaveIO.choosePath and SaveIO.choosePath()
    if path then
      local save, err = SaveIO.load(path)
      if save then
        S.testSave = save
        S.testSavePath = path
        S.status = "Loaded test save " .. path
      else
        S.status = "Save load failed: " .. tostring(err)
      end
    end
  end
  if Kit.button(x + 150 * s, listY, 100 * s, 30 * s, "Save",
      { kind = "primary", enabled = S.testSave ~= nil }) then
    if S.testSave and S.testSavePath then
      local ok, err = SaveIO.save(S.testSavePath, S.testSave)
      S.status = ok and ("Wrote " .. S.testSavePath) or tostring(err)
    end
  end
  Kit.text("micro", S.testSavePath or "(no save open)",
    x + 270 * s, listY + 8 * s, PAL.faint)
  listY = listY + 44 * s

  local filter = Search.field(S, "flagFilter", x, listY, 220 * s, 28 * s, "search flags...")
  listY = listY + 36 * s

  if not S.testSave then
    Kit.emptyBox(x, listY, w, h - (listY - y), "Open a save.lua to toggle flags")
    return
  end
  S.testSave.flags = S.testSave.flags or {}

  local flags = Search.filterIds(scrapeFlags(S), filter)
  local colW = (w - 12 * s) / 2
  local ry = listY
  local rowH = 28 * s
  local col = 0
  for _, name in ipairs(flags) do
    local cx = x + col * (colW + 12 * s)
    local on = S.testSave.flags[name] == true
    if Kit.chip(cx, ry, colW, rowH, name, on, PAL.green) then
      if on then
        S.testSave.flags[name] = nil
      else
        S.testSave.flags[name] = true
      end
      S.status = (on and "Cleared " or "Set ") .. name
    end
    col = col + 1
    if col > 1 then
      col = 0
      ry = ry + rowH + 6 * s
    end
    if ry > y + h - rowH then break end
  end
end

local HOOK_KINDS = {
  { id = "onEnter", label = "onEnter" },
  { id = "onVictory", label = "onVictory" },
  { id = "onStep", label = "onStep cells" },
  { id = "script", label = "Named scripts" },
}

local function ensureMapHooks(S, mapId)
  S.project.mapHooks = S.project.mapHooks or {}
  S.project.mapHooks[mapId] = S.project.mapHooks[mapId] or {}
  return S.project.mapHooks[mapId]
end

-- create=false: browse without inventing empty mod bags.
local function resolveHookSteps(hooks, kind, cellIdx, scriptName, create)
  if kind == "onEnter" then
    if not hooks.onEnter then
      if not create then return nil end
      hooks.onEnter = { steps = {} }
    end
    hooks.onEnter.steps = hooks.onEnter.steps or {}
    return hooks.onEnter.steps
  elseif kind == "onVictory" then
    if not hooks.onVictory then
      if not create then return nil end
      hooks.onVictory = { steps = {} }
    end
    hooks.onVictory.steps = hooks.onVictory.steps or {}
    return hooks.onVictory.steps
  elseif kind == "onStep" then
    if not hooks.onStepCells then
      if not create then return nil end
      hooks.onStepCells = { { x = 0, y = 0, steps = {} } }
    end
    cellIdx = tonumber(cellIdx) or 1
    if cellIdx < 1 then cellIdx = 1 end
    if not hooks.onStepCells[cellIdx] then
      if not create then return nil end
      hooks.onStepCells[cellIdx] = { x = 0, y = 0, steps = {} }
    end
    local cell = hooks.onStepCells[cellIdx]
    cell.steps = cell.steps or {}
    return cell.steps, cell
  elseif kind == "script" then
    hooks.scripts = hooks.scripts or {}
    scriptName = scriptName or "script"
    if not hooks.scripts[scriptName] then
      if not create then return nil end
      hooks.scripts[scriptName] = { steps = {} }
    end
    hooks.scripts[scriptName].steps = hooks.scripts[scriptName].steps or {}
    return hooks.scripts[scriptName].steps
  end
  return nil
end

local function vanillaHookLabel(info, kind)
  if kind == "script" then
    local n = 0
    for _ in pairs(info.scripts or {}) do n = n + 1 end
    if n > 0 then return string.format(" (%d)", n) end
    return ""
  end
  local h = info.hooks and info.hooks[kind]
  if not h then return "" end
  return h.form == "lua" and " *" or " +"
end

local function drawHooks(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  TalkIndex.ensureScripts()

  local mapColW = math.min(160 * s, w * 0.18)
  local listW = math.min(220 * s, w * 0.28)
  local qh = 28 * s
  local qy = y + 22 * s
  local listY = qy + qh + 6 * s
  local listH = h - (listY - y)

  Kit.caption(x, y, "MAP")
  local mapQ, mapQCh = Search.field(S, "hookMapQuery", x, qy, mapColW, qh, "maps...")
  if mapQCh then S.hookMapOffset = 0 end
  Kit.card(x, listY, mapColW, listH, 12 * s)
  local maps = Search.filterIds(TalkIndex.allMapIds(S), mapQ)
  if not S.eventMapId then
    S.eventMapId = S.dialogMapId or S.mapId or maps[1]
  end
  local mapRowH = 26 * s
  local perMap = math.max(1, math.floor((listH - 16 * s) / (mapRowH + 2 * s)))
  local mapScrollX = x + 6 * s
  local mapScrollW = mapColW - 12 * s
  local mapScrollH = listH - 16 * s
  local mapRowW = Kit.scrollInnerWidth(mapScrollW)
  S.hookMapOffset = Kit.scroll(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.hookMapOffset or 0, #maps, perMap)
  local ry = listY + 8 * s
  for i = (S.hookMapOffset or 0) + 1,
      math.min(#maps, (S.hookMapOffset or 0) + perMap) do
    local id = maps[i]
    if Kit.row(mapScrollX, ry, mapRowW, mapRowH, S.eventMapId == id, PAL.blue) then
      S.eventMapId = id
      S.hookFormScroll = nil
    end
    local hasV = TalkIndex.mapHasHooks(id)
    local mark = hasV and " *" or ""
    Kit.pushClip(mapScrollX, ry, mapRowW, mapRowH)
    Kit.text("micro",
      fitIn("micro", id .. mark, math.max(8, mapRowW - 12 * s)),
      mapScrollX + 6 * s, ry + 6 * s, hasV and PAL.yellow or PAL.text)
    Kit.popClip()
    ry = ry + mapRowH + 2 * s
  end
  S.hookMapOffset = Kit.scrollbar(mapScrollX, listY + 8 * s, mapScrollW,
    mapScrollH, S.hookMapOffset or 0, #maps, perMap)

  local pinX = x + mapColW + 10 * s
  Kit.caption(pinX, y, "HOOK")
  Kit.card(pinX, listY, listW, listH, 12 * s)
  S.eventHookKind = S.eventHookKind or "onEnter"
  local vanillaInfo = TalkIndex.mapHookInfo(S.eventMapId)
  ry = listY + 10 * s
  for _, hk in ipairs(HOOK_KINDS) do
    local on = S.eventHookKind == hk.id
    local label = hk.label .. vanillaHookLabel(vanillaInfo, hk.id)
    if Kit.chip(pinX + 10 * s, ry, listW - 20 * s, 28 * s, label, on, PAL.yellow) then
      S.eventHookKind = hk.id
    end
    ry = ry + 34 * s
  end
  local tipW = listW - 20 * s
  Kit.pushClip(pinX + 10 * s, ry + 4 * s, tipW,
    math.max(8, listY + listH - (ry + 8 * s)))
  local tips = {
    onEnter = "* = engine Lua hook. Mod steps also run.",
    onVictory = "* = engine hook. Mod steps compose.",
    onStep = "* = engine onStep (Lua cell logic).",
    script = "Named scripts from data/scripts + mod.",
  }
  Kit.text("micro",
    Kit.ellipsize("micro", tips[S.eventHookKind] or "", tipW),
    pinX + 10 * s, ry + 8 * s, PAL.faint)
  Kit.popClip()

  local formX = pinX + listW + 12 * s
  local formW = w - (formX - x)
  Kit.caption(formX, y, "STEPS")
  Kit.card(formX, listY, formW, listH, 12 * s)

  local mapId = S.eventMapId
  if not mapId then
    Kit.emptyBox(formX + 8 * s, listY + 8 * s, formW - 16 * s, listH - 16 * s,
      "Select a map")
    return
  end

  local hooks = ensureMapHooks(S, mapId)
  local kind = S.eventHookKind or "onEnter"
  local footerH = 100 * s
  local pad = 12 * s
  local metaH = 40 * s
  if kind == "onStep" or kind == "script" then metaH = 70 * s end
  local viewX = formX + pad
  local viewY = listY + pad + metaH
  local viewW = formW - 2 * pad
  local viewH = math.max(40 * s, listH - pad - footerH - metaH)

  Kit.text("micro",
    Kit.ellipsize("micro", mapId .. " / " .. kind, formW - 24 * s),
    formX + 12 * s, listY + 10 * s, PAL.faint)

  -- Named scripts: pick from vanilla list + mod drafts.
  if kind == "script" then
    local names, seen = {}, {}
    for name in pairs(vanillaInfo.scripts or {}) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    for name in pairs(hooks.scripts or {}) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    table.sort(names)
    if not S.eventHookScriptName or S.eventHookScriptName == "" then
      S.eventHookScriptName = names[1] or "script"
    end
    local nx = formX + 12 * s
    for _, name in ipairs(names) do
      local on = S.eventHookScriptName == name
      local lab = name
      if vanillaInfo.scripts and vanillaInfo.scripts[name] then
        lab = lab .. " *"
      end
      local bw = Kit.textWidth("micro", lab) + 14 * s
      if Kit.chip(nx, listY + 28 * s, bw, 24 * s, lab, on, PAL.blue) then
        S.eventHookScriptName = name
      end
      nx = nx + bw + 4 * s
    end
    local name = field(App, "hk_sn", formX + 12 * s, listY + 54 * s,
      160 * s, 24 * s, S.eventHookScriptName or "script", "script_name")
    name = tostring(name or "script"):gsub("%s+", "_")
    if name ~= S.eventHookScriptName then
      if hooks.scripts and hooks.scripts[S.eventHookScriptName]
          and not hooks.scripts[name] then
        hooks.scripts[name] = hooks.scripts[S.eventHookScriptName]
        hooks.scripts[S.eventHookScriptName] = nil
      end
      S.eventHookScriptName = name
      App.markDirty()
    end
    metaH = 86 * s
    viewY = listY + pad + metaH
    viewH = math.max(40 * s, listH - pad - footerH - metaH)
  elseif kind == "onStep" and hooks.onStepCells and #hooks.onStepCells > 0 then
    S.eventHookCellIdx = math.max(1, math.min(
      S.eventHookCellIdx or 1, #hooks.onStepCells))
    local idx = S.eventHookCellIdx
    local cell = hooks.onStepCells[idx]
    Kit.text("micro", "Mod cell #" .. idx, formX + 12 * s, listY + 28 * s, PAL.caption)
    cell.x = tonumber(field(App, "hk_cx", formX + 90 * s, listY + 24 * s,
      50 * s, 26 * s, tostring(cell.x or 0), "0")) or 0
    cell.y = tonumber(field(App, "hk_cy", formX + 150 * s, listY + 24 * s,
      50 * s, 26 * s, tostring(cell.y or 0), "0")) or 0
    if Kit.button(formX + 210 * s, listY + 24 * s, 60 * s, 26 * s, "Prev",
        { kind = "ghost", font = "small" }) and idx > 1 then
      S.eventHookCellIdx = idx - 1
    end
    if Kit.button(formX + 276 * s, listY + 24 * s, 60 * s, 26 * s, "Next",
        { kind = "ghost", font = "small" }) and idx < #hooks.onStepCells then
      S.eventHookCellIdx = idx + 1
    end
    if Kit.button(formX + 342 * s, listY + 24 * s, 70 * s, 26 * s, "+ Cell",
        { kind = "good", font = "small" }) then
      hooks.onStepCells[#hooks.onStepCells + 1] = { x = 0, y = 0, steps = {} }
      S.eventHookCellIdx = #hooks.onStepCells
      App.markDirty()
    end
  end

  local steps = resolveHookSteps(hooks, kind, S.eventHookCellIdx,
    S.eventHookScriptName, false)
  local editing = type(steps) == "table"

  local function ensureSteps()
    if editing then return steps end
    steps = resolveHookSteps(hooks, kind, S.eventHookCellIdx,
      S.eventHookScriptName, true)
    editing = true
    return steps
  end

  local function addStep(step)
    local bag = ensureSteps()
    bag[#bag + 1] = step
    App.markDirty()
  end

  local track = mapId .. "/" .. kind .. "/"
    .. tostring(S.eventHookCellIdx or 0) .. "/"
    .. tostring(S.eventHookScriptName or "")
    .. (editing and ":m" or ":v")
  FormPane.track(S, "hookFormScroll", track)
  local fy, view = FormPane.begin(S, "hookFormScroll", viewX, viewY, viewW, viewH)
  local contentTop = fy
  local fh = 28 * s
  local kindW = 150 * s
  local innerW = view.contentW or view.w

  -- Show engine hook summary when this kind exists in data/scripts.
  local vHook = (kind ~= "script") and vanillaInfo.hooks and vanillaInfo.hooks[kind]
  local vScript = (kind == "script") and vanillaInfo.scripts
    and vanillaInfo.scripts[S.eventHookScriptName or ""]
  if vHook or vScript then
    local form = (vHook and vHook.form) or (vScript and vScript.form)
    Kit.text("micro", "ENGINE", viewX, fy + 6 * s, PAL.yellow)
    if form == "lua" then
      Kit.text("micro",
        fitIn("micro",
          "Lua handler in data/scripts (not step rows). "
            .. "Edit there, or add mod steps below (onEnter composes).",
          innerW - 70 * s),
        viewX + 60 * s, fy + 6 * s, PAL.muted)
      fy = fy + fh + 4 * s
    elseif form == "rows" then
      local rows = (vHook and vHook.rows) or (vScript and vScript.rows) or {}
      Kit.text("micro",
        string.format("%d engine row(s) - read-only", #rows),
        viewX + 60 * s, fy + 6 * s, PAL.muted)
      fy = fy + fh + 4 * s
      local show = ModWriter.rowsToSteps(rows)
      for _, step in ipairs(show) do
        local sk = step.kind or "raw"
        Kit.text("micro", stepLabel(sk), viewX, fy + 6 * s, PAL.caption)
        local detail = step.note or step.text or step.flag or step.name or ""
        Kit.text("micro",
          fitIn("micro", tostring(detail), innerW - kindW - 8 * s),
          viewX + kindW + 8 * s, fy + 6 * s, PAL.faint)
        fy = fy + fh + 4 * s
        if fy > viewY + viewH + 200 * s then break end
      end
    end
    fy = fy + 8 * s
  end

  if not editing or #(steps or {}) == 0 then
    if not vHook and not vScript then
      Kit.text("small", "No engine hook and no mod steps yet.", viewX, fy, PAL.muted)
      fy = fy + 24 * s
    else
      Kit.text("small", "Mod steps (extra / override draft):", viewX, fy, PAL.muted)
      fy = fy + 24 * s
    end
    if Kit.button(viewX, fy, 110 * s, fh, "+ Text", {
        kind = "good", font = "small",
      }) then
      addStep({ kind = "show_text", text = "..." })
    end
    if Kit.button(viewX + 118 * s, fy, 110 * s, fh, "+ Engine", {
        kind = "accent", font = "small",
      }) then
      addStep({
        kind = "raw",
        note = "check_flag EVENT_FLAG",
        row = { "check_flag", "EVENT_FLAG" },
      })
    end
    if Kit.button(viewX + 236 * s, fy, 110 * s, fh, "+ Set flag", {
        kind = "ghost", font = "small",
      }) then
      addStep({ kind = "set_flag", flag = "DONE" })
    end
    if kind == "onStep" and Kit.button(viewX + 354 * s, fy, 100 * s, fh, "+ Cell", {
        kind = "ghost", font = "small",
        tooltip = "Add a mod onStep cell (x,y)",
      }) then
      ensureSteps()
      hooks.onStepCells = hooks.onStepCells or {}
      if #hooks.onStepCells == 0 then
        -- ensureSteps already created cell 1
      else
        hooks.onStepCells[#hooks.onStepCells + 1] = { x = 0, y = 0, steps = {} }
        S.eventHookCellIdx = #hooks.onStepCells
      end
      App.markDirty()
    end
    fy = fy + fh + 12 * s
  end

  if editing then
    for i, step in ipairs(steps) do
      local sk = step.kind or "show_text"
      if Kit.button(viewX, fy, kindW, fh, stepLabel(sk),
          { kind = "accent", font = "small" }) then
        step.kind = cycleKind(sk)
        App.markDirty()
      end
      local rowsN = drawStepFields(S, App, step, i, step.kind or sk,
        viewX + kindW + 8 * s, fy, innerW - kindW - 48 * s, fh, s)
      local blockH = math.max(1, rowsN) * (fh + 4 * s)
      if Kit.button(viewX + innerW - 32 * s, fy, 28 * s, fh, "X",
          { kind = "danger", font = "small" }) then
        table.remove(steps, i)
        App.markDirty()
      end
      fy = fy + blockH + 8 * s
    end
  end
  FormPane.finish(S, "hookFormScroll", contentTop, fy, view)

  local shortcuts = shortcutDefs(S)
  local bh = 26 * s
  local gap = 4 * s
  local bx = formX + 12 * s
  local by = listY + listH - footerH + 6 * s
  local maxX = formX + formW - 12 * s
  local maxY = listY + listH - 8 * s
  Kit.pushClip(formX + 4 * s, listY + listH - footerH, formW - 8 * s, footerH)
  for _, sc in ipairs(shortcuts) do
    local bw = Kit.textWidth("small", sc.label) + 16 * s
    if bx + bw > maxX then
      bx = formX + 12 * s
      by = by + bh + gap
    end
    if by + bh > maxY then break end
    if Kit.button(bx, by, bw, bh, sc.label,
        { kind = sc.kind or "ghost", font = "small", tooltip = sc.tip }) then
      addStep(sc.make())
    end
    bx = bx + bw + gap
  end
  Kit.popClip()
end

function Events.draw(S, x, y, w, h, App)
  local s = Kit.scale
  if not S.project then
    Kit.emptyBox(x, y, w, h, "Open a mod on the Project tab first")
    return
  end
  State.ensureProjectFields(S.project)

  if Kit.chip(x, y, 90 * s, 26 * s, "SCRIPTS",
      S.eventsMode ~= "starters" and S.eventsMode ~= "saveflags"
        and S.eventsMode ~= "hooks", PAL.yellow) then
    S.eventsMode = "scripts"
  end
  if Kit.chip(x + 96 * s, y, 90 * s, 26 * s, "HOOKS",
      S.eventsMode == "hooks", PAL.yellow) then
    S.eventsMode = "hooks"
  end
  if Kit.chip(x + 192 * s, y, 100 * s, 26 * s, "STARTERS",
      S.eventsMode == "starters", PAL.green) then
    S.eventsMode = "starters"
  end
  if Kit.chip(x + 298 * s, y, 120 * s, 26 * s, "SAVE FLAGS",
      S.eventsMode == "saveflags", PAL.blue) then
    S.eventsMode = "saveflags"
  end

  local bodyY = y + 36 * s
  local bodyH = h - 36 * s
  if S.eventsMode == "saveflags" then
    drawSaveFlags(S, x, bodyY, w, bodyH, App)
  elseif S.eventsMode == "starters" then
    drawStarters(S, x, bodyY, w, bodyH, App)
  elseif S.eventsMode == "hooks" then
    drawHooks(S, x, bodyY, w, bodyH, App)
  else
    drawScripts(S, x, bodyY, w, bodyH, App)
  end
end

return Events
