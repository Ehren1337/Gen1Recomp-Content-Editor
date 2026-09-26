return function(game)
  local U = require("tests.drivers.util")
  local root = os.getenv("HGSS_PROJECT") .. "/tests/content-editor/hgss-playtest/"
  local function report(s)
    local f=assert(io.open(root.."results.log", "a")); f:write(s,"\n"); f:close()
  end
  local function shot(name)
    game.capturePath=root..name..".png"
    for i=1,300 do U.wait(1); if not game.capturePath then break end end
    assert(not game.capturePath, "capture timed out")
  end
  U.wait(5)
  assert(game.mods.order[1]=="firered_hgss_voxel", "mod not loaded")
  assert(#game.mods.errors==0, table.concat(game.mods.errors,"\n"))
  game:_handleBootAction({action="new_game", name="VOXEL"})
  U.wait(180)
  assert(game.phase=="field", "field failed")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Tilt = require("src.render.Tilt")
  local function place(map,x,y)
    Map.load(nil, game, map, {x=x,y=y,facing="down"})
    U.wait(90)
  end
  place("FR_PALLET_TOWN",8,8)
  assert(Tilt.level==0, "2D tilt must be disabled for the real 3D camera")
  shot("pallet-town")
  report("PASS: mod loaded without errors; Pallet Town rendered with real 3D camera")
  local x,y=Player.px,Player.py
  U.hold(game,"down",30); U.wait(30)
  assert(Player.px~=x or Player.py~=y, "player did not walk")
  report("PASS: player movement with mod enabled")
  local menu=require("src.ui.game3.start_menu")
  menu.show({session=game.session,game=game})
  U.wait(25); shot("menu"); menu.close(true); U.wait(25)
  report("PASS: field menu opens and closes")
  place("FR_VIRIDIAN_CITY_POKEMON_CENTER_1F",7,7)
  shot("interior")
  report("PASS: outdoor-to-interior map load")
  place("FR_VIRIDIAN_CITY",19,21)
  shot("viridian-city")
  local Runtime=require("src.core.game3.runtime")
  require("src.core.game3.party").giveMon(Runtime.getSession(),6,50)
  local Battle=require("src.core.game3.battle")
  local ok,err=require("src.core.game3.battle_bridge").startWild(Runtime._mod, game, {species=16,level=2}, {fade=true})
  assert(ok, tostring(err))
  U.wait(200); shot("battle")
  report("PASS: wild battle transition rendered")
  local Ui=require("src.core.game3.battle.ui")
  for f=1,4000 do
    if not Battle.isActive() then break end
    local st=Battle.getState()
    if st and Battle._phase=="command" and Ui._mode=="menu" and not Ui._pendingCommand then
      st.player.mon.moves[1]=33
      st.player.mon.pp=st.player.mon.pp or {}; st.player.mon.pp[1]=10
      st.enemy.mon.hp=1
      Ui._pendingCommand={kind="move",move=33,slot=1,user="player"}; Ui._mode="none"
      U.wait(1)
    elseif f%14==0 then U.tap(game,"a") else U.wait(1) end
  end
  assert(not Battle.isActive(), "battle did not finish")
  U.wait(90); shot("after-battle")
  assert(#game.mods.errors==0,table.concat(game.mods.errors,"\n"))
  report("PASS: battle completed; returned to field; no mod errors")
  report("COMPLETE")
  love.event.quit()
end

