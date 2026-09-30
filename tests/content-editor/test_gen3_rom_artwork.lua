local runtime = assert(os.getenv("POKEPORT_RECOMP"))
package.path = "tools/content-editor/?.lua;" .. runtime .. "/?.lua;" .. package.path
local Rom = require("Gen3Rom")
love = {image={newImageData=function(w,h,format,bytes)
  assert(w==64 and h==64 and format=="rgba8" and #bytes==64*64*4)
  return {bytes=bytes}
end}}
local shiny="data/generated/gba/pokemon/front_shiny/25.rgba"
local castform="data/generated/gba/pokemon/back/385_2.rgba"
local files={[shiny]=string.rep("\1",64*64*4),[castform]=string.rep("\2",64*64*4)}
local S={data={_gen3Read=function(path) return files[path] end}}
for _,id in ipairs({-1,440,1000,1.5,"25"}) do
  local image,err=Rom.shiny(S,id,false)
  assert(not image and err:find("no original artwork",1,true),tostring(err))
end
assert(Rom.shiny(S,25,false).bytes==files[shiny])
assert(Rom.formPicture(S,385,true,2,2,false).bytes==files[castform])
local image,err=Rom.formPicture(S,410,false,1,0,false)
assert(not image and err:find("Missing Gen 3 cache",1,true),tostring(err))
files[shiny]="short"
image,err=Rom.shiny(S,25,false)
assert(not image and err:find("Missing Gen 3 cache",1,true),tostring(err))
print("PASS: cache artwork reads and graceful failures")
