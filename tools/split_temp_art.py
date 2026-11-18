#!/usr/bin/env python3
"""Classify the two supplied sheets; retain pixels and write aligned animated Aseprite + PNG strips."""
from pathlib import Path
import struct, zlib, json, hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'Game/assets/source'

def chunk(kind,data):return struct.pack('<IH',len(data)+6,kind)+data

def write_aseprite(path,frames,duration=120):
    width,height=frames[0].size;records=[]
    for index,image in enumerate(frames):
        chunks=[]
        if index==0:
            name=path.stem.encode();chunks.append(chunk(0x2004,struct.pack('<6HB3sH',3,0,0,0,0,0,255,b'\0'*3,len(name))+name))
        cel=struct.pack('<HhhBHh5sHH',0,0,0,255,2,0,b'\0'*5,width,height)+zlib.compress(image.convert('RGBA').tobytes())
        chunks.append(chunk(0x2005,cel));body=b''.join(chunks)
        records.append(struct.pack('<IHHHHI',16+len(body),0xF1FA,len(chunks),duration,0,len(chunks))+body)
    header=bytearray(128);struct.pack_into('<I5H',header,0,128+sum(map(len,records)),0xA5E0,len(frames),width,height,32)
    struct.pack_into('<IH',header,14,1,duration);header[34]=header[35]=1
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(header+b''.join(records))

def extract(source,boxes,threshold=96):
    frames=[]
    for box in boxes:
        frame=source.crop(box).convert('RGBA');alpha=frame.getchannel('A');alpha=alpha.point(lambda p: p if p>=threshold else 0);frame.putalpha(alpha)
        bounds=frame.getbbox()
        if not bounds:raise ValueError(f'Empty sprite: {box}')
        frames.append(frame.crop(bounds))
    # Shared bottom-centre anchor. Preserve original pixels; no resampling/recolouring.
    width=max(f.width for f in frames)+4;height=max(f.height for f in frames)+4
    aligned=[]
    for f in frames:
        canvas=Image.new('RGBA',(width,height));canvas.alpha_composite(f,((width-f.width)//2,height-f.height-2));aligned.append(canvas)
    return aligned

def main():
    atlas=Image.open(SOURCE/'atlas_temp.png').convert('RGBA');hero=Image.open(SOURCE/'heroine_temp.png').convert('RGBA');manifest=[]
    def atlas_box(row,col):return (round(col*atlas.width/8),round(row*atlas.height/9),round((col+1)*atlas.width/8),round((row+1)*atlas.height/9))
    def save(category,name,sheet,boxes,reverse=False):
        frames=extract(sheet,boxes);frames=frames[::-1] if reverse else frames
        ase=SOURCE/'temp'/category/(name+'.aseprite');write_aseprite(ase,frames)
        strip=Image.new('RGBA',(frames[0].width*len(frames),frames[0].height))
        for index,frame in enumerate(frames):strip.paste(frame,(index*frame.width,0))
        png=ROOT/'Game/assets/textures/temp'/category/(name+'.png');png.parent.mkdir(parents=True,exist_ok=True);strip.save(png)
        manifest.append(dict(id=name,category=category,source='atlas_temp.png' if sheet is atlas else 'heroine_temp.png',source_boxes=boxes,reverse=reverse,frames=len(frames),frame_size=list(frames[0].size),duration_ms=120,anchor='bottom_center',aseprite=str(ase.relative_to(ROOT/'Game')),texture='res://'+str(png.relative_to(ROOT/'Game'))))
    for name,row,cols in [('suit_walk_left',0,range(4)),('suit_walk_right',0,range(4,8)),('suit_walk_front',1,range(4)),('suit_walk_back',1,range(4,8))]:save('characters',name,atlas,[atlas_box(row,c) for c in cols])
    for name,row,cols in [('mutant_rat',2,range(4)),('hooded_scavenger',2,range(4,8)),('fungus_turret',3,range(4)),('mutant_crawler',3,range(4,8)),('rust_robot',4,range(4))]:save('monsters',name,atlas,[atlas_box(row,c) for c in cols])
    items=[(4,4,['metal_bottle','water_bottle','reagent_flask','hazard_canister']),(5,0,['power_box','single_cell','battery_pair','battery_pack','ration','mushroom_can','herb_tray','supply_crate']),(6,0,['bandage','syringe','capsules','medkit','beacon','battery_cluster','shield_emitter','lens_device']),(7,0,['armor_plate','exoskeleton_frame','battery_core','mutant_tentacle','green_ammo','red_ammo','wood_crate','locked_case']),(8,0,['metro_car','hazmat_helmet','metal_plate','scrap_metal','workbench','bunk','grow_cabinet','credit_card'])]
    for row,start,names in items:
        for col,name in enumerate(names,start):save('items',name,atlas,[atlas_box(row,col)])
    for row,direction in enumerate(['left','right','front','back']):
        top,bottom=[(0,256),(256,512),(512,768),(768,1002)][row]
        save('characters','heroine_walk_'+direction,hero,[(col*256,top,(col+1)*256,bottom) for col in range(4)])
    transition=[(col*256,top,(col+1)*256,bottom) for top,bottom in [(1002,1284),(1284,1536)] for col in range(4)]
    save('characters','heroine_undress',hero,transition);save('characters','heroine_dress',hero,transition,True)
    document={'version':1,'alpha_cutoff':96,'note':'Names classify visible temporary artwork; original sheets retained. Common canvas and bottom-centre anchors per animation.','sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [SOURCE/'atlas_temp.png',SOURCE/'heroine_temp.png']},'sprites':manifest}
    (SOURCE/'temp/manifest.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n')
    print(f'Extracted {len(manifest)} classified Aseprite assets and PNG strips.')
if __name__=='__main__':main()
