"""pngio.py - tiny PNG writer using only the Python standard library."""
import struct
import zlib


def write_png(path, width, height, rgb):
    """rgb: bytes of length width*height*3, row by row, top to bottom."""
    raw = bytearray()
    stride = width * 3
    for row in range(height):
        raw.append(0)  # filter type: none
        raw += rgb[row * stride:(row + 1) * stride]

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))
