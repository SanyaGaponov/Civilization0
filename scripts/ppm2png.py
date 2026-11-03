#!/usr/bin/env python3
"""Convert a binary PPM frame dump to PNG.  Usage: ppm2png.py in.ppm out.png"""
import sys

from pngio import write_png


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    # header: "P6\n<w> <h>\n255\n"
    parts = data.split(b"\n", 3)
    assert parts[0] == b"P6", "not a binary PPM"
    w, h = map(int, parts[1].split())
    write_png(dst, w, h, parts[3][: w * h * 3])
    print(f"{dst}: {w}x{h}")


if __name__ == "__main__":
    main()
