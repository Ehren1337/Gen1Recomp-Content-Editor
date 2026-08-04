# Content editor

LÖVE app that authors Gen1Recomp mods: maps, dialog, trainers, items,
Pokémon, and simple quest scripts.

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

Output: `dist/win/gen1recomp-content-editor-win64.zip` (no ROM cache).
Recipients unzip, run `ContentEditor.bat`, then **Link Recomp** or
**Import ROM** on the Project tab for full data.

See [docs/content-editor.md](../../docs/content-editor.md) and
[PACK_README.md](PACK_README.md).
