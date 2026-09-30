local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
local dir=root.."/tests/content-editor/emerald-playtest/"
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local lib=ffi.load(root.."/love/love.dll")
assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0);assert(lib.PHYSFS_mount(cache,"emerald",1)~=0)
local function report(text)
  local f=assert(io.open(dir.."export.txt","wb"));f:write(text);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  require("src.core.GameVersion").set("emerald")
  local IO=require("ModIO");local Json=require("src.link.Json")
  local data={};require("Gen3").load(data,function(path) return IO.readText(cache.."/"..path) end)
  assert(data.maps.EM_LITTLEROOT_TOWN,"EM_LITTLEROOT_TOWN missing")
  local mod=dir.."mod"
  assert(IO.ensureDirectory(mod))
  assert(IO.writeText(mod.."/manifest.json",Json.encode({id="emerald_e2e",name="Emerald e2e",version="1.0.0",entry="main.lua",games={"emerald"}})))
  local p=require("State").blankProject("emerald_e2e");p.game="emerald";p.gen3={pokemon={TREECKO={baseStats={hp=77}}}}
  local S={version="emerald",project=p,data=data,path=mod}
  local pages=require("src.mods.Merge").deepCopy(assert(require("Gen3RseCredits").manifest(S)).pages)
  pages[2][3].text="E2E Tester";p.gen3Screens={emeraldCredits=pages,emeraldCreditsEnabled=true}
  local bagPath="data/generated/gba/rse/bag/bg.png"
  local bag=love.image.newImageData(love.filesystem.newFileData(assert(data._gen3Read(bagPath)),"bg.png"))
  bag:mapPixel(function() return 1,0,0,1 end)
  assert(IO.ensureDirectory(mod.."/assets/gen3/rse/bag"))
  assert(IO.writeText(mod.."/assets/gen3/rse/bag/bg.png",bag:encode("png"):getString()))
  p.gen3Assets={[bagPath]={file="assets/gen3/rse/bag/bg.png",width=bag:getWidth(),height=bag:getHeight()}}
  local oldale=assert(require("Gen3Map").layout(data,"EM_OLDALE_TOWN"))
  local copy=require("src.mods.Merge").deepCopy(data.maps.EM_OLDALE_TOWN)
  copy.id,copy.name,copy.width,copy.height,copy.midLayout="EM_E2E_COPY","EM_E2E_COPY",oldale.width,oldale.height,nil
  p.gen3MapLayouts={EM_E2E_COPY={source="EM_OLDALE_TOWN",width=oldale.width,height=oldale.height,blank=false}}
  p.gen3.maps={EM_E2E_COPY=copy};p.gen3Modes={maps={EM_E2E_COPY="register"}}
  p.gen3Fly=require("Gen3Fly").rseDefaults(S)
  for _,row in ipairs(p.gen3Fly) do if row.section==7 then row.map,row.x,row.y,row.unlock="EM_OLDALE_TOWN",6,17,"always" end end
  p.gen3Starters={{map="EM_ROUTE101",matchSpecies={"TREECKO"},species="MUDKIP",level=12,nickname="E2E",onlyFirst=true,starterSlot=0}}
  require("Gen3ContentAdapter").prepare(S)
  p.text.gText_Birch_Welcome=require("Gen3Dialog").encode("E2E welcome")
  assert(require("Gen3ContentForms").dexText(S,p.pokemon.TREECKO.index):find("It makes its nest in a giant tree",1,true),"Treecko's original Pokédex description is missing")
  p.pokemon.TREECKO.dexEntry.kind="E2E KIND"
  p.gen3DexText={[p.pokemon.TREECKO.index]="E2E dex line\nsecond line"}
  require("Gen3Workspace").prepare(S)
  assert(require("Gen3Workspace").convert(S,"EM_LITTLEROOT_TOWN"))
  assert(require("LayeredMap").compileProject(S))
  assert(IO.save(mod,p,"emerald"))
  assert(IO.load(mod).gen3DexText[p.pokemon.TREECKO.index]=="E2E dex line\nsecond line","Pokédex description did not survive save")
  local loader,err=require("Gen3Mod").load(data,mod);assert(loader,err)
  assert(require("Gen3").catalog(data,"pokemon").TREECKO.baseStats.hp==77)
  report("PASS: Emerald mod exported (TREECKO hp 77, EM_LITTLEROOT_TOWN converted, credits page 2 edited, bag background replaced)")
  love.event.quit()
end
