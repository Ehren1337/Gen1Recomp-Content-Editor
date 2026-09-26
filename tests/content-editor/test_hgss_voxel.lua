local root = "mods/firered_hgss_voxel/"
local events, messages, calls = {}, {}, {}
local color, shader, depth = {1,1,1,1}, nil, 0
local ground, overhead, actor = {}, {}, {}
local g = {}
function g.getColor() return unpack(color) end
function g.setColor(...) color = {...} end
function g.getShader() return shader end
function g.setShader(value) shader = value end
function g.newShader() return {} end
function g.push() depth = depth + 1 end
function g.pop() depth = depth - 1; color = {1,1,1,1}; shader = nil end
function g.draw(object, x, y) calls[#calls+1] = {object, x, y, shader, color[1]} end
love = {graphics=g}
local failOnce = false
local view = {_nativeBatches={ground}, _nativeOverBatches={overhead}}
function view.draw(_, _, _, opts)
  if failOnce then failOnce=false; error("simulated driver failure") end
  if not (opts and opts.actorsOnly) then
    g.draw(ground, 0, 10)
    g.draw(overhead, 0, 20)
  end
  g.draw(actor, 0, 30)
end
package.loaded["src.core.game3.field_view"] = view
local tilt
package.loaded["src.render.Tilt"] = {setLevel=function(n) tilt=n end}
local mod = {events={}, log={}}
function mod:read(path)
  local f=assert(io.open(root..path)); local s=f:read("*a"); f:close(); return s
end
function mod.events:on(name, fn) events[name]=fn end
function mod.log:info() end
function mod.log:warn(message) messages[#messages+1]=message end
assert(loadfile(root.."main.lua"))()(mod)
events["game.ready"]()
local wrapped=view.draw
events["game.ready"]()
assert(view.draw==wrapped and tilt==2, "installation must be idempotent")
local originalDraw=g.draw
view.draw({},240,160)
assert(g.draw==originalDraw and depth==0, "graphics state leaked")
assert(#calls==6 and calls[2][3]==26 and calls[5][3]==20,
  "relief must extend below its cap without separating it from the base layer")
assert(calls[1][4] and not calls[6][4], "color shader must exclude actors")
calls={}
view.draw({},240,160,{actorsOnly=true})
assert(#calls==1 and calls[1][1]==actor, "upright pass must remain untouched")
failOnce=true
view.draw({},240,160)
assert(g.draw==originalDraw and depth==0 and #messages==1, "failure must restore and fall back")
calls={}
view.draw({},240,160)
assert(#calls==3, "failed relief must stay disabled")
print("PASS: relief layers, actor isolation, repeated game.ready, error cleanup and fallback")
