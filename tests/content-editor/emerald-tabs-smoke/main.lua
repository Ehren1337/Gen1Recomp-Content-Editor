-- Opens every editor tab with the real Emerald cache and reports which ones fail.
local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local dir=root.."/tests/content-editor/emerald-tabs-smoke/"
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
  ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local lines,failed,App,S,tabs,canvas={},0
local index,frame=1,0
local function report()
  lines[#lines+1]=(failed==0 and "PASS" or "FAIL")..": "..(#lines).." tabs checked, "..failed.." failed"
  local f=assert(io.open(dir.."result.txt","wb"));f:write(table.concat(lines,"\n"));f:close()
end
love.errorhandler=function(err)
  lines[#lines+1]="CRASH: "..debug.traceback(tostring(err));failed=failed+1;report()
  return function() return 1 end
end
function love.load()
  local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  -- Keep the user's editor settings and last game unchanged.
  love.filesystem.write=function() return true end
  App=require("App");App.load(nil,{version="emerald",eventWindow=true});S=App.getState()
  assert(S.version=="emerald" and S.data.maps.EM_LITTLEROOT_TOWN,"Real Emerald cache not loaded: "..tostring(S.status))
  S.project=require("State").ensureProjectFields(require("State").blankProject("emerald_tabs"));S.project.game="emerald"
  require("Gen3ContentAdapter").prepare(S);require("Gen3Workspace").prepare(S)
  tabs=App.tabList();canvas=love.graphics.newCanvas(1360,860)
end
local function frameOf(id)
  local ok,err=xpcall(function() App.update(1/60) end,debug.traceback)
  if not ok then return ok,err end
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  ok,err=xpcall(App.draw,debug.traceback)
  love.graphics.setCanvas();love.graphics.origin();love.graphics.setScissor()
  return ok,err
end
function love.draw()
  local tab=tabs[index]
  if not tab then report();love.event.quit(0);return end
  if frame==0 then S.tab=tab.id;S.status="" end
  local ok,err=frameOf(tab.id)
  frame=frame+1
  if not ok or frame==3 then
    if ok then
      local f=assert(io.open(dir..tab.id..".png","wb"));f:write(canvas:newImageData():encode("png"):getString());f:close()
      lines[#lines+1]="OK   "..tab.id..(S.status~="" and ("  status: "..tostring(S.status)) or "")
    else
      failed=failed+1;lines[#lines+1]="FAIL "..tab.id..": "..tostring(err)
    end
    index,frame=index+1,0
  end
end
