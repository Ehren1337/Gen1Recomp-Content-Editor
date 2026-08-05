-- Shared overworld sprite helpers for GFX + MAPS Objects.

local State = require("State")

local SpriteUtil = {}

function SpriteUtil.invalidateIdCache(S)
  if not S then return end
  S._spriteIdList = nil
  S._spriteIdListKey = nil
end

-- Allocate SPRITE_MOD, SPRITE_MOD_2, … and stub project.sprites[id].
-- Returns id, rec.  Does not mark dirty (caller does).
function SpriteUtil.createNew(S, opts)
  opts = opts or {}
  if not S or not S.project then return nil, nil end
  State.ensureProjectFields(S.project)
  S.project.sprites = S.project.sprites or {}
  local proj = S.project.sprites
  local data = (S.data and S.data.sprites) or {}
  local nid = "SPRITE_MOD"
  local n = 1
  while proj[nid] or data[nid] do
    n = n + 1
    nid = "SPRITE_MOD_" .. n
  end
  local rec = {
    id = nid,
    image = opts.image or ("assets/" .. nid:lower() .. ".png"),
    frames = opts.frames or 1,
    walker = opts.walker and true or false,
    _isNew = true,
  }
  if opts.trueColor then rec.trueColor = true end
  if type(opts.paletteSource) == "string" and opts.paletteSource ~= "" then
    rec.paletteSource = opts.paletteSource
  end
  proj[nid] = rec
  SpriteUtil.invalidateIdCache(S)
  return nid, rec
end

function SpriteUtil.isOwned(S, id)
  return S and S.project and S.project.sprites and S.project.sprites[id] ~= nil
end

function SpriteUtil.ensureOwned(S, id)
  if not (S and id and S.project) then return nil end
  State.ensureProjectFields(S.project)
  S.project.sprites = S.project.sprites or {}
  if S.project.sprites[id] then return S.project.sprites[id] end
  local src = S.data and S.data.sprites and S.data.sprites[id]
  if type(src) ~= "table" then return nil end
  local copy = {}
  for k, v in pairs(src) do
    if type(v) ~= "function" then copy[k] = v end
  end
  copy.id = copy.id or id
  copy._isNew = false
  S.project.sprites[id] = copy
  SpriteUtil.invalidateIdCache(S)
  return copy
end

return SpriteUtil
