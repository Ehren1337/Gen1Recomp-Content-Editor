local SRC = [[C:\Users\amand\OneDrive\Documents\GitHub\Gen1Recomp Content Editor]]
local out = SRC .. "\\tools\\diag-music\\out.txt"
local lines = {}
local function say(...) local p={} for i=1,select("#",...) do p[#p+1]=tostring(select(i,...)) end lines[#lines+1]=table.concat(p,"\t") end
local function flush() local f=io.open(out,"w"); f:write(table.concat(lines,"\n").."\n"); f:close() end
function love.load()
  package.path = SRC.."\\?.lua;"..SRC.."\\?\\init.lua;"
    ..SRC.."\\tools\\content-editor\\?.lua;"
    ..SRC.."\\tools\\content-editor\\panels\\?.lua;"
    ..package.path
  pcall(love.filesystem.mount, SRC, "", false)
  local ok, err = pcall(require, "UiPreview")
  say("UiPreview", ok, tostring(err):sub(1,500))
  flush(); love.event.quit(ok and 0 or 1)
end
function love.quit() flush() end
