#!/usr/bin/env python3
"""Create a simple original SlopNet .icns application icon, stdlib only."""

from pathlib import Path
import math
import struct
import sys
import zlib


def png_chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data +
            struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))


def icon_png(size):
    pixels = bytearray()
    scale = size / 1024
    for y in range(size):
        pixels.append(0)  # PNG filter: none
        for x in range(size):
            full_x = x / scale
            full_y = y / scale
            dx = full_x - 512
            dy = full_y - 512
            distance = math.hypot(dx, dy)
            colour = (8, 18, 34, 255)
            if distance < 420:
                colour = (18, 37, 68, 255)
            if 455 < distance < 490:
                colour = (112, 211, 255, 255)
            for center_x, center_y in ((340, 390), (670, 310), (650, 690), (350, 720)):
                if math.hypot(full_x - center_x, full_y - center_y) < 82:
                    colour = (250, 196, 62, 255)
            pixels.extend(colour)
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) +
            png_chunk(b"IDAT", zlib.compress(bytes(pixels), 9)) +
            png_chunk(b"IEND", b""))


target = Path(sys.argv[1])
entries = ((16, b"icp4"), (32, b"icp5"), (64, b"icp6"),
           (128, b"ic07"), (256, b"ic08"), (512, b"ic09"),
           (1024, b"ic10"))
payload = b"".join(
    icon_type + struct.pack(">I", len(image) + 8) + image
    for size, icon_type in entries
    for image in (icon_png(size),)
)
target.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
