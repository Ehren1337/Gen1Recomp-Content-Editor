-- Update editor (Updater.lua): reading GitHub's release answer, versions,
-- notes. Plain LuaJIT, no LOVE, no network. Run from the repository root:
--   luajit tests/content-editor/test_updater.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local U = require("Updater")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

run("JSON: objects, arrays, strings, numbers, escapes", function()
  local v = assert(U.decodeJson('{"a":[1,2.5,-3e2,true,false,null],"b":"x\\"y\\n\\u00e9\\ud83d\\ude00","c":{}}'))
  assert(v.a[1] == 1 and v.a[2] == 2.5 and v.a[3] == -300 and v.a[4] == true and v.a[5] == false)
  assert(v.b == 'x"y\n\195\169\240\159\152\128', "escapes and UTF-8")
  assert(next(v.c) == nil)
  assert(U.decodeJson("{nope") == nil, "bad JSON is an error, not a crash")
end)

run("versions: newer, unknown, short", function()
  assert(U.newer("content-editor-v0.1.105", "content-editor-v0.1.104"))
  assert(not U.newer("content-editor-v0.1.104", "content-editor-v0.1.104"))
  assert(U.newer("content-editor-v0.1.110", "content-editor-v0.1.99"), "numbers, not text")
  assert(not U.newer("content-editor-v0.1.99", "content-editor-v0.1.110"))
  assert(U.newer("content-editor-v0.2.0", "content-editor-v0.1.200"))
  assert(U.newer("content-editor-v0.1.1", nil), "unknown version: offer it")
  assert(not U.newer("nightly", "content-editor-v0.1.1"), "a tag with no version isn't newer")
  assert(U.short("content-editor-v0.1.104") == "v0.1.104")
end)

run("release: the pack for this system, notes, errors", function()
  local body = [[{"tag_name":"content-editor-v0.1.105","name":"Content Editor v0.1.105",
    "html_url":"https://github.com/r/releases/tag/x","body":"## What's Changed\r\n* GAME PATCHES by @PashleyAUS in https://github.com/r/pull/14\r\n\r\n**Full Changelog**: https://github.com/r/compare/a...b",
    "assets":[{"name":"gen1recomp-content-editor-win64.zip","size":42000000,"browser_download_url":"https://dl/win.zip"},
      {"name":"gen1recomp-content-editor-linux64.tar.gz","size":41000000,"browser_download_url":"https://dl/linux.tar.gz"}]}]]
  local r = assert(U.parseRelease(body, "Windows"))
  assert(r.tag == "content-editor-v0.1.105" and r.url == "https://dl/win.zip" and r.size == 42000000)
  assert(#r.notes == 1 and r.notes[1] == "- GAME PATCHES", r.notes[1])
  local l = assert(U.parseRelease(body, "Linux"))
  assert(l.url == "https://dl/linux.tar.gz")
  local m = assert(U.parseRelease(body, "OS X"))
  assert(m.url == nil and m.asset == "gen1recomp-content-editor-macos-universal.tar.gz", "no pack: release page instead")
  local r2, err = U.parseRelease('{"message":"API rate limit exceeded"}', "Windows")
  assert(r2 == nil and err:find("rate limit"))
  assert(U.parseRelease("", "Windows") == nil)
end)

run("a source checkout is recognised", function()
  assert(U.isCheckout("."), "this repository")
  assert(not U.isCheckout("tools/content-editor"))
end)

run("source commits use immutable archives without release assets", function()
  local sha = string.rep("a", 40)
  local r = assert(U.parseCommit('{"sha":"' .. sha .. '","commit":{"message":"Fix maps"}}'))
  assert(r.tag == sha and r.url == "https://api.github.com/repos/" .. U.REPO .. "/tarball/" .. sha)
  assert(r.notes[1] == "Fix maps" and U.short(sha) == string.rep("a", 12))
  assert(not U.parseCommit('{"sha":"main; echo bad"}'))
  local bad, err = U.parseCommit('{"message":"API rate limit exceeded"}')
  assert(not bad and err:find("rate limit"))
  assert(not U.parseCommit("broken"))
end)

run("staged and installing updates cannot be replaced by checks", function()
  for _, step in ipairs({"staged", "installing", "unpacking", "downloading"}) do
    local st = { step = step }
    U.state = st
    U.check(true)
    assert(U.state == st)
  end
  U.state = { step = "idle" }
end)

run("installer allowlist excludes user data and mods", function()
  local source = require("SourceUpdate")
  for _, path in ipairs(source.installUnits()) do
    assert(not path:match("^mods") and not path:match("^love") and not path:find("generated"))
    assert(not path:find("%.%.") and path:sub(1, 1) ~= "/")
  end
end)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
