local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local function report(s) local f=assert(io.open(root.."/tests/content-editor/cutscene-smoke/result.txt","w"));f:write(s);f:close() end
love.errorhandler=function(e) report(debug.traceback(tostring(e)));return function() return 1 end end
function love.load()
 local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
 local lib=ffi.load(root.."/love/love.dll");assert(lib.PHYSFS_mount(runtime,"",1)~=0)
 local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
 local function read(path) local f=io.open(cache.."/"..path,"rb");if not f then return end;local b=f:read("*a");f:close();return b end
 require("src.core.GameVersion").set("firered")
 local data={};require("Gen3").load(data,read)
 local S={data=data,project=require("State").blankProject("preview_test"),version="firered",path=root,
  g3CutsceneId="EventScript_AfterWhiteOutHeal",g3CutsceneView=true}
 require("Gen3Workspace").prepare(S)
 local maps=require("Generation").dataMaps(S)
 local mapId="FR_SAFFRON_CITY"
 S._cutsceneLocationId=mapId.."/preview/1"
 local K=require("Kit");K.layout(1360,860)
 local canvas=love.graphics.newCanvas(1360,860)
 love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
 K.beginFrame(0,0,false,0);require("Gen3Cutscenes").draw(S,20,20,1320,820,{markDirty=function() error("Preview mutated project") end});K.endFrame()
 love.graphics.setCanvas()
 assert(#S._cutsceneLocations.locations==0,"Expected unattached shared routine")
 assert(S._cutsceneLocationId==nil and S._cutscenePlayer==nil,"Unattached routine retained unrelated map context")
 local eventScript=assert(maps[mapId].objects[7]).scriptKey
 assert(eventScript,"Expected a real map event")
 S.g3CutsceneId=eventScript;S._cutsceneLocationId=nil;S._cutscenePlayer=nil
 love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
 K.beginFrame(0,0,false,0);require("Gen3Cutscenes").draw(S,20,20,1320,820,{markDirty=function() error("Preview mutated project") end});K.endFrame()
 love.graphics.setCanvas()
 assert(S._cutscenePlayer and S._cutscenePlayer.map,"Attached event did not select a map")
 local found=false
 for _,loc in ipairs(S._cutsceneLocations.locations) do
   if loc.key==S._cutsceneLocationId then assert(S._cutscenePlayer.map==maps[loc.map]);found=true end
 end
 assert(found,"Selected map is not an event attachment")
 local bytes=canvas:newImageData():encode("png")
 local f=assert(io.open(root.."/tests/content-editor/cutscene-smoke/viewer.png","wb"));f:write(bytes:getString());f:close()
 report("PASS: actual FireRed cache, map renderer, sprites, viewer UI and automatic event-map selection: "..mapId)
 love.event.quit()
end
