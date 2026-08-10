# Content editor

LÖVE app that authors Gen1Recomp mods: maps, dialog, trainers, items,
Pokémon, and simple quest scripts.

The **Map Builder** tab provides standalone 16×16 layered map authoring,
custom PNG tilesets, collision, animations, safe resizing, and guided warps.
Editable layers stay in `editor_project.lua`; Save generates the normal map
and tileset records plus a legal asset-transform recipe inside the same
shareable mod.

```sh
love . --content-editor
love . --content-editor --mod mods/my_content
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
