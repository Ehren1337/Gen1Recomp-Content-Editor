return function(game)
 local U=require("tests.drivers.util")
 U.wait(3)
 assert(#game.mods.errors==0,table.concat(game.mods.errors,"\n"))
 game:_handleBootAction({action="new_game",name="VOXEL"})
 U.wait(90)
 require("src.core.game3.map").load(nil,game,"FR_PALLET_TOWN",{x=10,y=10,facing="down"})
 while true do U.wait(60) end
end
