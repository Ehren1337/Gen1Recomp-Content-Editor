-- Gen 1 / Gen 2 UI images marked true color keep their own colors instead
-- of the Game Boy palette, under the same rule the runtime uses for
-- trueColor Pokemon art (PaletteFX.honorsTrueColor). Each image remembers
-- the path it was loaded from; drawing one whose path is marked skips the
-- palette shader and reports its canvas rect so Gen 1's SGB pass re-blits
-- it unshaded. Shared by the editor preview and exported mods (main.lua).
local M = {}
local sets = {}
local sources = setmetatable({}, { __mode = "k" })
local onRect

local function normal(path) return (path:gsub("\\", "/")) end

local function flagged(path)
  for _, set in pairs(sets) do if set[path] then return true end end
  return false
end

--- Record `path` as the source of `image` (loaders that bypass newImage).
function M.tag(image, path)
  if image and type(path) == "string" then sources[image] = normal(path) end
  return image
end

--- `owner`'s marked paths (a mod path, or "editor"); replaces its old list.
function M.setPaths(owner, list)
  local set = {}
  for _, path in ipairs(list or {}) do set[normal(path)] = true end
  sets[owner] = next(set) and set or nil
end

-- Canvas-space bounds of love.graphics.draw(image, [quad,] ...).
local function bounds(image, a, ...)
  local w, h, args
  if type(a) == "userdata" and a.typeOf and a:typeOf("Quad") then
    local _, _, qw, qh = a:getViewport()
    w, h, args = qw, qh, { ... }
  else
    w, h = image:getDimensions()
    args = { a, ... }
  end
  local t = args[1]
  if type(t) ~= "userdata" then
    local sx = args[4] or 1
    t = love.math.newTransform(args[1] or 0, args[2] or 0, args[3] or 0, sx, args[5] or sx,
      args[6] or 0, args[7] or 0, args[8] or 0, args[9] or 0)
  end
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, c in ipairs({ { 0, 0 }, { w, 0 }, { 0, h }, { w, h } }) do
    local x, y = love.graphics.transformPoint(t:transformPoint(c[1], c[2]))
    x1, y1 = math.min(x1, x), math.min(y1, y)
    x2, y2 = math.max(x2, x), math.max(y2, y)
  end
  return x1, y1, x2 - x1, y2 - y1
end

--- Wrap love.graphics once; `rect(x, y, w, h)` receives each tagged draw.
function M.install(rect)
  onRect = rect
  if M.installed then return end
  M.installed = true
  local P = require("src.render.PaletteFX")
  local newImage, draw = love.graphics.newImage, love.graphics.draw
  love.graphics.newImage = function(source, ...)
    local image = newImage(source, ...)
    if type(source) == "string" then sources[image] = normal(source) end
    return image
  end
  love.graphics.draw = function(image, ...)
    local path = sources[image]
    if not (path and flagged(path) and P.honorsTrueColor()) then return draw(image, ...) end
    local shader = love.graphics.getShader()
    love.graphics.setShader()
    draw(image, ...)
    love.graphics.setShader(shader)
    if onRect then onRect(bounds(image, ...)) end
  end
end

--- In game: report rects to PaletteFX. Game:draw marks classic states with
--- setMarkOffset for a translate transformPoint already includes.
function M.installRuntime()
  local P = require("src.render.PaletteFX")
  if not M.offsetWrapped then
    M.offsetWrapped = true
    local setMarkOffset = P.setMarkOffset
    P.setMarkOffset = function(dx)
      M.offset = tonumber(dx) or 0
      return setMarkOffset(dx)
    end
  end
  M.install(function(x, y, w, h) P.markTrueColor(x - (M.offset or 0), y, w, h) end)
end

return M
