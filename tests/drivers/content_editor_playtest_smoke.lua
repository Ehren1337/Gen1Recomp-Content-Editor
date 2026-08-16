return function(game)
  assert(game, "playtest did not create a game instance")
  assert(game.modStatus, "playtest did not initialize the mod loader")

  local expected = assert(os.getenv("POKEPORT_EXPECT_MOD"),
    "POKEPORT_EXPECT_MOD is required")
  local loaded = game.modStatus.loaded or {}
  assert(#loaded == 1, string.format(
    "expected exactly one loaded mod (%s), got %d", expected, #loaded))
  assert(loaded[1].id == expected, string.format(
    "expected loaded mod %s, got %s", expected, tostring(loaded[1].id)))

  local exits = 0
  game.stack:push({ exit = function() exits = exits + 1 end })
  game.stack:push({ exit = function() exits = exits + 1 end })
  game.stack:clear()
  assert(exits == 2, "StateStack.clear skipped an exit lifecycle hook")
  assert(game.stack:top() == nil, "StateStack.clear left a state behind")

  local output = assert(os.getenv("POKEPORT_TEST_OUTPUT"),
    "POKEPORT_TEST_OUTPUT is required")
  local file = assert(io.open(output, "wb"))
  file:write(string.format("version=%s\nmod=%s\nloaded=%d\nstack_clear=ok\n",
    tostring(require("src.core.GameVersion").get()), expected, #loaded))
  file:close()
end
