package.path='tools/content-editor/?.lua;runtime/gen1recomp/?.lua;'..package.path
local M=require('Gen3EventPlaytest')
local files={}
love={timer={getTime=function() return 1.25 end},filesystem={
  createDirectory=function(path) assert(path=='event-playtests');return true end,
  write=function(path,source) assert(not path:match('^[/\\]'));assert(loadstring(source));files[path]=source;return true end,
  getSaveDirectory=function() return 'C:/Users/Test User/AppData/Roaming/LOVE/editor/' end,
}}
local request={script='TEST',map='FR_PALLET_TOWN',x=1,y=1}
local first=assert(M.prepare(request));local second=assert(M.prepare(request))
assert(first~=second)
assert(first:find('C:/Users/Test User/AppData/Roaming/LOVE/editor/event-playtests/',1,true)==1)
assert(M.command('start game',first,true):find(first,1,true))
love.filesystem.write=function() return nil,'disk full' end
local path,err=M.prepare(request);assert(not path and err:find('disk full',1,true))
print('PASS: writable save-directory drivers, unique filenames, spaces, and write failures')
