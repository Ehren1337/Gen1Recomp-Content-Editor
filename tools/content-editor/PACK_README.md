# Gen1Recomp Content Editor

Author mods for Gen1Recomp (maps, Pokémon, trainers, dialog, and more).

This pack ships **without** a ROM cache (`data/generated`). That keeps it
legal to redistribute. On first launch you get stub fixture data until you
link a Gen1Recomp install or import your own ROM.

## Run

**Windows:** unzip anywhere → double-click `ContentEditor.bat`.

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
- **Import ROM** — choose a clean US Red/Blue/Yellow `.gb` (cache goes to the LÖVE save directory, not this pack), or
- **Use fixtures** — keep stub data for light authoring.

**Project** → Open `mods/New_PokemonTest`, or **Create** a new mod → edit → **Save**.

Save writes `mods/<id>/editor_project.lua` and `main.lua`.

## Playtest

- With a **linked Recomp**, Playtest copies your mod into that install’s
  `mods\` and launches it there.
- With an **imported** / local cache, Playtest launches this pack as the game.
- With **fixtures only**, Playtest is stub data — Link or Import for a real run.

## Share your mod

Zip and send the `mods\<your_mod>\` folder.

## Notes

- Windows 64-bit and Linux x86_64 packs. LÖVE 11.5 is included.
- Do **not** ship ROM files (`.gb`) or `data/generated` / `assets/generated`.
- More detail: `docs/content-editor.md`
