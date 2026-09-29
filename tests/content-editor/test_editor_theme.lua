-- Editor settings > Theme (Theme.lua palettes, EditorSettings.lua). Plain
-- LuaJIT, no LOVE. Run from the repository root:
--   luajit tests/content-editor/test_editor_theme.lua
package.path = "tools/content-editor/?.lua;tools/save-editor/?.lua;" .. package.path
local Theme = require("Theme")
local Settings = require("EditorSettings")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

local function lum(c)
  local function ch(v) v = v / 255; return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
  return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
local function contrast(a, b)
  local x, y = lum(a), lum(b)
  if x < y then x, y = y, x end
  return (x + 0.05) / (y + 0.05)
end

run("stock and purple are the exact palettes", function()
  local st = Theme.palette("stock")
  assert(st.bgTop[1] == 22 and st.bgTop[2] == 34 and st.bgTop[3] == 74 and st.blue[3] == 255)
  local pu = Theme.palette("purple")
  assert(pu.bgTop[1] == 70 and pu.bgTop[2] == 0 and pu.bgTop[3] == 78 and pu.blue[1] == 217)
  assert(Theme.palette("nonsense") == st)
end)

run("apply recolours in place and keeps meaning colours", function()
  local blue, green = Theme.PAL.blue, Theme.PAL.green
  local g1 = green[1]
  Theme.apply("ruby")
  assert(Theme.PAL.blue == blue, "same table, so every holder sees the new colour")
  assert(blue[1] ~= 70 and green[1] == g1, "accent changed, green didn't")
  assert(Theme.current.id == "ruby")
  Theme.apply("custom", 60)
  assert(Theme.current.id == "custom" and Theme.current.hue == 60)
  Theme.apply("stock")
  assert(blue[1] == 70 and blue[2] == 150 and blue[3] == 255 and Theme.current.id == "stock")
end)

run("every hue stays readable", function()
  for hue = 0, 359, 5 do
    local p = Theme.palette("custom", hue)
    for _, bg in ipairs({ p.bgTop, p.bgMid, p.cardBody }) do
      assert(contrast(p.text, bg) >= 7, "text at hue " .. hue)
      assert(contrast(p.caption, bg) >= 4.5, "captions at hue " .. hue)
      assert(contrast(p.blue, bg) >= 4.3, "accent at hue " .. hue)
    end
  end
end)

run("every ready-made look stays readable", function()
  for _, preset in ipairs(Theme.PRESETS) do
    local p = Theme.palette(preset.id)
    for _, bg in ipairs({ p.bgTop, p.bgMid, p.cardBody }) do
      assert(contrast(p.text, bg) >= 7, "text in " .. preset.label)
      assert(contrast(p.caption, bg) >= 4.5, "captions in " .. preset.label)
      assert(contrast(p.blue, bg) >= 4.3, "accent in " .. preset.label)
    end
  end
  assert(Theme.palette("soulsilver").blue[1] > 150, "Soul Silver is silver")
end)

run("settings file: saved values read back, nothing runs", function()
  local text = Settings.serialize({ theme = "custom", themeHue = 120, bad = function() end })
  local t = Settings.parse(text)
  assert(t.theme == "custom" and t.themeHue == 120 and t.bad == nil)
  assert(next(Settings.parse("os.exit(1)")) == nil and next(Settings.parse(nil)) == nil)
  assert(next(Settings.parse("return { x = os and os.time() }")) == nil)
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
