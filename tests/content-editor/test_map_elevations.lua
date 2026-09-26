package.path = "tools/content-editor/?.lua;" .. package.path
local M = require("MapElevations")
local area = {cellWidth = 3, cellHeight = 3, gen3Elevation = {2,2,9,2,9,2,9,2,2}}
assert(M.fill(area, 0, 0, 0))
assert(area.gen3Elevation[1] == 0 and area.gen3Elevation[2] == 0 and area.gen3Elevation[4] == 0)
assert(area.gen3Elevation[6] == 2 and area.gen3Elevation[8] == 2, "Fill must not cross diagonal boundaries")
assert(not M.fill(area, 0, 0, 0) and not M.fill(area, -1, 0, 5))
assert(not M.fill(area, 0, 0, 16))
assert(M.rectangle(area, {x0=4,y0=4,x1=1,y1=1}, 15))
assert(area.gen3Elevation[5] == 15 and area.gen3Elevation[9] == 15)
assert(area.gen3Elevation[3] == 9 and area.gen3Elevation[7] == 9)
assert(not M.rectangle(area, {x0=1,y0=1,x1=2,y1=2}, 15))
local large = {cellWidth=128,cellHeight=128,collision={}}
assert(M.fill(large, 0, 0, 7) and M.value(large,127,127) == 7, "Fill must handle large regions without recursion")
local editable = {cellWidth = 2, cellHeight = 1, collision = {"walk", "water"}}
assert(M.value(editable, 0, 0) == 3 and M.value(editable, 1, 0) == 0)
assert(not M.paint(editable, 0, 0, 3), "Default height is already effective")
assert(M.paint(editable, 0, 0, 0) and M.value(editable, 0, 0) == 0)
assert(not M.paint(editable, 0, 0, 0), "Repeated stroke must be a no-op")
assert(M.paint(editable, 1, 0, 15) and M.value(editable, 1, 0) == 15)
for _, value in ipairs({-1, 16, 1.5, "2"}) do assert(not M.paint(editable, 0, 0, value)) end
assert(not M.paint(editable, -1, 0, 2) and not M.paint(editable, 2, 0, 2))
assert(editable.collision[1] == "walk" and editable.collision[2] == "water")
local S = {data = {}, project = {layeredMaps = {
  current = {cellWidth = 2, cellHeight = 1, gen3Elevation = {2, 4}},
}}}
local w, h, read = M.reader(S, "current")
assert(w == 2 and h == 1 and read(0, 0) == 2 and read(1, 0) == 4)
-- The overlay must reflect unsaved edits immediately.
S.project.layeredMaps.current.gen3Elevation[2] = 7
assert(read(1, 0) == 7)
package.loaded.Gen3Map = {
  layout = function(_, id) if id == "neighbor" then return {width = 3, height = 2} end end,
  cell = function(_, id, _, x, y)
    assert(id == "neighbor")
    return {elev = x + y + 5}
  end,
}
w, h, read = M.reader(S, "neighbor")
assert(w == 3 and h == 2 and read(1, 1) == 7)
assert(M.reader(S, "missing") == nil)
local labels = {}
love = {graphics = {
  getFont = function() return {
    getHeight = function() return 12 end,
    getWidth = function(_, text) return #text * 6 end,
  } end,
  setColor = function() end, rectangle = function() end,
  print = function(text) labels[#labels + 1] = text end,
}}
M.draw(S, "current", 0, 0, 32, 16)
assert(#labels == 0, "Disabled overlay must not draw")
S.mapShowElevations = true
M.draw(S, "neighbor", 16, 16, 15, 15)
assert(#labels == 1 and labels[1] == "7", "Neighbor overlay must cull in local coordinates")
labels = {}
M.draw(S, "current", 0, 0, 32, 16)
assert(#labels == 2 and labels[1] == "2" and labels[2] == "7")
print("PASS: elevation values, live edits, neighbors, toggle, and viewport culling")
