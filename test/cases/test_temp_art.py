"""Validate every aligned Aseprite frame against its runtime PNG, without image generation."""
import json,struct,zlib,unittest,hashlib
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
class TemporaryArt(unittest.TestCase):
 def test_all_classified_aseprite_frames_round_trip(self):
  manifest=json.loads((ROOT/'Game/assets/source/temp/manifest.json').read_text())
  self.assertEqual(len(manifest['sprites']),51)
  self.assertEqual({s['category'] for s in manifest['sprites']},{'characters','monsters','items'})
  for name,digest in manifest['sources'].items():self.assertEqual(hashlib.sha256((ROOT/'Game/assets/source'/name).read_bytes()).hexdigest(),digest)
  for sprite in manifest['sprites']:
   raw=(ROOT/'Game'/sprite['aseprite']).read_bytes();length,magic,count,w,h,depth=struct.unpack_from('<I5H',raw)
   self.assertEqual((length,magic,count,[w,h],depth),(len(raw),0xA5E0,sprite['frames'],sprite['frame_size'],32))
   png=Image.open(ROOT/'Game'/sprite['texture'][6:]).convert('RGBA');self.assertEqual(png.size,(w*count,h));cursor=128
   for frame in range(count):
    size,frame_magic,chunks,duration,_,_=struct.unpack_from('<IHHHHI',raw,cursor);self.assertEqual(frame_magic,0xF1FA);self.assertEqual(duration,120)
    chunk_cursor=cursor+16;found=False
    for _ in range(chunks):
     chunk_size,kind=struct.unpack_from('<IH',raw,chunk_cursor)
     if kind==0x2004:self.assertEqual(struct.unpack_from('<H',raw,chunk_cursor+6)[0]&3,3)
     if kind==0x2005:
      pixels=zlib.decompress(raw[chunk_cursor+26:chunk_cursor+chunk_size]);self.assertEqual(pixels,png.crop((frame*w,0,(frame+1)*w,h)).tobytes());found=True
     chunk_cursor+=chunk_size
    self.assertTrue(found);self.assertEqual(chunk_cursor,cursor+size);cursor+=size
   self.assertEqual(cursor,len(raw))
if __name__=='__main__':unittest.main()
