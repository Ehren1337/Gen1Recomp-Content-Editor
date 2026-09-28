-- The "Update" button on the top bar and its pop-up (Updater does the work).

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL
local U = require("Updater")

local M = {}

local function mb(n) return n and ("%.1f MB"):format(n / 1048576) or "?" end

--- The top-bar button's label and kind for the current state.
function M.label()
  local st = U.state
  if st.step == "blocked" then return "Update paused", "ghost" end
  if st.step == "ready" then return "Update to " .. U.short(st.release.tag), "good" end
  if st.step == "unpacking" then return "Preparing update...", "accent" end
  if st.step == "downloading" then
    local pct = st.release and st.release.size and st.got and math.floor(st.got * 100 / st.release.size)
    return pct and ("Downloading " .. math.min(99, pct) .. "%") or "Downloading...", "accent"
  end
  if st.step == "staged" then return "Restart to update", "good" end
  if st.step == "checking" and not st.auto then return "Checking...", "ghost" end
  return "Updates", "ghost"
end

function M.isOpen(S) return S._updateOpen == true end

function M.open(S)
  S._updateOpen = true
  local step = U.state.step
  if step == "idle" or step == "error" or (step == "latest" and os.time() - (U.state.checked or 0) > 60) then
    U.check(false)
  end
end

