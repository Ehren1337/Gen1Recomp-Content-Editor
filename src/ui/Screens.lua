-- Screen id -> factory resolution.  The screens registry (Data.screens)
-- wins; engine screens are the require fallback, so a mod-free boot
-- resolves every id to the exact module it required before.  One cache,
-- dropped with the rest of the asset caches on dev-mode hot reload.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Screens = {}

-- ids whose builtin module is not under src/ui/
local BUILTIN = {
  ManagerState = "src.mods.ManagerState",
}

local cache = {}

local function builtinFor(id)
  local path = BUILTIN[id]
  if not path then
    -- Gold ids are "Gen2TitleState" → src.ui.gen2.TitleState (and friends).
    if type(id) == "string" and id:sub(1, 4) == "Gen2" then
      path = "src.ui.gen2." .. id:sub(5)
    else
      path = "src.ui." .. id
    end
  end
  return require(path)
end

local function resolve(game, id)
  local hit = cache[id]
  if hit then return hit end
  local screens = game and game.data and game.data.screens
  local record = screens and screens[id]
  local factory
  if record then
    -- registry record: { new = fn } or a bare function (05-registry-system)
    factory = (type(record) == "function") and { new = record } or record
    factory.__modOwned = true
  else
    factory = builtinFor(id)
  end
  cache[id] = factory
  return factory
end

function Screens.get(game, id)
  return resolve(game, id)
end

function Screens.push(game, id, ...)
  local factory = resolve(game, id)
  local inst
  if factory.__modOwned then
    -- a broken mod screen degrades to the builtin, never a dead end
    local ok, result = pcall(factory.new, game, ...)
    if ok and result then
      inst = result
    else
      Logger.error("mod screen '%s' failed: %s -- using builtin",
                   id, tostring(result))
      cache[id] = nil
      inst = builtinFor(id).new(game, ...)
    end
  else
    inst = factory.new(game, ...)
  end
  inst.screenId = inst.screenId or id
  game.stack:push(inst)
  return inst
end

function Screens.invalidate()
  cache = {}
end

Assets.register(Screens.invalidate)

return Screens
