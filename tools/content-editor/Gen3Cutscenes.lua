local M={}
local K=require("Kit")
local Preview=require("Gen3CutscenePreview")
local copy=require("src.mods.Merge").deepCopy
function M.create(S,catalog)
  local p=S.project;p.gen3=p.gen3 or {};p.gen3.map_scripts=p.gen3.map_scripts or {}
  local n=1;while p.gen3.map_scripts["EditorCutscene_"..n] or catalog["EditorCutscene_"..n] do n=n+1 end
  local id="EditorCutscene_"..n
  local rows={{op="lockall"}}
  for _,row in ipairs(require("Gen3EventActions").create(S,"text")) do rows[#rows+1]=row end
  rows[#rows+1]={op="releaseall"};rows[#rows+1]={op="end"}
  p.gen3.map_scripts[id]=rows
  p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {};p.gen3Modes.map_scripts[id]="register"
  return id
end
function M.draw(S,x,y,w,h,App)
  local s=K.scale;local catalog=require("Gen3").catalog(S.data,"map_scripts")
  local edits=(S.project.gen3 or {}).map_scripts or {}
  local ids=require("RegList").mergeIds(edits,catalog)
  local id=S.g3CutsceneId;if not id or not (edits[id] or catalog[id]) then id=ids[1];S.g3CutsceneId=id end
  require("ChoicePicker").field(S,{x=x,y=y,w=math.max(100*s,w-160*s),h=28*s,ids=ids,current=id,title="CUTSCENE SCRIPT",
    onPick=function(value) S.g3CutsceneId=value;S._cutscenePlayer=nil end})
  if K.button(x+w-150*s,y,150*s,28*s,"New cutscene",{kind="good"}) then
    S.g3CutsceneId=M.create(S,catalog);S._cutscenePlayer=nil;App.markDirty();return
  end
  y=y+40*s;h=h-40*s
  if not id then K.caption(x,y,"Create a cutscene or choose an existing event script.");return end
  if K.button(x,y,130*s,28*s,S.g3CutsceneView and "Open maker" or "Open viewer",{}) then S.g3CutsceneView=not S.g3CutsceneView;S._cutscenePlayer=nil end
  K.caption(x+145*s,y+6*s,K.ellipsize("micro","Attach in Map events > Edit appearance / conditions.",w-145*s))
  y=y+40*s;h=h-40*s
  local rows=edits[id] or catalog[id]
  if not S.g3CutsceneView then
    if S._cutsceneSource~=rows then S._cutsceneSource=rows;S._cutsceneDraft=copy(rows) end
    require("Gen3ScriptSteps").draw(S,"cutscene/"..id,S._cutsceneDraft,require("Gen3ScriptSteps").templates(catalog),x,y,w,h,function()
      S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
      S.project.gen3.map_scripts[id]=copy(S._cutsceneDraft);S._cutsceneSource=S.project.gen3.map_scripts[id]
      S._g3ScriptSource=nil;S._cutscenePlayer=nil;App.markDirty()
    end)
    return
  end
  local Maps=require("Gen3CutsceneMaps")
  local cache=S._cutsceneLocations
  if not cache or cache.id~=id or cache.project~=S.project or not S._cutscenePlayer then
    local scripts={};for key,v in pairs(catalog) do scripts[key]=v end
    for key,v in pairs(edits) do scripts[key]=v end
    local locations,maps=Maps.locations(require("Generation").dataMaps(S),S.project.maps,scripts,id)
    cache={id=id,project=S.project,locations=locations,maps=maps};S._cutsceneLocations=cache
  end
  local locationIds,labels,lookup={},{},{}
  for _,loc in ipairs(cache.locations) do
    locationIds[#locationIds+1]=loc.key;lookup[loc.key]=loc
    labels[loc.key]=require("Gen3Names").map(loc.map).." / "..loc.kind.." "..loc.index
  end
  local selected=S._cutsceneLocationId
  if not lookup[selected] then
    selected=#cache.locations>0 and locationIds[1] or nil
    local target=S._cutsceneTarget
    for _,loc in ipairs(cache.locations) do
      if target and target.script==id and target.map==loc.map and target.actor==loc.actor then selected=loc.key;break end
    end
    S._cutsceneLocationId=selected
  end
  require("ChoicePicker").field(S,{x=x,y=y,w=w,h=28*s,ids=locationIds,labels=labels,current=selected,
    emptyLabel="No maps contain this event",title="EVENT LOCATION",onPick=function(key) S._cutsceneLocationId=key;S._cutscenePlayer=nil end})
  y=y+38*s;h=h-38*s
  local location=lookup[selected];local mapId=location and location.map
  local map=mapId and cache.maps[mapId]
  if not location then S._cutscenePlayer=nil;K.caption(x,y,"No map event references this script. Attach it to a map event to preview it here.");return end
  if K.button(x,y,170*s,28*s,"Playtest event",{kind="good"}) then
    local event=type(location.event)=="table" and location.event or {}
    App.playtestMod({script=id,map=mapId,actor=location.actor,x=event.x or 0,
      y=(event.y or 0)+(location.kind=="objects" and 1 or 0)})
  end
  K.caption(x+185*s,y+6*s,"Runs in the real game; saving is disabled.")
  y=y+38*s;h=h-38*s
  local function reset()
    S._cutscenePlayer=Preview.new(rows,map,function(row) return require("Gen3EventActions").text(S,row) end,
      location and location.actor or nil,
      function(key) return ((S.project.gen3 or {}).map_scripts or {})[key] or catalog[key] end,id)
    local p=S._cutscenePlayer
    p.movements=require("Gen3Resources").readTable(S.data,"data/generated/gba/scripts/movements.lua")
    if location and type(location.event)=="table" then
      p.actors[255].x=location.event.x or 0
      p.actors[255].y=(location.event.y or 0)+(location.kind=="objects" and 1 or 0)
    end
    S._cutscenePlayer.source=rows;S._cutscenePlayer.map=map;S._cutscenePlayer.time=love.timer.getTime();S._cutscenePage=1
  end
  if not S._cutscenePlayer or S._cutscenePlayer.source~=rows or S._cutscenePlayer.map~=map then reset() end
  local p=S._cutscenePlayer;local now=love.timer.getTime();Preview.update(p,now-p.time);p.time=now
  if K.button(x,y,90*s,28*s,p.playing and "Pause" or "Play",{enabled=not p.done and not p.error and not p.prompt}) and not p.done and not p.error and not p.prompt then p.playing=not p.playing end
  if K.button(x+100*s,y,90*s,28*s,"Step",{enabled=not p.done and not p.error and not p.prompt}) then p.playing=false;Preview.step(p) end
  if K.button(x+200*s,y,100*s,28*s,"Restart",{}) then reset();p=S._cutscenePlayer end
  K.caption(x+315*s,y+6*s,K.ellipsize("micro",tostring(p.script or id).." - Command "..p.index.." / "..#p.steps..(p.done and " - Finished" or p.waiting and " - Press Play to continue" or ""),w-315*s))
  y=y+40*s
  if p.prompt then
    K.caption(x,y,p.prompt.kind=="skip" and "This command needs game playtest for full behavior." or "Preview only: choose "..(p.prompt.kind=="flag" and "switch " or "variable ")..tostring(p.prompt.id).." to select the story path.")
    y=y+27*s
    if p.prompt.kind=="skip" then
      if K.button(x,y,200*s,28*s,"Continue without effect",{}) then Preview.answer(p,true);p.playing=true end
    elseif p.prompt.kind=="flag" then
      if K.button(x,y,110*s,28*s,"ON",{}) then Preview.answer(p,true);p.playing=true end
      if K.button(x+120*s,y,110*s,28*s,"OFF",{}) then Preview.answer(p,false);p.playing=true end
    else
      S._cutsceneVar=K.textfield("cutsceneVariable",x,y,140*s,28*s,S._cutsceneVar or "0","")
      local value=tonumber(S._cutsceneVar);local valid=value and value>=0 and value<=65535 and value%1==0
      if K.button(x+150*s,y,110*s,28*s,"Continue",{enabled=valid}) and valid then Preview.answer(p,value);p.playing=true end
    end
    y=y+38*s;h=h-65*s
  end
  if K.button(x,y,115*s,26*s,S._cutsceneOverview and "Focus event" or "Full map",{}) then S._cutsceneOverview=not S._cutsceneOverview end
  if K.button(x+125*s,y,40*s,26*s,"-",{}) then S._cutsceneZoom=math.max(1,(S._cutsceneZoom or 3)-1);S._cutsceneOverview=false end
  if K.button(x+175*s,y,40*s,26*s,"+",{}) then S._cutsceneZoom=math.min(8,(S._cutsceneZoom or 3)+1);S._cutsceneOverview=false end
  K.caption(x+230*s,y+5*s,S._cutsceneOverview and "Full map overview" or ("Zoom "..(S._cutsceneZoom or 3).."x - camera follows the highlighted actor"))
  y=y+34*s
  local vh=math.max(60*s,h-240*s)
  Maps.draw(S,mapId,p,x,y,w,vh)
  y=y+vh+12*s
  if p.notice then
    K.text("small",K.ellipsize("small",p.notice,w),x,y,require("Theme").PAL.text)
    K.offerTooltip(x,y,w,28*s,p.notice);y=y+30*s
  end
  if p.error then K.text("small",K.ellipsize("small",p.error,w),x,y,require("Theme").PAL.text);K.offerTooltip(x,y,w,28*s,p.error);y=y+32*s end
  if p.dialogue then
    if S._cutsceneDialogue~=p.dialogue then S._cutsceneDialogue=p.dialogue;S._cutscenePage=1 end
    local height,info=require("Gen3Dialog").preview(S,p.dialogue,x,y,math.min(w,600*s),{page=S._cutscenePage or 1})
    y=y+height+8*s
    if K.button(x,y,55*s,26*s,"<",{}) then S._cutscenePage=math.max(1,info.page-1) end
    K.caption(x+65*s,y+4*s,"Page "..info.page.." / "..info.pageCount)
    if K.button(x+190*s,y,55*s,26*s,">",{}) then S._cutscenePage=math.min(info.pageCount,info.page+1) end
  end
end
return M
