#!/usr/bin/python3
"""Pixel size of an image, read from its header without decoding it.

    imageinfo.py <path>

Prints one JSON object: {"path", "width", "height"}, or {"path", "error"}.
Decoding the image would cost what the wallpaper picker is trying to show
(width x height x 4 bytes), so only the header is read: PNG, JPEG, GIF, WebP
and BMP. Standard library only.
"""

import json
import struct
import sys

# JPEG start-of-frame markers; C4 (Huffman), C8 (reserved) and CC (arithmetic
# coding) share the range but carry no frame size.
SOF = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}


def jpeg_size(f) -> tuple[int, int]:
    f.seek(2)
    while True:
        byte = f.read(1)
        if not byte:
            raise ValueError("no frame header")
        if byte != b"\xff":
            continue
        marker = f.read(1)
        while marker == b"\xff":  # fill bytes
            marker = f.read(1)
        if not marker:
            raise ValueError("no frame header")
        m = marker[0]
        if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:  # no length field
            continue
        length = struct.unpack(">H", f.read(2))[0]
        if m in SOF:
            height, width = struct.unpack(">xHH", f.read(5))
            return width, height
        f.seek(length - 2, 1)


def webp_size(head: bytes) -> tuple[int, int]:
    chunk = head[12:16]
    if chunk == b"VP8 ":
        width, height = struct.unpack("<HH", head[26:30])
        return width & 0x3FFF, height & 0x3FFF
    if chunk == b"VP8L":
        bits = int.from_bytes(head[21:25], "little")
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if chunk == b"VP8X":
        return int.from_bytes(head[24:27], "little") + 1, int.from_bytes(head[27:30], "little") + 1
    raise ValueError("unknown WebP chunk")


def image_size(path: str) -> tuple[int, int]:
    with open(path, "rb") as f:
        head = f.read(32)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            return struct.unpack(">II", head[16:24])
        if head[:2] == b"\xff\xd8":
            return jpeg_size(f)
        if head[:6] in (b"GIF87a", b"GIF89a"):
            return struct.unpack("<HH", head[6:10])
        if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
            return webp_size(head)
        if head[:2] == b"BM":
            width, height = struct.unpack("<ii", head[18:26])
            return width, abs(height)
    raise ValueError("not a PNG, JPEG, GIF, WebP or BMP image")


def main() -> int:
    if len(sys.argv) != 2:
        print(json.dumps({"error": "usage: imageinfo.py <path>"}))
        return 2
    path = sys.argv[1]
    try:
        width, height = image_size(path)
        print(json.dumps({"path": path, "width": width, "height": height}))
        return 0
    except (OSError, ValueError, struct.error) as err:
        print(json.dumps({"path": path, "error": str(err)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
