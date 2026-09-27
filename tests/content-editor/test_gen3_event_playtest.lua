package.path='tools/content-editor/?.lua;runtime/gen1recomp/?.lua;'..package.path
local M=require('Gen3EventPlaytest')
local source=M.source({script='g3:081673b0',map='FR_SAFFRON_CITY',actor=7,x=22,y=22})
assert(loadstring(source))
local path=assert(os.getenv('EDITOR_TEST_ROOT')):gsub('\\','/')..'/tests/content-editor/cutscene-smoke/event-result.txt'
local ending=string.format([[local f=assert(io.open(%q,'w'));f:write('PASS: real game map='..session.map..' script='..tostring(Space.vm._scriptKey)..' saveBlocked='..tostring(Save.save()==false));f:close();love.event.quit();while true do coroutine.yield() end]],path)
source=source:gsub('while true do coroutine.yield%(%) end',function() return ending end)
local f=assert(io.open('tests/content-editor/cutscene-smoke/event-driver.lua','w'));f:write(source);f:close()
