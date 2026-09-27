-- Work out the size a PNG map really is. Screenshots and shared maps are
-- often blown up (2x, 3x ...), so every game pixel is a k x k block. In such
-- an image colour changes only happen on block edges; in a native image they
-- land anywhere. Count where the changes fall to find k and the block phase.
-- Tolerant of JPEG noise: small differences are not counted as changes.
local M = {}

local TOLERANCE = 48      -- 0..255 per channel; smaller changes are noise
local MIN_EDGES = 200     -- fewer changes than this: too flat to tell
local THRESHOLD = 0.9     -- share of changes that must sit on block edges
local MAX_SCALE = 8
local MAX_LINES = 400     -- rows / columns sampled each way on big images

local function differs(s, a, b)
  for i = 0, 3 do
    local d = s:byte(a + i) - s:byte(b + i)
    if d > TOLERANCE or d < -TOLERANCE then return true end
  end
  return false
end

-- Positions p (edge between pixel p-1 and p) of colour changes along one
-- axis, over a sample of lines.
local function edges(bytes, w, h, horizontal)
  local out = {}
  local lines, length = horizontal and h or w, horizontal and w or h
  local step = math.max(1, math.floor(lines / MAX_LINES))
  for line = 0, lines - 1, step do
    for p = 1, length - 1 do
      local x1, y1, x0, y0
      if horizontal then x1, y1, x0, y0 = p, line, p - 1, line
      else x1, y1, x0, y0 = line, p, line, p - 1 end
      if differs(bytes, (y1 * w + x1) * 4 + 1, (y0 * w + x0) * 4 + 1) then
        out[#out + 1] = p
      end
    end
  end
  return out
end

-- Best phase for scale k: share of changes at positions == phase (mod k).
local function fit(list, k)
  local counts = {}
  for _, p in ipairs(list) do
    local r = p % k
    counts[r] = (counts[r] or 0) + 1
  end
  local phase, best = 0, 0
  for r = 0, k - 1 do
    if (counts[r] or 0) > best then phase, best = r, counts[r] end
  end
  return best / math.max(1, #list), phase
end

-- imageData -> scale, phaseX, phaseY (a pixel block starts at x == phaseX mod scale).
function M.detect(imageData)
  local w, h = imageData:getDimensions()
  local bytes = imageData:getString()
  local across, down = edges(bytes, w, h, true), edges(bytes, w, h, false)
  if #across + #down < MIN_EDGES then return 1, 0, 0 end
  for k = MAX_SCALE, 2, -1 do
    if w >= k * 16 and h >= k * 16 then
      local fx, px = fit(across, k)
      local fy, py = fit(down, k)
      if fx >= THRESHOLD and fy >= THRESHOLD then return k, px, py end
    end
  end
  return 1, 0, 0
end

-- Shrink by `scale`, averaging each block (so JPEG noise evens out).
function M.shrink(imageData, scale, phaseX, phaseY)
  if not scale or scale <= 1 then return imageData end
  phaseX, phaseY = phaseX or 0, phaseY or 0
  local w, h = imageData:getDimensions()
  local nw = math.floor((w - phaseX) / scale)
  local nh = math.floor((h - phaseY) / scale)
  local bytes = imageData:getString()
  local out = love.image.newImageData(nw, nh)
  local n = scale * scale
  for y = 0, nh - 1 do
    for x = 0, nw - 1 do
      local r, g, b, a = 0, 0, 0, 0
      for by = 0, scale - 1 do
        local o = ((phaseY + y * scale + by) * w + phaseX + x * scale) * 4
        for bx = 0, scale - 1 do
          local i = o + bx * 4
          local pr, pg, pb, pa = bytes:byte(i + 1, i + 4)
          r, g, b, a = r + pr, g + pg, b + pb, a + pa
        end
      end
      out:setPixel(x, y, r / n / 255, g / n / 255, b / n / 255, a / n / 255)
    end
  end
  return out
end

-- Everything the map import needs: scale, phase, and size in 16x16 cells.
function M.measure(imageData)
  local scale, px, py = M.detect(imageData)
  local w, h = imageData:getDimensions()
  local gw = math.floor((w - px) / scale)
  local gh = math.floor((h - py) / scale)
  return {
    scale = scale, phaseX = px, phaseY = py,
    pixelWidth = gw, pixelHeight = gh,
    cols = math.floor(gw / 16), rows = math.floor(gh / 16),
  }
end

return M
