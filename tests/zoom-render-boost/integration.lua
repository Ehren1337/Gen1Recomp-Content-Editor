return function(workspace, report)
  local realTime, clock, logs = love.timer.getTime, 100, {}
  love.timer.getTime = function() clock=clock+0.001;return clock end
  local chains, ready, inside, draws, vanillaCalls = {}, nil, false, 0, 0
  local root = {pair="test", midLayout={width=10,height=10, midAt=function() return 7 end}}
  local Map = {world={},neighborList={},worldMidAt=function()
    vanillaCalls = vanillaCalls + 1
    return 7,"test"
  end}
  local View = {draw=function()
    draws=draws+1
    assert(Map.refreshWorld()==Map.world)
    assert(Map.worldMidAt(0,0,root)==7)
    if inside == "slow" then clock=clock+0.12 end
    if inside == "error" then error("draw failed") end
  end}
  Map.refreshWorld=function() return Map.world end
  package.loaded["src.core.game3.map"] = Map
  package.loaded["src.core.game3.field_view"] = View
  package.loaded["src.mods.Runtime"] = {
    wantsHook=function(name) return chains[name]~=nil end,
    call=function(name,base,...)
      if chains[name] then return chains[name](base,...) end
      return base(...)
    end,
  }
  local mod={
    read=function(_,name)
      local f=assert(io.open(workspace.."/mods/zoom_render_boost/"..name))
      local s=f:read("*a");f:close();return s
    end,
    hooks={wrap=function(_,name,fn) chains[name]=fn end},
    events={on=function(_,_,fn) ready=fn end},
    log={info=function(_,fmt,...) logs[#logs+1]=string.format(fmt,...) end,warn=function() end},
  }
  assert(loadfile(workspace.."/mods/zoom_render_boost/main.lua"))()(mod)
  ready();ready()
  View.draw({},640,480)
  assert(draws==1 and vanillaCalls==0,"fast lookup not active")
  assert(logs[#logs]:find("queries=1 fast=1",1,true),"optimized queries not counted")
  Map.worldMidAt(0,0,root)
  assert(vanillaCalls==1,"optimization leaked outside drawing")
  inside="error"
  assert(not pcall(View.draw,{},640,480))
  Map.worldMidAt(0,0,root)
  assert(vanillaCalls==2,"draw failure leaked optimization")
  inside=false
  chains["editor.gen3.connections.worldMidAt"]=true
  clock=clock+6
  View.draw({},640,480)
  assert(vanillaCalls==3,"custom connection lookup bypassed")
  assert(logs[#logs]:find("queries=1 fast=0",1,true),"original queries not counted")
  assert(logs[#logs]:find("mode=custom-connections",1,true),"missing bypass explanation")
  inside="slow";clock=clock+6
  View.draw({},640,480)
  assert(logs[#logs-1]:find("Render stall v1.2",1,true),"slow draw not reported")
  assert(logs[#logs-1]:find("refresh=1.00ms",1,true),"refresh timing missing")
  inside=false
  chains={}
  View.draw({},640,480)
  assert(vanillaCalls==5,"disabled mod did not restore vanilla")
  love.timer.getTime=realTime
  report("PASS: draw integration, duplicate ready, error cleanup, custom connections, disabled-mod behavior; original/fast counters, refresh timings and stall reports.")
end
