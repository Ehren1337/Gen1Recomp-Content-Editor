-- Border > Around the map (Gen3Void.lua): extrude, hand-painted tiles past
-- a map's edge, margins, mod default. Plain LuaJIT, no LOVE. Run from the
-- repository root:
--   luajit tests/content-editor/test_gen3_void.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local Void = require("Gen3Void")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

run("extrude repeats the last 2 rows / columns", function()
  local w = 10
  local want = { [-4] = 0, [-3] = 1, [-2] = 0, [-1] = 1, [0] = 0, [5] = 5, [9] = 9, [10] = 8, [11] = 9, [12] = 8, [13] = 9 }
  for c, e in pairs(want) do assert(Void.edge(c, w) == e, c .. " -> " .. Void.edge(c, w)) end
  assert(Void.edge(-3, 1) == 0 and Void.edge(4, 1) == 0)
end)

run("painting stays outside the map and inside the margin", function()
  local p = {}
  assert(Void.paint(p, "M", 10, 8, -1, 0, 5, "pairA"))
  assert(not Void.paint(p, "M", 10, 8, -1, 0, 5, "pairA"))
  assert(select(2, Void.paint(p, "M", 10, 8, 3, 3, 5, "pairA")) == "inside")
  assert(select(2, Void.paint(p, "M", 10, 8, -17, 0, 5, "pairA")) == "margin")
  assert(Void.paint(p, "M", 10, 8, 17, 15, 7, "pairB"))
  local c = Void.cell(p, "M", 17, 15); assert(c.m == 7 and c.p == "pairB")
  assert(Void.paint(p, "M", 10, 8, -1, 0, nil))
  assert(Void.cell(p, "M", -1, 0) == nil)
end)

run("keys round-trip, negative coordinates included", function()
  for _, xy in ipairs({ { -64, -64 }, { -1, 0 }, { 575, 575 }, { 0, -1 } }) do
    local x, y = Void.unkey(Void.key(xy[1], xy[2]))
    assert(x == xy[1] and y == xy[2])
  end
end)

run("a smaller margin drops tiles past it", function()
  local p = {}
  Void.paint(p, "M", 10, 8, -16, 0, 1, "a"); Void.paint(p, "M", 10, 8, -2, 0, 1, "a")
  local changed, removed = Void.setMargin(p, "M", 10, 8, 4)
  assert(changed and removed == 1 and Void.margin(p, "M") == 4)
  assert(Void.cell(p, "M", -2, 0) and not Void.cell(p, "M", -16, 0))
  assert(not Void.setMargin(p, "M", 10, 8, 65))
end)

run("mod default covers outdoor maps; a map's own choice wins", function()
  local p = {}
  assert(Void.fillFor(p, "M", true) == "border")
  Void.setDefault(p, "extrude")
  assert(Void.fillFor(p, "M", true) == "extrude" and Void.fillFor(p, "M", false) == "border")
  Void.setMapFill(p, "M", "border"); assert(Void.fillFor(p, "M", true) == "border")
  Void.setMapFill(p, "H", "extrude"); assert(Void.fillFor(p, "H", false) == "extrude")
  Void.setMapFill(p, "M", nil); assert(Void.fillFor(p, "M", true) == "extrude")
end)

run("empty records tidy away; used() and compile()", function()
  local p = {}
  assert(not Void.used(p) and Void.compile(p) == nil)
  Void.paint(p, "M", 10, 8, -1, 0, 3, "a")
  assert(Void.used(p))
  local c = Void.compile(p); assert(c.default == "border" and c.maps.M.cells[Void.key(-1, 0)].m == 3)
  Void.paint(p, "M", 10, 8, -1, 0, nil)
  assert(p.gen3VoidMaps == nil and not Void.used(p))
  Void.setDefault(p, "extrude"); assert(Void.used(p)); Void.setDefault(p, "border"); assert(p.gen3VoidDefault == nil)
end)

run("the editor preview matches what the game draws", function()
  local p = {}
  local grid = function(x, y) return y * 100 + x end
  local border = { width = 2, height = 2, pair = "b", cellAt = function(_, x, y) return { mid = 900 + y * 2 + x } end }
  local opts = { width = 10, height = 8, pair = "map", outdoor = true, cell = grid, border = border }
  local mid, pair, kind = Void.preview(p, "M", -1, 3, opts)
  assert(kind == "border" and pair == "b" and mid == 900 + 1 * 2 + 1)
  Void.setDefault(p, "extrude")
  mid, pair, kind = Void.preview(p, "M", -1, 3, opts)
  assert(kind == "extrude" and pair == "map" and mid == grid(1, 3))
  Void.paint(p, "M", 10, 8, -1, 3, 42, "x")
  mid, pair, kind = Void.preview(p, "M", -1, 3, opts)
  assert(kind == "painted" and mid == 42 and pair == "x")
end)

run("space outside every map belongs to the nearest map", function()
  local rects = { { ox = 0, oy = 0, w = 10, h = 10 }, { ox = -5, oy = -20, w = 30, h = 20 } }
  assert(Void.owner(rects, 3, -1) == 2)      -- right under the northern map
  assert(Void.owner(rects, -1, 5) == 1)      -- beside the open map
  assert(Void.owner(rects, -8, -2) == 2)     -- nearer the wide northern map
  assert(Void.owner(rects, 12, 12) == 1)
  -- ties go to the open map (listed first)
  assert(Void.owner({ { ox = 0, oy = 0, w = 4, h = 4 }, { ox = 7, oy = 0, w = 4, h = 4 } }, 5, 2) == 1)
end)

run("validate rejects bad data", function()
  assert(not pcall(Void.validate, { gen3VoidDefault = "fog" }))
  assert(not pcall(Void.validate, { gen3VoidMaps = { M = { margin = 99 } } }))
  assert(not pcall(Void.validate, { gen3VoidMaps = { M = { cells = { [5] = { m = 2000, p = "a" } } } } }))
  assert(pcall(Void.validate, { gen3VoidMaps = { M = { fill = "extrude", cells = { [5] = { m = 2, p = "a" } } } } }))
end)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
