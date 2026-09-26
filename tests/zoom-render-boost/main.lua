-- Headless LOVE test using real ImageData and the installed runtime's original
-- animation implementation. Pass workspace and runtime paths after this folder.
function love.load(args)
  local workspace, runtime = assert(args[1]), assert(args[2])
  local reportPath = workspace .. "/tests/zoom-render-boost/results.txt"
  local lines = {}
  local function report(s) lines[#lines + 1] = s end
  local ok, err = pcall(function()
    package.loaded["src.import.gba.extract_island1"] = { CACHE_ROOT = "unused" }
    package.loaded["src.import.gba.versions"] = { NATIVE_RENDER = true }
    local anim = assert(loadfile(runtime .. "/src/core/game3/tileset_anim.lua"))()
    local original = anim._applyKind
    local callback, ready
    package.loaded["src.core.game3.tileset_anim"] = anim
    package.loaded["src.mods.Runtime"] = { call = function(_, base, ...)
      if callback then return callback(base, ...) end
      return base(...)
    end }
    local warnings = 0
    local mod = {
      read = function(_, name)
        local file = assert(io.open(workspace .. "/mods/zoom_render_boost/" .. name, "r"))
        local source = file:read("*a"); file:close(); return source
      end,
      hooks = { wrap = function(_, _, fn) callback = fn end },
      events = { on = function(_, _, fn) ready = fn end },
      log = { warn = function() warnings = warnings + 1 end },
    }
    assert(loadfile(workspace .. "/mods/zoom_render_boost/main.lua"))()(mod)
    ready()
    local dispatch = anim._applyKind
    ready()
    assert(anim._applyKind == dispatch, "duplicate ready must not stack wrappers")

    local newData = love.image.newImageData
    local allocations = 0
    love.image.newImageData = function(...)
      allocations = allocations + 1
      return newData(...)
    end
    local function entry()
      local data = newData(256, 256, "rgba8")
      data:mapPixel(function(x, y) return x / 255, y / 255, 0.3, 1 end)
      local gpu = newData(256, 256, "rgba8", data:getString())
      local texture = { bytes = 0, uploads = 0, gpu = gpu }
      function texture:replacePixels(source, slice, mip, x, y)
        if self.failPartial and x ~= nil then error("partial upload unsupported") end
        assert(slice == nil or slice == 1)
        assert(mip == nil or mip == 1)
        self.bytes = self.bytes + source:getWidth() * source:getHeight() * 4
        self.uploads = self.uploads + 1
        gpu:paste(source, x or 0, y or 0)
      end
      local banks = {}
      for ki, kind in ipairs({"water", "sand", "flower"}) do
        local pieces = {}
        for frame = 0, 7 do
          for i = 1, 3 do
            pieces[#pieces + 1] = string.rep(string.char(frame * 30, i * 60, ki * 70, 255), 256)
          end
        end
        banks[kind] = { frames = 8, mids = {ki * 10, ki * 10 + 1, ki * 10 + 2}, rgba = table.concat(pieces) }
      end
      return {frames = {}, banks = banks, atlas = {
        cols = 16, imageData = data, image = texture,
        midToSlot = {[10]=0, [11]=1, [12]=17, [20]=34, [21]=35, [22]=50,
          [30]=70, [31]=71, [32]=86},
      }}
    end
    local base, fast = entry(), entry()
    local baseAlloc, fastAlloc = 0, 0
    for tick = 0, 639 do
      for _, kind in ipairs({"water", "sand", "flower"}) do
        local frame = math.floor(tick / (kind == "sand" and 8 or 16)) % 8
        allocations = 0
        original(base, kind, frame)
        baseAlloc = baseAlloc + allocations
        allocations = 0
        dispatch(fast, kind, frame)
        fastAlloc = fastAlloc + allocations
        assert(base.atlas.imageData:getString() == fast.atlas.imageData:getString(), "CPU atlas differs")
        assert(base.atlas.image.gpu:getString() == fast.atlas.image.gpu:getString(), "uploaded pixels differ")
      end
    end
    assert(warnings == 0, "optimization unexpectedly fell back")
    assert(fastAlloc < baseAlloc, "allocation reduction missing")
    assert(fast.atlas.image.bytes < base.atlas.image.bytes, "upload reduction missing")
    assert(fast.atlas.image.uploads == base.atlas.image.uploads, "extra GPU uploads")
    report(string.format("PASS: 640 ticks, 3 animation kinds, CPU/GPU pixels identical after every call. Allocations %d -> %d; uploaded bytes %d -> %d; %d uploads each.", baseAlloc, fastAlloc, base.atlas.image.bytes, fast.atlas.image.bytes, fast.atlas.image.uploads))
    -- New atlas after invalidation must not reuse another atlas's static rows.
    local freshBase, freshFast = entry(), entry()
    freshBase.atlas.imageData:setPixel(100, 0, 1, 0, 1, 1)
    freshFast.atlas.imageData:setPixel(100, 0, 1, 0, 1, 1)
    original(freshBase, "water", 3)
    dispatch(freshFast, "water", 3)
    assert(freshBase.atlas.image.gpu:getString() == freshFast.atlas.image.gpu:getString())
    -- Partial upload failure must let original repair the entire texture.
    freshFast.atlas.image.failPartial = true
    original(freshBase, "water", 4)
    dispatch(freshFast, "water", 4)
    assert(warnings == 1 and freshFast.frames.water == 4)
    assert(freshBase.atlas.image.gpu:getString() == freshFast.atlas.image.gpu:getString())
    dispatch(freshFast, "water", 5)
    assert(warnings == 1, "failed backend repeatedly retried")
    -- Removing the mod's hook restores vanilla behavior through the dispatch.
    callback = nil
    dispatch(freshFast, "water", 6)
    assert(freshFast.frames.water == 6)
    report("PASS: fresh atlas, repeated game.ready, backend fallback, and hook removal.")
    assert(loadfile(workspace .. "/tests/zoom-render-boost/world.lua"))()(workspace, runtime, report)
    assert(loadfile(workspace .. "/tests/zoom-render-boost/integration.lua"))()(workspace, report)
    assert(loadfile(workspace .. "/tests/zoom-render-boost/layers.lua"))()(workspace, report)
  end)
  if not ok then report("FAIL: " .. tostring(err)) end
  local out = assert(io.open(reportPath, "w"))
  out:write(table.concat(lines, "\n") .. "\n")
  out:close()
  love.event.quit(ok and 0 or 1)
end
