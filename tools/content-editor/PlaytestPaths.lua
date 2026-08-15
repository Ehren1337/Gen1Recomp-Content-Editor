local PlaytestPaths = {}

local function separator()
  return package.config:sub(1, 1)
end

function PlaytestPaths.absoluteFromRoot(path, root)
  path = tostring(path or "")
  local windowsAbsolute = path:match("^%a:[/\\]") ~= nil
    or path:match("^[/\\][/\\]") ~= nil
  local unixAbsolute = path:sub(1, 1) == "/"
  if windowsAbsolute or unixAbsolute then return path end
  return root .. separator() .. path
end

function PlaytestPaths.same(a, b)
  local sep = separator()
  local function normalize(path)
    path = tostring(path or ""):gsub("[/\\]+", sep):gsub("[/\\]+$", "")
    if sep == "\\" then path = path:lower() end
    return path
  end
  return normalize(a) == normalize(b)
end

return PlaytestPaths
