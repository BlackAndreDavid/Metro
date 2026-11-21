#!/usr/bin/env python3
"""Document-scoped saves and save/discard/cancel flows in the shared desktop editor UI."""
import tempfile,subprocess,shutil,json
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2];OUTPUT=ROOT/'test/results/furniture-editor';OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-catalog-browser-') as scratch:
 game=Path(scratch)/'Game';shutil.copytree(ROOT/'Game/content',game/'content');shutil.copytree(ROOT/'Game/assets/textures',game/'assets/textures');shutil.copy2(ROOT/'Game/project.godot',game/'project.godot')
 server=subprocess.Popen(['python3','tools/editors/server.py','--project',str(game),'--port','0','--no-browser'],cwd=ROOT,stdout=subprocess.PIPE,text=True)
 try:
  url=server.stdout.readline().strip().split('Metro editors: ',1)[1]
  with sync_playwright() as playwright:
   browser=playwright.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=browser.new_page(viewport={'width':1600,'height':1400});errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.goto(url);page.wait_for_selector('#customerCards button')
   page.set_default_timeout(12000)
   page.click('#furnitureTab');page.wait_for_selector('#furnitureMask')
   page.locator('#catalogCards [data-catalog-id=preparation]').click();assert page.locator('#furnitureRules input[data-field=distance]').input_value()=='3'
   page.locator('#furnitureRules input[data-field=distance]').fill('4');page.click('#saveAll');page.wait_for_function('!EditorSession.hasChanges()&&!EditorSession.busy')
   defs=json.loads((game/'content/furniture.json').read_text())['furniture'];assert next(v for v in defs if v['id']=='preparation')['distance_rules'][0]['distance']==4
   page.click('#newCatalog');page.locator('#catalogForm input[data-field=id]').fill('browser_furniture');page.locator('#catalogForm input[data-field=name]').fill('动画储物家具')
   page.get_by_role('button',name='墙面占位',exact=True).click();grid=page.locator('#furnitureMask');grid.scroll_into_view_if_needed();grid.click(position={'x':5,'y':5})
   assert page.evaluate('C.data.wall_cells.length===1&&C.data.floor_cells.length===4')
   page.locator('#catalogForm select[data-field=item_id]').select_option('water');page.locator('#catalogForm select[data-field=interaction]').select_option('storage')
   page.get_by_text('具有储物功能',exact=True).locator('input').check()
   from PIL import Image
   import io,base64
   images=[Image.new('RGBA',(16,16),color) for color in ['red','green','blue']];buffer=io.BytesIO();images[0].save(buffer,format='GIF',save_all=True,append_images=images[1:],duration=[100,200,300],loop=0)
   gif=Path(scratch)/'furniture.gif';gif.write_bytes(buffer.getvalue());page.set_input_files('#contentUpload',str(gif));page.click('#uploadContent');page.wait_for_function('C.data.animation.frames===3')
   assert page.evaluate('C.data.animation.columns')==2 and page.evaluate('C.data.animation.durations')==[100,200,300]
   # Manipulate the animated frame with the same camera transform used for rendering.
   before=page.evaluate('structuredClone(furnitureBinding())');assert before['width']==.5 and before['height']==.5
   page.evaluate('G.viewZoom=4;G.viewPan=[120,80];drawCatalogPreview()')
   def drag_texture(start,end):
    canvas=page.locator('#catalogPreview');canvas.scroll_into_view_if_needed();box=canvas.bounding_box()
    def screen(point):
     at=page.evaluate('p=>p.map((v,i)=>v*G.viewZoom+G.viewPan[i])',point)
     return box['x']+at[0]*box['width']/600,box['y']+at[1]*box['height']/340
    page.mouse.move(*screen(start));page.mouse.down();page.mouse.move(*screen(end),steps=12);page.mouse.up()
   center=page.evaluate('furnitureCenter(furnitureBinding())');drag_texture(center,[center[0]+16,center[1]+8]);moved=page.evaluate('structuredClone(C.data.texture_binding)');assert abs(moved['x']-.5)<.01 and abs(moved['y']-.25)<.01
   b=page.evaluate('structuredClone(C.data.texture_binding)');center=page.evaluate('furnitureCenter(furnitureBinding())');corner=[center[0]+b['width']*16,center[1]+b['height']*16];drag_texture(corner,[corner[0]+6,corner[1]+6]);scaled=page.evaluate('structuredClone(C.data.texture_binding)');assert scaled['width']>b['width'] and abs(scaled['width']/scaled['height']-b['width']/b['height'])<.01
   center=page.evaluate('furnitureCenter(furnitureBinding())');handle=[center[0],center[1]-scaled['height']*16-18];drag_texture(handle,[center[0]+scaled['height']*16+18,center[1]]);bound=page.evaluate('structuredClone(C.data.texture_binding)');assert abs(bound['rotation']-90)<2
   page.get_by_role('button',name='墙面占位',exact=True).click();grid=page.locator('#furnitureMask');grid.scroll_into_view_if_needed();r=grid.bounding_box();grid.click(position={'x':56*r['width']/560,'y':8*r['height']/192});assert page.evaluate('C.data.width===4') and page.evaluate('structuredClone(C.data.texture_binding)')==bound
   page.click('#saveAll');page.wait_for_function('!EditorSession.hasChanges()&&!EditorSession.busy')
   defs=json.loads((game/'content/furniture.json').read_text())['furniture'];furniture=next(v for v in defs if v['id']=='browser_furniture');assert furniture['storage']=={'width':4,'height':4} and furniture['item_id']=='water' and furniture['texture_binding']==bound
   items=json.loads((game/'content/items.json').read_text())['items'];water=next(v for v in items if v['id']=='water');assert water['furniture_kind']=='browser_furniture' and water['texture']!=furniture['texture']
   page.locator('#catalogPreview').screenshot(path=str(OUTPUT/'animated-furniture.png'))
   broken={**furniture,'distance_rules':[{'target_type':'furniture','target':'missing','relation':'require','distance':3}]};response=page.request.post(url+'/api/furniture',data=broken,headers={'X-Editor-Token':page.evaluate('S.project.token')});assert response.status==400
   page.reload();page.wait_for_selector('#customerCards button');page.click('#furnitureTab');page.locator('#catalogCards [data-catalog-id=browser_furniture]').click();assert page.evaluate('C.data.animation.frames===3&&C.data.wall_cells.length===2')
   assert page.evaluate('C.data.texture_binding.rotation')==bound['rotation']
   dock=page.locator('#saveAll').bounding_box();assert abs(dock['width']-285)<1 and abs(dock['x']+dock['width']-1584)<1
   page.set_viewport_size({'width':900,'height':650});dock=page.locator('#saveAll').bounding_box();assert abs(dock['width']-285)<1 and abs(dock['x']+dock['width']-884)<1 and dock['y']>550
   assert not errors,errors
   print('FURNITURE_EDITOR_OK: dual masks, generic distance rules, storage, item linkage, GIF grid animation, manual texture drag/scale/rotate, stable binding, right save dock, validation and persistence')
   browser.close()
 finally:server.terminate();server.wait(timeout=5)
