#!/usr/bin/env python3
"""Export the first frame of the project's normal-blend RGBA Aseprite art.

Requires Pillow. Unsupported layer/cel formats fail explicitly; source files
are never changed. Full transparent canvases preserve furniture coordinates.
"""
from pathlib import Path
import struct
import zlib
from PIL import Image


def render(source):
    data = source.read_bytes()
    _, magic, frames, width, height, depth = struct.unpack_from('<I5H', data)
    if magic != 0xA5E0 or frames < 1 or depth != 32:
        raise ValueError(f'{source}: expected RGBA Aseprite')
    frame_size, frame_magic, old_count = struct.unpack_from('<IHH', data, 128)
    if frame_magic != 0xF1FA:
        raise ValueError('Invalid frame')
    count = struct.unpack_from('<I', data, 140)[0] or old_count
    layers, cels = [], []
    cursor = 144
    for _ in range(count):
        size, kind = struct.unpack_from('<IH', data, cursor)
        chunk = data[cursor + 6:cursor + size]
        if kind == 0x2004:
            flags, layer_type, child_level, _, _, blend = struct.unpack_from('<6H', chunk)
            if layer_type != 0 or child_level != 0 or blend != 0:
                raise ValueError('Only flat, normal-blend image layers are supported; export with Aseprite CLI for other formats')
            layers.append((bool(flags & 1), chunk[12]))
        elif kind == 0x2005:
            layer, x, y, opacity, cel_type = struct.unpack_from('<HhhBH', chunk)
            if cel_type not in (0, 2):
                raise ValueError('Linked/tilemap cels require Aseprite CLI')
            w, h = struct.unpack_from('<HH', chunk, 16)
            raw = chunk[20:] if cel_type == 0 else zlib.decompress(chunk[20:])
            cels.append((layer, x, y, opacity, Image.frombytes('RGBA', (w, h), raw)))
        cursor += size
    if cursor != 128 + frame_size:
        raise ValueError('Invalid frame size')
    canvas = Image.new('RGBA', (width, height))
    for layer, x, y, opacity, image in sorted(cels, key=lambda cel: cel[0]):
        visible, layer_opacity = layers[layer]
        if not visible:
            continue
        alpha = opacity * layer_opacity / (255 * 255)
        if alpha != 1:
            image.putalpha(image.getchannel('A').point(lambda value: round(value * alpha)))
        canvas.alpha_composite(image, (x, y))
    return canvas


def export(source, target):
    canvas = render(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target)
    print(f'{source.name} -> {target.name}, {canvas.size}, visible bounds={canvas.getbbox()}')


if __name__ == '__main__':
    assets = Path(__file__).resolve().parents[1] / 'Game/assets'
    for name in ('Carriage', 'BG_Afternoon', 'Bed', 'LapTop', 'Door', 'Locker', 'Screen'):
        export(assets / 'source' / (name + '.aseprite'), assets / 'textures' / (name + '.png'))
