-- Turn a whole picture (a PNG map, 16x16 cells) into real FireRed blocks.
--
-- Each distinct 16x16 cell becomes a new block in the map's tileset, made of
-- your own tiles (GFX > Blocks lists and edits them like any other block).
-- The hardware rules apply: a tile draws in ONE 16-colour palette (colour 0
-- is see-through), and a tileset has 13 palettes whose game colours can't
-- change. So every tile is given the palette that shows it best: colours the
-- palette already has are reused, missing ones go into colour numbers no
-- game block uses (Gen3Blocks.addColours), and when a palette runs out the
-- nearest colour stands in. Colours are the game's 5-bit ones, as the GBA
-- shows them.
--
-- Plain Lua apart from reading the ImageData.
local Blocks = require("Gen3Blocks")

local M = {}

local HEX = "0123456789abcdef"
local NEAR = 9          -- (weighted) distance that counts as "the same colour"
local UNFIT = 9 * 31 * 31
local ROUNDS = 6        -- refinement passes after the first fit

local function to5(v) return math.floor(v * 31 / 255 + 0.5) end
local function key5(r, g, b) return r + g * 32 + b * 1024 end
local function split5(k) return k % 32, math.floor(k / 32) % 32, math.floor(k / 1024) % 32 end
local function to8(v5) return math.floor(v5 * 255 / 31 + 0.5) end

-- Squared 5-bit distance, green counted most (the eye is keenest there).
local function dist(a, b)
  local ar, ag, ab = split5(a)
  local br, bg, bb = split5(b)
  local dr, dg, db = ar - br, ag - bg, ab - bb
  return 3 * dr * dr + 4 * dg * dg + 2 * db * db
end

-- Cells ------------------------------------------------------------------------

-- ImageData -> cols, rows, cells[i] = { tiles = {t1..t4} } with each tile a
-- list of 64 colour keys (0 = see-through).
local function readCells(imageData, cols, rows)
  local w = imageData:getWidth()
  local bytes = imageData:getString()
  local cells = {}
  for cy = 0, rows - 1 do
    for cx = 0, cols - 1 do
      local tiles = {}
      for q = 0, 3 do
        local ox, oy = cx * 16 + (q % 2) * 8, cy * 16 + math.floor(q / 2) * 8
        local t = {}
        for y = 0, 7 do
          for x = 0, 7 do
            local o = ((oy + y) * w + ox + x) * 4
            local r, g, b, a = bytes:byte(o + 1, o + 4)
            -- +1 so key 0 (pure black) stays apart from see-through.
            t[y * 8 + x + 1] = a < 128 and 0 or key5(to5(r), to5(g), to5(b)) + 1
          end
        end
        tiles[q + 1] = t
      end
      cells[cy * cols + cx + 1] = tiles
    end
  end
  return cells
end

