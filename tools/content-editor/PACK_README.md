# Gen1Recomp Content Editor

Author mods for Gen1Recomp (maps, Pokémon, trainers, dialog, and more).

This pack ships **without** a ROM cache (`data/generated`). That keeps it
legal to redistribute. On first launch you get stub fixture data until you
link a Gen1Recomp install or import your own ROM.

## Run

**Windows:** unzip anywhere → double-click `ContentEditor.bat`.

**macOS:**

```sh
tar -xzf gen1recomp-content-editor-macos-universal.tar.gz
cd gen1recomp-content-editor-macos-universal
chmod +x ContentEditor.command
./ContentEditor.command
```

Do not open `love/love.app` directly — that yields `No code to run`.
The pack script writes `ContentEditor.command` with LF endings; if an older
Windows-built pack still has `^M` in the shebang, run
`sed -i '' 's/\r$//' ContentEditor.command` once.

**Linux (x86_64):**

```sh
tar -xzf gen1recomp-content-editor-linux64.tar.gz
cd gen1recomp-content-editor-linux64
chmod +x ContentEditor.sh love/love-11.5-x86_64.AppImage
./ContentEditor.sh
```

File dialogs need `zenity`, `kdialog`, or `yad` (e.g. `sudo apt install zenity`).
Without one, Link Recomp / Import ROM opens an in-app path paste box instead.

Then on **Project** → **GAME DATA**:

- **Link Recomp** — pick your Gen1Recomp folder (must already have imported a ROM), or
- **Import ROM** — choose a clean US Red/Blue/Yellow `.gb` or Gold `.gbc` (cache goes to the LÖVE save directory, not this pack), or
- **Use fixtures** — keep stub data for light authoring.

**Project** → Open `mods/New_PokemonTest`, or **Create** a new mod. Use
**Maps** to select an existing map or create a custom map, then **Save**.

Save writes editable layers to `mods/<id>/editor_project.lua`, the runtime
records to `main.lua`, and a transform recipe that derives flattened map art
from each player's own imported cache on first load.

## Maps workspace

The former Map Builder and Maps screens are now one workspace:

- Select a map in the left column to preview it without changing the mod.
- Click **Edit this map** to make an editable layered copy, or use
  **Create new map** to start from a size preset and visual style.
- Use **Paint map** for terrain and passage, and **Add events** for NPCs, signs,
  trainers, fixed wild encounters, and dragging existing markers.
- Use **Map setup**, **Layers**, **Tile animation**, and **Doors & exits** for
  settings. **World View** shows connected neighbors.
- Use **More tools**, **More settings**, **More options**, and **More actions**
  when you need specialized or destructive commands.

Selecting, scrolling, keyboard navigation, and World View never convert a
source-game map. Save still emits normal Gen1Recomp map blocks and records for
maps explicitly added to the project.

## Tile animations

1. In **Maps**, open **More options** and add a 16×16-tile source with
   **+ New PNG**.
2. Select a tile and click **Animate tile**.
3. Choose an initial frame count in **Tile animation**.
4. Set each frame's tile and duration in milliseconds; reorder, add, or delete
   frames as needed. Tiles marked **A** are animated starting tiles.
5. Save and Playtest. The first game load builds derived frame images in the
   player's save cache.

Animation playback requires a Gen1Recomp build that supports generated
`tileset.animatedTiles` frame records. If the map loads but its animated tiles
remain static, update/rebuild the linked Gen1Recomp runtime before Playtest.

## Validate / Playtest

On **Project**, under Overview:

- **Validate** runs `modkit.py validate`. Needs Python on PATH, plus LuaJIT.
- Without an imported game-data cache, Validate still checks structure, Lua,
  permissions, and packaging, but skips vanilla cross-reference rules MK102 and
  MK103 instead of reporting normal game IDs as errors.
  If LuaJIT is missing: **Windows** tries `winget install DEVCOM.LuaJIT`
  (Program Files — not AppData; Defender flags AppData LuaJIT as SuspLua);
  **Linux** tries a passwordless `apt`/`dnf`/`pacman` install, else install
  manually (`sudo apt install luajit`) or set `MODKIT_LUAJIT`.
- **Playtest** — linked Recomp syncs `mods\<id>` into that install and launches
  it; imported/local cache launches this pack; fixtures warn about stub data.

## Share your mod

Zip and send the `mods\<your_mod>\` folder.

## Notes

- Windows 64-bit, Linux x86_64, and macOS universal packs. LÖVE 11.5 is included.
- Do **not** ship ROM files (`.gb`) or `data/generated` / `assets/generated`.
- Do not ship `save/mod-derived`; Gen1Recomp rebuilds those animation/map assets.
- More detail: `docs/content-editor.md`
