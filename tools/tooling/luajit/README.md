# LuaJIT validator runtime

These binaries provide the Lua 5.1-compatible interpreter used by the Content
Editor's offline mod validator. They are not used to run the game.

- Version: LuaJIT 2.1.1785763465
- Project: https://luajit.org/
- Copyright: 2005-2026 Mike Pall
- License: MIT; see `LICENSE`

**Windows:** `luajit.exe` + `lua51.dll` in this folder.

**macOS:** Homebrew `luajit` (`/opt/homebrew/bin/luajit` or
`/usr/local/bin/luajit`). Optional `macos-universal/luajit` in this folder.
The editor also runs `brew install luajit` when Homebrew is present.

**Linux x86_64:** optional `linux-x64/luajit` (and `libluajit-5.1.so.2` beside
it if the binary is dynamically linked). The editor also uses `/usr/bin/luajit`
and PATH, then a passwordless `apt`/`dnf`/`pacman` install.

The editor prefers a bundled copy, then `MODKIT_LUAJIT`, then the system
install. It does not download LuaJIT into the LÖVE save folder.
