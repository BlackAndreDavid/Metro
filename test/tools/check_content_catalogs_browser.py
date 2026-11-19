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
   def choose_art(name):
    if not page.locator('#artChoices').is_visible():page.locator('details:has(#artChoices) > summary').click()
    page.locator('#artChoices [data-art="'+name+'"]').click()
   def drag_asset(selector,x,y):
    canvas=page.locator('#map');canvas.scroll_into_view_if_needed();box=canvas.bounding_box();page.locator(selector).drag_to(canvas,target_position={'x':x/1000*box['width'],'y':y/510*box['height']})
   page.click('#enemyTab');page.click('#newCatalog');fill('id','browser_rat');fill('name','浏览器鼠');fill('patrol_speed',77);fill('cone_length',300);fill('collision_width',120);choose_art('mutant_crawler');save('browser_rat')
   enemies=json.loads((game/'content/enemies.json').read_text())['enemies'];rat=next(e for e in enemies if e['id']=='browser_rat');assert rat['movement']['patrol_speed']==77 and rat['alert']['cone_length']==300 and 'mutant_crawler' in rat['sprite']['texture']
   page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('恢复')");page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('删除')")
   page.click('#itemTab');page.click('#newCatalog');fill('id','browser_item');fill('name','浏览器物资');fill('price',42.5);fill('width',2);fill('height',3);choose_art('medkit');save('browser_item')
   item=next(e for e in json.loads((game/'content/items.json').read_text())['items'] if e['id']=='browser_item');assert (item['price'],item['width'],item['height'])==(42.5,2,3)
   page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('恢复')");page.click('#archiveCatalog');page.wait_for_function("document.getElementById('archiveCatalog').textContent.includes('删除')")
   page.click('#buildingTab');page.click('#newCatalog');fill('id','browser_house');fill('name','浏览器储物楼');page.locator('#catalogForm > label input[data-field=width]').fill('240');fill('floors',2);page.locator('#catalogForm fieldset input[data-field=width]').fill('240');page.locator('#catalogForm fieldset input[data-field=height]').fill('220');choose_art('grow_cabinet');page.click('#clearBuildingTexture')
   page.click('#addLootPoint');page.click('#addLootPoint');page.click('#removeLootPoint');page.locator('#lootPointForm input[data-field=x]').fill('120');page.locator('#lootPointForm input[data-field=floor]').fill('1');page.locator('#lootPointForm input[data-field=chance]').fill('0.75');page.locator('#lootPointForm input[data-field=rolls]').fill('2')
   page.locator('#lootItemCards [data-loot-item=browser_item]').drag_to(page.locator('#catalogPreview'));page.locator('#lootChoices input[data-field=weight]').last.fill('9');save('browser_house')
   building=next(e for e in json.loads((game/'content/building_templates.json').read_text())['templates'] if e['id']=='browser_house');assert len(building['loot_points'])==1 and building['loot_points'][0]['choices'][-1]=={'kind':'browser_item','weight':9},building
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
   page.click('#customerTab');page.get_by_role('button',name='－ 删除当前顾客（归档）').click();page.wait_for_function("[...document.querySelectorAll('button')].some(b=>b.textContent==='恢复当前顾客')");page.get_by_role('button',name='恢复当前顾客').click()
   assert not errors,errors;print('CONTENT_CATALOG_BROWSER_OK: monster/item/building CRUD, sprite selection, weighted cabinets, offset +/- controls, monster placement, building instance editing, customer archival');browser.close()
 finally:server.terminate();server.wait(timeout=10)
