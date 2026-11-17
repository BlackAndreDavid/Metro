#!/usr/bin/env python3
"""Temporary art pipeline: describe -> generate 2/3 candidates -> select -> simplify.
All credentials come from environment variables; never stored in manifests.
"""
import argparse
import base64
from collections import Counter, deque
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import tempfile
import urllib.request
from PIL import Image

STYLE = Path(__file__).with_name('art') / 'style.json'

def describe(subject, purpose, frames=1):
    style = json.loads(STYLE.read_text())
    return dict(style=style['name'], subject=subject, purpose=purpose, frames=frames,
                prompt=f"{style['prompt']} Subject: {subject}. Function: {purpose}. "
                       f"Produce {frames} equal-size animation frame(s), aligned feet and unchanged camera, palette and proportions. "
                       "For multiple frames use a single horizontal strip, one pose per cell, no labels.")

def generate(prompt, count, output):
    """OpenAI-compatible images API; one request per candidate for backend compatibility."""
    key = os.environ.get('OPENAI_API_KEY')
    if not key:
        raise ValueError('Set OPENAI_API_KEY to generate images; prepare/simplify/select work offline.')
    endpoint = os.environ.get('OPENAI_BASE_URL', 'https://api.openai.com/v1').rstrip('/')
    model = os.environ.get('ART_IMAGE_MODEL', json.loads(STYLE.read_text())['model'])
    paths = []
    for index in range(count):
        payload = json.dumps(dict(model=model, prompt=prompt, n=1, size='1024x1024',
                                  background='transparent')).encode()
        req = urllib.request.Request(endpoint + '/images/generations', data=payload,
                                     headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=300) as response:
            result = json.load(response)['data'][0]
        if 'b64_json' in result:
            data = base64.b64decode(result['b64_json'])
        else:
            with urllib.request.urlopen(result['url'], timeout=120) as response:
                data = response.read()
        path = output / f'candidate_{index + 1}.png'
        path.write_bytes(data)
        # Decode before counting it as a candidate.
        with Image.open(path) as image:
            image.verify()
        paths.append(path)
    return paths

def region_medians(image, tolerance=24, minimum=12):
    """Connected similar-color regions become their per-channel median, preserving alpha."""
    image = image.convert('RGBA')
    width, height = image.size
    pixels = list(image.getdata())
    visited = bytearray(width * height)
    for start, seed in enumerate(pixels):
        if visited[start] or seed[3] < 128:
            continue
        visited[start] = 1
        queue, members = deque([start]), []
        while queue:
            index = queue.popleft()
            members.append(index)
            x, y = index % width, index // width
            for other in ((index-1 if x else -1), (index+1 if x+1 < width else -1),
                          (index-width if y else -1), (index+width if y+1 < height else -1)):
                if other < 0 or visited[other] or pixels[other][3] < 128:
                    continue
                color = pixels[other]
                if sum((color[c]-seed[c])**2 for c in range(3)) <= tolerance**2:
                    visited[other] = 1
                    queue.append(other)
        if len(members) >= minimum:
            median = tuple(int(statistics.median(pixels[i][c] for i in members)) for c in range(3))
            for index in members:
                pixels[index] = median + (pixels[index][3],)
    image.putdata(pixels)
    return image

