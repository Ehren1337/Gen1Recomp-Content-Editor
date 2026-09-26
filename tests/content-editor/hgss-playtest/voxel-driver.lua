return function(game)
 local U=require("tests.drivers.util")
 local root=os.getenv("HGSS_PROJECT").."/tests/content-editor/hgss-playtest/"
 local function report(t) local f=assert(io.open(root.."voxel-results.log","a"));f:write(t,"\n");f:close() end
 local function shot(name)
  game.capturePath=root..name..".png"
  for i=1,300 do U.wait(1); if not game.capturePath then return end end
  error("capture timeout")
 end
 U.wait(3);assert(#game.mods.errors==0,table.concat(game.mods.errors,"\n"))
 game:_handleBootAction({action="new_game",name="VOXEL"});U.wait(240)
 local Map=require("src.core.game3.map")
 Map.load(nil,game,"FR_PALLET_TOWN",{x=10,y=10,facing="down"});U.wait(240)
 shot("voxel-pallet");report("Pallet 3D rendered")
 game:keypressed("f7");U.wait(10);shot("voxel-orbit");report("Camera orbit rendered")
 game:keypressed("f7");game:keypressed("f7");U.wait(10);shot("voxel-side");report("Side geometry rendered")
 game:keypressed("f8");U.wait(20);shot("voxel-native-toggle");game:keypressed("f8");U.wait(20);shot("voxel-restored");report("Native toggle and 3D restore passed")
 assert(#game.mods.errors==0,table.concat(game.mods.errors,"\n"));report("PASS")
 love.event.quit()
end