local function lines(S)
  local st = U.state
  local rel = st.release
  local out, buttons = {}, {}
  local function add(text, colour) out[#out + 1] = { text, colour } end
  local installed = U.currentVersion()
  add("Installed source: " .. (installed and U.short(installed) or "could not determine the current commit"), PAL.muted)
  if st.step == "idle" or st.step == "checking" then
    add("Checking GitHub for a newer editor...")
  elseif st.step == "latest" then
    add("Up to date with GitHub main. Updates are automatic.", PAL.green)
    buttons[#buttons + 1] = { "Check again", "ghost", function() U.check(false) end }
  elseif st.step == "blocked" then
    add("Automatic update paused", PAL.yellow)
    add(tostring(st.error), PAL.text)
    buttons[#buttons + 1] = { "Try again", "ghost", function() U.check(false) end }
  elseif st.step == "error" then
    add("Couldn't check for updates: " .. tostring(st.error), PAL.red)
    buttons[#buttons + 1] = { "Try again", "ghost", function() U.check(false) end }
    buttons[#buttons + 1] = { "Open source page", "ghost", function() love.system.openURL(U.releasesPage()) end }
  elseif rel then
    add("GitHub main: " .. U.short(rel.tag), PAL.green)
    for i, line in ipairs(rel.notes or {}) do
      if i > 8 then add("...", PAL.faint) break end
      add(line, PAL.text)
    end
    local page = { "Source page", "ghost", function() love.system.openURL(rel.page or U.releasesPage()) end }
    if not rel.url then
      add("This source update has no download URL.", PAL.yellow)
      buttons[#buttons + 1] = page
    elseif st.step == "ready" then
      add("Your mods, ROM data, saves and settings are never touched by an update.", PAL.muted)
      buttons[#buttons + 1] = { "Download update (" .. mb(rel.size) .. ")", "primary", function() U.download() end }
      buttons[#buttons + 1] = page
    elseif st.step == "unpacking" then
      add("Preparing the source update in the background...", PAL.text)
    elseif st.step == "downloading" then
      add(st.checkout and "Fetching source changes and checking that your local work can be preserved..."
        or ("Downloading... %s of %s"):format(mb(st.got or 0), mb(rel.size)), PAL.text)
      out.progress = rel.size and st.got and math.min(1, st.got / rel.size) or 0
    elseif st.step == "staged" then
      add("Ready. The update installs automatically when you close the editor, or you can restart now. Your mods stay untouched.", PAL.text)
      buttons[#buttons + 1] = { S._updateUnsaved and "Save and restart" or "Restart to update", "primary", "install" }
    elseif st.step == "installing" then
      add(("Closing the editor to install %s -- it opens again by itself in a few seconds."):format(U.short(rel.tag)), PAL.green)
    end
  end
  return out, buttons
end

--- Install the downloaded update now: save first if needed, start the
-- helper, and close the editor on the next frame (it opens again once the
-- files are in). The pop-up stays up saying so until the window closes.
function M.restart(S, App)
  U.log("Restart to update pressed (step " .. tostring(U.state.step) .. ")")
  if App.hasUnsaved and App.hasUnsaved() then App.save() end
  if App.hasUnsaved and App.hasUnsaved() then
    U.log("unsaved changes -- not restarting")
    S.status = "Save your changes (manifest / code / cart too) before updating"
    S._updateOpen = true
    return false
  end
  local ok, err = U.install()
  U.log("install helper: " .. (ok and "started" or ("failed: " .. tostring(err))))
  if not ok then
    U.state.step, U.state.error = "error", err
    S._updateOpen = true
    return false
  end
  S.status = "Closing the editor to install the update..."
  S._updateOpen = true
  S._quitArmed = true
  S._updateQuitAt = (love.timer and love.timer.getTime() or 0) + 0.4
  return true
end

--- Call every frame: closes the editor once Restart to update has started
-- the helper.
function M.update(S)
  if S._updateQuitAt and (not love.timer or love.timer.getTime() >= S._updateQuitAt) then
    S._updateQuitAt = nil
    S._quitArmed = true
    U.log("closing the editor")
    love.event.quit()
  end
end

local function wrapCount(f, text, width)
  if f and f.getWrap then local _, w = f:getWrap(text, width); return math.max(1, #w) end
  return 1
end

function M.draw(S, App, W, H)
  if not M.isOpen(S) then return end
  local s = Kit.scale
  S._updateUnsaved = App.hasUnsaved and App.hasUnsaved() or false
  local text, buttons = lines(S)
  local G = love.graphics
  local f = Kit.fonts and Kit.fonts.small
  local bw = math.min(W - 40 * s, 620 * s)
  local tw = bw - 40 * s
  local lh = f and f:getHeight() * 1.25 or 18 * s
  local total = 0
  for _, l in ipairs(text) do total = total + wrapCount(f, l[1], tw) * lh + 6 * s end
  if text.progress then total = total + 22 * s end
  local bh = total + 116 * s
  local bx, by = (W - bw) / 2, math.max(40 * s, (H - bh) / 3)
  Theme.col(PAL.bgBot, 0.7)
  G.rectangle("fill", 0, 0, W, H)
  Theme.col(PAL.bgMid, 1)
  G.rectangle("fill", bx, by, bw, bh, 16 * s, 16 * s)
  Kit.card(bx, by, bw, bh)
  Kit.text("button", "Update editor", bx + 20 * s, by + 18 * s, PAL.heading)
  local ty = by + 54 * s
  for _, l in ipairs(text) do
    Theme.col(l[2] or PAL.text, 1)
    if f then G.setFont(f) end
    G.printf(l[1], bx + 20 * s, ty, tw, "left")
    ty = ty + wrapCount(f, l[1], tw) * lh + 6 * s
  end
  if text.progress then
    Theme.col(PAL.cardBorder, 0.5)
    G.rectangle("fill", bx + 20 * s, ty + 4 * s, tw, 10 * s, 5 * s, 5 * s)
    Theme.col(PAL.green, 1)
    G.rectangle("fill", bx + 20 * s, ty + 4 * s, math.max(10 * s, tw * text.progress), 10 * s, 5 * s, 5 * s)
  end
  G.setColor(1, 1, 1, 1)
  local x = bx + 20 * s
  local yb = by + bh - 46 * s
  for _, b in ipairs(buttons) do
    local w = Kit.textWidth("micro", b[1]) + 36 * s
    if Kit.button(x, yb, w, 30 * s, b[1], { kind = b[2], font = "micro" }) then
      if b[3] == "install" then
        M.restart(S, App)
      else
        b[3]()
      end
    end
    x = x + w + 10 * s
  end
  if Kit.button(bx + bw - 140 * s, yb, 120 * s, 30 * s, "Close", { kind = "ghost", font = "micro" }) then
    S._updateOpen = nil
  end
end

return M
