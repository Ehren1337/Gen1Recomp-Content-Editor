-- Standalone Content Editor entry point. The surrounding source tree is
-- assembled from the pinned Gen1Recomp checkout; only tools/ is editor-owned.
local EditorApp

local function mountPinnedRuntime()
  if not require("tools.content-editor.RuntimeMount").mount() then
    error("Could not find Gen1Recomp.\n\n"
      .. "Use a bundled runtime/gen1recomp folder, set POKEPORT_RECOMP, "
      .. "or choose your Gen1Recomp checkout when asked.\n"
      .. "That folder must contain src/core/GameVersion.lua.")
  end
end

local function addEditorRequirePath()
  local paths = table.concat({
    "tools/content-editor/?.lua",
    "tools/content-editor/panels/?.lua",
    "tools/save-editor/?.lua",
    "tools/save-editor/panels/?.lua",
  }, ";") .. ";"
  if love.filesystem.setRequirePath and love.filesystem.getRequirePath then
    love.filesystem.setRequirePath(paths .. love.filesystem.getRequirePath())
  else
    package.path = love.filesystem.getSource() .. "/" .. paths .. package.path
  end
end

local function argumentAfter(args, wanted)
  for i, value in ipairs(args or {}) do
    if value == wanted then return args[i + 1] end
  end
end

function love.load(args)
  love.graphics.setDefaultFilter("nearest", "nearest")
  mountPinnedRuntime()
  addEditorRequirePath()
  local version = os.getenv("POKEPORT_VERSION") or "red"
  require("src.core.GameVersion").set(version)
  require("src.import.CacheFs").mountVersion(version)
  EditorApp = require("App")
  EditorApp.load(argumentAfter(args, "--mod"), { version = version })
end

function love.update(dt)
  return EditorApp.update(dt)
end
function love.draw() return EditorApp.draw() end
function love.keypressed(key) return EditorApp.keypressed(key) end
function love.textinput(value) return EditorApp.textinput(value) end
function love.mousepressed(x, y, button)
  return EditorApp.mousepressed(x, y, button)
end
function love.mousereleased(x, y, button)
  return EditorApp.mousereleased(x, y, button)
end
function love.wheelmoved(x, y) return EditorApp.wheelmoved(x, y) end
function love.filedropped(file) return EditorApp.filedropped(file) end
function love.quit() return EditorApp.quit() end
