return function(data,root)
  local State=require("State");local S=State.new()
  S.data=data;S.version="firered";S.project=State.blankProject("town_maps_test")
  local Content=require("Gen3UiContent");local seen={};local sheet=love.graphics.newCanvas(480,320)
  local K=require("Kit")
  for i,region in ipairs(Content.townMapKeys) do
    local path="data/generated/gba/region_map/"..region.."_map.png"
    local bytes=assert(data._gen3Read(path),"Missing Gen 3 cache: "..path)
    local pixels=love.image.newImageData(love.filesystem.newFileData(bytes,"map.png"))
    assert(pixels:getWidth()==240 and pixels:getHeight()==160)
    assert(not seen[bytes],"Duplicate region artwork");seen[bytes]=true
    love.graphics.setCanvas(sheet);love.graphics.setColor(1,1,1,1)
    love.graphics.draw(love.graphics.newImage(pixels),((i-1)%2)*240,math.floor((i-1)/2)*160)
    S.g3TownRegion=region;love.graphics.setCanvas();love.graphics.clear(.04,.06,.12,1)
    K.beginFrame(0,0,false,0)
    require("Gen3UiContent").draw(S,20,20,1320,850,{markDirty=function() end},"town")
    K.endFrame();assert(not S.g3UiContentError,S.g3UiContentError)
  end
  love.graphics.setCanvas()
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/town-maps.png","wb"))
  f:write(sheet:newImageData():encode("png"):getString());f:close()
end

