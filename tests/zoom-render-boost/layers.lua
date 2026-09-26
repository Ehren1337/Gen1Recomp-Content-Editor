return function(workspace, report)
  local function read(path)
    local f=assert(io.open(workspace.."/"..path));local s=f:read("*a");f:close();return s
  end
  local old=read("tests/zoom-render-boost/layer_original.lua.txt")
  local source=read("tools/content-editor/Gen3LayeredRuntime.lua")
  local first=assert(source:find("    local built,images",1,true))
  local last=assert(source:find("    for id,source in pairs(layered.maps) do",first,true))
  local new=source:sub(first,last-1)
  local function fixture(code, animated)
    local counters={draws=0,clears=0,quads=0,gets=0}
    local function image(w,h)
      local o={data=love.image.newImageData(w,h,"rgba8")}
      function o:getWidth() return w end
      function o:getDimensions() return w,h end
      function o:setFilter() end
      return o
    end
    local native,over,custom=image(32,16),image(32,16),image(32,16)
    native.data:mapPixel(function(x) return x<16 and 0.3 or 0.8,0.2,0.4,1 end)
    over.data:mapPixel(function(x,y) return 0.5,0.7,0.2,y<8 and 0.5 or 0 end)
    custom.data:mapPixel(function(x) return 0.2,x<16 and 0.3 or 0.9,0.8,0.5 end)
    local ts={image=native,overImage=over,cols=2}
    local T={_pairs={native=ts}}
    function T.get() counters.gets=counters.gets+1;return T._pairs.native end
    function T.slotFor(_,tile) return tile end
    function T.quad(_,tile) return {x=tile*16,y=0} end
    T.overQuad=T.quad
    function T.setSlotPalette(pair)
      local target=type(pair)=="table" and pair or T._pairs[pair]
      target.image.data:mapPixel(function() return 1,0.1,0.1,1 end)
      return true
    end
    local anim={_pairs={native={frames={water=0,sand=0,flower=0}}}}
    local layered={sources={custom={image="custom",columns=2,
      animations=animated and {[0]={{tile=0,duration=200},{tile=1,duration=200}}} or {}}},animations={}}
    local graphics,stack,state={}, {}, {color={1,1,1,1}}
    function graphics.push() stack[#stack+1]=state;state={canvas=state.canvas,color=state.color} end
    function graphics.pop() state=table.remove(stack) end
    function graphics.setCanvas(c) state.canvas=c end
    function graphics.clear()
      counters.clears=counters.clears+1
      state.canvas.data:mapPixel(function() return 0,0,0,0 end)
    end
    function graphics.origin() end
    function graphics.setColor(r,g,b,a) state.color={r,g,b,a} end
    function graphics.newQuad(x,y) counters.quads=counters.quads+1;return {x=x,y=y} end
    function graphics.draw(img,q,dx,dy)
      counters.draws=counters.draws+1
      if counters.fail then error("test draw failure") end
      for y=0,15 do for x=0,15 do
        local r,g,b,a=img.data:getPixel(q.x+x,q.y+y)
        a=a*state.color[4]
        local dr,dg,db,da=state.canvas.data:getPixel(dx+x,dy+y)
        state.canvas.data:setPixel(dx+x,dy+y,r*a+dr*(1-a),g*a+dg*(1-a),b*a+db*(1-a),a+da*(1-a))
      end end
    end
    local env=setmetatable({T=T,layered=layered,
      mod={assets={image=function() return custom end}},love={graphics=graphics},
      require=function() return anim end},{__index=_G})
    local chunk=assert(loadstring(code.."\nreturn function(entry,t) frameClock=t;return render(entry) end"))
    setfenv(chunk,env)
    local render=chunk()
    local entry={ts={cols=3,image=image(48,16),overImage=image(48,16)},slots={
      {{source="@runtime:native",tile=0,opacity=1},{source="custom",tile=0,opacity=0.6}},
      {{source="@runtime:native",tile=1,opacity=1}},
      {{source="@runtime:native",tile=0,opacity=1,bridge=true}},
    }}
    return {render=function(t) return render(entry,t) end,entry=entry,counts=counters,
      T=T,ts=ts,anim=anim,stack=stack}
  end
  local function equal(a,b)
    for _,name in ipairs({"image","overImage"}) do
      assert(a.entry.ts[name].data:getString()==b.entry.ts[name].data:getString(),"layer pixels differ: "..name)
    end
  end
  local a,b=fixture(old,true),fixture(new,true)
  for tick=0,300 do
    local t=tick/30
    local water=math.floor(t*60/16)%8
    for _,f in ipairs({a,b}) do
      f.anim._pairs.native.frames.water=water
      f.ts.image.data:mapPixel(function() return water/8,0.2,0.6,1 end)
      f.render(t)
    end
    equal(a,b)
  end
  assert(b.counts.clears<a.counts.clears)
  assert(b.counts.quads==2,"custom animation quads must be reused")
  report(string.format("PASS: 301 animated layer updates pixel-identical (opacity, bridges, upper layers); atlas clears %d -> %d, native gets %d -> %d, custom quads %d -> %d.",a.counts.clears,b.counts.clears,a.counts.gets,b.counts.gets,a.counts.quads,b.counts.quads))
  a,b=fixture(old,false),fixture(new,false)
  for tick=0,300 do a.render(tick/30);b.render(tick/30);equal(a,b) end
  assert(b.counts.clears==2,"static atlas must render once")
  for _,f in ipairs({a,b}) do f.T.setSlotPalette("native",0,{});f.render(11) end
  equal(a,b);assert(b.counts.clears==4,"palette edit must invalidate")
  for _,f in ipairs({a,b}) do
    f.ts.image=f.ts.overImage;f.render(12)
  end
  equal(a,b);assert(b.counts.clears==6,"texture replacement must invalidate")
  b.counts.fail=true;b.ts._editorLayerRevision=10
  assert(not pcall(b.render,13));assert(#b.stack==0,"graphics state not restored after failure")
  b.counts.fail=false;b.render(13);equal(a,b)
  report("PASS: static layers render once instead of 301 times; palette mutation, texture replacement and retry after draw errors preserve output.")
  -- Patch the exported mod with exactly the renderer tested here.
  local exported=read("mods/Sevii-Routes/main.lua")
  assert(exported:find(new,1,true),"exported renderer differs from tested generator")
  assert(not exported:find("if entry then render(entry);View._nativeDirty=true end",1,true))
  assert(loadstring(exported),"exported mod does not compile")
  report("PASS: Sevii Routes contains the tested renderer, removes redundant batch invalidation, and compiles.")
end
