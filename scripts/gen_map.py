#!/usr/bin/env python3
"""Convert an ASCII map into memory files (.mem, .coe, preview .png).

Usage: gen_map.py <map.txt> <output prefix>
"""
import os
import sys

from pngio import write_png

MAP_W, MAP_H = 64, 32          # stored map size (must match the hardware)
VISIBLE_W, VISIBLE_H = 40, 25  # tiles on screen at 1280x800 (marked red in the preview)

# char -> (terrain code, 12-bit colour); must match the hardware terrain codes
LEGEND = {
    "~": (0x0, 0x15A),  # ocean
    ".": (0x1, 0x4A3),  # grass
    ",": (0x2, 0xBB5),  # plains
    "f": (0x3, 0x262),  # forest
    "h": (0x4, 0x864),  # hills
    "^": (0x5, 0xAAA),  # mountain
}
COLOR = {code: rgb for code, rgb in LEGEND.values()}


def load(path):
    rows = [line.rstrip("\n") for line in open(path, encoding="utf-8")]
    rows = [r for r in rows if r and not r.startswith("#")]
    if len(rows) > MAP_H:
        sys.exit(f"{path}: {len(rows)} rows, max is {MAP_H}")
    grid = [[0] * MAP_W for _ in range(MAP_H)]
    for y, row in enumerate(rows):
        if len(row) > MAP_W:
            sys.exit(f"{path}:{y + 1}: {len(row)} columns, max is {MAP_W}")
        for x, ch in enumerate(row):
            if ch not in LEGEND:
                sys.exit(f"{path}:{y + 1}:{x + 1}: unknown terrain '{ch}' (use one of {''.join(LEGEND)})")
            grid[y][x] = LEGEND[ch][0]
    return grid, len(rows[0]) if rows else 0, len(rows)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    grid, w, h = load(src)
    flat = [grid[y][x] for y in range(MAP_H) for x in range(MAP_W)]

    with open(out + ".mem", "w") as f:
        f.write("\n".join(f"{v:x}" for v in flat) + "\n")

    with open(out + ".coe", "w") as f:
        f.write("memory_initialization_radix=16;\nmemory_initialization_vector=\n")
        f.write(",\n".join(f"{v:x}" for v in flat) + ";\n")

    s = 8  # preview pixels per tile
    img = bytearray()
    for py in range(MAP_H * s):
        for px in range(MAP_W * s):
            c = COLOR[grid[py // s][px // s]]
            img += bytes((((c >> 8) & 0xF) * 17, ((c >> 4) & 0xF) * 17, (c & 0xF) * 17))

    # Red border around the part shown on screen (1280x800 -> 40x25 tiles).
    # Everything outside it is padding that only exists in memory.
    vis_w, vis_h = VISIBLE_W * s, VISIBLE_H * s
    for py in range(MAP_H * s):
        for px in range(MAP_W * s):
            on_vertical = py < vis_h + 2 and (px in (0, 1) or px in (vis_w, vis_w + 1))
            on_horizontal = px < vis_w + 2 and (py in (0, 1) or py in (vis_h, vis_h + 1))
            if on_vertical or on_horizontal:
                i = (py * MAP_W * s + px) * 3
                img[i:i + 3] = b"\xff\x00\x00"
    write_png(out + "_preview.png", MAP_W * s, MAP_H * s, img)

    print(f"{src}: {w}x{h} tiles drawn -> {out}.mem / .coe / _preview.png ({MAP_W}x{MAP_H} stored)")


if __name__ == "__main__":
    main()