def detect_block(image):
    """Estimate the smallest repeated pixel cluster from horizontal/vertical color runs."""
    lengths = Counter()
    px = image.load()
    for vertical in [False, True]:
        major, minor = image.size if vertical else image.size[::-1]
        for line in range(0, major, max(1, major//64)):
            run, previous = 0, None
            for index in range(minor):
                color = px[line,index] if vertical else px[index,line]
                if color == previous:
                    run += 1
                else:
                    if previous and previous[3] >= 128 and 2 <= run <= 16:
                        lengths[run] += 1
                    previous, run = color, 1
    return lengths.most_common(1)[0][0] if lengths else 1

def simplify(image, target=(48,80), colors=18, block=0, tolerance=24, crop_bounds=None):
    image = image.convert('RGBA')
    image.putalpha(image.getchannel('A').point(lambda a: 255 if a >= 128 else 0))
    bounds = crop_bounds or image.getchannel('A').getbbox()
    if not bounds:
        raise ValueError('Candidate is fully transparent')
    image = image.crop(bounds)
    # Reserve a one-pixel gutter, keep the whole figure and preserve aspect ratio.
    scale = min((target[0]-2)/image.width, (target[1]-2)/image.height)
    size = (max(1, round(image.width*scale)), max(1, round(image.height*scale)))
    image = image.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', target)
    canvas.alpha_composite(image, ((target[0]-image.width)//2, target[1]-image.height-1))
    canvas = region_medians(canvas, tolerance)
    canvas = canvas.quantize(colors=colors+1, method=Image.Quantize.FASTOCTREE).convert('RGBA')
    block = block or detect_block(canvas)
    return dominant_blocks(canvas,block), block

def dominant_blocks(image, block):
    result = Image.new('RGBA',image.size)
    for y in range(0,image.height,block):
        for x in range(0,image.width,block):
            bounds = (x,y,min(x+block,image.width),min(y+block,image.height))
            dominant = Counter(image.crop(bounds).getdata()).most_common(1)[0][0]
            dominant = dominant[:3] + (255 if dominant[3] >= 128 else 0,)
            result.paste(dominant,bounds)
    return result

def simplify_strip(image, target, colors, block, frames):
    if frames < 1 or image.width < frames: raise ValueError('Invalid frame count')
    image = image.convert('RGBA')
    image.putalpha(image.getchannel('A').point(lambda a: 255 if a >= 128 else 0))
    cells = [image.crop((round(i*image.width/frames),0,round((i+1)*image.width/frames),image.height)) for i in range(frames)]
    boxes = [cell.getchannel('A').getbbox() for cell in cells]
    if any(box is None for box in boxes): raise ValueError('Empty animation frame')
    common = (min(b[0] for b in boxes), min(b[1] for b in boxes),
              max(b[2] for b in boxes), max(b[3] for b in boxes))
    strip = Image.new('RGBA',(target[0]*frames,target[1]))
    for i,cell in enumerate(cells):
        final, block = simplify(cell,target,colors,block,crop_bounds=common)
        strip.alpha_composite(final,(target[0]*i,0))
    # Use one shared palette for the complete animation.
    strip = strip.quantize(colors=colors+1,method=Image.Quantize.FASTOCTREE).convert('RGBA')
    return strip, block

def evaluate(image):
    """Usability heuristic, not a claim to semantic/animation quality. Manual override allowed."""
    rgba = image.convert('RGBA')
    bounds = rgba.getchannel('A').getbbox()
    if not bounds: return {'score': -1, 'reason':'empty'}
    area = sum(p[3] >= 128 for p in rgba.getdata()) / (rgba.width*rgba.height)
    center = abs((bounds[0]+bounds[2])/2/rgba.width-0.5)
    clipped = sum([bounds[0] == 0,bounds[1] == 0,bounds[2] == rgba.width,bounds[3] == rgba.height])
    score = 100 - abs(area-0.4)*70 - center*40 - clipped*8
    return dict(score=round(score,3), foreground_fraction=round(area,3), clipped_edges=clipped)

def select(paths, output, name, target, colors, block, index=None, delete=False, frames=1, keep_source=False):
    output.mkdir(parents=True,exist_ok=True)
    images = [Image.open(p).convert('RGBA') for p in paths]
    evaluations = [evaluate(im) for im in images]
    chosen = index if index is not None else max(range(len(images)), key=lambda i:evaluations[i]['score'])
    if not 0 <= chosen < len(images): raise ValueError('Selection index outside candidate list')
    final, block = simplify_strip(images[chosen],target,colors,block,frames)
    destination = output / f'{name}.png'
    if any(destination.resolve() == Path(p).resolve() for p in paths):
        raise ValueError('Output must differ from candidate inputs')
    final.save(destination)
    if keep_source: images[chosen].save(output / f'{name}_source.png')
    if frames > 1:
        for frame in range(frames):
            final.crop((frame*target[0],0,(frame+1)*target[0],target[1])).save(output / f'{name}_{frame:02d}.png')
    record = dict(selected=chosen, mode='manual' if index is not None else 'usability_heuristic',
                  pixel_block=block, colors=colors, size=target, frames=frames, candidates=[
                      dict(sha256=hashlib.sha256(Path(p).read_bytes()).hexdigest(), **score)
                      for p,score in zip(paths,evaluations)])
    (output / f'{name}.json').write_text(json.dumps(record,indent=2)+'\n')
    for im in images: im.close()
    if delete:
        for candidate_index,p in enumerate(paths):
            if candidate_index != chosen: Path(p).unlink()
    return record

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command',required=True)
    prepare = commands.add_parser('prepare')
    prepare.add_argument('subject'); prepare.add_argument('--purpose',default='game sprite')
    prepare.add_argument('--frames',type=int,default=1); prepare.add_argument('--output',type=Path,required=True)
    for command in ['run','select','simplify']:
        sub = commands.add_parser(command)
        sub.add_argument('--output',type=Path,required=True); sub.add_argument('--name',required=True)
        sub.add_argument('--width',type=int,default=48); sub.add_argument('--height',type=int,default=80)
        sub.add_argument('--frames',type=int,default=1)
        sub.add_argument('--colors',type=int,default=18); sub.add_argument('--block',type=int,default=0)
        if command == 'run':
            sub.add_argument('subject'); sub.add_argument('--purpose',default='game sprite')
            sub.add_argument('--count',type=int,choices=[2,3],default=3)
        else:
            sub.add_argument('inputs',nargs='*',type=Path)
            sub.add_argument('--index',type=int); sub.add_argument('--delete-unselected',action='store_true')
    args = parser.parse_args()
    if args.command == 'prepare':
        if args.frames < 1: parser.error('frames must be positive')
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(describe(args.subject,args.purpose,args.frames),ensure_ascii=False,indent=2)+'\n')
        return
    if min(args.width,args.height) < 3 or not 2 <= args.colors <= 255 or args.block < 0 or args.frames < 1:
        parser.error('Invalid dimensions, palette or block size')
    target = args.width,args.height
    if args.command == 'run':
        args.output.mkdir(parents=True,exist_ok=True)
        description = describe(args.subject,args.purpose,args.frames)
        (args.output / f'{args.name}_prompt.json').write_text(json.dumps(description,indent=2)+'\n')
        with tempfile.TemporaryDirectory(prefix='metro-art-') as scratch:
            candidates = generate(description['prompt'],args.count,Path(scratch))
            result = select(candidates,args.output,args.name,target,args.colors,args.block,frames=args.frames,keep_source=True)
    else:
        if not args.inputs: parser.error('Supply candidate PNG paths')
        if args.command == 'select' and len(args.inputs) not in [2,3]: parser.error('select requires 2 or 3 candidates')
        if args.command == 'simplify' and len(args.inputs) != 1: parser.error('simplify requires one input')
        result = select(args.inputs,args.output,args.name,target,args.colors,args.block,args.index,args.delete_unselected,frames=args.frames)
    print(json.dumps(result))

if __name__ == '__main__':
    main()
