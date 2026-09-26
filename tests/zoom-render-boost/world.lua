return function(workspace, runtime, report)
  package.loaded["src.core.game3.map_ids"] = {}
  package.loaded["src.core.game3.connections"] = {}
  local Map = assert(loadfile(runtime .. "/src/core/game3/map.lua"))()
  local lookupFor = assert(loadfile(workspace .. "/mods/zoom_render_boost/world_lookup.lua"))()
  local function def(id, w, h)
    return {pair = "pair" .. id, midLayout = {width = w, height = h,
      midAt = function(self, x, y)
        if self.empty then return nil end
        return id * 100000 + y * 100 + x + (self.edit or 0)
      end}}
  end
  local root = def(1, 20, 18)
  Map.neighborList = {
    {dir="north", offset=-4, def=def(2, 30, 15)},
    {dir="north", offset=6, def=def(3, 20, 16)},
    {dir="south", offset=-10, def=def(4, 40, 20)},
    {dir="west", offset=-10, def=def(5, 20, 40)},
    {dir="east", offset=-12, def=def(6, 20, 40)},
  }
  for y = -4, 4 do
    for x = -4, 4 do
      Map.world[#Map.world+1] = {def=def(10+#Map.world, 24, 24), ox=x*24, oy=y*24}
    end
  end
  local fast = lookupFor(Map)
  local queries = 0
  local function compare()
    for y = -110, 115 do
      for x = -110, 115 do
        local a,b,c = Map.worldMidAt(x,y,root)
        local d,e,f = fast(x,y,root)
        assert(a==d and b==e and c==f, string.format("lookup mismatch at %d,%d",x,y))
        queries = queries + 1
      end
    end
  end
  compare()
  root.midLayout.empty = true
  Map.neighborList[2].def.midLayout.empty = true
  Map.world[1].def.midLayout.empty = true
  compare()
  root.midLayout.empty = nil
  root.midLayout.edit = 900
  compare()
  Map.world = {{def=def(99, 20, 20), ox=40, oy=40}}
  Map.neighborList = {}
  fast = lookupFor(Map)
  compare()
  report(string.format("PASS: %d lookup comparisons, negative coordinates, overlapping neighbors, nil tiles, live tile edits, world replacement and void flags.",queries))

  -- Rebuild the spatial cache each draw, as the mod does. Include that cost.
  Map.world = {}
  for y = -4, 4 do
    for x = -4, 4 do
      Map.world[#Map.world+1] = {def=def(10+#Map.world,24,24), ox=x*24, oy=y*24}
    end
  end
  local function bench(optimized)
    collectgarbage("collect")
    local start, checksum = love.timer.getTime(), 0
    for frame=1,100 do
      local query = optimized and lookupFor(Map) or Map.worldMidAt
      for y=-40,39 do
        for x=-60,59 do
          checksum = checksum + query(x,y,root)
        end
      end
    end
    return (love.timer.getTime()-start)*1000, checksum
  end
  bench(false); bench(true)
  local vanilla, a = bench(false)
  local optimized, b = bench(true)
  assert(a==b)
  report(string.format("BENCHMARK: 100 moving views, 960000 queries, 81 connected maps: original %.1f ms, spatial %.1f ms (%.2fx). Synthetic CPU lookup workload only.",vanilla,optimized,vanilla/optimized))
end
