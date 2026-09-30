local M={}
local K,C=require("Kit"),require("ChoicePicker")
local function readRegionMap(S,name)
  local path="data/generated/gba/region_map/"..name
  return assert(load(assert(S.data._gen3Read(path),"Missing "..path),"@"..path,"t",{}))()
end
-- Kanto Fly destinations (outdoor arrival tiles, not whiteout rooms); the
-- town map cell is the section's top-left corner.
function M.defaults(S)
  local sections=readRegionMap(S,"map_sections.lua").sections
  local corners=readRegionMap(S,"section_geometry.lua").topLeft
  local sevii;for id,sec in pairs(sections) do if sec.id=="MAPSEC_ONE_ISLAND" then sevii=id end end
  local rows={}
  for _,dest in pairs(readRegionMap(S,"fly_destinations.lua").fly_destinations) do
    if dest.mapsec<sevii then rows[#rows+1]=dest end
  end
  table.sort(rows,function(a,b) return a.healLocation<b.healLocation end)
  local result={}
  for _,dest in ipairs(rows) do
    local corner=assert(corners[dest.mapsec],"No town map cell for mapsec "..dest.mapsec)
    result[#result+1]={name=sections[dest.mapsec].name,map=dest.map,x=dest.x,y=dest.y,mapX=corner[1],mapY=corner[2],unlock="visited",enabled=true}
  end
  return result
end
-- Emerald rows name a Hoenn map section. Towns, the Battle Frontier and
-- Southern Island already land somewhere (pokeemerald/src/region_map.c:1995).
local function hasOriginal(section) return section<=15 or section==58 or section==73 end
function M.rseData(S)
  if S.data._g3RseFly then return S.data._g3RseFly end
  local function read(name)
    local path="data/generated/gba/region_map/"..name
    return assert(load(assert(S.data._gen3Read(path),"Missing "..path),"@"..path,"t",{}))()
  end
  local fly=read("fly_destinations.lua")
  local data={fly=fly.fly_destinations,sections=read("map_sections.lua").sections,ids={},labels={},warps={}}
  for _,warp in pairs(fly.map_warps or {}) do data.warps[warp.mapsec]=warp.map end
  for id=0,87 do local sec=data.sections[id];if sec and sec.width>0 then data.ids[#data.ids+1]=id;data.labels[id]=sec.name end end
  S.data._g3RseFly=data;return data
end
function M.rseDefaults(S)
  local data=M.rseData(S);local rows={}
  local visited=require("src.core.game3.constants").of("emerald"):flag("FLAG_VISITED_LITTLEROOT_TOWN")
  for _,dest in pairs(data.fly) do
    rows[#rows+1]={name=data.labels[dest.mapsec],section=dest.mapsec,x=dest.x,y=dest.y,unlock="flag",flag=visited+dest.mapsec,enabled=true}
  end
  table.sort(rows,function(a,b) return a.section<b.section end)
  return rows
end
function M.validate(rows)
  local sections={}
  for _,r in ipairs(rows) do
    assert(type(r.name)=="string" and r.name:match("%S"),"Give each Fly destination a name")
    if r.section~=nil then
      assert(type(r.section)=="number" and r.section>=0 and r.section<=87 and r.section%1==0,"Choose a Town Map section")
      assert(not sections[r.section],"Each Town Map section can have only one Fly destination");sections[r.section]=true
      assert(r.map==nil or (type(r.map)=="string" and r.map~=""),"Choose a landing map")
      assert(r.map or hasOriginal(r.section),"Choose a landing map for "..r.name)
      assert(r.map or r.unlock~="visited","Choose a landing map to unlock "..r.name.." after visiting it")
      for _,key in ipairs({"x","y"}) do assert(type(r[key])=="number" and r[key]>=0 and r[key]%1==0,"Fly coordinates must be whole, non-negative numbers") end
    else
      assert(type(r.map)=="string" and r.map~="","Choose a landing map")
      for _,key in ipairs({"x","y","mapX","mapY"}) do assert(type(r[key])=="number" and r[key]>=0 and r[key]%1==0,"Fly coordinates must be whole, non-negative numbers") end
      assert(r.mapX<=21 and r.mapY<=14,"Fly marker is outside the Town Map")
    end
    assert(r.unlock=="visited" or r.unlock=="always" or r.unlock=="flag","Choose when Fly becomes available")
    if r.unlock=="flag" then assert(type(r.flag)=="number" and r.flag>0 and r.flag%1==0,"Choose a valid unlock flag") end
  end
end
function M.draw(S,x,y,w,h,App)
  local s=K.scale;local fh=30*s
  local game=require("Generation").id(S);local emerald=game=="emerald"
  if not S.project.gen3Fly then
    K.caption(x,y,"Set where Fly takes the player, and when each location unlocks.")
    if K.button(x,y+40*s,260*s,fh,"Set up Fly destinations",{kind="good"}) then S.project.gen3Fly=emerald and M.rseDefaults(S) or M.defaults(S);App.markDirty() end
    return
  end
  local rows=S.project.gen3Fly;local ids,labels={},{}
  for i,r in ipairs(rows) do ids[i]=tostring(i);labels[tostring(i)]=r.name end
  S.g3FlyIndex=math.max(1,math.min(S.g3FlyIndex or 1,#rows))
  C.field(S,{x=x,y=y,w=w-230*s,h=fh,current=tostring(S.g3FlyIndex),ids=ids,labels=labels,title="Fly destination",onPick=function(id) S.g3FlyIndex=tonumber(id) end})
  if K.button(x+w-220*s,y,210*s,fh,"Add destination",{kind="good"}) then
    if emerald then
      local data=M.rseData(S);local used={};for _,row in ipairs(rows) do if row.section then used[row.section]=true end end
      local section;for _,id in ipairs(data.ids) do if not used[id] then section=id;break end end
      if not section then S.status="Every Town Map section already has a Fly destination";return end
      rows[#rows+1]={name=data.labels[section],section=section,map=not hasOriginal(section) and data.warps[section] or nil,x=0,y=0,unlock="always",enabled=true}
    else
      rows[#rows+1]={name="New destination",map="FR_PALLET_TOWN",x=6,y=8,mapX=4,mapY=11,unlock="visited",enabled=true}
    end
    S.g3FlyIndex=#rows;App.markDirty()
  end
  local r=rows[S.g3FlyIndex];if not r then return end
  y=y+45*s
  local function text(label,key)
    K.caption(x,y,label);local v=K.textfield("fly_"..key,x+160*s,y,w-170*s,fh,r[key] or "","")
    if v~=r[key] then r[key]=v;App.markDirty() end;y=y+40*s
  end
  local function choice(label,key,options,names,after)
    K.caption(x,y,label);C.field(S,{x=x+160*s,y=y,w=w-170*s,h=fh,current=r[key],ids=options,labels=names,title=label,onPick=function(id) r[key]=id;if after then after(id) end;App.markDirty() end});y=y+40*s
  end
  text("Location name","name")
  local maps,mapNames={},{};local seen={}
  for _,bag in ipairs({S.data.maps or {},S.project.maps or {},S.project.gen3Maps or {}}) do for id in pairs(bag) do if not seen[id] then seen[id]=true;maps[#maps+1]=id;mapNames[id]=require("Gen3Labels").map(id) end end end;table.sort(maps)
  if emerald then
    local data=M.rseData(S)
    choice("Town Map section","section",data.ids,data.labels)
    local landing,landingNames=maps,mapNames
    if hasOriginal(r.section) then
      landing={""};landingNames=setmetatable({[""]="Original landing spot"},{__index=mapNames})
      for _,id in ipairs(maps) do landing[#landing+1]=id end
    end
    K.caption(x,y,"Landing map");C.field(S,{x=x+160*s,y=y,w=w-170*s,h=fh,current=r.map or "",ids=landing,labels=landingNames,title="Landing map",onPick=function(id) r.map=id~="" and id or nil;App.markDirty() end});y=y+40*s
  else choice("Landing map","map",maps,mapNames) end
  local function number(label,key,max)
    K.caption(x,y,label);local v=require("RegList").num(App,"fly_"..key,x+160*s,y,130*s,fh,r[key]);v=math.max(0,math.min(max or 65535,math.floor(v)))
    if v~=r[key] then r[key]=v;App.markDirty() end;y=y+40*s
  end
  if r.map then number("Landing tile X","x");number("Landing tile Y","y") end
  choice("Available when","unlock",{"visited","always","flag"},{visited="After visiting the landing map",always="Always available",flag="A story flag is set"},function(id) if id=="flag" then r.flag=r.flag or 1 end end)
  if r.unlock=="flag" then
    local flags,names={},{};for id,name in pairs(require("src.core.game3.scripting.flags").forVersion(game).NAMES or {}) do if type(id)=="number" and id>0 then flags[#flags+1]=id;names[id]=name:gsub("^FLAG_",""):gsub("_"," ") end end;table.sort(flags)
    choice("Story flag","flag",flags,names)
  end
  if not emerald then number("Town Map column","mapX",21);number("Town Map row","mapY",14) end
  if K.button(x,y,180*s,fh,r.enabled==false and "Enable destination" or "Disable destination",{}) then r.enabled=r.enabled==false;App.markDirty() end
  if K.button(x+190*s,y,180*s,fh,"Remove destination",{kind="danger"}) then table.remove(rows,S.g3FlyIndex);App.markDirty() end
  y=y+42*s;K.caption(x,y,"Tiles start at 0. Choose a clear outdoor tile. Fly still requires the "..(emerald and "Feather" or "Thunder").." Badge.")
  K.caption(x,y+24*s,"Visited locations are remembered from when this mod is enabled.")
end
function M.emit(p,encode,out)
  if not p.gen3Fly then return end
  M.validate(p.gen3Fly)
  out[#out+1]="local fly=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FlyRuntime.lua")).."\nend)()\nfly.install(mod,"..encode(p.gen3Fly)..")"
end
return M
