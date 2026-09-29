return function(game)
  local U = require("tests.drivers.util")
  local root = os.getenv("EDITOR_TEST_ROOT") .. "/tests/content-editor/emerald-playtest/"
  local function report(s)
    local f=assert(io.open(root.."results.log", "a")); f:write(s,"\n"); f:close()
  end
  local function shot(name)
    game.capturePath=root..name..".png"
    for i=1,300 do U.wait(1); if not game.capturePath then break end end
    assert(not game.capturePath, "capture timed out")
  end
  U.wait(5)
  assert(game.mods.order[1]=="emerald_e2e", "mod not loaded")
  assert(#game.mods.errors==0, table.concat(game.mods.errors,"\n"))
  report("PASS: emerald_e2e loaded without errors")
  local hp=require("src.mods.Gen3Compat").pokemonRecord("TREECKO").baseStats.hp
  assert(hp==77, "TREECKO hp is "..tostring(hp))
  report("PASS: TREECKO base HP is 77 in game")
  game:_handleBootAction({action="new_game", name="E2E"})
  U.wait(180)
  assert(game.phase=="field", "field failed")
  shot("new-game")
  report("PASS: new game reached the field")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  Map.load(nil, game, "EM_LITTLEROOT_TOWN", {x=10,y=10,facing="down"})
  U.wait(90)
  shot("littleroot")
  local x,y=Player.px,Player.py
  U.hold(game,"down",30); U.wait(30)
  assert(Player.px~=x or Player.py~=y, "player did not walk")
  report("PASS: modded Littleroot Town loaded and player walked")
  assert(#game.mods.errors==0,table.concat(game.mods.errors,"\n"))
  report("COMPLETE")
  love.event.quit()
end