-- A tile with more than 15 colours: merge the closest pair (the rarer into
-- the commoner) until it fits. Returns colour -> colour.
local function reduce(counts)
  local list = {}
  for c, n in pairs(counts) do list[#list + 1] = { c = c, n = n } end
  local remap = {}
  while #list > 15 do
    local bi, bj, bd = 1, 2, math.huge
    for i = 1, #list do
      for j = i + 1, #list do
        local d = dist(list[i].c - 1, list[j].c - 1)
        if d < bd then bi, bj, bd = i, j, d end
      end
    end
    local keep, drop = list[bi], list[bj]
    if drop.n > keep.n then keep, drop = drop, keep end
    keep.n = keep.n + drop.n
    remap[drop.c] = keep.c
    for from, to in pairs(remap) do if to == drop.c then remap[from] = keep.c end end
    for i, e in ipairs(list) do if e == drop then table.remove(list, i) break end end
  end
  return remap
end

-- Palettes ---------------------------------------------------------------------

-- What each of the 13 palettes offers: colours already there (by key) and
-- colour numbers still free for new ones.
local function paletteState(S, pair)
  local pack = assert(Blocks.pack(S, pair))
  local state = {}
  for p = 0, Blocks.PALETTES - 1 do
    local free = Blocks.freeColours(S, pair, p)
    local isFree = {}
    for _, c in ipairs(free) do isFree[c] = true end
    local have, list = {}, {}
    for c = 1, 15 do
      local rgb = (pack.rgb[p] or {})[c]
      if rgb and not isFree[c] then
        local k = key5(to5(rgb[1]), to5(rgb[2]), to5(rgb[3])) + 1
        if not have[k] then have[k] = c; list[#list + 1] = k end
      end
    end
    local fixed = {}
    for i, k in ipairs(list) do fixed[i] = k end
    local slots = {}
    for i, c in ipairs(free) do slots[i] = c end
    state[p] = { have = have, list = list, free = free, added = {},
      fixed = fixed, slots = slots, isSlot = isFree }
  end
  return state
end

local function nearestIn(st, c)
  local best, bd = nil, math.huge
  for _, k in ipairs(st.list) do
    local d = dist(k - 1, c - 1)
    if d < bd then best, bd = k, d end
  end
  return best, bd
end

-- How well palette `st` shows a tile: error, new colours it would take.
local function score(st, colours)
  local err, need = 0, {}
  for _, e in ipairs(colours) do
    if not st.have[e.c] then
      local _, d = nearestIn(st, e.c)
      if d <= NEAR then err = err + d * e.w
      else need[#need + 1] = { c = e.c, w = e.w, d = d } end
    end
  end
  table.sort(need, function(a, b) return a.w > b.w end)
  local slots = #st.free
  for i, n in ipairs(need) do
    if i > slots then err = err + math.min(n.d, UNFIT) * n.w end
  end
  return err, math.min(#need, slots), need
end

-- Put a tile's colours into palette `st`; returns colour -> colour number,
-- and the largest shift (squared 5-bit distance) any pixel had to take.
local function commit(st, colours, need)
  local slots = #st.free
  for i, n in ipairs(need) do
    if i <= slots then
      local idx = table.remove(st.free, 1)
      st.have[n.c] = idx
      st.list[#st.list + 1] = n.c
      st.added[idx] = n.c
    end
  end
  local map, worst = {}, 0
  for _, e in ipairs(colours) do
    local idx = st.have[e.c]
    if not idx then
      local k, d = nearestIn(st, e.c)
      idx = k and st.have[k] or 1
      if d > NEAR and d > worst then worst = d end
    end
    map[e.c] = idx
  end
  return map, worst
end

-- Refinement ---------------------------------------------------------------------
--
-- The first fit hands out free colour numbers in one pass, so early tiles
-- can take colours the map hardly uses. Then, a few times over: move each
-- palette's added colours to the middle of the colours its tiles ask for
-- (weighted k-means; the game's colours stay put), and give every tile the
-- palette that now shows it best.

local function centres(st)
  local out = {}
  for _, k in ipairs(st.fixed) do out[#out + 1] = k end
  for _, idx in ipairs(st.slots) do
    if st.added[idx] then out[#out + 1] = st.added[idx] end
  end
  return out
end

local function nearestKey(list, c)
  local best, bd = nil, math.huge
  for _, k in ipairs(list) do
    local d = dist(k - 1, c - 1)
    if d < bd then best, bd = k, d end
  end
  return best, bd
end

local function tileCost(list, t)
  local err = 0
  for _, e in ipairs(t.colours) do
    local _, d = nearestKey(list, e.c)
    err = err + math.min(d, UNFIT) * e.w
  end
  return err
end

local function refine(state, tiles)
  local P = {}
  for p in pairs(state) do P[#P + 1] = p end
  table.sort(P)
  local function total()
    local err = 0
    for _, t in ipairs(tiles) do err = err + tileCost(centres(state[t.pal]), t) end
    return err
  end
  local best = total()
  local saved = {}
  local function save()
    for _, p in ipairs(P) do
      local a = {}
      for idx, k in pairs(state[p].added) do a[idx] = k end
      saved[p] = a
    end
    for _, t in ipairs(tiles) do t.bestPal = t.pal end
  end
  save()
  for _ = 1, ROUNDS do
    -- Each palette's added colours to the middle of what its tiles want.
    for _, p in ipairs(P) do
      local st = state[p]
      if #st.slots > 0 then
        local want = {}
        for _, t in ipairs(tiles) do
          if t.pal == p then
            for _, e in ipairs(t.colours) do want[e.c] = (want[e.c] or 0) + e.w end
          end
        end
        for _ = 1, 8 do
          local acc = {}
          local cs = {}
          for _, k in ipairs(st.fixed) do cs[#cs + 1] = { k = k } end
          for _, idx in ipairs(st.slots) do
            if st.added[idx] then cs[#cs + 1] = { k = st.added[idx], idx = idx } end
          end
          local worstC, worstE = nil, 0
          for c, w in pairs(want) do
            local bi, bd = nil, math.huge
            for i, ce in ipairs(cs) do
              local d = dist(ce.k - 1, c - 1)
              if d < bd then bi, bd = i, d end
            end
            local ce = bi and cs[bi]
            if ce and ce.idx then
              local a = acc[ce.idx] or { 0, 0, 0, 0 }
              local r, g, b = split5(c - 1)
              a[1], a[2], a[3], a[4] = a[1] + r * w, a[2] + g * w, a[3] + b * w, a[4] + w
              acc[ce.idx] = a
            end
            if bd * w > worstE then worstC, worstE = c, bd * w end
          end
          local moved = false
          for _, idx in ipairs(st.slots) do
            local a = acc[idx]
            local k
            if a and a[4] > 0 then
              k = key5(math.floor(a[1] / a[4] + 0.5), math.floor(a[2] / a[4] + 0.5),
                math.floor(a[3] / a[4] + 0.5)) + 1
            elseif worstC then
              -- an unused colour number: give it the worst-shown colour
              k, worstC = worstC, nil
            end
            if k ~= st.added[idx] then st.added[idx] = k; moved = true end
          end
          if not moved then break end
        end
      end
    end
    -- Every tile to its best palette now.
    local lists = {}
    for _, p in ipairs(P) do lists[p] = centres(state[p]) end
    for _, t in ipairs(tiles) do
      local bp, be = t.pal, tileCost(lists[t.pal], t)
      for _, p in ipairs(P) do
        if p ~= t.pal then
          local e = tileCost(lists[p], t)
          if e < be then bp, be = p, e end
        end
      end
      t.pal = bp
    end
    local now = total()
    if now < best then best = now; save() end
  end
  -- Keep the best round.
  for _, p in ipairs(P) do state[p].added = saved[p] end
  for _, t in ipairs(tiles) do t.pal = t.bestPal end
  return best
end

-- The plan -----------------------------------------------------------------------

local function flipped(px, h, v)
  local out = {}
  for y = 0, 7 do
    for x = 0, 7 do
      local sx, sy = h and 7 - x or x, v and 7 - y or y
      out[y * 8 + x + 1] = px:sub(sy * 8 + sx + 1, sy * 8 + sx + 1)
    end
  end
  return table.concat(out)
end

--- Work out the blocks for a picture without touching the project.
-- imageData: the picture at game size; cols x rows cells of 16x16.
-- Returns plan or nil, message. plan = { pair, cols, rows, cellBlock[i]
-- (index into plan.blocks), blocks = { {slots}... }, tiles = { px ... },
-- colours = { [pal] = { [index] = key } }, approx, worst }.
-- mask (optional): mask[i] false leaves cell i out (plan.cellBlock[i] nil).
function M.plan(S, pair, imageData, cols, rows, mask)
  if not Blocks.pack(S, pair) then
    return nil, "The game data has no blocks for " .. tostring(pair) .. " -- load FireRed on the Project tab"
  end
  local cells = readCells(imageData, cols, rows)
  -- Distinct tiles and how much of the map each covers.
  local tileOf, tiles = {}, {}
  for i, cell in ipairs(cells) do
    if mask and not mask[i] then cells[i] = false end
  end
  for _, cell in ipairs(cells) do
    if cell then for q = 1, 4 do
      local sig = table.concat(cell[q], ",")
      local t = tileOf[sig]
      if not t then
        t = { px = cell[q], uses = 0 }
        tileOf[sig] = t
        tiles[#tiles + 1] = t
      end
      t.uses = t.uses + 1
      cell[q] = t
    end end
  end
  for _, t in ipairs(tiles) do
    local counts = {}
    for _, c in ipairs(t.px) do if c ~= 0 then counts[c] = (counts[c] or 0) + 1 end end
    local remap = reduce(counts)
    local merged = {}
    for c, n in pairs(counts) do
      local to = remap[c] or c
      merged[to] = (merged[to] or 0) + n
    end
    t.remap, t.colours = remap, {}
    for c, n in pairs(merged) do t.colours[#t.colours + 1] = { c = c, w = n * t.uses } end
    table.sort(t.colours, function(a, b) return a.w > b.w end)
    t.weight = t.uses * 64
  end
  -- Hardest tiles first (most colours), then the ones the map shows most.
  local order = {}
  for i, t in ipairs(tiles) do order[i] = t end
  table.sort(order, function(a, b)
    if #a.colours ~= #b.colours then return #a.colours > #b.colours end
    return a.weight > b.weight
  end)
  local state = paletteState(S, pair)
  for _, t in ipairs(order) do
    local bestP, bestErr, bestNew, bestNeed
    for p = 0, Blocks.PALETTES - 1 do
      local err, new, need = score(state[p], t.colours)
      if not bestP or err < bestErr or (err == bestErr and new < bestNew) then
        bestP, bestErr, bestNew, bestNeed = p, err, new, need
      end
    end
    commit(state[bestP], t.colours, bestNeed)
    t.pal = bestP
  end
  local err = refine(state, tiles)
  -- Colour numbers: the game's own, then the added ones.
  local approx, worst, shifted, painted = 0, 0, 0, 0
  local final = {}
  for p, st in pairs(state) do
    local idxOf, list = {}, {}
    for k, idx in pairs(st.have) do
      if not st.isSlot[idx] then idxOf[k] = idx; list[#list + 1] = k end
    end
    for idx, k in pairs(st.added) do
      if not idxOf[k] then idxOf[k] = idx; list[#list + 1] = k end
    end
    final[p] = { idxOf = idxOf, list = list }
  end
  for _, t in ipairs(tiles) do
    local idxOf, list = final[t.pal].idxOf, final[t.pal].list
    local map, off = {}, false
    for _, e in ipairs(t.colours) do
      local k, d = nearestKey(list, e.c)
      map[e.c] = k and idxOf[k] or 1
      painted = painted + e.w
      if d > NEAR then
        off = true
        shifted = shifted + e.w
        if d > worst then worst = d end
      end
    end
    if off then approx = approx + 1 end
    local chars = {}
    for i, c in ipairs(t.px) do
      local idx = c == 0 and 0 or map[t.remap[c] or c]
      chars[i] = HEX:sub(idx + 1, idx + 1)
    end
    t.hex = table.concat(chars)
  end
  -- Your tiles: one per distinct picture, sharing flipped copies.
  local made, list = {}, {}
  for _, t in ipairs(tiles) do
    local hit
    for f = 0, 3 do
      local h, v = f % 2 == 1, f >= 2
      local n = made[t.pal .. ":" .. (f == 0 and t.hex or flipped(t.hex, h, v))]
      if n then hit = { n = n, h = h, v = v } break end
    end
    if not hit then
      list[#list + 1] = t.hex
      made[t.pal .. ":" .. t.hex] = #list
      hit = { n = #list, h = false, v = false }
    end
    t.ref = hit
  end
  -- Blocks: one per distinct cell.
  local blockOf, blocks, cellBlock = {}, {}, {}
  for i, cell in ipairs(cells) do
    if cell then
    local parts = {}
    for q = 1, 4 do
      local r = cell[q].ref
      parts[q] = r.n .. ":" .. cell[q].pal .. (r.h and "h" or "") .. (r.v and "v" or "")
    end
    local sig = table.concat(parts, "|")
    local b = blockOf[sig]
    if not b then
      local slots = {}
      for q = 1, 4 do
        local r = cell[q].ref
        slots[q] = { tile = r.n, pal = cell[q].pal, hflip = r.h, vflip = r.v }
        slots[q + 4] = { tile = false, pal = 0, hflip = false, vflip = false }
      end
      blocks[#blocks + 1] = { slots = slots }
      b = #blocks
      blockOf[sig] = b
    end
    cellBlock[i] = b
    end
  end
  local colours, added = {}, 0
  for p, st in pairs(state) do
    for idx, k in pairs(st.added) do
      colours[p] = colours[p] or {}
      colours[p][idx] = k - 1
      added = added + 1
    end
  end
  return { pair = pair, cols = cols, rows = rows, cellBlock = cellBlock, blocks = blocks,
    tiles = list, colours = colours, added = added, approx = approx, worst = worst, error = err,
    shifted = painted > 0 and shifted / painted or 0 }
end

-- Block ids nobody uses (game or project), from 640; a contiguous run when
-- one is long enough so GFX > Blocks can list the import as a range.
local function freeMids(S, pair, count)
  local pack = Blocks.pack(S, pair)
  local rows = Blocks.own(S.project, pair) or {}
  local free = {}
  for mid = Blocks.PRIMARY, Blocks.MAX_MID do
    if not pack.index[mid] and rows[tostring(mid)] == nil then free[#free + 1] = mid end
  end
  if #free < count then return nil, #free end
  for i = 1, #free - count + 1 do
    if free[i + count - 1] - free[i] == count - 1 then
      local run = {}
      for j = 0, count - 1 do run[j + 1] = free[i] + j end
      return run, #free
    end
  end
  local some = {}
  for j = 1, count do some[j] = free[j] end
  return some, #free
end

--- Can the tileset take the plan? Returns mids or nil, message.
function M.room(S, plan)
  local freeTiles = Blocks.MAX_CUSTOM + 1 - #Blocks.customTiles(S.project, plan.pair)
  if #plan.tiles > freeTiles then
    return nil, ("needs %d new tiles, %s has room for %d"):format(#plan.tiles, plan.pair, freeTiles)
  end
  local mids, have = freeMids(S, plan.pair, #plan.blocks)
  if not mids then
    return nil, ("needs %d new blocks, %s has room for %d"):format(#plan.blocks, plan.pair, have)
  end
  return mids
end

--- Write a plan into the project: colours, tiles, blocks, an entry in the
-- tileset's import list (GFX > Blocks can remove it), and the map's ground
-- layer. Returns the import record, or nil and a message.
-- keep: only the planned cells change (a map being turned into blocks in
-- place); otherwise the map is sized to the picture and its layers cleared.
function M.apply(S, plan, mapId, name, keep)
  local mids, err = M.room(S, plan)
  if not mids then return nil, err end
  local pair = plan.pair
  for p, row in pairs(plan.colours) do
    local idxs, list = {}, {}
    for idx in pairs(row) do idxs[#idxs + 1] = idx end
    table.sort(idxs)
    for i, idx in ipairs(idxs) do
      local r, g, b = split5(row[idx])
      list[i] = { to8(r), to8(g), to8(b) }
    end
    assert(Blocks.addColours(S, pair, p, list, idxs))
  end
  local tileNo = {}
  for i, px in ipairs(plan.tiles) do
    local n = assert(Blocks.newTile(S, pair, nil))
    Blocks.customTile(S.project, pair, n).px = px
    tileNo[i] = n
  end
  for b, blk in ipairs(plan.blocks) do
    local slots = {}
    for q = 1, 8 do
      local s = blk.slots[q]
      slots[q] = { tile = s.tile and tileNo[s.tile] or false, pal = s.pal, hflip = s.hflip, vflip = s.vflip }
    end
    Blocks.store(S, pair, mids[b], { slots = slots, layerType = "normal", behavior = 0, new = true })
  end
  local source = S.project.layeredMaps and S.project.layeredMaps[mapId]
  if source then
    local LayeredMap = require("LayeredMap")
    local ref = "@runtime:" .. pair
    if keep then
      local cells = source.layers[1].cells
      for i = 1, plan.cols * plan.rows do
        local b = plan.cellBlock[i]
        if b then cells[i] = { source = ref, tile = mids[b] } end
      end
    else
      local ok, resizeErr = LayeredMap.resizeMap(S.project, mapId, plan.cols, plan.rows)
      if not ok then return nil, resizeErr end
      local cells = {}
      for i = 1, plan.cols * plan.rows do
        local b = plan.cellBlock[i]
        cells[i] = b and { source = ref, tile = mids[b] } or nil
      end
      source.layers[1].cells = cells
      for li = 2, #source.layers do source.layers[li].cells = {} end
    end
    LayeredMap.internSourceCells(source)
  end
  local contiguous = mids[#mids] - mids[1] == #mids - 1
  local rec = { name = tostring(name or "map"), base = mids[1], count = #mids,
    w = plan.cols, h = plan.rows, frames = 1, map = mapId,
    mids = not contiguous and mids or nil }
  S.project.gen3Imports = S.project.gen3Imports or {}
  S.project.gen3Imports[pair] = S.project.gen3Imports[pair] or {}
  local list = S.project.gen3Imports[pair]
  list[#list + 1] = rec
  Blocks.clearImages(S)
  return rec
end

--- One status line about a finished conversion.
function M.describe(plan, cols, rows)
  local s = string.format("Map is %dx%d cells of FireRed blocks: %d blocks, %d tiles in your tileset %s%s (GFX > Blocks)",
    cols, rows, #plan.blocks, #plan.tiles, plan.pair,
    plan.base and (", a copy of " .. plan.base) or "")
  if plan.added > 0 then s = s .. string.format(", %d colours added", plan.added) end
  if plan.shifted >= 0.005 then
    s = s .. string.format("; %d%% of pixels show the nearest colour the palettes allow",
      math.floor(plan.shifted * 100 + 0.5))
  end
  return s
end

-- How many distinct 16x16 cells a picture has (= blocks it will need).
local function distinctCells(imageData, cols, rows, mask)
  local w = imageData:getWidth()
  local bytes = imageData:getString()
  local seen, n = {}, 0
  for cy = 0, rows - 1 do
    for cx = 0, cols - 1 do
      if not mask or mask[cy * cols + cx + 1] then
        local parts = {}
        for y = 0, 15 do
          local o = ((cy * 16 + y) * w + cx * 16) * 4
          parts[y + 1] = bytes:sub(o + 1, o + 64)
        end
        local sig = table.concat(parts)
        if not seen[sig] then seen[sig] = true; n = n + 1 end
      end
    end
  end
  return n
end

M.TRY = 6 -- tilesets tried besides the map's own

--- Tilesets worth trying for a map: its own first, then the ones with the
-- most free colour numbers (they show a new picture most faithfully) that
-- have enough free block ids.
function M.candidates(S, mapId, needBlocks)
  local out, seen = {}, {}
  local function roomy(pair)
    local pack = Blocks.pack(S, pair)
    if not pack then return nil end
    local rows = Blocks.own(S.project, pair) or {}
    local freeMids = 0
    for mid = Blocks.PRIMARY, Blocks.MAX_MID do
      if not pack.index[mid] and rows[tostring(mid)] == nil then freeMids = freeMids + 1 end
    end
    if needBlocks and freeMids < needBlocks then return nil end
    local colours = 0
    for p = 0, Blocks.PALETTES - 1 do colours = colours + #Blocks.freeColours(S, pair, p) end
    return colours
  end
  local source = S.project.layeredMaps and S.project.layeredMaps[mapId]
  local own = source and source.baseTileset
  if type(own) == "string" and roomy(own) then out[1] = own; seen[own] = true end
  local ranked = {}
  for _, pair in ipairs(Blocks.pairs(S)) do
    if not seen[pair] then
      seen[pair] = true
      local colours = roomy(pair)
      if colours then ranked[#ranked + 1] = { pair = pair, colours = colours } end
    end
  end
  table.sort(ranked, function(a, b)
    if a.colours ~= b.colours then return a.colours > b.colours end
    return a.pair < b.pair
  end)
  for i = 1, math.min(M.TRY, #ranked) do out[#out + 1] = ranked[i].pair end
  return out
end

--- Make a map's picture into blocks. The tileset that shows it best is
-- chosen from the game's, then COPIED (Gen3Blocks.newCopy) and the blocks
-- go into the copy, so the game's own tilesets stay exactly as they are.
-- Returns record, plan; or nil and a message.
function M.convert(S, mapId, imageData, cols, rows, name, mask)
  local best, reasons = nil, {}
  local need = distinctCells(imageData, cols, rows, mask)
  local list = M.candidates(S, mapId, need)
  if #list == 0 then
    return nil, ("No tileset has room for %d more blocks"):format(need)
  end
  for _, pair in ipairs(list) do
    local plan, err = M.plan(S, pair, imageData, cols, rows, mask)
    local ok, roomErr = false, err
    if plan then ok, roomErr = M.room(S, plan) end
    if ok then
      if not best or plan.error < best.error then best = plan end
    else
      reasons[#reasons + 1] = roomErr
    end
  end
  if not best then
    return nil, "No tileset has room for this map: " .. (reasons[1] or "no FireRed tilesets loaded")
  end
  local copy = Blocks.newCopy(S, best.pair, name)
  local plan, err = M.plan(S, copy, imageData, cols, rows, mask)
  local rec
  if plan then rec, err = M.apply(S, plan, mapId, name, mask ~= nil) end
  if not rec then
    S.project.gen3TilesetCopies[copy] = nil
    if not next(S.project.gen3TilesetCopies) then S.project.gen3TilesetCopies = nil end
    Blocks.syncCopies(S)
    return nil, err
  end
  plan.base = best.pair
  return rec, plan
end

--- The picture a pixel-sheet map shows (TilePixels source cells) at game
-- size, for maps made before they became blocks. Returns imageData, cols,
-- rows, sourceId or nil, message.
function M.pictureOf(S, mapId)
  local source = S.project.layeredMaps and S.project.layeredMaps[mapId]
  local layer = source and source.layers and source.layers[1]
  if not layer then return nil, "no map" end
  local sheetId
  for _, ref in pairs(layer.cells or {}) do
    local src = type(ref) == "table" and S.project.mapTileSources
      and S.project.mapTileSources[ref.source]
    if src and src.pixels then sheetId = ref.source break end
  end
  if not sheetId then return nil, "This map isn't made from a PNG" end
  local src = S.project.mapTileSources[sheetId]
  local sheet = require("TilePixels").imageData(src.pixels)
  local cols, rows = source.cellWidth, source.cellHeight
  local out = love.image.newImageData(cols * 16, rows * 16)
  local scols = src.columns or 1
  local mask = {}
  for i = 1, cols * rows do
    local ref = layer.cells[i]
    if type(ref) == "table" and ref.source == sheetId then
      local cx, cy = (i - 1) % cols, math.floor((i - 1) / cols)
      local t = ref.tile
      out:paste(sheet, cx * 16, cy * 16, (t % scols) * 16, math.floor(t / scols) * 16, 16, 16)
      mask[i] = true
    end
  end
  return out, cols, rows, sheetId, mask
end

--- Does this map's ground still show a PNG kept as a pixel sheet?
function M.hasSheet(S, source)
  local layer = source and source.layers and source.layers[1]
  local sources = S.project and S.project.mapTileSources
  if not (layer and sources) then return false end
  for _, ref in pairs(layer.cells or {}) do
    local src = type(ref) == "table" and sources[ref.source]
    if src and src.pixels then return true end
  end
  return false
end

return M
