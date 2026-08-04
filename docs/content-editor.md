# Content editor (maps, dialog, trainers, items, Pokémon, events)

In-game LÖVE editor that authors **mod folders** — never the ROM cache under
`data/generated/`. Launch:

```sh
love . --content-editor
love . --content-editor --mod mods/my_content
# or
POKEPORT_CONTENT_EDITOR=1 love .
```

On Windows with the bundled runtime:

```powershell
.\love\love-11.5-win64\love.exe . --content-editor
```

Game data (tilesets, species, maps) comes from, in order of an explicit
Project choice or auto-detect:

1. **Local** `data/generated` (dev checkout)
2. **Linked Gen1Recomp** folder (Project → Link Recomp)
3. **Imported ROM** cache in the LÖVE save directory (Project → Import ROM)
4. **Fixtures** — `tests/fixture_data` (ROM-free stub data)

The shareable pack from `scripts/pack_content_editor.ps1` never includes
`data/generated` or `assets/generated`. Prefs are stored as
`content_editor_data.json` in the save directory.

## Tabs

| Tab | What it authors |
|-----|-----------------|
| **Project** | Create / open / save; game data source; `field.boot` + `constants`; Validate / Playtest |
| **Manifest** | Edit `mods/<id>/manifest.json` |
| **Code** | Browse/edit Lua under `mods/` (paste multi-line; Ctrl+Z undoes code) |
| **Maps** | Blocks, warps, NPCs, signs, encounters, hidden items, badge gates; TMX import |
| **Dialog** | NPC/sign `TEXT_*` bindings and string table text |
| **Trainers** | `OPP_*` parties / money / name + trainer headers |
| **AI** | `ai_classes` (uses / item / switch behavior) |
| **Items** | Items + effect templates (heal / status / ball / key) |
| **Pokémon** | Species stats, types, sprites, icons, scales, cry/palette |
| **Moves** | Move stats + advanced fields (multi-hit, fixed damage, charge…) |
| **Effects** | Author `move_effects` from templates (status, recoil, drain, OHKO…) |
| **Types** | Type chart entries / matchups |
| **Audio** | Music, cries, SFX, map songs |
| **GFX** | Palettes (preview), overworld sprites, tileset walk/door/warp |
| **Events** | Talk script steps (incl. labels/jumps) + save-flag tester |

## Workflow

1. **Project** — Create a mod id or Open an existing folder.
2. Author content on the other tabs.
3. **Save** — writes:
   - `editor_project.lua` — structured editor state (source of truth)
   - `main.lua` — regenerated loadable mod
4. Enable the mod in the launcher, or validate:

```sh
python tools/modkit.py validate <id>
python tools/modkit.py pack mods/<id>
```

Hand-written mods (e.g. `example_mew_starter`) are protected: Save will refuse
to overwrite their `main.lua`. Create a **new mod id** for editor work.

## Dialog

1. Place an **object** or **sign** on Maps (auto-assigns a `TEXT_*` id).
2. Open **Dialog**, select the map and pin, edit the string (`\n` / `\f` /
   `{PLAYER}`).
3. Save emits `mod.content.text:override` and `text_pointers:patch` keyed by
   the map **label**.

## Trainers

1. On **Trainers**, patch a vanilla `OPP_*` or create a new class (party,
   money, base pic).
2. On **Maps**, choose the **TRAINER** tool and click a cell — places an
   object with `trainerClass` / `trainerParty` and seeds a
   `trainer_headers` entry (sight range, battle/won/after text, beat flag).
3. Save emits `trainers` + `trainer_headers` (new registry) + text strings.

## Events

**Scripts** mode builds linear talk scripts for a `MAP/TEXT_*` key:

| Step | Emits |
|------|--------|
| Show text | `show_text` |
| Label / Jump | `label` / `jump` / `jump_if_true` / `jump_if_false` |
| Set / clear flag | `set_flag` / `clear_flag` (`MOD_<modId>_…`) |
| Skip if flag | `check_flag` + `jump_if_true end` |
| Give / take item | `give_item` / `take_item` |
| One-shot gift | check done flag → give item once |

Use **From Dialog selection** after picking an NPC on the Dialog tab.

**Save flags** mode opens a real `save.lua` and toggles `MOD_*` / scraped
`EVENT_*` flags for playtesting. That edits save state, not mod content (same
idea as `love . --editor` Events).

## Items and effects

| Template     | Emits |
|--------------|--------|
| Heal HP      | `item_effects` heal + `items.effect` |
| Status cure  | `item_effects` status clear |
| Ball         | `balls:register` + `items.ball` |
| Key item     | noop effect, not tossable |
| Data only    | item record only |

## Project validate / playtest

On **Project**, **Validate** runs `python tools/modkit.py validate <id>` and
shows the log. **Playtest** enables the mod in options and launches a second
LOVE window:

- Linked Recomp → syncs `mods/<id>` into that install and launches it
- Local / imported cache → launches this pack’s game root
- Fixtures only → launches with a stub-data warning

## Pack for sharing

```powershell
.\scripts\pack_content_editor.ps1              # windows + linux
.\scripts\pack_content_editor.ps1 -Platform linux
```

Builds cache-free packs:

- `dist/win/gen1recomp-content-editor-win64.zip`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz` (LÖVE AppImage)

See `tools/content-editor/PACK_README.md`.

## Maps

- Paint in **blocks** (32×32). One map uses **one** `tileset` (Gen1 / Tiled
  semantics: a palette tile is a block). Assign switches the tileset; the dock
  only paints that tileset’s blocks.
- Warps / objects / signs use the 16×16 **cell** grid (block × 2).
- **Hidden** / **Gates** sections edit `field.hiddenItems` and `field.badgeGates`.
- New maps get `index >= 1000`.
- For world view, blockset composition, collision shapes, and diff
  `maps:patch` export, use the external [Tiled workflow](tiled-map-editing.md)
  (`tiled_export.py` + [tiled_gen1recomp](https://github.com/bryanthaboi/tiled_gen1recomp)).

### Pokemonium / Pokenet TMX import

```sh
python tools/tmx_import.py path/to/res/maps --mod mods/my_content
```

Or **Import TMX** on the Maps tab. Converts 32×32 layers into Gen1 blocks + a
new tileset; scripts/MMO AI do not convert. Do not redistribute Nintendo/fan
tilesets in packed mods.

## Related

- [Tiled map editing](tiled-map-editing.md)
- [Modding](modding.md)
- Save editor: `love . --editor` (player saves, not content)
