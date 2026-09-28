-- Hidden guide edit mode for the editor's own authors. Turned on and off with
-- the arrow keys Up Up Down Left Right Up Down, typed within 5 seconds, and
-- remembered in the save folder (guide-edit-mode). While on, a GUIDE EDIT
-- tag shows next to the title and GUIDES gets Edit guides.

local M = {}

M.SEQUENCE = { "up", "up", "down", "left", "right", "up", "down" }
M.WINDOW = 5 -- seconds from the first key to the last
M.FILE = "guide-edit-mode"

local keys = {}
local cached

local function now()
  return love and love.timer and love.timer.getTime() or os.clock()
end

function M.enabled()
  if cached == nil then
    local fs = love and love.filesystem
    cached = fs and fs.getInfo and fs.getInfo(M.FILE) ~= nil or false
    -- its earlier name
    if fs and fs.getInfo and fs.getInfo("debug-mode") then
      fs.remove("debug-mode")
      if not cached then fs.write(M.FILE, "on\n"); cached = true end
    end
  end
  return cached
end

function M.set(on)
  cached = on == true
  if love and love.filesystem then
    if cached then love.filesystem.write(M.FILE, "on\n") else love.filesystem.remove(M.FILE) end
  end
  return cached
end

--- Feed every key press here. Returns true when the sequence was just
-- completed (guide edit mode flipped).
function M.keypressed(key)
  local t = now()
  local isArrow = key == "up" or key == "down" or key == "left" or key == "right"
  if not isArrow then keys = {} return false end
  keys[#keys + 1] = { key, t }
  while #keys > #M.SEQUENCE do table.remove(keys, 1) end
  if #keys < #M.SEQUENCE then return false end
  for i, want in ipairs(M.SEQUENCE) do
    if keys[i][1] ~= want then return false end
  end
  if t - keys[1][2] > M.WINDOW then return false end
  keys = {}
  M.set(not M.enabled())
  return true
end

return M
