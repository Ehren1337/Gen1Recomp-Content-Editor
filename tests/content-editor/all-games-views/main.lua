-- Opens every tab for one game (env GAME) with its real cache and reports
-- crashes and on-screen text that names another game, a generation, or an error.
local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local game=assert(os.getenv("GAME"))
local dir=root.."/tests/content-editor/all-games-views/out/"..game.."/"
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
  ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path

local GAMES={"Red","Blue","Yellow","Gold","Silver","Crystal","FireRed","LeafGreen","Emerald"}
local SUSPECT={"Gen 1","Gen 2","Gen 3","Gen1","Gen2","Gen3","GEN 1","GEN 2","GEN 3","generation","Generation",
  "error","Error","nil value","missing","Missing","failed","Failed","not found","Select the original","requires"}
local lines,failed,flagged,App,S={},0,0
local views,queued,index,frame,seen,chips={},{},1,0,{},{}
local own

local function name(view)
  local keys={}
  for k in pairs(view.set) do keys[#keys+1]=k end
  table.sort(keys)
  local parts={view.tab}
  for _,k in ipairs(keys) do parts[#parts+1]=k.."-"..tostring(view.set[k]) end
  return table.concat(parts,"_")
end
local function add(tab,set)
  local view={tab=tab,set=set or {}}
  local id=name(view)
  if queued[id] or #views>=600 then return end
  queued[id]=true;views[#views+1]=view
end
local function each(tab,field,values,base)
  for _,v in ipairs(values) do
    local set={}
    for k,x in pairs(base or {}) do set[k]=x end
    set[field]=v
    add(tab,set)
  end
end
-- Sub-views drawn with their own chips instead of RegList.modeChips.
local function addSubViews(gen3,species,map)
  each("code","codeSourceKind",{"mod","repo"})
  each("maps","mapViewMode",{"editor","world"})
  each("maps","mapEditMode",{"map","events"},{mapViewMode="editor"})
  each("maps","builderPane",{"details","layers","tileset","stamps","warps"},{mapViewMode="editor",mapEditMode="map"})
  each("maps","mapSection",{"basics","objects","warps","signs","coordEvents","encounters"},{mapViewMode="editor",mapEditMode="events"})
  if not gen3 then
    each("pokemon","pokemonSection",{"basics","learnset","evolutions","trees","tmhm","dex"})
    each("trainers","trainerSection",{"basics","parties","place"})
    each("events","eventsMode",{"scripts","hooks","starters","phone","saveflags","gifts","decorations","trainerhouse"})
    return
  end
  each("maps","g3MapMode",{"terrain","records","layout","border"},{mapBorderEditor=true})
  each("maps","g3BorderView",{"around","pattern"},{mapBorderEditor=true,g3MapMode="border"})
  each("encounters","g3EncounterKind",{"land","water","rocks","fishing"},{g3EncounterSection="wild",g3EncounterTime="all"})
  each("encounters","g3EncounterTime",{"morning","day","night"},{g3EncounterSection="wild",g3EncounterKind="land"})
  add("encounters",{g3EncounterSection="roamers"})
  each("trainers","trainerSection",{"basics","parties","ai"})
  each("ui","g3UiMode",{"credits","areas","intro","oak","playback","menus","bag","party","summary","backgrounds",
    "minigames","battle","town","fonts","dex","trainer","fame","teachy","naming","help","overworld","banners","all"})
  each("ui","g3OakMode",{"scene","dialogue","artwork"},{g3UiMode="oak"})
  each("ui","g3TeachySection",{"shared","battle","status","matchups","catching","tms","register"},{g3UiMode="teachy"})
  each("ui","g3DexScreen",{"data","area","size"},{g3UiMode="dex",g3DexSpecies=species})
  each("ui","g3TownFly",{false,true},{g3UiMode="town"})
  each("pokemon","pokemonSection",{"basics","learnset","evolutions","trees","tmhm","dex","forms","positions"},{pokemonId=species})
  each("breeding","g3BreedingMode",{"species","daycare"},{breedingSpeciesId=species})
  each("anims","g3AnimSection",{"moves","status","general","special","labels","tags","animBgs"})
  each("effects","g3EffectsMode",{"effects","abilities","custom"})
  each("rules","g3RulesMode",{"battle","safari"})
  each("gfx","g3GfxMode",{"pokemon","ow","trainers","native","blocks","field_effects","daynight"},{g3SpriteId=species})
  each("events","g3EventMode",{"map","cutscenes","builder","quests","gifts","scripts"},{g3EventMap=map})
end

local function report()
  lines[#lines+1]=(failed==0 and "PASS" or "FAIL")..": "..#views.." views checked, "..failed.." failed, "..flagged.." flagged"
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
    if s:find(p,1,true) then seen[s:sub(1,160)]=true return end
  end
  for _,g in ipairs(GAMES) do
    if g~=own and s:find("%f[%a]"..g.."%f[%A]") then seen[s:sub(1,160)]=true return end
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
  love.filesystem.createDirectory(dir)
  os.execute('mkdir "'..dir:gsub("/","\\")..'" 2>nul')
  love.graphics.print=watch(love.graphics.print);love.graphics.printf=watch(love.graphics.printf)
  -- Captions are letter-spaced: drawn one character at a time.
  local Kit=require("Kit");local caption=Kit.caption
  Kit.caption=function(x,y,text,...) check(text);return caption(x,y,text,...) end
  -- Every mode chip row drawn is a list of sub-views to visit.
  local RegList=require("RegList");local modeChips=RegList.modeChips
  RegList.modeChips=function(state,key,modes,...)
    chips[key]=modes
    return modeChips(state,key,modes,...)
  end
  local GameVersion=require("src.core.GameVersion")
  own=GameVersion.VERSIONS[game].label
  GameVersion.set(game);require("src.import.CacheFs").mountVersion(game)
  App=require("App");App.load(nil,{version=game,eventWindow=true});S=App.getState()
  assert(S.version==game,"Wrong game loaded: "..tostring(S.version).." "..tostring(S.status))
  local State=require("State")
  S.project=State.ensureProjectFields(State.blankProject(game.."_views"));S.project.game=game
  local gen3=require("Generation").isGen3(S)
  if gen3 then
    require("Gen3ContentAdapter").prepare(S);require("Gen3Workspace").prepare(S)
  end
  local tabs={}
  for _,tab in ipairs(App.visibleTabs()) do tabs[tab.id]=true;tabs[#tabs+1]=tab.id;add(tab.id) end
  lines[#lines+1]="tabs: "..table.concat(tabs," ")
  local species=game=="emerald" and "TREECKO" or "BULBASAUR"
  addSubViews(gen3,species,game=="emerald" and "EM_LITTLEROOT_TOWN" or nil)
  local kept={}
  for _,view in ipairs(views) do if tabs[view.tab] then kept[#kept+1]=view end end
  views=kept
end
-- Queue each chip the view drew that the view did not already pin.
local function expand(view)
  for key,modes in pairs(chips) do
    if view.set[key]==nil then
      for _,m in ipairs(modes) do
        local set={}
        for k,x in pairs(view.set) do set[k]=x end
        set[key]=m.id
        add(view.tab,set)
      end
    end
  end
end
-- Draws to the window like the editor does: an outer canvas would change
-- what previews restore after their own setCanvas.
local function frameOf()
  local ok,err=xpcall(function() App.update(1/60) end,debug.traceback)
  if not ok then return ok,err end
  love.graphics.clear(.04,.06,.12,1)
  ok,err=xpcall(App.draw,debug.traceback)
  love.graphics.origin();love.graphics.setScissor()
  return ok,err
end
function love.draw()
  local view=views[index]
  if not view then report();love.event.quit(0);return end
  local id=name(view)
  if frame==0 then
    for k in pairs(views[index-1] and views[index-1].set or {}) do S[k]=nil end
    S.tab=view.tab;S.status="";seen={};chips={}
    for k,v in pairs(view.set) do S[k]=v end
  end
  local ok,err=frameOf()
  frame=frame+1
  if not ok or frame==4 then
    if ok then
      expand(view)
      love.graphics.captureScreenshot(function(image)
        local f=assert(io.open(dir..id..".png","wb"));f:write(image:encode("png"):getString());f:close()
      end)
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
