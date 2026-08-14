# Maps

The Maps workspace combines terrain, events, layers, animation, map settings,
World View, and coordinate-based transfers in one screen.

## Safe viewing and editing

Selecting an existing game map is read-only. The header says **Map preview**,
the map list remains available, and **World View** can be opened without adding
anything to the mod.

Click **Edit Map** only when you want an editable project copy. This explicitly
converts the selected map to the 16×16-cell layered source model while retaining
its map record, objects, signs, encounters, connections, and other metadata.
Maps already owned by the project show **EDIT** in the list.

> Selecting, scrolling, using keyboard navigation, or opening World View never
> converts a vanilla map. Starting a transfer and navigating to a read-only map
> cancels the transfer instead of converting that destination.

## Create a map

1. Click **Create new map**.
2. Enter a unique ID.
3. Enter even width and height values. Sizes are measured in 16×16 walk cells.
4. Choose the starting visual style and click **Create map**.

Both dimensions must be even because the runtime stores four 16×16 cells in
each 32×32 block.

## Workspace layout

- Left: map search/list and tileset sources.
- Center: **Paint map** or **Add events** toolbar and canvas.
- Right: **Map setup**, **Layers**, **Tile animation**, and
  **Doors & exits** drawers.
- Header: the four-step guide, World View, **Edit this map**,
  **Create new map**, and **More actions**.

The map list uses full IDs. **EDIT** is a text label as well as a color cue, so
editable state does not depend on color alone.

The initial view contains the everyday controls. **More tools** reveals
selection, collision, warp, trainer, and other specialized tools;
**More settings** reveals hidden items and badge gates; **More options** reveals
tileset import, replacement, TMX, and export; and **More actions** contains
destructive or legacy map commands.

## Paint map tools

| Tool | Action |
|---|---|
| Pencil | Paint the selected 16×16 source tile. |
| Eraser | Clear cells on the active layer. |
| Fill | Flood-fill matching cells. |
| Rectangle | Paint a filled rectangular area. |
| Picker | Pick the top visible tile and its layer. |
| Select | Select one or more rectangular ranges. |
| Collision | Paint solid, walk, grass, water, or shore passage. |
| Warp | Create a guided map transfer. |
| Pan | Move the camera without editing. |

Shift-drag adds selection ranges. Ctrl+C and Ctrl+V copy and paste selected
terrain; Delete clears it. Use the mouse wheel to zoom and Pan, middle mouse,
Space/Alt drag, or WASD to move the camera.

## Layers

Ground always exists. Additional layers can be added, named, reordered, hidden,
given partial opacity, or removed.

- **Eye** controls editor visibility.
- **Out** controls whether Save includes the layer in the game map.

Transparent layers are alpha-composed in order. Resizing keeps the top-left
area; shrinking reports and removes terrain or events outside the new bounds.

## Tileset sources and full color

Click **Import PNG** or **+ New PNG** to add a sheet whose width and height are
multiples of 16 pixels. A map may paint from several imported and game sources.

Each imported source has a color mode:

- **True color** preserves every PNG color and is the default.
- **Palette** treats the artwork as four shades and applies the effective map
  palette.

The palette, map canvas, animated frames, layer composition, generated atlas,
and runtime use the same rule. Mixing modes is supported: palette layers are
palette-colored before being alpha-composed with true-color layers. Save marks
the generated tileset as `trueColor` whenever any exported cell uses a
true-color source, preventing runtime palette remapping from corrupting it.

### Export source PNGs

- **Export PNG** exports the currently selected source.
- **Export All** exports every available source.

Exports copy original PNG bytes. Color mode, palette selection, animation, and
map composition never quantize or rewrite exported source artwork. Both actions
write automatically to `<open-mod>/exports/tilesets/`.

## Tile animation

Animations are available for imported PNG sources:

1. Select the starting tile.
2. Click **Animate tile**.
3. Choose 2, 3, 4, 6, or 8 initial frames.
4. Choose each frame tile and duration; reorder, add, or delete frames as needed.
5. Paint the animated starting tile on the map.

Animated starting tiles show **A**. Choose **Static** to remove an animation.
Save writes frame images and timing records; durations are converted to the
runtime's 60 Hz clock.

## Add events

Switch the center toolbar to **Add events** to place an Event, Sign, Trainer,
or fixed Wild encounter. **Select** chooses an existing marker without creating
one. Drag a marker to move it, Ctrl+C/Ctrl+V to duplicate it, Delete to remove
it, and **Dialog** to edit associated text.

## Doors & exits

**Doors & exits** uses stable endpoints and generates runtime indices on Save.

- **Two-way:** A links to B and B links to A.
- **One-way:** A links to B; B is arrival-only.
- **Custom return:** A links to B, and B returns to a separately selected C.

Active endpoints are red and arrival-only endpoints are blue. Deleting an
endpoint safely disables links that targeted it.

## Save output

Editor-only layered source remains in `editor_project.lua`. Save also writes:

- normal map and generated tileset records;
- `mapbuilder_transforms.lua` and its manifest reference;
- a flattened atlas recipe and animation-frame recipes;
- collision lists and resolved warp records.

Derived atlases are generated under
`save/mod-derived/<mod-id>/mapbuilder/` on game startup. They are cache output
and should not be distributed. The compiled format retains the Gen I limits of
256 unique 8×8 graphics and 256 blocks per composed map.

## Shortcuts

| Shortcut | Action |
|---|---|
| Ctrl+S | Save. |
| Ctrl+Z / Ctrl+Y | Undo / redo. |
| Ctrl+C / Ctrl+V | Copy / paste terrain selections or events. |
| Delete / Backspace | Clear selected terrain or delete the selected event. |
| Space or Alt + drag | Pan the map. |
| WASD | Pan the map camera. |
| Mouse wheel | Scroll lists or zoom/pan the canvas. |
