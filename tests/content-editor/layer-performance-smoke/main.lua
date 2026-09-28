local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/save-editor/?.lua;"..package.path
local function report(text)
  local f=assert(io.open(root.."/tests/content-editor/layer-performance-smoke/result.txt","w"))
  f:write(text);f:close()
end
love.errorhandler=function(e) report(debug.traceback(tostring(e)));return function() return 1 end end
function love.load()
  local calls,clears,draws=0,0,0
  local image=love.image.newImageData(80,16)
  image:mapPixel(function(x) return math.floor(x/16)/4,0,0,1 end)
  local ts={image=love.graphics.newImage(image),cols=5}
  local T={_pairs={native=ts}}
  function T.get(pair) calls=calls+1;return T._pairs[pair] end
  function T.slotFor(_,tile) return tile end
  function T.quad(_,tile) return love.graphics.newQuad(tile*16,0,16,16,80,16) end
  T.overQuad=T.quad
  local anim={counter=0,_visible={},_pairs={native={frames={water=0,sand=0},banks={water={mids={0}},sand={mids={4}}}}}}
  function anim.step() anim.counter=anim.counter+1 end
  local Map={current="animated",neighborList={},world={}}
  local Collision={installWarps=function() end,_warps={}}
  local doors={_layoutCache={},getDoorEntryAt=function(id) return id end}
  local hooks={}
  package.loaded["src.core.game3.tileset_native"]=T
  package.loaded["src.core.game3.tileset_anim"]=anim
  package.loaded["src.core.game3.layout_native"]={fromDecoded=function(data,_,pair) data.pair=pair;return data end}
  package.loaded["src.core.game3.scripting.interaction_scripts"]={behaviors={}}
  package.loaded["src.core.game3.map"]=Map
  package.loaded["src.core.game3.collision"]=Collision
  package.loaded["src.core.game3.doors"]=doors
  package.loaded["src.mods.Runtime"]={call=function(key,fn,...) return hooks[key](fn,...) end}
  local function source(tiles)
    local cells={};for i,tile in ipairs(tiles) do cells[i]={source="@runtime:native",tile=tile} end
    return {cellWidth=#tiles,cellHeight=1,baseTileset="native",gen3Border={width=1,height=1,mids={2}},layers={{cells=cells}}}
  end
  local layered={maps={animated=source({0,1,2,1}),static=source({2})},sources={},
    animations={native={[1]={{tile=1,duration=100},{tile=3,duration=100}}}}}
  local data={maps={animated={},static={}}}
  local ready
  local mod={id="perf",events={on=function(_,_,fn) ready=fn end},hooks={wrap=function(_,key,fn) hooks[key]=fn end}}
  local clear,draw=love.graphics.clear,love.graphics.draw
  love.graphics.clear=function(...) clears=clears+1;return clear(...) end
  love.graphics.draw=function(batch,...) assert(batch:typeOf("SpriteBatch"));draws=draws+1;return draw(batch,...) end
  assert(loadstring("return function(mod,layered,tilePixels) "..require("Gen3LayeredRuntime").." end"))()(mod,layered,{})
  ready({game={data=data}})
  assert(data.maps.animated.pair,"Build failed")
  assert(not layered.maps.animated.layers and layered.maps.animated.cellSlots[2]==layered.maps.animated.cellSlots[4])
  assert(doors.getDoorEntryAt("animated",2,0):match("native_2$"),"Compact door lookup lost native tile")
  local builtCalls=calls
  clears,draws=0,0
  anim._pairs.native.frames.sand=1;anim.step()
  assert(clears==0 and draws==0,"Unrelated sand bank redrew entry")
  anim._pairs.native.frames.water=1;anim.step()
  assert(clears==2 and draws==1,"One native tile should clear only its two slot planes")
  clears,draws=0,0
  for i=1,5 do anim.step() end
  assert(clears==2 and draws==1,"Custom frame should redraw one deduplicated slot")
  local atlas=T._pairs[data.maps.animated.pair]
  local pixels=atlas.image:newImageData()
  local slots=layered.maps.animated.cellSlots
  local function red(slot) return pixels:getPixel((slot-1)%atlas.cols*16,math.floor((slot-1)/atlas.cols)*16) end
  assert(math.abs(red(slots[2])-.75)<.01,"Animation pixels did not change")
  assert(math.abs(red(slots[3])-.5)<.01,"Dirty-slot clear damaged static pixels")
  Map.current="static";clears,draws=0,0
  for i=1,120 do anim._pairs.native.frames.water=i;anim.step() end
  assert(clears==0 and draws==0,"Static map redrew")
  assert(calls==builtCalls,"Animation rebound source pairs")
  assert(not hooks["editor.gen3.layers.draw"],"Draw polling is still installed")
  love.graphics.clear,love.graphics.draw=clear,draw
  report("PASS: tile-local changes, dirty slot pixels, sprite batches, static maps, compact doors, no rebinding or draw polling")
  love.event.quit()
end
