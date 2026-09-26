return function(game)
 local U=require("tests.drivers.util")
 U.wait(3); game:_handleBootAction({action="new_game",name="VOXEL"}); U.wait(80)
 local Map=require("src.core.game3.map")
 Map.load(nil,game,"FR_PALLET_TOWN",{x=8,y=10,facing="down"}); U.wait(40)
 local d=Map.currentDef(); local l=d.midLayout
 local root=os.getenv("HGSS_PROJECT").."/tests/content-editor/hgss-playtest/"
 local f=assert(io.open(root.."map.txt","w")); f:write(d.pair," ",l.width," ",l.height,"\n")
 for y=0,l.height-1 do for x=0,l.width-1 do f:write(string.format("%03x ",l:midAt(x,y))) end f:write("\n") end f:close()
 local ts=require("src.core.game3.tileset_native").get(d.pair)
 local c=love.graphics.newCanvas(1024,math.ceil(ts.midCount/16)*52)
 love.graphics.push("all"); love.graphics.setCanvas(c); love.graphics.clear(.2,.2,.2,1)
 local N=require("src.core.game3.tileset_native")
 for mid,slot in pairs(ts.midToSlot) do
 local x=(slot%16)*64; local y=math.floor(slot/16)*52
 love.graphics.setColor(1,1,1,1); love.graphics.draw(ts.image,N.quad(ts,slot),x,y,0,2,2)
 if ts.overImage then love.graphics.draw(ts.overImage,N.overQuad(ts,slot),x,y,0,2,2) end
 love.graphics.print(string.format("%03x",mid),x,y+32)
 end
 love.graphics.pop()
 local bytes=c:newImageData():encode("png"); local o=assert(io.open(root.."atlas.png","wb"));o:write(bytes:getString());o:close()
 love.event.quit()
end
