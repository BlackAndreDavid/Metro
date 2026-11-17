"""Offline verification of region medians, majority blocks, frame alignment and selection cleanup."""
from pathlib import Path
import importlib.util
import tempfile
import unittest
import base64
import io
import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('art_tool',ROOT/'tools/art_asset_tool.py')
art = importlib.util.module_from_spec(spec); spec.loader.exec_module(art)

class ArtTools(unittest.TestCase):
    def test_similar_area_uses_median_preserving_transparency(self):
        image = Image.new('RGBA',(4,4),(100,110,120,255))
        image.putpixel((1,1),(105,115,125,255)); image.putpixel((3,3),(0,0,0,0))
        result = art.region_medians(image,tolerance=20,minimum=4)
        self.assertEqual(result.getpixel((1,1)),(100,110,120,255))
        self.assertEqual(result.getpixel((3,3))[3],0)
    def test_block_chooses_majority_not_average(self):
        image = Image.new('RGBA',(2,2),(200,0,0,255)); image.putpixel((0,0),(0,0,255,255))
        self.assertEqual(set(art.dominant_blocks(image,2).getdata()),{(200,0,0,255)})
    def test_common_frame_baseline_and_palette(self):
        strip = Image.new('RGBA',(20,12))
        for x in range(3,7):
            for y in range(2,10): strip.putpixel((x,y),(90,140,160,255))
        for x in range(13,17):
            for y in range(5,10): strip.putpixel((x,y),(100,150,170,255))
        result,block = art.simplify_strip(strip,(12,16),8,1,2)
        first = result.crop((0,0,12,16)).getchannel('A').getbbox()
        second = result.crop((12,0,24,16)).getchannel('A').getbbox()
        self.assertEqual(first[3],second[3]); self.assertGreater(second[1],first[1])
        self.assertLessEqual(len(result.getcolors()),9)
    def test_selection_preserves_best_and_discards_others(self):
        with tempfile.TemporaryDirectory() as scratch:
            folder=Path(scratch); paths=[]
            for i in range(3):
                image=Image.new('RGBA',(16,20))
                for x in range(4,12):
                    for y in range(2,19): image.putpixel((x,y),(50+i*30,80,90,255))
                path=folder/f'{i}.png'; image.save(path); paths.append(path)
            result=art.select(paths,folder/'selected','sprite',(16,20),8,1,index=1,delete=True)
            self.assertEqual(result['selected'],1)
            self.assertTrue(paths[1].exists()); self.assertFalse(paths[0].exists()); self.assertFalse(paths[2].exists())
            self.assertTrue((folder/'selected/sprite.png').exists())
            self.assertEqual(len(result['candidates']),3)

    def test_complete_generation_contract_without_external_api(self):
        image=Image.new('RGBA',(32,20))
        for x in list(range(4,12))+list(range(20,28)):
            for y in range(3,19): image.putpixel((x,y),(80,130,140,255))
        buffer=io.BytesIO(); image.save(buffer,format='PNG')
        encoded=base64.b64encode(buffer.getvalue()).decode()
        requests=[]
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_POST(self):
                requests.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
                data=json.dumps({'data':[{'b64_json':encoded}]}).encode()
                self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(data)
        server=HTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        try:
            with tempfile.TemporaryDirectory() as scratch:
                env=os.environ.copy(); env.update(OPENAI_API_KEY='offline-test-secret',OPENAI_BASE_URL=f'http://127.0.0.1:{server.server_port}/v1')
                result=subprocess.run([sys.executable,str(ROOT/'tools/art_asset_tool.py'),'run','mechanic','--count','3','--frames','2','--name','visitor','--width','16','--height','20','--block','1','--output',scratch],env=env,capture_output=True,text=True,timeout=30)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(len(requests),3)
                self.assertIn('2 equal-size animation',requests[0]['prompt'])
                files={p.name for p in Path(scratch).iterdir()}
                self.assertEqual(files,{'visitor.png','visitor_source.png','visitor.json','visitor_prompt.json','visitor_00.png','visitor_01.png'})
                self.assertNotIn('offline-test-secret',(Path(scratch)/'visitor.json').read_text())
        finally:
            server.shutdown(); server.server_close(); thread.join()

if __name__ == '__main__': unittest.main()
