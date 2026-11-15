#!/usr/bin/env python3
"""Convert 16x16 text sprites into a memory file (.mem) and a preview .png.

Usage: gen_sprites.py <output prefix> <sprite.txt> ...   (order = sprite number)
"""
import os
import sys

from pngio import write_png

SIZE = 16
TEAM = 0xE22  # preview in Player 1's colour

# char -> (palette index, 12-bit colour), as sprite_color() in game_pkg.sv
LEGEND = {
    ".": (0x0, None),                              # transparent
    "k": (0x1, 0x111),                             # outline
    "P": (0x2, TEAM),                              # player colour
    "p": (0x3, (TEAM >> 1) & 0x777),               # dark player colour
    "w": (0x4, 0xFFF),                             # white
    "s": (0x5, 0xFC9),                             # skin
    "b": (0x6, 0x963),                             # wood
    "d": (0x7, 0x631),                             # dark wood
    "g": (0x8, 0xCCC),                             # steel / stone
    "G": (0x9, 0x888),                             # dark steel / stone
    "y": (0xA, 0xFD2),                             # gold
}


def load(path):
    rows = [line.rstrip("\n") for line in open(path, encoding="utf-8")]
    if len(rows) != SIZE or any(len(r) != SIZE for r in rows):
        sys.exit(f"{path}: must be {SIZE} lines of {SIZE} characters")
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch not in LEGEND:
                sys.exit(f"{path}:{y + 1}:{x + 1}: unknown colour '{ch}' (use one of {''.join(LEGEND)})")
    return rows


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out, paths = sys.argv[1], sys.argv[2:]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    sprites = [load(p) for p in paths]

    # one hex digit per pixel; address = {sprite, row, column}
    with open(out + ".mem", "w") as f:
        for rows in sprites:
            for row in rows:
                f.write("".join(f"{LEGEND[ch][0]:x}\n" for ch in row))

    # preview: sprites side by side, 8x enlarged, on a grey background
    s, gap = 8, 8
    w, h = len(sprites) * (SIZE * s + gap) + gap, SIZE * s + 2 * gap
    img = bytearray(b"\x55" * (w * h * 3))
    for n, rows in enumerate(sprites):
        for py in range(SIZE * s):
            for px in range(SIZE * s):
                c = LEGEND[rows[py // s][px // s]][1]
                if c is None:
                    continue
                i = ((gap + py) * w + gap + n * (SIZE * s + gap) + px) * 3
                img[i:i + 3] = bytes((((c >> 8) & 15) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17))
    write_png(out + "_preview.png", w, h, img)

    print(f"{len(sprites)} sprites -> {out}.mem / _preview.png")


if __name__ == "__main__":
    main()
