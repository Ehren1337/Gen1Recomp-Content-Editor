-- Opens every tab's sub-views with the real Emerald cache and reports crashes
-- and on-screen text that points at FireRed data or errors.
local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local dir=root.."/tests/content-editor/emerald-views-smoke/"
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
  ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path

local V={}
local function add(tab,set) V[#V+1]={tab=tab,set=set or {}} end
local function each(tab,field,values,base)
  for _,v in ipairs(values) do
    local set={}
    for k,x in pairs(base or {}) do set[k]=x end
    set[field]=v
    add(tab,set)
  end
end
for _,tab in ipairs({"guides","project","manifest","cart","code","patches","dialog","shops","trades","items","moves","types","ai"}) do add(tab) end
each("maps","mapViewMode",{"editor","world"},{mapBorderEditor=false})
each("maps","mapEditMode",{"map","events"},{mapBorderEditor=false,mapViewMode="editor"})
each("maps","builderPane",{"details","layers","tileset","stamps","warps"},{mapBorderEditor=false,mapViewMode="editor",mapEditMode="map"})
each("maps","g3MapMode",{"terrain","records","layout","border"},{mapBorderEditor=true})
each("maps","g3BorderView",{"around","pattern"},{mapBorderEditor=true,g3MapMode="border"})
each("encounters","g3EncounterKind",{"land","water","rocks","fishing"},{g3EncounterSection="wild",g3EncounterTime="all"})
each("encounters","g3EncounterTime",{"morning","day","night"},{g3EncounterSection="wild",g3EncounterKind="land"})
add("encounters",{g3EncounterSection="roamers"})
each("trainers","trainerSection",{"basics","parties","ai"})
each("player","playerMode",{"start","starters","overworld","pics"})
each("ui","g3UiMode",{"credits","areas","intro","oak","playback","menus","bag","party","summary","backgrounds",
  "minigames","battle","town","fonts","dex","trainer","fame","teachy","naming","help","overworld","banners","all"})
each("ui","g3OakMode",{"scene","dialogue","artwork"},{g3UiMode="oak"})
for _,game in ipairs({"slots","crush","jump","dodrio"}) do
  each("ui","g3MinigameView",{"playback","images"},{g3UiMode="minigames",g3Minigame=game})
end
each("ui","g3TeachySection",{"shared","battle","status","matchups","catching","tms","register"},{g3UiMode="teachy"})
each("ui","g3DexScreen",{"data","area","size"},{g3UiMode="dex",g3DexSpecies="TREECKO"})
each("ui","g3TownFly",{false,true},{g3UiMode="town"})
each("pokemon","pokemonSection",{"basics","learnset","evolutions","trees","tmhm","dex","forms","positions"},{pokemonId="TREECKO"})
each("breeding","g3BreedingMode",{"species","daycare"},{breedingSpeciesId="TREECKO"})
each("anims","g3AnimSection",{"moves","status","general","special","labels","tags","animBgs"})
each("effects","g3EffectsMode",{"effects","abilities","custom"})
each("rules","g3RulesMode",{"battle","safari"})
each("audio","audioMode",{"music","cries","sfx","map_songs"})
each("gfx","g3GfxMode",{"pokemon","ow","trainers","native","blocks","field_effects","daynight"},{g3SpriteId="TREECKO"})
each("events","g3EventMode",{"map","cutscenes","builder","quests","gifts","scripts"},{g3EventMap="EM_LITTLEROOT_TOWN"})

local SUSPECT={"FR_","FireRed","FIRERED","pokefirered","Kanto","KANTO","Oak","error","Error","nil value",
  "missing","Missing","failed","Failed","not found"}
local lines,failed,flagged,App,S,canvas={},0,0
local index,frame,seen=1,0,{}
local function name(view)
  local keys={}
  for k in pairs(view.set) do keys[#keys+1]=k end
  table.sort(keys)
  local parts={view.tab}
  for _,k in ipairs(keys) do parts[#parts+1]=tostring(view.set[k]) end
  return table.concat(parts,"_")
end
local function report()
  lines[#lines+1]=(failed==0 and "PASS" or "FAIL")..": "..#V.." views checked, "..failed.." failed, "..flagged.." flagged"
  local f=assert(io.open(dir.."result.txt","wb"));f:write(table.concat(lines,"\n"));f:close()
end
love.errorhandler=function(err)
  lines[#lines+1]="CRASH: "..debug.traceback(tostring(err));failed=failed+1;report()
  return function() return 1 end
end
-- Coloured text is { colour, "text", colour, "text", ... }.
local function plain(text)
  if type(text)~="table" then return tostring(text) end
  local out={}
  for _,v in ipairs(text) do if type(v)=="string" then out[#out+1]=v end end
  return table.concat(out)
end
local function check(text)
  local s=plain(text)
  for _,p in ipairs(SUSPECT) do
    if s:find(p,1,true) then seen[s:sub(1,120)]=true break end
  end
end
local function watch(fn)
  return function(text,...) check(text);return fn(text,...) end
end
function love.load()
  local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  -- Keep the user's editor settings and last game unchanged.
  love.filesystem.write=function() return true end
  -- Before the editor loads, so modules that keep their own reference see it.
  love.graphics.print=watch(love.graphics.print);love.graphics.printf=watch(love.graphics.printf)
  -- Captions are letter-spaced: drawn one character at a time.
  local Kit=require("Kit");local caption=Kit.caption
  Kit.caption=function(x,y,text,...) check(text);return caption(x,y,text,...) end
  App=require("App");App.load(nil,{version="emerald",eventWindow=true});S=App.getState()
  assert(S.version=="emerald" and S.data.maps.EM_LITTLEROOT_TOWN,"Real Emerald cache not loaded: "..tostring(S.status))
  S.project=require("State").ensureProjectFields(require("State").blankProject("emerald_views"));S.project.game="emerald"
  require("Gen3ContentAdapter").prepare(S);require("Gen3Workspace").prepare(S)
  S.mapId,S.builderMapId,S.dialogMapId="EM_LITTLEROOT_TOWN","EM_LITTLEROOT_TOWN","EM_LITTLEROOT_TOWN"
  canvas=love.graphics.newCanvas(1360,860)
end
local function frameOf()
  local ok,err=xpcall(function() App.update(1/60) end,debug.traceback)
  if not ok then return ok,err end
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  ok,err=xpcall(App.draw,debug.traceback)
  love.graphics.setCanvas();love.graphics.origin();love.graphics.setScissor()
  return ok,err
end
function love.draw()
  local view=V[index]
  if not view then report();love.event.quit(0);return end
  if frame==0 then
    S.tab=view.tab;S.status="";seen={}
    for k,v in pairs(view.set) do S[k]=v end
  end
  local ok,err=frameOf()
  frame=frame+1
  if not ok or frame==4 then
    local id=name(view)
    if ok then
      local f=assert(io.open(dir..id..".png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close()
      local texts={}
      for s in pairs(seen) do texts[#texts+1]=s end
      table.sort(texts)
      if S.status~="" then texts[#texts+1]="status: "..tostring(S.status) end
      if #texts>0 then flagged=flagged+1 end
      lines[#lines+1]=(#texts>0 and "FLAG " or "OK   ")..id..(#texts>0 and ("\n       "..table.concat(texts,"\n       ")) or "")
    else
      failed=failed+1;lines[#lines+1]="FAIL "..id..": "..tostring(err)
    end
    index,frame=index+1,0
  end
end
