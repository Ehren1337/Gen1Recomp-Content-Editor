-- Export source (not bytecode) for day and night (Gen3DayNight): the game
-- side. Nothing in the engine is changed.
--
-- The field is drawn into the renderer's world canvas; menus and text boxes
-- are drawn afterwards on their own. One function is wrapped the way the
-- other editor runtimes do it (Runtime.call + mod.hooks:wrap):
--   Renderer.endWorldPass -- just before the world canvas is finished, on an
--                            outdoor map, it is redrawn through the day/night
--                            shader: every colour multiplied by the time's
--                            tint, except the lit colours.
-- The clock is the device's own (os.date), like Crystal's; `testHour` in the
-- settings pins the hour for playtests.
--
-- Night paint (pixels given their own night colour in GFX > Blocks): while it
-- is night on an outdoor map, those pixels are written into the tileset's
-- pictures in their night colours and put back at dawn or indoors. Each night
-- colour is nudged one 5-bit step if a loaded palette already has it, then
-- joins the lit colours, so exactly those pixels skip the night tint.
--
-- Wild encounters by time of day: a table with its own morning / day / night
-- list uses it at that time, on any map. Just before the game rolls (a step,
-- Rock Smash, a rod), that table's lists are swapped for the current part of
-- the day, and swapped back when the part has none of its own. The same
-- clock and test hour as the looks. With GAME PATCHES > Encounter tables on,
-- Pokemon Crystal's morning / day / night grass lists (`daynight.crystal`)
-- are used on FireRed's own tables that have no lists of your own. Tables in
-- `daynight.allDay` keep their all-day list; with Encounter tables off,
-- nothing here is emitted and every table uses its all-day list.
return function(data, encode)
  return "  local daynight=" .. encode(data) .. "\n"
    .. "  local dnCore=(function()\n"
    .. assert(love.filesystem.read("tools/content-editor/Gen3DayNightCore.lua"), "Gen3DayNightCore.lua missing")
    .. "\n  end)()\n"
    .. [=[
  mod.events:on("game.ready",function(ctx)
    local okR,Renderer=pcall(require,"src.render.Renderer")
    if not okR or type(Renderer)~="table" or not Renderer.endWorldPass then return end
    local Runtime=require("src.mods.Runtime")
    local T=require("src.core.game3.tileset_native")
    if not Renderer["editor.gen3.daynight.world"] then
      Renderer["editor.gen3.daynight.world"]=true
      local original=Renderer.endWorldPass
      Renderer.endWorldPass=function(...) return Runtime.call("editor.gen3.daynight.world",original,...) end
    end

    local shader,failed,scratch
    local lit,litReady={},false
    -- Lit colours as the game shows them: from each tileset's palettes,
    -- after any colours the project added (GFX > Blocks merges).
    local function resolveLit()
      if litReady then return end
      litReady=true
      for _,e in ipairs(daynight.lit or {}) do
        local ok,ts=pcall(T.get,e[1])
        local row=ok and ts and ts.bgr and ts.bgr[e[2]]
        if row and row[e[3]] and #lit<dnCore.MAX_LIT then
          local r,g,b=dnCore.bgr5(row[e[3]])
          lit[#lit+1]={r,g,b}
        end
      end
    end

    -- Night colours, as unique 5-bit colours: { ["rrggbb"] = {r,g,b} }.
    local DIGITS="123456789abcdefghijklmnopqrstuvwxyz"
    local paintColours
    local function resolvePaint()
      if paintColours then return end
      paintColours={}
      local used={}
      for _,ts in pairs(T._pairs or {}) do
        for p=0,15 do
          local row=type(ts)=="table" and ts.bgr and ts.bgr[p]
          if row then for c=0,15 do if row[c] then
            local r,g,b=dnCore.bgr5(row[c]);used[r*1024+g*32+b]=true
          end end end
        end
      end
      for _,e in ipairs(daynight.paint or {}) do
        for _,hex in ipairs(e[4]) do
          if not paintColours[hex] then
            local r,g,b=dnCore.hex(hex)
            r,g,b=math.floor(r*31+0.5),math.floor(g*31+0.5),math.floor(b*31+0.5)
            local pick={r,g,b}
            for _,d in ipairs({{0,0,0},{0,0,1},{0,0,-1},{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{1,1,0},{-1,-1,0}}) do
              local q1,q2,q3=r+d[1],g+d[2],b+d[3]
              if q1>=0 and q1<=31 and q2>=0 and q2<=31 and q3>=0 and q3<=31 and not used[q1*1024+q2*32+q3] then
                pick={q1,q2,q3};break
              end
            end
            used[pick[1]*1024+pick[2]*32+pick[3]]=true
            paintColours[hex]=pick
            if #lit<dnCore.MAX_LIT then lit[#lit+1]=pick end
          end
        end
      end
    end
    local okV,View=pcall(require,"src.core.game3.field_view")
    -- Write (on) or take back (off) the night pixels in every loaded tileset.
    local function nightPixels(on)
      for _,e in ipairs(daynight.paint or {}) do
        local ok,ts=pcall(T.get,e[1])
        local slot=ok and ts and ts.imageData and ts.midToSlot and ts.midToSlot[e[2]]
        if slot then
          ts._dnNight=ts._dnNight or {}
          local state=ts._dnNight[e[2]]
          if (state~=nil)~=on then
            local cols=ts.cols or 16
            local ax,ay=slot%cols*16,math.floor(slot/cols)*16
            local over=false
            if on then
              state={}
              for i=1,256 do
                local k=DIGITS:find(e[3]:sub(i,i),1,true)
                local c=k and paintColours[e[4][k]]
                if c then
                  local x,y=ax+(i-1)%16,ay+math.floor((i-1)/16)
                  local target=ts.imageData
                  if ts.overImageData then
                    local _,_,_,a=ts.overImageData:getPixel(x,y)
                    if a>0 then target=ts.overImageData;over=true end
                  end
                  local r,g,b,a=target:getPixel(x,y)
                  state[#state+1]={target,x,y,r,g,b,a}
                  target:setPixel(x,y,c[1]/31,c[2]/31,c[3]/31,1)
                end
              end
              ts._dnNight[e[2]]=state
            else
              for _,p in ipairs(state) do
                p[1]:setPixel(p[2],p[3],p[4],p[5],p[6],p[7])
                if p[1]==ts.overImageData then over=true end
              end
              ts._dnNight[e[2]]=nil
            end
            if ts.image and ts.image.replacePixels then ts.image:replacePixels(ts.imageData) end
            if over and ts.overImage and ts.overImage.replacePixels then ts.overImage:replacePixels(ts.overImageData) end
            if okV and View then View._nativeDirty=true end
            -- Maps built in the editor draw from their own atlas, copied from
            -- this one; tell them to copy again (Gen3LayeredRuntime).
            ts._editorLayerRevision=(ts._editorLayerRevision or 0)+1
          end
        end
      end
    end

    local function clock()
      local t=os.date("*t")
      if daynight.testHour then return daynight.testHour,0 end
      return t.hour,t.min
    end
    local last,tr,tg,tb,period=-1,1,1,1,"day"
    local function tint()
      local now=love.timer.getTime()
      if now-last>=1 then
        last=now
        local h,m=clock()
        tr,tg,tb,period=dnCore.tintAt(daynight,h,m)
      end
      return tr,tg,tb
    end

    -- Mods see no `package`; engine modules come through require.
    local okG,GameRuntime=pcall(require,"src.core.game3.runtime")
    local okM,Map=pcall(require,"src.core.game3.map")
    local okB,Battle=pcall(require,"src.core.game3.battle")
    if not okG then GameRuntime=nil end
    if not okM then Map=nil end
    if not okB then Battle=nil end
    local function outdoors()
      local game=GameRuntime and GameRuntime._game
      local id=(game and game.currentMap) or (Map and Map.current)
      local maps=game and game.data and game.data.maps
      local def=id and maps and maps[id]
      if not def then return false end
      local kind=tonumber(def.mapType)
      if kind then return dnCore.OUTDOOR[kind]==true end
      return def.outdoor==true
    end

    -- Wild encounters by time of day.
    local okE,E=pcall(require,"src.core.game3.encounters")
    if okE and type(E)=="table" and (next(daynight.encounters or {}) or next(daynight.crystal or {})) then
      local okP,Pokemon=pcall(require,"src.core.game3.pokemon")
      local originals=setmetatable({},{__mode="k"})
      local converted={}
      local KINDS={"land","water","rocks","fishing"}
      -- Species ids to the game's species numbers (custom species too).
      local function speciesNum(id)
        if type(id)=="number" then return id end
        local ok,rec=pcall(function() return mod.content.pokemon:get(id) end)
        if ok and type(rec)=="table" and tonumber(rec.index) then return tonumber(rec.index) end
        local n=okP and Pokemon and Pokemon.speciesFromName and Pokemon.speciesFromName(id)
        return n or tonumber(id)
      end
      local function areaFor(set,tag,id,period,kind,fallbackRate)
        local key=tag.."|"..id.."|"..period.."|"..kind
        if converted[key]==nil then
          local src=set[id][period][kind]
          local area={rate=src.rate or fallbackRate or 21,slots={}}
          for i,slot in ipairs(src.slots or {}) do
            area.slots[i]={species=speciesNum(slot.species) or 0,minLevel=slot.minLevel,maxLevel=slot.maxLevel}
          end
          converted[key]=area
        end
        return converted[key]
      end
      local function currentPeriod()
        local h,m=clock()
        return dnCore.period(daynight,h,m)
      end
      -- The game keeps a table per name (ROUTE_1, FR_ROUTE_1, "3:19", ...);
      -- the one the editor named and the one the map rolls on are matched
      -- by map group and number, the way the content registry matches them.
      local function find(set,t,mapId)
        if set[mapId] then return mapId,set[mapId] end
        local g,n=t.mapGroup,t.mapNum
        for id,periods in pairs(set) do
          local ok2,other=pcall(E.tableFor,id)
          if ok2 and type(other)=="table" and (other==t
              or (g~=nil and n~=nil and other.mapGroup==g and other.mapNum==n)) then
            return id,periods
          end
        end
      end
      local function hasKind(periods,kind)
        for _,kinds in pairs(periods) do if kinds[kind] then return true end end
        return false
      end
      -- Lists for the time of day: your own first; else Crystal's
      -- (GAME PATCHES > Encounter tables); else the table's usual list.
      local function apply(mapId)
        if mapId==nil or not E.tableFor then return end
        local ok,t=pcall(E.tableFor,mapId)
        if not ok or type(t)~="table" then return end
        local uid,user=find(daynight.encounters or {},t,mapId)
        local cid,cry=find(daynight.crystal or {},t,mapId)
        if not user and not cry then return end
        -- kinds kept on their all-day list (Encounters > All day)
        local _,pinned=find(daynight.allDay or {},t,mapId)
        pinned=pinned or {}
        local orig=originals[t]
        if not orig then
          orig={}
          for kind in pairs({land=1,grass=1,water=1,rocks=1,fishing=1}) do orig[kind]=t[kind] or false end
          originals[t]=orig
        end
        local period=currentPeriod()
        for _,kind in ipairs(KINDS) do
          local area
          if pinned[kind] then
            area=nil
          elseif user and hasKind(user,kind) then
            if (user[period] or {})[kind] then area=areaFor(daynight.encounters,"u",uid,period,kind) end
          elseif cry and hasKind(cry,kind) then
            if (cry[period] or {})[kind] then
              local base=orig[kind] or (kind=="land" and orig.grass) or nil
              area=areaFor(daynight.crystal,"c",cid,period,kind,base and base.rate)
            end
          end
          if area then
            t[kind]=area
            if kind=="land" then t.grass=nil end
          else
            t[kind]=orig[kind] or nil
            if kind=="land" then t.grass=orig.grass or nil end
          end
        end
      end
      for _,name in ipairs({"onStep","rollLand","rollWater","rollRocks","rollFishing","hasFishingMons"}) do
        local key="editor.gen3.daynight.encounters."..name
        if type(E[name])=="function" and not E[key] then
          E[key]=true
          local original=E[name]
          E[name]=function(...) return Runtime.call(key,original,...) end
        end
        mod.hooks:wrap(key,function(proceed,mapId,...)
          apply(mapId)
          return proceed(mapId,...)
        end)
      end
    end

    local paintOn=false
    mod.hooks:wrap("editor.gen3.daynight.world",function(proceed,self,...)
      local canvas=self and self.worldCanvas
      local battle=Battle and Battle.isActive and Battle.isActive()
      local out=not battle and outdoors()
      if daynight.paint and #daynight.paint>0 and not battle then
        tint()
        local want=out and period=="night"
        if want then resolveLit();resolvePaint() end
        -- once a second (and whenever a tileset was reloaded) settle the pixels
        if want~=paintOn or last~=(self._dnPaintCheck or 0) then
          self._dnPaintCheck=last
          nightPixels(want)
          paintOn=want
        end
      end
      if canvas and not failed and out then
        local r,g,b=tint()
        if r<0.999 or g<0.999 or b<0.999 then
          if not shader then
            local ok,sh=pcall(love.graphics.newShader,dnCore.SHADER)
            if ok then shader=sh else failed=true end
          end
          if shader then
            resolveLit()
            local w,h=canvas:getDimensions()
            if not scratch or scratch:getWidth()~=w or scratch:getHeight()~=h then
              if scratch and scratch.release then scratch:release() end
              scratch=love.graphics.newCanvas(w,h,{dpiscale=1})
              scratch:setFilter("nearest","nearest")
            end
            love.graphics.push("all")
            love.graphics.origin()
            love.graphics.setScissor()
            love.graphics.setColor(1,1,1,1)
            love.graphics.setBlendMode("replace")
            love.graphics.setCanvas(scratch)
            shader:send("tint",{r,g,b})
            shader:send("litCount",#lit)
            if #lit>0 then shader:send("lit",(table.unpack or unpack)(lit)) end
            love.graphics.setShader(shader)
            love.graphics.draw(canvas,0,0)
            love.graphics.setShader()
            love.graphics.setCanvas(canvas)
            love.graphics.draw(scratch,0,0)
            love.graphics.pop()
          end
        end
      end
      return proceed(self,...)
    end)
  end,-150)
]=]
end
