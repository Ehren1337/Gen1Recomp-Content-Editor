# Content editor

LÖVE app that authors Gen1Recomp mods: maps, dialog, trainers, items,
Pokémon, and simple quest scripts.

The contextual **Maps** workspace provides standalone 16×16 layered map authoring,
custom PNG tilesets, collision, animations, safe resizing, and guided warps.
Editable layers stay in `editor_project.lua`; Save generates the normal map
and tileset records plus a legal asset-transform recipe inside the same
shareable mod.

The former Map Builder and Maps workflows are unified here. The left column
contains maps and tile sources, the center switches between **Terrain** and
**Events**, and the right drawer contains **Map**, **Layers**, **Animate**, and
**Warps**. Existing maps are prepared for the 16×16 grid when selected; use
**+ New Map** for a new layered map and **World View** for connected neighbors.

## Tile animations

Import a 16×16-tile PNG with **+ New PNG**, select the animated starting tile,
and click **Animate tile**. Choose an initial frame count in the **Animate**
drawer, then set every frame's source tile and duration independently. Frames
can be reordered, added, or deleted; **Static** removes the animation. Animated
starting tiles are marked **A** in the palette.

Save emits `tileset.animatedTiles` plus `mapbuilder_transforms.lua`. Gen1Recomp
builds the derived frame images on first load. Playback therefore requires a
Gen1Recomp runtime with `animatedTiles` support; the development runtime used by
this project is `D:\decomp\gen1recomp` (`src/render/TileRenderer.lua`).

```sh
git submodule update --init --recursive
./ContentEditor.sh
./ContentEditor.sh --mod mods/my_content
```

Windows (bundled runtime in this checkout):

```powershell
.\love\love-11.5-win64\love.exe . --content-editor
```

Portable zip for sharing (Windows):

```powershell
.\scripts\pack_content_editor.ps1
```

Outputs (no ROM cache):

- `dist/win/gen1recomp-content-editor-win64.zip` → `ContentEditor.bat`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz` → `./ContentEditor.sh`

Then **Link Recomp** or **Import ROM** on the Project tab for full data.

See [docs/content-editor.md](../../docs/content-editor.md) and
[PACK_README.md](PACK_README.md).
