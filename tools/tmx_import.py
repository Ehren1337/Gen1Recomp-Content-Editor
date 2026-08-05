#!/usr/bin/env python3
"""Import Pokemonium / Pokenet / generic Tiled TMX maps into a Gen1Recomp mod.

Pokemonium maps are 32x32 multi-layer TMX (res/maps/X.Y.tmx) with Collisions /
Water / Ledge layers.  This tool converts them into Gen1-style block maps + a
new tileset (each unique 32x32 tile becomes one block of 16 8x8 tiles).

Usage:
    python tools/tmx_import.py Client/res/maps/3.0.tmx --mod mods/my_mod
    python tools/tmx_import.py Client/res/maps --mod mods/my_mod

Writes assets under the mod, and tmx_import_result.lua for the content editor
to merge.  Does NOT redistribute tileset art — runs on the user's local files.

Requires: Pillow
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import struct
import sys
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional, Tuple

try:
    from PIL import Image
except ImportError:
    sys.exit("tmx_import needs Pillow: python -m pip install Pillow")


SPECIAL_LAYERS = {
    "collisions", "collision", "water",
    "ledgesleft", "ledgesright", "ledgesdown", "ledgesup",
    "ledges", "fringe", "overhead",
}

# Tiled global-tile-id flip flags (see docs.mapeditor.org global-tile-ids).
FLIP_H = 0x80000000
FLIP_V = 0x40000000
FLIP_D = 0x20000000
GID_MASK = 0x1FFFFFFF


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_list_nums(nums: List[int], per_line: int = 16) -> str:
    if not nums:
        return "{}"
    parts = []
    for i in range(0, len(nums), per_line):
        chunk = ", ".join(str(n) for n in nums[i:i + per_line])
        parts.append("      " + chunk + ",")
    return "{\n" + "\n".join(parts) + "\n    }"


def parse_csv_layer(data_text: str, width: int, height: int) -> List[int]:
    text = (data_text or "").replace("\n", ",").replace(" ", "")
    vals = [int(x) for x in text.split(",") if x != ""]
    # pad / trim
    need = width * height
    if len(vals) < need:
        vals.extend([0] * (need - len(vals)))
    return vals[:need]


def decode_layer_data(data_el, width: int, height: int) -> List[int]:
    encoding = (data_el.get("encoding") or "csv").lower()
    compression = (data_el.get("compression") or "").lower()
    text = (data_el.text or "").strip()
    if encoding == "csv" and not compression:
        return parse_csv_layer(text, width, height)
    if encoding == "base64":
        import base64
        raw = base64.b64decode(text)
        if compression == "zlib":
            import zlib
            raw = zlib.decompress(raw)
        elif compression == "gzip":
            import gzip
            raw = gzip.decompress(raw)
        elif compression:
            raise ValueError(f"unsupported compression {compression}")
        # little-endian uint32 gids
        vals = list(struct.unpack("<%dI" % (len(raw) // 4), raw))
        need = width * height
        if len(vals) < need:
            vals.extend([0] * (need - len(vals)))
        return vals[:need]
    raise ValueError(f"unsupported layer encoding {encoding!r}")


class TilesetInfo:
    def __init__(self, firstgid: int, tilewidth: int, tileheight: int,
                 image_path: str, columns: int, tilecount: int, name: str,
                 tsx_path: Optional[str] = None,
                 trans: Optional[str] = None):
        self.firstgid = firstgid
        self.tilewidth = tilewidth
        self.tileheight = tileheight
        self.image_path = image_path
        self.columns = columns
        self.tilecount = tilecount
        self.name = name
        self.tsx_path = tsx_path
        self.trans = trans  # Tiled color-key hex, e.g. "000000"
        self.image: Optional[Image.Image] = None

    def load(self):
        if self.image is not None:
            return
        im = Image.open(self.image_path).convert("RGBA")
        # Many Pokemonium .tsx files omit image width/columns; derive from the
        # PNG so local tile ids do not walk off the bottom of a 1-column sheet
        # (which produced a fully transparent Gen1 atlas).
        if self.tilewidth > 0:
            derived = max(1, im.size[0] // self.tilewidth)
            if self.columns <= 1 and derived > 1:
                self.columns = derived
            elif self.columns <= 0:
                self.columns = derived
        if self.tilecount <= 0 and self.tilewidth > 0 and self.tileheight > 0:
            cols = max(1, self.columns)
            rows = max(1, im.size[1] // self.tileheight)
            self.tilecount = cols * rows
        if self.trans:
            im = apply_color_key(im, self.trans)
        self.image = im


def resolve_path(base: str, rel: str) -> str:
    return os.path.normpath(os.path.join(base, rel))


def safe_filename(name: str) -> str:
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._")
    return name or "tiles"


def apply_color_key(im: Image.Image, trans_hex: str) -> Image.Image:
    """Apply Tiled image@trans color key → alpha 0."""
    hex_s = (trans_hex or "").strip().lstrip("#")
    if len(hex_s) != 6:
        return im
    try:
        kr = int(hex_s[0:2], 16)
        kg = int(hex_s[2:4], 16)
        kb = int(hex_s[4:6], 16)
    except ValueError:
        return im
    out = im.copy()
    key = (kr, kg, kb)
    out.putdata([
        (0, 0, 0, 0) if (p[0], p[1], p[2]) == key else p
        for p in out.getdata()
    ])
    return out


def load_tileset_el(ts_el, tmx_dir: str) -> TilesetInfo:
    firstgid = int(ts_el.get("firstgid", 1))
    source = ts_el.get("source")
    if source:
        tsx_path = resolve_path(tmx_dir, source)
        tree = ET.parse(tsx_path)
        root = tree.getroot()
        return _tileset_from_root(root, firstgid, os.path.dirname(tsx_path),
                                  root.get("name") or os.path.splitext(
                                      os.path.basename(tsx_path))[0],
                                  tsx_path=tsx_path)
    return _tileset_from_root(ts_el, firstgid, tmx_dir,
                              ts_el.get("name") or "tiles")


def _tileset_from_root(root, firstgid: int, base_dir: str,
                       name: str, tsx_path: Optional[str] = None) -> TilesetInfo:
    tilewidth = int(root.get("tilewidth", 32))
    tileheight = int(root.get("tileheight", 32))
    image = root.find("image")
    if image is None:
        raise ValueError(f"tileset {name} has no image")
    image_path = resolve_path(base_dir, image.get("source"))
    img_w = int(image.get("width") or 0)
    img_h = int(image.get("height") or 0)
    # Prefer on-disk size: Pokemonium TSX often omits width/height/columns.
    if os.path.isfile(image_path):
        with Image.open(image_path) as probe:
            img_w = img_w or probe.size[0]
            img_h = img_h or probe.size[1]
    columns = int(root.get("columns") or 0)
    if columns <= 0 and img_w and tilewidth:
        columns = max(1, img_w // tilewidth)
    columns = max(1, columns)
    tilecount = int(root.get("tilecount") or 0)
    if tilecount == 0 and img_w and img_h and tilewidth and tileheight:
        tilecount = (img_w // tilewidth) * (img_h // tileheight)
    trans = image.get("trans")
    return TilesetInfo(firstgid, tilewidth, tileheight, image_path,
                       columns, tilecount, name, tsx_path=tsx_path,
                       trans=trans)


def copy_source_tilesets(tilesets: List[TilesetInfo], mod_dir: str,
                         report: List[str]) -> List[dict]:
    """Copy the TMX's original .png / .tsx into the mod for reuse in Tiled."""
    out_dir = os.path.join(mod_dir, "assets", "tilesets", "source")
    os.makedirs(out_dir, exist_ok=True)
    copied: List[dict] = []
    seen = set()
    for ts in tilesets:
        key = os.path.abspath(ts.image_path or "")
        if not key or key in seen:
            continue
        seen.add(key)
        if not os.path.isfile(ts.image_path):
            report.append(f"missing source tileset image: {ts.image_path}")
            continue
        img_name = safe_filename(os.path.basename(ts.image_path))
        dest_img = os.path.join(out_dir, img_name)
        if os.path.exists(dest_img) and os.path.abspath(dest_img) != key:
            stem, ext = os.path.splitext(img_name)
            img_name = safe_filename(f"{stem}_{ts.name}{ext}")
            dest_img = os.path.join(out_dir, img_name)
        shutil.copy2(ts.image_path, dest_img)
        rel_img = f"assets/tilesets/source/{img_name}"
        rel_tsx = None
        if ts.tsx_path and os.path.isfile(ts.tsx_path):
            tsx_name = safe_filename(os.path.basename(ts.tsx_path))
            dest_tsx = os.path.join(out_dir, tsx_name)
            shutil.copy2(ts.tsx_path, dest_tsx)
            rel_tsx = f"assets/tilesets/source/{tsx_name}"
        try:
            ts.load()
            img_w, img_h = ts.image.size
            columns = ts.columns
            tilecount = ts.tilecount
        except Exception:
            img_w = img_h = 0
            columns = ts.columns
            tilecount = ts.tilecount
        tid = safe_filename(ts.name).upper() or "TILESET"
        copied.append({
            "id": tid,
            "name": ts.name,
            "image": rel_img,
            "tsx": rel_tsx,
            "tilewidth": ts.tilewidth,
            "tileheight": ts.tileheight,
            "columns": columns,
            "tilecount": tilecount,
            "firstgid": ts.firstgid,
            "imageWidth": img_w,
            "imageHeight": img_h,
        })
        report.append(
            f"imported source tileset {ts.name} "
            f"(firstgid={ts.firstgid}, cols={columns}) -> {rel_img}")
    return copied


