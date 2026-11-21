#!/usr/bin/env python3
"""Verify preview overlay draw order and view-only visibility toggles."""
import tempfile,subprocess,shutil,json
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2];OUTPUT=ROOT/'test/results/preview-layers';OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-catalog-browser-') as scratch:
 game=Path(scratch)/'Game';shutil.copytree(ROOT/'Game/content',game/'content');shutil.copytree(ROOT/'Game/assets/textures',game/'assets/textures');shutil.copy2(ROOT/'Game/project.godot',game/'project.godot')
 server=subprocess.Popen(['python3','tools/editors/server.py','--project',str(game),'--port','0','--no-browser'],cwd=ROOT,stdout=subprocess.PIPE,text=True)
 try:
  url=server.stdout.readline().strip().split('Metro editors: ',1)[1]
  with sync_playwright() as playwright:
   browser=playwright.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=browser.new_page(viewport={'width':1600,'height':1400});errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.goto(url);page.wait_for_selector('#customerCards button')
   from PIL import Image
   import io,base64
   buffer=io.BytesIO();Image.new('RGBA',(64,64),'red').save(buffer,format='PNG')
   texture=page.evaluate("async data=>(await api('/api/content-image',{kind:'items',id:'preview_probe',data})).texture",'data:image/png;base64,'+base64.b64encode(buffer.getvalue()).decode())
   item={'id':'preview_probe','name':'预览探针','width':2,'height':2,'cells':[[0,0],[1,0],[0,1],[1,1]],'texture':texture,'price':1,'rarity':0,'category':'materials','enabled':True,'active_use':{'action':'none','amount':1},'texture_binding':{'x':0,'y':0,'width':2,'height':2,'rotation':0}}
   page.evaluate("async item=>{await api('/api/item',item);S.project=await api('/api/project')}",item)
   def pixel(x,y):return page.evaluate('p=>Array.from(document.getElementById("catalogPreview").getContext("2d").getImageData(p[0],p[1],1,1).data)',[x,y])[:3]
   page.click('#itemTab');page.locator('#catalogCards [data-catalog-id=preview_probe]').click();page.wait_for_function('imageFor(C.data.texture)?.complete');page.evaluate('drawCatalogPreview()');before=page.evaluate('JSON.stringify(C.data)')
   assert pixel(146,48)!=[255,0,0],pixel(146,48)
   page.uncheck('#previewShowCells');assert pixel(146,48)==[255,0,0],pixel(146,48)
   assert page.evaluate('JSON.stringify(C.data)')==before and not page.evaluate('EditorSession.hasChanges()')
   page.check('#previewShowCells')
   furniture={'id':'preview_furniture','name':'家具预览探针','width':2,'height':2,'texture':texture,'animation':{'frames':1,'columns':1,'fps':6},'floor_cells':[[0,0],[1,0],[0,1],[1,1]],'wall_cells':[],'placement_type':'floor','interaction':'none','function_text':'查看','default_owned':False,'default_placement':None,'storage':None,'item_id':'','distance_rules':[],'effects':[],'texture_binding':item['texture_binding']}
   page.evaluate("async data=>{await api('/api/furniture',data);S.project=await api('/api/project')}",furniture)
   page.click('#furnitureTab');page.locator('#catalogCards [data-catalog-id=preview_furniture]').click();page.wait_for_function('imageFor(C.data.texture)?.complete');page.evaluate('drawCatalogPreview()');before=page.evaluate('JSON.stringify(C.data)')
   assert pixel(46,44)!=[255,0,0],pixel(46,44)
   page.locator('#catalogPreview').screenshot(path=str(OUTPUT/'furniture-mask-above-texture.png'))
   page.uncheck('#previewShowCells');assert pixel(46,44)==[255,0,0],pixel(46,44)
   assert page.evaluate('JSON.stringify(C.data)')==before and not page.evaluate('EditorSession.hasChanges()')
   page.locator('#catalogPreview').screenshot(path=str(OUTPUT/'furniture-texture-only.png'))
   building={'id':'preview_building','name':'建筑预览探针','texture':texture,'width':100,'floors':1,'floor_positions':[0],'wall':'#555555','light_level':1,'collision':{'x':10,'y':10,'width':80,'height':90},'loot_points':[],'texture_binding':{'x':0,'y':0,'width':100,'height':110,'rotation':0}}
   page.evaluate("async data=>{await api('/api/building-template',data);S.project=await api('/api/project')}",building)
   page.click('#buildingTab');page.locator('#catalogCards [data-catalog-id=preview_building]').click();page.wait_for_function('imageFor(C.data.texture)?.complete');page.evaluate('drawCatalogPreview()');before=page.evaluate('JSON.stringify(C.data)')
   assert pixel(251,150)!=[255,0,0],pixel(251,150)
   page.uncheck('#previewShowCollision');assert pixel(251,150)==[255,0,0],pixel(251,150)
   assert page.evaluate('JSON.stringify(C.data)')==before and not page.evaluate('EditorSession.hasChanges()')
   assert not errors,errors
   print('PREVIEW_LAYERS_OK: item/furniture grids and building collision render above textures, toggles restore texture pixels without changing authored data')
   browser.close()
 finally:server.terminate();server.wait(timeout=5)
