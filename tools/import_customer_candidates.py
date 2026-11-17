#!/usr/bin/env python3
"""Split 3x4 candidate contact sheet, retain four separate chosen customer PNGs."""
import argparse
import json
from pathlib import Path
import tempfile
from PIL import Image
from art_asset_tool import select, evaluate, STYLE

ROLES = ['scavenger','mechanic','commuter','medic']
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sheet',type=Path)
    parser.add_argument('--row',type=int,choices=[0,1,2],required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--reason',required=True)
    args = parser.parse_args()
    sheet = Image.open(args.sheet).convert('RGBA')
    args.source.mkdir(parents=True,exist_ok=True)
    args.output.mkdir(parents=True,exist_ok=True)
    records = {}
    with tempfile.TemporaryDirectory(prefix='metro-customer-') as scratch:
        for column, role in enumerate(ROLES):
            paths = []
            for row in range(3):
                crop = sheet.crop((round(column*sheet.width/4),round(row*sheet.height/3),
                                   round((column+1)*sheet.width/4),round((row+1)*sheet.height/3)))
                path = Path(scratch) / f'{role}_{row}.png'
                crop.save(path); paths.append(path)
            # The retained full-resolution source is independent too.
            retained = Image.open(paths[args.row])
            retained.crop(retained.getchannel('A').getbbox()).save(args.source / f'{role}.png')
            records[role] = select(paths,args.output,role,(48,80),18,1,args.row)
            records[role]['selection_reason'] = args.reason
            # Keep only final PNGs and a single combined audit manifest.
            (args.output / f'{role}.json').unlink()
    manifest = {'style':json.loads(STYLE.read_text())['name'], 'selected_row':args.row,
                'candidate_count_per_role':3,'customers':records,
                'animation':'Runtime depth animation: scale, opacity and brightness; each source is independent.'}
    (args.source / 'generation.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('Exported 4 independent 48x80 sprites and selected sources; temporary candidates discarded.')
if __name__ == '__main__': main()
