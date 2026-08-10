# Gen1Recomp Content Editor

Author **mods** for Gen1Recomp: maps, Pokémon, trainers, dialog, items, moves,
palettes, and talk scripts. Edits live under `mods/<id>/` — never the ROM cache.

Deep reference: [docs/content-editor.md](docs/content-editor.md)

---

## Launch

**From a source checkout**

```sh
love . --content-editor
love . --content-editor --mod mods/my_content
```

Windows (bundled runtime):

```powershell
.\love\love-11.5-win64\love.exe . --content-editor
```

**Portable pack (share with others)**

```powershell
.\scripts\pack_content_editor.ps1              # windows + linux
.\scripts\pack_content_editor.ps1 -Platform linux
.\scripts\pack_content_editor.ps1 -Platform windows
```

Outputs (no ROM cache):

- `dist/win/gen1recomp-content-editor-win64.zip` → `ContentEditor.bat`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz` → `./ContentEditor.sh`
  (after `chmod +x ContentEditor.sh love/love-11.5-x86_64.AppImage`)

On **Project → GAME DATA** they can **Link Recomp** (reuse an existing
install’s cache), **Import ROM** (cache in the LÖVE save directory), or
**Use fixtures** (stub data).

---

## Quick start

1. **Project → GAME DATA** — Link Gen1Recomp, Import a ROM, or stay on fixtures.
2. **Project** — Create a new mod id, or Open an existing `mods/<id>/` folder.
3. Edit on the other tabs (Maps, Pokémon, Trainers, …).
4. **Save** (Ctrl+S) writes:
   - `editor_project.lua` — editor source of truth
   - `main.lua` — loadable mod the game runs
5. **Playtest**, or enable the mod in the Gen1Recomp launcher / validate:

```sh
python tools/modkit.py validate <id>
```

Hand-written example mods are protected: Save will not overwrite their
`main.lua`. Use a **new mod id** for editor work.

### Share your mod

Zip and send the `mods/<your_mod>/` folder (include `assets/` if you added
sprites). Do **not** ship ROM files (`.gb`) or `data/generated` /
`assets/generated`.

---

## Tabs

| Tab | Purpose |
|-----|---------|
| **Project** | Create / open / save; game data source; boot & constants; Validate / Playtest |
| **Manifest** | `manifest.json` (name, version, deps) |
| **Code** | Browse / edit Lua under `mods/` |
| **Map Builder** | Native 16×16 layered maps, custom PNG tilesets, collision, animations, and guided warps |
| **Maps** | Classic blocks plus NPCs, signs, encounters, connections, and optional TMX import |
| **Dialog** | NPC / sign text (`TEXT_*`) |
| **Trainers** | Parties, money, battle pics, palette |
| **AI** | Trainer AI classes |
| **Items** | Items + heal / status / ball / key templates |
| **Pokémon** | Stats, types, sprites, icons, cry, palette |
| **Moves** | Power, accuracy, effects, flags |
| **Effects** | Move-effect templates |
| **Types** | Type chart |
| **Audio** | Music, cries, SFX, map songs |
| **GFX** | SGB palettes, overworld sprites, tilesets |
| **Events** | Talk scripts + save-flag tester |

---

## Native layered maps

Use **Map Builder** for new map work. It is built into the standalone editor;
Tiled and changes to the Gen1Recomp workspace are not required.

1. Select a game map and click **Convert**, or click **+ New** and choose the
   custom map ID, size, and starting game tileset.
2. Click **Import PNG** to add any tileset arranged as 16×16 tiles. A map can
   paint from several imported tilesets.
3. Add and reorder layers. Layers are exported by default; turn **Out** off to
   keep a reference layer in the project without putting it in the game.
4. Paint collision and warps, then Save.

The editor keeps the original layer data in `editor_project.lua`. Save also
generates runtime blocks, collision lists, map records, and a
`mapbuilder_transforms.lua` recipe. On first game load, that recipe composes
the map atlas and animation frames from the player's own imported game art
plus the custom PNGs in the mod. The shareable mod is self-contained, carries
no copied game graphics, and runs on an unchanged Gen1Recomp installation.

Paint tools are **Pencil**, **Eraser**, **Fill**, **Rectangle**, **Picker**,
**Select**, **Collision**, **Warp**, and **Pan**. Select supports several
rectangular ranges: hold Shift while dragging to add a range, then use
**Clear tiles** or press Delete to erase every selected range on the active
layer.

Tileset color mode is an enum:

- **True color** preserves all PNG colors and is the default for imported art.
- **Palette** treats the PNG as four-shade graphics and applies the map palette.

Animations use consecutive tiles in an imported PNG. Select the first tile,
choose the frame count, and set the frame time in milliseconds. A composed
cell may contain one animated source tile.

### Warps without indices

Choose **Warps** and select a link type:

- **Two-way** — source and destination return to each other.
- **One-way** — the destination is arrival-only and does not immediately fire.
- **Custom return** — the destination returns to a third map or cell.

Click the source cell, select the destination map from the left list, and
click the arrival cell. Custom return asks for one final cell. The editor owns
map IDs and destination indices and rebuilds them safely when endpoints move.

Map dimensions are 16×16 cells and must be even because the game stores maps
as 2×2-cell blocks. Resizing preserves the top-left area and removes only
warps, NPCs, or signs that end up outside the smaller map.

Use **Maps** for NPCs, signs, trainers, encounters, connections, palettes, and
other classic map details. Its 32×32 block painter remains available for old
projects.

### Optional TMX import

**Import TMX** on the Maps tab, or:

```sh
python tools/tmx_import.py path/to/maps --mod mods/my_content
```

TMX is retained as a migration path; it is not needed by Map Builder.

---

## Pokémon / Trainers / palettes

- **Pokémon** — set types (must exist on the type chart; use `FLYING` not
  `BIRD`), sprites, icon class, and an **SGB palette**. Click the front /
  back / icon preview or the Palette row to open the picker.
- Display **names** must use Gen1 font characters (no `_` — e.g. `NEWMON`
  not `NEW_MON`). The species **id** can still use underscores.
- **Trainers** — click the battle pic or Palette row to pick a portrait
  palette (default MEWMON).

---

## Dialog & trainers on the map

1. Place an object or sign on **Maps** (gets a `TEXT_*` id).
2. Edit the string on **Dialog** (`\n`, `\f`, `{PLAYER}`).
3. For battles: author an `OPP_*` on **Trainers**, then use the **TRAINER**
   tool on Maps to place them.

---

## Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+S | Save |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Esc | Close picker / quit editor |
| [ / ] or Tab | Previous / next tab |
| Space + drag | Pan map while painting |
| Mouse wheel over a list | Scroll maps, tilesets, layers, or warps |
| Mouse wheel over the classic map | Zoom map or scroll the block dock |

---

## Requirements

- LÖVE **11.5** (bundled in the portable pack / `love/` in this checkout).
- Full tilesets/species/playtest need either a linked Gen1Recomp install, an
  imported ROM (save-dir cache), or a local `data/generated` in a dev
  checkout. Otherwise the editor uses `tests/fixture_data`.

---

## Pack for sharing (maintainers)

```powershell
.\scripts\pack_content_editor.ps1 -Platform all
```

Outputs:

- `dist/win/gen1recomp-content-editor-win64.zip`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz`

Editor + LÖVE runtime + fixtures + sample mods, **no ROM cache**.
