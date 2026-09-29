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
  require("Gen3Workspace").prepare(S)
  assert(require("Gen3Workspace").convert(S,"EM_LITTLEROOT_TOWN"))
  assert(require("LayeredMap").compileProject(S))
  assert(IO.save(mod,p,"emerald"))
  local loader,err=require("Gen3Mod").load(data,mod);assert(loader,err)
  assert(require("Gen3").catalog(data,"pokemon").TREECKO.baseStats.hp==77)
  report("PASS: Emerald mod exported (TREECKO hp 77, EM_LITTLEROOT_TOWN converted)")
  love.event.quit()
end
