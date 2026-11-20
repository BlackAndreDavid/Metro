#!/usr/bin/env python3
"""Real mouse flows for monster/item/building editors, offsets, weighted cabinets and +/- pairs."""
import tempfile,subprocess,shutil,json
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2];OUTPUT=ROOT/'test/results/catalog-ui';OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-catalog-browser-') as scratch:
 game=Path(scratch)/'Game';shutil.copytree(ROOT/'Game/content',game/'content');shutil.copytree(ROOT/'Game/assets/textures',game/'assets/textures');shutil.copy2(ROOT/'Game/project.godot',game/'project.godot')
 server=subprocess.Popen(['python3','tools/editors/server.py','--project',str(game),'--port','0','--no-browser'],cwd=ROOT,stdout=subprocess.PIPE,text=True)
 try:
  url=server.stdout.readline().strip().split('Metro editors: ',1)[1]
  with sync_playwright() as playwright:
   browser=playwright.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=browser.new_page(viewport={'width':1600,'height':1400});errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.goto(url);page.wait_for_selector('#customerCards button')
   def fill(name,value):page.locator('#catalogForm input[data-field="'+name+'"]').fill(str(value))
   def save(id):page.click('#saveCatalog');page.wait_for_selector('#catalogCards [data-catalog-id="'+id+'"]')
   def drag_preview(start,end):
    canvas=page.locator('#catalogPreview');canvas.scroll_into_view_if_needed();box=canvas.bounding_box()
    def screen(p):
     p=page.evaluate('p=>p.map((v,i)=>v*G.viewZoom+G.viewPan[i])',p)
     return (box['x']+p[0]*box['width']/600,box['y']+p[1]*box['height']/340)
    page.mouse.move(*screen(start));page.mouse.down();page.mouse.move(*screen(end),steps=10);page.mouse.up()
   def choose_art(name):
    if not page.locator('#artChoices').is_visible():page.locator('details:has(#artChoices) > summary').click()
    page.locator('#artChoices [data-art="'+name+'"]').click()
   def drag_asset(selector,x,y):
    canvas=page.locator('#map');canvas.scroll_into_view_if_needed();box=canvas.bounding_box();page.locator(selector).drag_to(canvas,target_position={'x':x/1000*box['width'],'y':y/510*box['height']})
   page.click('#enemyTab');page.click('#newCatalog');fill('id','browser_rat');fill('name','浏览器鼠');fill('patrol_speed',77);fill('cone_length',300);fill('collision_width',120);choose_art('mutant_crawler');save('browser_rat')
   enemies=json.loads((game/'content/enemies.json').read_text())['enemies'];rat=next(e for e in enemies if e['id']=='browser_rat');assert rat['movement']['patrol_speed']==77 and rat['alert']['cone_length']==300 and 'mutant_crawler' in rat['sprite']['texture']
   page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('恢复')");page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('删除')")
   page.click('#itemTab');page.click('#newCatalog');fill('id','browser_item');fill('name','浏览器物资');fill('price',42.5);grid=page.locator('#itemFootprint');grid.scroll_into_view_if_needed();box=grid.bounding_box();page.mouse.move(box['x']+8,box['y']+8);page.mouse.down();page.mouse.move(box['x']+42,box['y']+70,steps=8);page.mouse.up();assert page.evaluate('C.data.width===2&&C.data.height===3');page.get_by_role('button',name='旋转预览',exact=True).click();assert page.evaluate('C.previewRotated');page.get_by_role('button',name='镜像预览',exact=True).click();assert page.evaluate('C.previewMirrored');choose_art('medkit');assert page.evaluate('C.previewRotated&&C.previewMirrored');page.locator('#catalogPreview').screenshot(path=str(OUTPUT/'item-footprint-preview.png'));save('browser_item')
   item=next(e for e in json.loads((game/'content/items.json').read_text())['items'] if e['id']=='browser_item');assert (item['price'],item['width'],item['height'])==(42.5,2,3)
   page.get_by_role('button',name='－ 删除格子',exact=True).click();grid=page.locator('#itemFootprint');grid.scroll_into_view_if_needed();box=grid.bounding_box();grid.click(position={'x':42,'y':14});assert page.evaluate('C.data.cells.length===5&&!C.data.cells.some(c=>c[0]===1&&c[1]===0)')
   page.get_by_role('button',name='拖动贴图',exact=True).click();before=page.evaluate('structuredClone(C.data.texture_binding)');center=page.evaluate('stageXY([C.data.texture_binding.x+C.data.texture_binding.width/2,C.data.texture_binding.y+C.data.texture_binding.height/2])');drag_preview(center,[center[0]+32,center[1]+16]);assert page.evaluate('C.data.texture_binding.x')>before['x']+.8
   page.get_by_role('button',name='缩放贴图',exact=True).click();edge=page.evaluate('stageXY([C.data.texture_binding.x+C.data.texture_binding.width,C.data.texture_binding.y+C.data.texture_binding.height])');drag_preview(edge,[edge[0]+20,edge[1]+20]);assert page.evaluate('C.data.texture_binding.width')>before['width']
   page.get_by_role('button',name='旋转贴图',exact=True).click();handle=page.evaluate('(()=>{const b=C.data.texture_binding,c=stageXY([b.x+b.width/2,b.y+b.height/2]);return [c[0],c[1]-b.height*16-18]})()');drag_preview(handle,[handle[0]+35,handle[1]+12]);assert abs(page.evaluate('C.data.texture_binding.rotation'))>5
   page.click('#saveCatalog');page.wait_for_function("S.project.items.find(i=>i.id==='browser_item')?.cells?.length===5")
   stored=next(i for i in json.loads((game/'content/items.json').read_text())['items'] if i['id']=='browser_item');assert len(stored['cells'])==5 and abs(stored['texture_binding']['rotation'])>5
   page.locator('#catalogPreview').screenshot(path=str(OUTPUT/'irregular-bound-item.png'))
   before=page.evaluate('JSON.stringify(C.data)');page.get_by_role('button',name='＋ 展示放大',exact=True).click();assert page.evaluate('G.viewZoom')>1;assert page.evaluate('JSON.stringify(C.data)')==before
   page.get_by_role('button',name='拖动贴图',exact=True).click();center=page.evaluate('stageXY([C.data.texture_binding.x+C.data.texture_binding.width/2,C.data.texture_binding.y+C.data.texture_binding.height/2])');page.evaluate('p=>zoomPreview(2,p)',center);old_x=page.evaluate('C.data.texture_binding.x');drag_preview(center,[center[0]+16,center[1]]);assert .3<page.evaluate('C.data.texture_binding.x')-old_x<.7
   page.get_by_role('button',name='重置视图',exact=True).click();assert page.evaluate('G.viewZoom')==1
   before=(game/'content/items.json').read_bytes();fill('id','water');page.wait_for_function("document.getElementById('itemIdStatus').textContent.includes('占用')");page.click('#saveCatalog');assert (game/'content/items.json').read_bytes()==before
   fill('id','browser_renamed');page.click('#saveCatalog');page.wait_for_function("S.project.items.some(i=>i.id==='browser_renamed')")
   renamed=next(i for i in json.loads((game/'content/items.json').read_text())['items'] if i['id']=='browser_renamed');assert renamed['runtime_id']=='browser_item' and 'browser_item' in renamed['aliases']
   response=page.request.post(url+'/api/item',data={**renamed,'id':'water','_original_id':'browser_renamed'},headers={'X-Editor-Token':page.evaluate('S.project.token')});assert response.status==400
   fill('id','browser_item');page.click('#saveCatalog');page.wait_for_function("S.project.items.some(i=>i.id==='browser_item')")


   page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('恢复')");page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('删除')")
   page.click('#buildingTab');page.click('#newCatalog');fill('id','browser_house');fill('name','浏览器储物楼');page.locator('#catalogForm > label input[data-field=width]').fill('240');page.get_by_role('button',name='＋ 添加楼层',exact=True).click();page.locator('#catalogForm fieldset input[data-field=width]').fill('240');page.locator('#catalogForm fieldset input[data-field=height]').fill('220');choose_art('grow_cabinet');page.click('#clearBuildingTexture')
   page.click('#addLootPoint');page.click('#addLootPoint');page.click('#removeLootPoint');page.locator('#lootPointForm input[data-field=x]').fill('120');page.locator('#lootPointForm input[data-field=floor]').fill('1');page.locator('#lootPointForm input[data-field=chance]').fill('0.75');page.locator('#lootPointForm input[data-field=rolls]').fill('2')
   page.locator('#lootItemCards [data-loot-item=browser_item]').drag_to(page.locator('#catalogPreview'));page.locator('#lootChoices input[data-field=weight]').last.fill('9');save('browser_house')
   building=next(e for e in json.loads((game/'content/building_templates.json').read_text())['templates'] if e['id']=='browser_house');assert len(building['loot_points'])==1 and building['loot_points'][0]['choices'][-1]=={'kind':'browser_item','weight':9},building
   page.get_by_role('button',name='＋ 添加楼层',exact=True).click();page.get_by_role('button',name='－ 减少楼层',exact=True).click();page.locator('[data-floor-index="1"]').fill('145');page.locator('[data-floor-index="1"]').press('Tab');assert page.evaluate('C.data.floor_positions[1]')==145
   page.get_by_role('button',name='弧线掉落区域',exact=True).click();control=page.evaluate('stageXY([selectedPoint().region.control[0],floorY(selectedPoint().floor)+selectedPoint().region.control[1]])');drag_preview(control,[control[0]+12,control[1]-10]);assert page.evaluate('selectedPoint().region.control[1]')>40
   page.click('[data-building-layer=textures]');assert page.locator('#bindingFields').is_visible();choose_art('grow_cabinet');page.get_by_role('button',name='拖动贴图',exact=True).click();center=page.evaluate('(()=>{const b=ensureBinding();return stageXY([b.x+b.width/2,b.y+b.height/2])})()');drag_preview(center,[center[0]+10,center[1]-10]);assert page.evaluate('C.data.texture_binding.x>0&&C.data.texture_binding.y>0');page.click('[data-building-layer=physics]');assert not page.locator('#bindingFields').count();page.locator('#catalogPreview').screenshot(path=str(OUTPUT/'layered-building-regions.png'))
   page.click('#saveCatalog');page.wait_for_function("S.project.building_templates.find(i=>i.id==='browser_house')?.floor_positions?.[1]===145")
   building=next(e for e in json.loads((game/'content/building_templates.json').read_text())['templates'] if e['id']=='browser_house');assert building['loot_points'][0]['region']['type']=='arc'

   page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('恢复')");page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('删除')")
   page.locator('#lootEditor').scroll_into_view_if_needed();page.screenshot(path=str(OUTPUT/'building-cabinets.png'),full_page=True)
   page.click('#levelTab');page.click('#chooseStation');page.fill('#stationSearch','南京东路');page.locator('g[data-station="南京东路"] circle').last.click();page.wait_for_function("document.getElementById('stationBadge').textContent.includes('南京东路')")
   assert not page.locator('#objectPalette [data-asset=loot]').count()
   canvas=page.locator('#map');canvas.scroll_into_view_if_needed();box=canvas.bounding_box();canvas.click(position={'x':500/1000*box['width'],'y':365/510*box['height']})
   page.fill('#streetStart','200');page.click('#startLater');page.click('#startEarlier');assert page.locator('#streetStart').input_value()=='200'
   canvas=page.locator('#map');canvas.scroll_into_view_if_needed();box=canvas.bounding_box();start_x=20+200*960/1880+10;start_y=20+2*490/3+12
   page.mouse.move(box['x']+start_x/1000*box['width'],box['y']+start_y/510*box['height']);page.mouse.down();page.mouse.move(box['x']+(start_x+40)/1000*box['width'],box['y']+start_y/510*box['height'],steps=10);page.mouse.up();assert page.locator('#streetStart').input_value()=='280'
   page.fill('#streetStart','200');page.click('#stationBadge')
   drag_asset('#objectPalette [data-asset=browser_rat]',400,420);drag_asset('#buildingPalette [data-asset=browser_house]',180,120)
   page.get_by_role('button',name='编辑此建筑 · 贴图/碰撞/柜子').click();page.locator('#lootPointForm input[data-field=chance]').fill('1');page.click('#saveCatalog');page.click('#saveLevel');page.wait_for_function("document.getElementById('status').textContent.includes('关卡已保存')")
   registry=json.loads((game/'content/registry.json').read_text());level=json.loads((game/registry['stations']['南京东路']['level'][6:]).read_text())
   assert level['street_starts'][2]==200 and any(e['enemy']=='browser_rat' and e['row']==2 for e in level['monsters'])
   assert level['loot']==[];placed=next(b for b in level['buildings'] if b.get('template_id')=='browser_house');assert placed['loot_points'][0]['chance']==1
   page.locator('#map').scroll_into_view_if_needed();page.screenshot(path=str(OUTPUT/'offsets-and-monsters.png'),full_page=True)
   drag_asset('#objectPalette [data-asset=spawn_points]',470,420)
   page.get_by_role('button',name='编辑物资类型与权重').click();page.get_by_role('button',name='散落物资',exact=True).click();page.locator('#lootPointForm input[data-field=chance]').fill('0.9');page.click('#saveCatalog');page.click('#saveLevel');page.wait_for_function("document.getElementById('status').textContent.includes('关卡已保存')")
   level=json.loads((game/registry['stations']['南京东路']['level'][6:]).read_text());assert any(p['container']=='loose' and p['chance']==.9 for p in level['spawn_points'])
   page.click('#customerTab')
   page.locator('#sellCategories details[data-trade-category=supplies] summary').click()
   page.locator('#sellCategories input[data-trade-item=water]').fill('7')
   page.locator('#sellCategories input[data-trade-item=ration]').fill('0')
   page.locator('#sellCategories').screenshot(path=str(OUTPUT/'customer-item-list.png'));customer_id=page.evaluate('S.customer.id');page.click('#saveCustomer');page.wait_for_function("S.project.customers.find(c=>c.id===S.customer.id)?.sell_item_weights?.supplies?.water===7")
   saved_customer=next(c for c in json.loads((game/'content/customers.json').read_text())['customers'] if c['id']==customer_id)
   assert saved_customer['sell_item_weights']['supplies']['water']==7 and saved_customer['sell_item_weights']['supplies']['ration']==0
   page.click('#customerTab');page.get_by_role('button',name='－ 删除当前顾客（归档）').click();page.wait_for_function("[...document.querySelectorAll('button')].some(b=>b.textContent==='恢复当前顾客')");page.get_by_role('button',name='恢复当前顾客').click()
   assert not errors,errors;print('CONTENT_CATALOG_BROWSER_OK: monster/item/building CRUD, sprite selection, weighted cabinets, offset +/- controls, monster placement, building instance editing, customer archival');browser.close()
 finally:server.terminate();server.wait(timeout=10)
