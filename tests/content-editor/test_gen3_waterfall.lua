-- Waterfall export against the real field, player and collision code.
-- Synthetic vertical waterfall; plain LuaJIT, no LOVE.
-- Run from the repository root:
--   POKEPORT_RECOMP=<runtime checkout> luajit tests/content-editor/test_gen3_waterfall.lua
local RUNTIME = assert(os.getenv("POKEPORT_RECOMP"), "Set POKEPORT_RECOMP")
package.path = "tools/content-editor/?.lua;tools/save-editor/?.lua;" .. RUNTIME .. "/?.lua;"
  .. RUNTIME .. "/?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = {
  plain = function(k) return k end, box = function(k) return k end,
  ascii = function(k) return k end, has = function() return true end,
  key = function(n) return n end, at = function(n) return n end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

-- Sound: record what plays; each sound "plays" for 40 frames.
package.loaded["src.core.game3.m4a_mix"] = { SAMPLE_RATE = 44100 }
local played, playing = {}, {}
package.loaded["src.core.game3.audio"] = setmetatable({
  playSe = function(id) played[#played + 1] = id; playing[id] = 40; return true end,
  isSePlaying = function(id) return (playing[id] or 0) > 0 end,
}, { __index = function() return function() end end })
local function soundTick() for k, v in pairs(playing) do playing[k] = v - 1 end end

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

-- UI stubs: record what is shown and answer yes/no.
local shown, answer = {}, true
package.loaded["src.ui.game3.message"] = {
  show = function(text, cb) shown[#shown + 1] = text; if type(cb) == "function" then cb() end end,
  close = function() end, isOpen = function() return false end,
}
package.loaded["src.ui.game3.choice"] = { yesNo = function(cb) cb(answer) end }
package.loaded["src.core.game3.field_move_show_mon"] = { start = function(_, _, cb) cb() end }
package.loaded["src.core.game3.pokemon"] = setmetatable({
  displayMonName = function(mon) return mon.nickname end,
}, { __index = function() return function() end end })
local hooks = {}
package.loaded["src.mods.Runtime"] = {
  wants = function() return false end, wantsHook=function() return false end, emit = function() end,
  call = function(name, proceed, ...)
    if hooks[name] then return hooks[name](proceed, ...) end
    return proceed(...)
  end,
}

local W = require("Gen3Whirlpool")
local Emit = require("Gen3WhirlpoolRuntime")
local encode = require("ModWriter").encodeLua
local Collision = require("src.core.game3.collision")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")

local stops=0
package.loaded["src.core.game3.audio"].stopSe=function(id) stops=stops+1;playing[id]=0 end
local map={pair="falls",midLayout={width=3,height=7,
  midAt=function(_,x,y) return x==1 and y>=2 and y<=4 and 2 or 1 end,
  -- Falls bridge different elevations: upper pool 3, falls 1, lower pool 1.
  elevAt=function(_,x,y) return y<2 and 3 or 1 end}}
Interaction.behaviors.falls={[1]=0x10,[2]=0x13}
Collision._mapDef=map;Collision._mapId="FALLS"
Collision._widthCells,Collision._heightCells=3,7
Collision._grid={}
for i=1,21 do Collision._grid[i]=0x29 end
for y=2,4 do Collision._grid[y*3+2]=255 end
local ready
assert(loadstring("return function(mod) "..require("Gen3WaterfallRuntime").." end"))()({
  events={on=function(_,_,fn) ready=fn end},hooks={wrap=function(_,key,fn) hooks[key]=fn end}})
ready()
-- Both runtime extensions share the same engine functions in exported mods.
local whirlReady
assert(loadstring("return function(mod) "..Emit(W.compile({gen3Layered={TEST={collision={"whirlpool"}}}}),encode).." end"))()({
  events={on=function(_,_,fn) whirlReady=fn end},hooks={wrap=function(_,key,fn) hooks[key]=fn end}})
whirlReady()
package.loaded["src.core.game3.scripting.space"]={vm={isRunning=function() return false end}}
Field._session={party={},flags={}}
local function start(y,dir)
  Player.reset(1,y,dir);Player.surfing=true
  Player.currentElevation=Collision.elevationAt(1,y)
  Field.running=true;Field.locked=false;Field._waterfall=nil
end
local function drive()
  local n=0
  for i=1,500 do
    Field.updateWaterfall(nil);Player.tick(nil);soundTick();n=i
    assert(Player.surfing,"Dismounted on waterfall")
    if not Player.moving and not Field.locked and not Collision.isWaterfall(Collision.behavior(Player.cellX,Player.cellY)) then break end
  end
  assert(n<500,"Ride did not finish")
  return n
end
start(5,"up")
assert(not Collision.canEnter(nil,1,4,{surfing=true,dir="up",fromX=1,fromY=5}),"Can surf uphill without move")
assert(not Collision.canEnter(nil,1,2,{surfing=false,dir="down"}),"Can walk onto waterfall")
Field.rideWaterfall("up")
assert(drive()>=128,"Climb too fast")
assert(Player.cellY==1 and not Field.locked)
assert(#played>1 and stops==1,"Sound did not repeat and stop")
start(1,"down")
local entry={surfing=true,dir="down",fromX=1,fromY=1,elevation=3}
assert(Collision.canEnter(nil,1,2,entry),"Downhill entrance blocked")
assert(entry.elevation==3,"Collision check mutated caller's elevation")
local override=Field.metatileOverrideAt
Field.metatileOverrideAt=function() return {impassable=true} end
assert(not Collision.canEnter(nil,1,2,entry),"Downhill entry bypassed an explicit obstacle")
Field.metatileOverrideAt=override
assert(not Collision.canEnter(nil,0,2,{surfing=true,dir="down",fromX=0,fromY=1,elevation=3}),
  "Ordinary water must still reject elevation changes")
assert(Player.tryMove("down",nil,false)=="step","Normal downhill input did not enter waterfall")
drive()
assert(Player.cellY==5 and not Field.locked,"Descent did not finish on water")
assert(#Field._session.party==0,"Descent test must have no move user")
assert(stops==2,"Descent sound leaked: "..stops.." active="..tostring(Field._waterfall))
love={filesystem={read=function(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end}}
local exported=require("Gen3").emit({gen3Layered={TEST={collision={"waterfall"}}}},encode)
assert(exported:find("editor.gen3.waterfall.tick",1,true),"Waterfall runtime missing from export")
assert(loadstring(exported),"Invalid exported mod Lua")
-- Maps known to have no falls bypass both the hook bus and behavior probing.
map._editorHasWaterfalls=false;Field._waterfall=nil
local runtime=package.loaded["src.mods.Runtime"];local call=runtime.call
local behavior=Collision.behavior
runtime.call=function(key,fn,...) assert(not key:find("editor.gen3.waterfall",1,true),"Empty map used waterfall hook bus");return call(key,fn,...) end
Collision.behavior=function() error("Empty-map waterfall tick probed behavior") end
Field.updateWaterfall(nil)
Collision.behavior=behavior;runtime.call=call
print("PASS: real player stays surfing; uphill blocked; automatic descent without move; slow ride and repeating sound")

