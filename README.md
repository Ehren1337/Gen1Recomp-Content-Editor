# Gen1Recomp Content Editor

Author **mods** for Gen1Recomp: maps, Pokémon, trainers, dialog, items, moves,
palettes, and talk scripts. Edits live under `mods/<id>/` — never the ROM cache.

Deep reference: [docs/content-editor.md](../../docs/content-editor.md) ·
Tiled maps: [docs/tiled-map-editing.md](../../docs/tiled-map-editing.md)

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
.\scripts\pack_content_editor.ps1
```

Gives `dist/win/gen1recomp-content-editor-win64.zip`. The zip **excludes**
`data/generated`, `assets/generated`, ROMs, and `portable.txt`. Recipients
unzip anywhere and double-click `ContentEditor.bat` (LÖVE is included).

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
| **Maps** | Paint blocks, warps, NPCs, signs, encounters; Import TMX |
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

## Maps (short)

- One map → **one tileset**. The bottom dock paints that tileset’s **blocks**
  (Gen1 / Tiled: tile = block).
- Tools: paint / erase / pick / pan, plus warp · object · sign · trainer.
- **SGB palette** — Basics field or click the canvas swatches to open the
  palette picker (previews tint with the map palette).
- **Sprite picker** — Objects section; **More…** pages wrap around.
- For full world view, collision shapes, and blockset composition, use the
  [Tiled fork](https://github.com/bryanthaboi/tiled_gen1recomp) +
  `tiled_export.py` (see tiled-map-editing docs).

### TMX import

**Import TMX** on the Maps tab, or:

```sh
python tools/tmx_import.py path/to/maps --mod mods/my_content
```

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
| Mouse wheel | Zoom map (or scroll block dock) |

---

## Requirements

- LÖVE **11.5** (bundled in the portable pack / `love/` in this checkout).
- Full tilesets/species/playtest need either a linked Gen1Recomp install, an
  imported ROM (save-dir cache), or a local `data/generated` in a dev
  checkout. Otherwise the editor uses `tests/fixture_data`.

---

## Pack for sharing (maintainers)

```powershell
.\scripts\pack_content_editor.ps1
```

Output: `dist/win/gen1recomp-content-editor-win64.zip` — editor + runtime +
fixtures + sample mods, **no ROM cache**. Recipients only need Windows 64-bit.
