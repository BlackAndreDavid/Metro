#!/usr/bin/env python3
"""Losslessly trim the transparent canvas of a single-frame RGBA Aseprite.

Preserves original layers, cel pixels, opacity and compressed cel data; shifts
cel origins and updates canvas dimensions only. Refuses coordinate-bearing
metadata requiring additional transforms. Requires Pillow, via export_home_art.
"""
import argparse
from pathlib import Path
import struct
import tempfile
from export_home_art import render


def trim(source):
    before = render(source)
    bounds = before.getbbox()
    if bounds is None:
        raise ValueError('Cannot trim an entirely transparent image')
    left, top, right, bottom = bounds
    data = bytearray(source.read_bytes())
    if struct.unpack_from('<H', data, 6)[0] != 1:
        raise ValueError('This tool only supports single-frame assets')
    struct.pack_into('<HH', data, 8, right - left, bottom - top)
    frame_size, _, old_count = struct.unpack_from('<IHH', data, 128)
    count = struct.unpack_from('<I', data, 140)[0] or old_count
    cursor = 144
    for _ in range(count):
        size, kind = struct.unpack_from('<IH', data, cursor)
        if kind in (0x2022, 0x2016, 0x2017):
            raise ValueError('Slices or mask/path metadata require Aseprite UI trimming')
        if kind == 0x2005:
            x, y = struct.unpack_from('<hh', data, cursor + 8)
            struct.pack_into('<hh', data, cursor + 8, x - left, y - top)
        cursor += size
    if cursor != len(data) or cursor != 128 + frame_size:
        raise ValueError('Invalid source size')
    with tempfile.TemporaryDirectory() as directory:
        candidate = Path(directory) / source.name
        candidate.write_bytes(data)
        after = render(candidate)
        if after.size != (right - left, bottom - top) or after.tobytes() != before.crop(bounds).tobytes():
            raise ValueError('Pixel validation failed; original source left unchanged')
    source.write_bytes(data)
    print(f'{source.name}: {before.size} -> {after.size}; removed origin ({left}, {top}); pixels verified')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    trim(parser.parse_args().source)