def gid_to_local(gid: int, tilesets: List[TilesetInfo]
                 ) -> Optional[Tuple[TilesetInfo, int]]:
    """Resolve a Tiled global tile id → (tileset, local id).

    Tiled: clear flip flags, then pick the tileset with the largest firstgid
    that is still <= gid (tilesets are ordered by ascending firstgid).
    """
    gid = gid & GID_MASK
    if gid == 0:
        return None
    ordered = sorted(tilesets, key=lambda t: t.firstgid, reverse=True)
    for ts in ordered:
        if ts.firstgid <= gid:
            return ts, gid - ts.firstgid
    return None


def apply_tile_flips(tile: Image.Image, raw_gid: int) -> Image.Image:
    """Apply Tiled flip flags to a tile image."""
    if raw_gid & FLIP_D:
        tile = tile.transpose(Image.TRANSPOSE)
    if raw_gid & FLIP_H:
        tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
    if raw_gid & FLIP_V:
        tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
    return tile


def extract_tile(ts: TilesetInfo, local_id: int) -> Image.Image:
    ts.load()
    cols = max(1, ts.columns)
    tw, th = ts.tilewidth, ts.tileheight
    x = (local_id % cols) * tw
    y = (local_id // cols) * th
    iw, ih = ts.image.size
    if x + tw > iw or y + th > ih or x < 0 or y < 0:
        raise ValueError(
            f"local id {local_id} out of range for {ts.name} "
            f"({iw}x{ih}, {tw}x{th}, cols={cols})")
    return ts.image.crop((x, y, x + tw, y + th))


def render_gid(raw_gid: int, tilesets: List[TilesetInfo],
               out_size: Tuple[int, int]) -> Optional[Image.Image]:
    """Rasterize one Tiled GID (any tileset) into out_size RGBA."""
    hit = gid_to_local(raw_gid, tilesets)
    if not hit:
        return None
    ts, local = hit
    try:
        tile = extract_tile(ts, local)
    except Exception:
        return None
    tile = apply_tile_flips(tile, raw_gid)
    if tile.size != out_size:
        tile = tile.resize(out_size, Image.NEAREST)
    return tile


def composite_gids(gids: List[int], tilesets: List[TilesetInfo],
                   out_size: Tuple[int, int]) -> Optional[Image.Image]:
    """Stack Tiled layer GIDs bottom→top (0 = empty), like the Tiled canvas."""
    canvas = None
    for gid in gids:
        if not (gid & GID_MASK):
            continue
        tile = render_gid(gid, tilesets, out_size)
        if tile is None:
            continue
        if canvas is None:
            canvas = Image.new("RGBA", out_size, (0, 0, 0, 0))
        paste_rgba(canvas, tile, (0, 0))
    return canvas


def paste_rgba(dst: Image.Image, src: Image.Image, xy: Tuple[int, int]) -> None:
    """Paste RGBA without soft-compositing away opaque pixels onto a clear dst."""
    if src.mode != "RGBA":
        src = src.convert("RGBA")
    x, y = xy
    # Build a hard mask: any source alpha > 0 replaces the destination pixel.
    mask = src.split()[3].point(lambda a: 255 if a > 0 else 0)
    dst.paste(src, (x, y), mask)


def block_from_32(tile: Image.Image) -> Tuple[Image.Image, List[int]]:
    """Resize/slice a tile into 4x4 of 8x8; return sheet strip + 16 local ids 0..15."""
    if tile.size != (32, 32):
        tile = tile.resize((32, 32), Image.NEAREST)
    cells = []
    for row in range(4):
        for col in range(4):
            cells.append(tile.crop((col * 8, row * 8, col * 8 + 8, row * 8 + 8)))
    strip = Image.new("RGBA", (128, 8), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        paste_rgba(strip, c, (i * 8, 0))
    return strip, list(range(16))


class Converter:
    def __init__(self):
        self.key_to_block: Dict[object, int] = {}
        self.block_tiles: List[List[int]] = []  # each 16 tile ids into sheet
        self.sheet_tiles: List[Image.Image] = []  # 8x8 tiles
        self.walkable_tile_ids: set = set()
        self.water_tile_ids: set = set()
        self.notes: List[str] = []
        self.tileset_names_used: set = set()

    def _append_block_from_tile(self, tile: Image.Image) -> int:
        strip, _ = block_from_32(tile)
        base = len(self.sheet_tiles)
        for i in range(16):
            self.sheet_tiles.append(strip.crop((i * 8, 0, i * 8 + 8, 8)))
        block_id = len(self.block_tiles)
        self.block_tiles.append([base + i for i in range(16)])
        for tid in self.block_tiles[-1]:
            self.walkable_tile_ids.add(tid)
        return block_id

    def ensure_block_image(self, tile: Image.Image, cache_key) -> int:
        if cache_key in self.key_to_block:
            return self.key_to_block[cache_key]
        block_id = self._append_block_from_tile(tile)
        self.key_to_block[cache_key] = block_id
        return block_id

    def ensure_block(self, gid: int, tilesets: List[TilesetInfo]) -> int:
        """Single-GID block (no layer stacking)."""
        raw = gid & GID_MASK
        if raw == 0:
            return 0
        key = ("gid", gid)
        if key in self.key_to_block:
            return self.key_to_block[key]
        hit = gid_to_local(gid, tilesets)
        if not hit:
            self.notes.append(f"unknown gid {raw}")
            return 0
        ts, local = hit
        self.tileset_names_used.add(ts.name)
        try:
            tile = extract_tile(ts, local)
        except Exception as exc:  # noqa: BLE001
            self.notes.append(f"tile extract {ts.name}#{local}: {exc}")
            return 0
        tile = apply_tile_flips(tile, gid)
        if ts.tilewidth != 32 or ts.tileheight != 32:
            self.notes.append(
                f"tileset {ts.name} is {ts.tilewidth}x{ts.tileheight}; "
                "scaled to 32x32")
        return self.ensure_block_image(tile, key)


def layer_name(layer) -> str:
    return (layer.get("name") or "").strip()


def is_special(name: str) -> bool:
    return name.lower().replace(" ", "") in SPECIAL_LAYERS


def parse_tmx(path: str) -> dict:
    tree = ET.parse(path)
    root = tree.getroot()
    width = int(root.get("width"))
    height = int(root.get("height"))
    tilewidth = int(root.get("tilewidth", 32))
    tileheight = int(root.get("tileheight", 32))
    tmx_dir = os.path.dirname(os.path.abspath(path))
    tilesets = [load_tileset_el(ts, tmx_dir) for ts in root.findall("tileset")]
    layers = []
    for layer in root.findall("layer"):
        data = layer.find("data")
        if data is None:
            continue
        gids = decode_layer_data(data, width, height)
        layers.append({"name": layer_name(layer), "gids": gids})
    objects = []
    for og in root.findall("objectgroup"):
        for obj in og.findall("object"):
            props = {}
            for p in obj.findall("properties/property"):
                props[p.get("name")] = p.get("value")
            objects.append({
                "name": obj.get("name") or "",
                "type": obj.get("type") or obj.get("class") or "",
                "x": float(obj.get("x") or 0),
                "y": float(obj.get("y") or 0),
                "properties": props,
                "group": layer_name(og),
            })
    return {
        "path": path,
        "width": width,
        "height": height,
        "tilewidth": tilewidth,
        "tileheight": tileheight,
        "tilesets": tilesets,
        "layers": layers,
        "objects": objects,
    }


def map_id_from_path(path: str) -> str:
    base = os.path.splitext(os.path.basename(path))[0]
    m = re.fullmatch(r"(-?\d+)\.(-?\d+)", base)
    if m:
        return f"PM_{m.group(1)}_{m.group(2)}".replace("-", "M")
    safe = re.sub(r"[^A-Za-z0-9_]+", "_", base).upper()
    return "PM_" + safe


def world_coords(path: str) -> Optional[Tuple[int, int]]:
    base = os.path.splitext(os.path.basename(path))[0]
    m = re.fullmatch(r"(-?\d+)\.(-?\d+)", base)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def convert_map(parsed: dict, conv: Converter) -> dict:
    w, h = parsed["width"], parsed["height"]
    tilesets = parsed["tilesets"]
    # Preload / fix columns for every tileset (Tiled maps often use many).
    for ts in tilesets:
        try:
            ts.load()
        except Exception as exc:  # noqa: BLE001
            conv.notes.append(f"tileset load {ts.name}: {exc}")

    ground = []
    collisions: List[List[int]] = []
    water_layers: List[List[int]] = []
    for layer in parsed["layers"]:
        name = layer["name"]
        low = name.lower().replace(" ", "")
        if low in ("collisions", "collision"):
            collisions.append(layer["gids"])
        elif low == "water":
            water_layers.append(layer["gids"])
        elif not is_special(name):
            # Walkable / WalkBehind / unnamed paint layers — Tiled draws these
            # bottom→top; we keep file order (TMX lists bottom layers first).
            ground.append(layer)

    if not ground:
        ground = [parsed["layers"][0]] if parsed["layers"] else []

    # Gen1 block = 32x32; Pokemonium maps are often 16x16 tiles.
    out_size = (32, 32)
    blocks = [0] * (w * h)
    for i in range(w * h):
        stack = [layer["gids"][i] for layer in ground]
        if not any(g & GID_MASK for g in stack):
            continue
        # Track which source tilesets contributed (for the import report).
        for g in stack:
            hit = gid_to_local(g, tilesets) if (g & GID_MASK) else None
            if hit:
                conv.tileset_names_used.add(hit[0].name)
        composed = composite_gids(stack, tilesets, out_size)
        if composed is None:
            continue
        # Cache key: the exact GID stack (includes flip flags).
        key = ("stack", tuple(stack))
        blocks[i] = conv.ensure_block_image(composed, key)

    # collisions: any non-zero on ANY Collisions layer => blocked
    if collisions:
        for i in range(w * h):
            hit = False
            for layer in collisions:
                if layer[i] & GID_MASK:
                    hit = True
                    break
            if not hit:
                continue
            bid = blocks[i]
            if bid and bid < len(conv.block_tiles):
                # feet tile = bottom-left of block (gen1 rule)
                # 4x4 row-major: row 3, col 0 => index 12
                feet = conv.block_tiles[bid][12]
                conv.walkable_tile_ids.discard(feet)

    if water_layers:
        for i in range(w * h):
            wet = False
            for layer in water_layers:
                if layer[i] & GID_MASK:
                    wet = True
                    break
            if not wet:
                continue
            bid = blocks[i]
            if bid and bid < len(conv.block_tiles):
                for tid in conv.block_tiles[bid]:
                    conv.water_tile_ids.add(tid)

    warps, objects, signs, unknown = [], [], [], []
    for obj in parsed["objects"]:
        # cell coords: Pokemonium uses pixel coords on 32px tiles; gen1 warps
        # are on 16px cells => multiply block by 2
        bx = int(obj["x"] // parsed["tilewidth"])
        by = int(obj["y"] // parsed["tileheight"])
        cx, cy = bx * 2, by * 2
        props = obj["properties"]
        otype = (obj["type"] or props.get("type") or "").lower()
        name = (obj["name"] or "").lower()
        if "warp" in otype or "warp" in name or props.get("destMap") or props.get("map"):
            warps.append({
                "x": cx, "y": cy,
                "destMap": str(props.get("destMap") or props.get("map") or "PALLET_TOWN"),
                "destWarp": int(props.get("destWarp") or props.get("warp") or 0),
            })
        elif "sign" in otype or "sign" in name:
            signs.append({
                "x": cx, "y": cy,
                "text": props.get("text") or obj["name"] or "SIGN",
            })
        elif "npc" in otype or "object" in otype or obj["name"]:
            objects.append({
                "index": len(objects) + 1,
                "x": cx, "y": cy,
                "sprite": props.get("sprite") or "SPRITE_RED",
                "movement": props.get("movement") or "STAY",
                "range": int(props.get("range") or 0),
                "text": props.get("text") or obj["name"] or "TEXT",
            })
        else:
            unknown.append(obj)

    mid = map_id_from_path(parsed["path"])
    return {
        "id": mid,
        "label": mid,
        "width": w,
        "height": h,
        "blocks": blocks,
        "warps": warps,
        "objects": objects,
        "signs": signs,
        "unknown_objects": len(unknown),
        "world": world_coords(parsed["path"]),
        "path": parsed["path"],
    }


def build_sheet(conv: Converter) -> Image.Image:
    n = max(1, len(conv.sheet_tiles))
    cols = 16
    rows = (n + cols - 1) // cols
    img = Image.new("RGBA", (cols * 8, rows * 8), (0, 0, 0, 0))
    for i, tile in enumerate(conv.sheet_tiles):
        paste_rgba(img, tile, ((i % cols) * 8, (i // cols) * 8))
    return img


def emit_result_lua(mod_dir: str, tileset_id: str, tileset_rel: str,
                    conv: Converter, maps: List[dict],
                    connections: Dict[str, dict], report: List[str],
                    sheet_size: Tuple[int, int],
                    source_tilesets: List[dict]) -> str:
    walkable = sorted(conv.walkable_tile_ids)
    water = sorted(conv.water_tile_ids)
    img_w, img_h = sheet_size
    lines = [
        "-- generated by tools/tmx_import.py; merged by the content editor",
        "return {",
        f"  tilesetId = {lua_str(tileset_id)},",
        "  tileset = {",
        f"    id = {lua_str(tileset_id)},",
        f"    image = {lua_str(tileset_rel)},",
        "    tilesPerRow = 16,",
        f"    imageWidth = {img_w},",
        f"    imageHeight = {img_h},",
        '    animation = "TILEANIM_NONE",',
        "    doorTiles = {},",
        "    warpTiles = {},",
        "    counterTiles = {},",
        "    _isNew = true,",
        "    blocks = {",
    ]
    for block in conv.block_tiles:
        lines.append("      { " + ", ".join(str(t) for t in block) + " },")
    if not conv.block_tiles:
        lines.append("      { " + ", ".join(["0"] * 16) + " },")
    lines += [
        "    },",
        f"    walkable = {lua_list_nums(walkable)},",
        f"    waterTiles = {lua_list_nums(water)},",
        "  },",
        # Each Tiled tileset is also registered so the editor can browse /
        # assign them like Tiled's tileset tabs (map still uses the merged
        # Gen1 atlas above).
        "  tilesets = {",
    ]
    seen_ids = {tileset_id}
    for src in source_tilesets:
        tid = src.get("id") or safe_filename(src["name"]).upper() or "TILESET"
        base = tid
        n = 2
        while tid in seen_ids:
            tid = f"{base}_{n}"
            n += 1
        seen_ids.add(tid)
        img_w = int(src.get("imageWidth") or 0)
        img_h = int(src.get("imageHeight") or 0)
        # Build a simple 8x8-index block list so GFX / map picker can thumb.
        tile_w = max(1, img_w // 8) if img_w else 16
        tile_h = max(1, img_h // 8) if img_h else 1
        n_tiles = tile_w * tile_h
        n_blocks = max(1, (n_tiles + 15) // 16)
        lines.append(f"    [{lua_str(tid)}] = {{")
        lines.append(f"      id = {lua_str(tid)},")
        lines.append(f"      image = {lua_str(src['image'])},")
        lines.append("      tilesPerRow = 16,")
        if img_w:
            lines.append(f"      imageWidth = {img_w},")
        if img_h:
            lines.append(f"      imageHeight = {img_h},")
        lines.append('      animation = "TILEANIM_NONE",')
        lines.append("      doorTiles = {}, warpTiles = {}, counterTiles = {},")
        lines.append("      _isNew = true,")
        lines.append(
            f"      _tiledName = {lua_str(src['name'])},")
        lines.append(
            f"      _tiledTileSize = {src['tilewidth']},")
        lines.append("      blocks = {")
        for b in range(n_blocks):
            ids = [b * 16 + i for i in range(16)]
            lines.append("        { " + ", ".join(str(t) for t in ids) + " },")
        lines.append("      },")
        lines.append("      walkable = {},")
        lines.append("      waterTiles = {},")
        lines.append("    },")
    lines += [
        "  },",
        "  sourceTilesets = {",
    ]
    for src in source_tilesets:
        lines.append("    {")
        lines.append(f"      name = {lua_str(src['name'])},")
        if src.get("id"):
            lines.append(f"      id = {lua_str(src['id'])},")
        lines.append(f"      image = {lua_str(src['image'])},")
        if src.get("tsx"):
            lines.append(f"      tsx = {lua_str(src['tsx'])},")
        lines.append(
            f"      firstgid = {int(src.get('firstgid') or 0)}, "
            f"tilewidth = {src['tilewidth']}, "
            f"tileheight = {src['tileheight']}, "
            f"columns = {src['columns']}, tilecount = {src['tilecount']},")
        lines.append("    },")
    lines += [
        "  },",
        "  maps = {",
    ]
    for m in maps:
        cons = connections.get(m["id"], {})
        lines += [
            f"    [{lua_str(m['id'])}] = {{",
            f"      id = {lua_str(m['id'])},",
            f"      label = {lua_str(m['label'])},",
            f"      tileset = {lua_str(tileset_id)},",
            f"      width = {m['width']}, height = {m['height']},",
            f"      blocks = {lua_list_nums(m['blocks'], 20)},",
            "      borderBlock = 0,",
            "      warps = {",
        ]
        for w in m["warps"]:
            lines.append(
                f"        {{ x = {w['x']}, y = {w['y']}, "
                f"destMap = {lua_str(w['destMap'])}, destWarp = {w['destWarp']} }},")
        lines.append("      },")
        lines.append("      objects = {")
        for o in m["objects"]:
            lines.append(
                f"        {{ index = {o['index']}, x = {o['x']}, y = {o['y']}, "
                f"sprite = {lua_str(o['sprite'])}, movement = {lua_str(o['movement'])}, "
                f"range = {o['range']}, text = {lua_str(o['text'])} }},")
        lines.append("      },")
        lines.append("      signs = {")
        for s in m["signs"]:
            lines.append(
                f"        {{ x = {s['x']}, y = {s['y']}, text = {lua_str(s['text'])} }},")
        lines.append("      },")
        lines.append("      connections = {")
        for dir_, info in cons.items():
            lines.append(
                f"        {dir_} = {{ map = {lua_str(info['map'])}, offset = 0 }},")
        lines.append("      },")
        lines.append("      _isNew = true,")
        lines.append("    },")
    lines += [
        "  },",
        "  report = {",
    ]
    for r in report:
        lines.append(f"    {lua_str(r)},")
    lines += [
        "  },",
        "}",
        "",
    ]
    path = os.path.join(mod_dir, "tmx_import_result.lua")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    return path


def collect_tmx(path: str) -> List[str]:
    if os.path.isdir(path):
        files = []
        for name in sorted(os.listdir(path)):
            if name.lower().endswith(".tmx"):
                files.append(os.path.join(path, name))
        return files
    return [path]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", help="TMX file or directory of TMX files")
    ap.add_argument("--mod", required=True, help="Destination mod directory")
    ap.add_argument("--tileset-id", default=None,
                    help="Tileset id to register (default: source "
                         "tileset name, or PM_TILES)")
    args = ap.parse_args(argv)

    mod_dir = os.path.abspath(args.mod)
    os.makedirs(os.path.join(mod_dir, "assets", "tilesets"), exist_ok=True)

    files = collect_tmx(args.input)
    if not files:
        print("tmx_import: no .tmx files found", file=sys.stderr)
        return 2

    conv = Converter()
    maps = []
    all_tilesets: List[TilesetInfo] = []
    report = [f"importing {len(files)} tmx file(s)"]
    for path in files:
        try:
            parsed = parse_tmx(path)
            if parsed["tilewidth"] != 32 or parsed["tileheight"] != 32:
                report.append(
                    f"{os.path.basename(path)}: tile size "
                    f"{parsed['tilewidth']}x{parsed['tileheight']} "
                    "(expected 32x32; scaling tiles)")
            for ts in parsed["tilesets"]:
                all_tilesets.append(ts)
            m = convert_map(parsed, conv)
            maps.append(m)
            report.append(
                f"{m['id']}: {m['width']}x{m['height']} blocks, "
                f"{len(m['warps'])} warps, {len(m['objects'])} objects, "
                f"{m['unknown_objects']} unknown objects")
        except Exception as exc:  # noqa: BLE001
            report.append(f"FAIL {path}: {exc}")

    # Copy original Tiled tileset art into the mod (in addition to the
    # Gen1 block sheet built below).
    source_tilesets = copy_source_tilesets(all_tilesets, mod_dir, report)

    # connections from Pokemonium X.Y naming
    by_world = {}
    for m in maps:
        if m["world"]:
            by_world[m["world"]] = m["id"]
    connections: Dict[str, dict] = {}
    for m in maps:
        if not m["world"]:
            continue
        x, y = m["world"]
        cons = {}
        for (dx, dy, dir_) in ((0, -1, "north"), (0, 1, "south"),
                               (-1, 0, "west"), (1, 0, "east")):
            nid = by_world.get((x + dx, y + dy))
            if nid:
                cons[dir_] = {"map": nid}
        connections[m["id"]] = cons

    if args.tileset_id:
        tileset_id = args.tileset_id
    elif len(source_tilesets) == 1:
        tileset_id = safe_filename(source_tilesets[0]["name"]).upper() or "PM_TILES"
    else:
        tileset_id = "PM_TILES"
    if conv.tileset_names_used:
        used = ", ".join(sorted(conv.tileset_names_used))
        report.append(f"used {len(conv.tileset_names_used)} Tiled tileset(s): {used}")
    sheet = build_sheet(conv)
    rel = f"assets/tilesets/{tileset_id.lower()}.png"
    abs_img = os.path.join(mod_dir, *rel.split("/"))
    os.makedirs(os.path.dirname(abs_img), exist_ok=True)
    sheet.save(abs_img)
    # Quick sanity: fully transparent atlas means GID/columns still broken.
    extrema = sheet.getextrema()
    a_ext = extrema[3] if len(extrema) == 4 else (0, 0)
    if a_ext == (0, 0):
        report.append(
            "WARNING: merged tileset atlas is fully transparent — check "
            "tileset columns / image paths")
    report.append(f"tileset {tileset_id}: {len(conv.block_tiles)} blocks, "
                  f"{len(conv.sheet_tiles)} 8x8 tiles -> {rel}")
    # Dedupe noisy per-tile notes
    seen_notes = set()
    for note in conv.notes:
        if note in seen_notes:
            continue
        seen_notes.add(note)
        report.append(note)
        if len(seen_notes) >= 40:
            break

    # assign indices
    for i, m in enumerate(maps):
        m["index"] = 1000 + i

    out = emit_result_lua(mod_dir, tileset_id, rel, conv, maps, connections,
                          report, sheet.size, source_tilesets)
    # also stitch indices into result by rewriting — indices are in maps list
    # already available when content editor merges; include index in lua:
    # re-emit quickly with index field
    text = open(out, encoding="utf-8").read()
    for m in maps:
        needle = f"[{lua_str(m['id'])}] = {{"
        repl = (f"[{lua_str(m['id'])}] = {{\n"
                f"      index = {m['index']},")
        text = text.replace(needle, repl, 1)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(text)

    print("\n".join(report))
    print(f"wrote {out}")
    print("Open the mod in the content editor (or re-Save) to merge + emit main.lua.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
