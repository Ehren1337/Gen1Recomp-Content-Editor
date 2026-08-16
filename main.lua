-- Source-checkout entry. Mounts the pinned or linked Gen1Recomp runtime,
-- then starts the content editor.
local chunk = assert(love.filesystem.load("tools/content-editor/runtime/main.lua"))
chunk()
