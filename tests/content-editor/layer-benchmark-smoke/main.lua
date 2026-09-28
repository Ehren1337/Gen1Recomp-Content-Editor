-- Controlled A/B workload using real LOVE canvases, images and SpriteBatches.
-- Game modules are fixtures: these timings are not whole-game FPS measurements.
local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local variant=os.getenv("EDITOR_BENCH_VARIANT") or "updated"
local scenario=os.getenv("EDITOR_BENCH_SCENARIO") or "animated"
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/save-editor/?.lua;"..package.path
local output=root.."/tests/content-editor/layer-benchmark-smoke/"..variant.."-"..scenario..".txt"
local function report(s) local f=assert(io.open(output,"w"));f:write(s);f:close() end
love.errorhandler=function(e) report(debug.traceback(tostring(e)));return function() return 1 end end
function love.load()
  local timer=love.timer.getTime
  local now,calls,draws,clears=0,0,0,0
  local pixels=love.image.newImageData(512,512)
  pixels:mapPixel(function(x,y) return x/512,y/512,.5,1 end)
  local ts={image=love.graphics.newImage(pixels),cols=32,quads={}}
  local T={_pairs={native=ts}}
  function T.get(pair) calls=calls+1;return T._pairs[pair] end
  function T.slotFor(_,tile) return tile end
  function T.quad(t,tile)
    if not t.quads[tile] then t.quads[tile]=love.graphics.newQuad(tile%32*16,math.floor(tile/32)*16,16,16,512,512) end
    return t.quads[tile]
  end
  T.overQuad=T.quad
  local anim={counter=0,_visible={},_pairs={native={frames={sand=0},banks={sand={mids={1023}}}}}}
  function anim.step()
    anim.counter=anim.counter+1
    anim._pairs.native.frames.sand=math.floor(anim.counter/8)%8
  end
  local Map={current="MAP1",neighbors={},neighborList={},world={}}
  local View={draw=function() end}
  local hooks={}
  package.loaded["src.core.game3.tileset_native"]=T
  package.loaded["src.core.game3.tileset_anim"]=anim
  package.loaded["src.core.game3.layout_native"]={fromDecoded=function(data,_,pair) data.pair=pair;return data end}
  package.loaded["src.core.game3.scripting.interaction_scripts"]={behaviors={}}
  package.loaded["src.core.game3.map"]=Map
  package.loaded["src.core.game3.field_view"]=View
  package.loaded["src.core.game3.collision"]={installWarps=function() end,_warps={}}
  package.loaded["src.core.game3.doors"]={_layoutCache={},getDoorEntryAt=function() end}
  package.loaded["src.mods.Runtime"]={call=function(key,fn,...) return hooks[key](fn,...) end}
  local layered={maps={},sources={},animations={native={}}}
  if scenario=="animated" then layered.animations.native[1]={{tile=1,duration=100},{tile=2,duration=100}} end
  local data={maps={}}
  for n=1,5 do
    local layers={{cells={}},{cells={}},{cells={}}}
    for i=1,16000 do
      layers[1].cells[i]={source="@runtime:native",tile=(i-1)%512+1}
      layers[2].cells[i]={source="@runtime:native",tile=600+math.floor((i-1)/512)%8}
      layers[3].cells[i]={source="@runtime:native",tile=700}
    end
    layered.maps["MAP"..n]={cellWidth=80,cellHeight=200,baseTileset="native",
      gen3Border={width=1,height=1,mids={700}},layers=layers}
    data.maps["MAP"..n]={}
  end
  local ready
  local mod={id="bench",events={on=function(_,_,fn) ready=fn end},hooks={wrap=function(_,key,fn) hooks[key]=fn end}}
  local body=variant=="baseline" and assert(loadfile(root.."/tests/content-editor/layer-benchmark-smoke/baseline.lua"))()
    or require("Gen3LayeredRuntime")
  assert(loadstring("return function(mod,layered,tilePixels) "..body.." end"))()(mod,layered,{})
  ready({game={data=data}})
  assert(data.maps.MAP5.pair,"Map build failed")
  collectgarbage("collect");collectgarbage("collect")
  local heap=collectgarbage("count")/1024
  local gcTimes={}
  for i=1,9 do local start=timer();collectgarbage("collect");gcTimes[i]=(timer()-start)*1000 end
  table.sort(gcTimes)
  local draw,clear=love.graphics.draw,love.graphics.clear
  love.graphics.draw=function(...) draws=draws+1;return draw(...) end
  love.graphics.clear=function(...) clears=clears+1;return clear(...) end
  love.timer.getTime=function() return now end
  calls=0
  local start=timer()
  for frame=1,600 do now=frame/60;anim.step();View.draw({data=data}) end
  love.graphics.flushBatch()
  local submitMs=(timer()-start)*1000
  -- Readback waits for queued GPU work before the total measurement ends.
  local atlas=T._pairs[data.maps.MAP1.pair]
  atlas.image:newImageData():release()
  local totalMs=(timer()-start)*1000
  love.timer.getTime=timer;love.graphics.draw=draw;love.graphics.clear=clear
  report(string.format("%s %s | heap_MiB=%.3f | median_full_GC_ms=%.3f | 600_steps_submit_ms=%.3f | with_GPU_sync_ms=%.3f | draw_calls=%d | canvas_clears=%d | T_get_calls=%d\n",
    variant,scenario,heap,gcTimes[5],submitMs,totalMs,draws,clears,calls))
  love.event.quit()
end
