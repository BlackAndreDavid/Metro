#!/usr/bin/env python3
"""Document-scoped saves and save/discard/cancel flows in the shared desktop editor UI."""
import tempfile,subprocess,shutil,json
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2];OUTPUT=ROOT/'test/results/save-sessions';OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-catalog-browser-') as scratch:
 game=Path(scratch)/'Game';shutil.copytree(ROOT/'Game/content',game/'content');shutil.copytree(ROOT/'Game/assets/textures',game/'assets/textures');shutil.copy2(ROOT/'Game/project.godot',game/'project.godot')
 server=subprocess.Popen(['python3','tools/editors/server.py','--project',str(game),'--port','0','--no-browser'],cwd=ROOT,stdout=subprocess.PIPE,text=True)
 try:
  url=server.stdout.readline().strip().split('Metro editors: ',1)[1]
  with sync_playwright() as playwright:
   browser=playwright.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=browser.new_page(viewport={'width':1600,'height':1400});errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.goto(url);page.wait_for_selector('#customerCards button')
   page.set_default_timeout(8000)
   def clean():page.wait_for_function("!EditorSession.hasChanges()")
   def changed():page.wait_for_function("EditorSession.hasChanges()")
   def prompt():page.wait_for_selector('#unsavedDialog[open]')
   def field(key):return page.locator('#catalogForm input[data-field='+key+']')
   def catalogue():return json.loads((game/'content/items.json').read_text())['items']
   page.click('#itemTab');page.wait_for_selector('#catalogView:not([hidden])');clean()
   first=page.evaluate('C.data.id');old_price=page.evaluate('C.data.price');disk=(game/'content/items.json').read_bytes()
   field('price').fill(str(old_price+5));field('name').fill('连续编辑测试');changed()
   assert (game/'content/items.json').read_bytes()==disk
   page.click('#itemTab');assert field('name').input_value()=='连续编辑测试'
   other=page.locator('#catalogCards button').nth(1);other_id=other.get_attribute('data-catalog-id');other.click();prompt();page.locator('#unsavedDialog').screenshot(path=str(OUTPUT/'save-item-prompt.png'))
   page.click('#unsavedCancel');assert page.evaluate('C.data.id')==first;changed()
   page.locator('#catalogCards [data-catalog-id="'+other_id+'"]').click();prompt();page.click('#unsavedSave')
   page.wait_for_function('id=>C.data.id===id',arg=other_id);clean()
   saved=next(i for i in catalogue() if i['id']==first);assert saved['name']=='连续编辑测试' and saved['price']==old_price+5
   field('price').fill('999');page.click('#buildingTab');prompt();page.click('#unsavedDiscard');page.wait_for_function("C.kind==='building_templates'");clean()
   assert next(i for i in catalogue() if i['id']==other_id)['price']!=999
   page.click('#newCatalog');changed();field('name').fill('整栋建筑草稿');page.click('#levelTab');prompt();page.click('#unsavedCancel');assert field('name').input_value()=='整栋建筑草稿'
   page.click('#levelTab');prompt();page.click('#unsavedDiscard');page.wait_for_selector('#levelView:not([hidden])');clean()
   page.evaluate("S.type='buildings';S.entity=0;entityForm()");page.locator('#entityFields input[data-key=name]').fill('无需应用即可切换');page.evaluate('S.entity=1;entityForm()');assert page.evaluate('S.level.buildings[0].name')=='无需应用即可切换';page.evaluate('S.entity=0;entityForm()');page.click('#saveLevel');clean()
   page.get_by_role('button',name='编辑此建筑 · 贴图/碰撞/柜子').click();page.click('#returnToLevel');clean()
   page.get_by_role('button',name='编辑此建筑 · 贴图/碰撞/柜子').click();field('name').fill('子建筑连续调整');page.click('#returnToLevel');changed()
   assert page.evaluate('S.level.buildings[0].name')=='子建筑连续调整'
   original=page.evaluate('S.level.cell_names[W.row].length');page.click('#addColumn');changed()
   page.click('#itemTab');prompt();page.click('#unsavedSave');page.wait_for_selector('#catalogView:not([hidden])');clean()
   registry=json.loads((game/'content/registry.json').read_text());postal=json.loads((game/registry['stations']['邮电新村']['level'][6:]).read_text());assert len(postal['cell_names'][2])==original+1 and postal['buildings'][0]['name']=='子建筑连续调整'
   page.click('#levelTab');clean();page.click('#addColumn');page.click('#chooseStation');page.evaluate("void selectStation('南京东路')");prompt();page.click('#unsavedCancel');assert page.evaluate('S.station')=='邮电新村';page.click('#closeStations')
   page.click('#itemTab');prompt();page.click('#unsavedDiscard');clean()
   field('id').fill('water');changed();page.click('#levelTab');prompt();page.click('#unsavedSave');page.wait_for_function("document.getElementById('unsavedError').textContent.includes('失败')");assert page.locator('#unsavedDialog').is_visible();assert page.locator('#catalogView').is_visible();page.click('#unsavedCancel')
   page.click('#levelTab');prompt();page.click('#unsavedDiscard');clean()
   page.click('#networkTab');page.wait_for_selector('#networkCanvas svg');clean();width=page.evaluate('N.data.canvas.width');page.fill('#networkWidth',str(width+20));page.locator('#networkWidth').press('Tab');changed()
   page.click('#itemTab');prompt();page.click('#unsavedCancel');assert page.locator('#networkView').is_visible()
   page.click('#itemTab');prompt();page.click('#unsavedDiscard');clean();page.click('#networkTab');assert page.evaluate('N.data.canvas.width')==width;clean()
   page.click('#customerTab');clean();customer=page.evaluate('S.customer.id');page.fill('#customerName','客户草稿');changed();page.locator('#customerCards button').nth(1).click();prompt();page.click('#unsavedSave');page.wait_for_function('id=>S.customer.id!==id',arg=customer);clean()
   assert next(c for c in json.loads((game/'content/customers.json').read_text())['customers'] if c['id']==customer)['name']=='客户草稿'
   page.fill('#customerName','关闭测试');page.evaluate('EditorSession.requestClose()');prompt();page.click('#unsavedCancel');page.wait_for_function("EditorSession.closeDecision==='cancelled'")
   page.evaluate('EditorSession.requestClose()');prompt();page.click('#unsavedSave');page.wait_for_function("EditorSession.closeDecision==='approved'");clean()
   assert not errors,errors
   (OUTPUT/'summary.json').write_text(json.dumps({'passed':True,'coverage':['document boundaries','batch edits','save/discard/cancel','nested inspectors','validation failure','close']},ensure_ascii=False,indent=2)+'\n')
   print('SAVE_SESSIONS_OK: item/map/building/customer/network boundaries, batch edits, save/discard/cancel, validation failure and close',flush=True)
   browser.close()
 finally:server.terminate();server.wait(timeout=5)
