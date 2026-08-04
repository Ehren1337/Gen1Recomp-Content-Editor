# Gen1Recomp Content Editor

Author mods for Gen1Recomp (maps, Pokémon, trainers, dialog, and more).

This pack ships **without** a ROM cache (`data/generated`). That keeps it
legal to redistribute. On first launch you get stub fixture data until you
link a Gen1Recomp install or import your own ROM.

## Run

1. Unzip this folder (anywhere — not inside Gen1Recomp).
2. Double-click `ContentEditor.bat`.
3. On **Project** → **GAME DATA**:
   - **Link Recomp** — pick your Gen1Recomp folder (must already have imported a ROM), or
   - **Import ROM** — choose a clean US Red/Blue/Yellow `.gb` (cache goes to the LÖVE save directory, not this pack), or
   - **Use fixtures** — keep stub data for light authoring.
4. **Project** → Open `mods\New_PokemonTest`, or **Create** a new mod.
5. Edit on the other tabs → **Save**.

Save writes `mods\<id>\editor_project.lua` and `main.lua`.

## Playtest

- With a **linked Recomp**, Playtest copies your mod into that install’s
  `mods\` and launches it there.
- With an **imported** / local cache, Playtest launches this pack as the game.
- With **fixtures only**, Playtest is stub data — Link or Import for a real run.

## Share your mod

Zip and send the `mods\<your_mod>\` folder.

## Notes

- Windows 64-bit. LÖVE is included — no install needed.
- Do **not** ship ROM files (`.gb`) or `data\generated` / `assets\generated`.
- More detail: `docs\content-editor.md`
