#!/usr/bin/env python3
"""Optional Chromium/Playwright editor flow check, always using an isolated project."""
from pathlib import Path
import tempfile,shutil,subprocess,json
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[2];output=root/'test/results/editor-ui';output.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-editor-browser-') as scratch:
 game=Path(scratch)/'Game';shutil.copytree(root/'Game/content',game/'content');shutil.copytree(root/'Game/assets/textures/customers',game/'assets/textures/customers');shutil.copy2(root/'Game/project.godot',game/'project.godot')
 server=subprocess.Popen(['python3','tools/editors/server.py','--project',str(game),'--port','0','--no-browser'],cwd=root,stdout=subprocess.PIPE,text=True)
 try:
  url=server.stdout.readline().strip().split('Metro editors: ',1)[1]
  with sync_playwright() as p:
   browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
   page=browser.new_page(viewport={'width':1440,'height':1050});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   page.goto(url);page.wait_for_function("document.getElementById('customers').options.length===4")
   page.click('#newCustomer');page.fill('#customerId','browser_guest');page.fill('#customerName','浏览器客户');page.fill('#budget','88');page.fill('#weight','3');page.select_option('#faction','red')
   page.set_input_files('#upload',str(root/'Game/assets/textures/customers/commuter.png'));page.click('#uploadButton');page.wait_for_function("document.getElementById('status').textContent.includes('贴图已导入')")
   page.click('#newStory');page.fill('#storyName','浏览器分支剧情');page.fill('#storyConditions','{"day_min":1}');page.fill('#nodeText','浏览器起始节点')
   page.click('#addNode');page.fill('#nodeText','浏览器分支结尾');page.fill('#nodeFlags','browser_done');page.fill('#nodeAffection','7');page.fill('#nodeTrust','4')
   canvas=page.locator('#graph');canvas.scroll_into_view_if_needed();box=canvas.bounding_box();canvas.click(position={'x':box['width']*.10,'y':box['height']*60/360})
   page.click('#addChoice');page.locator('#choices input').first.fill('继续');page.locator('#choices select').first.select_option('node_1')
   page.click('#saveCustomer');page.wait_for_function("document.getElementById('customers').options.length===5")
   customers=json.loads((game/'content/customers.json').read_text());c=customers['customers'][-1]
   assert c['base_budget']==88 and c['weight']==3 and c['stories'][0]['nodes']['start']['choices'][0]['next']=='node_1',c
   assert c['faction']=='red' and c['stories'][0]['nodes']['node_1']['effects']=={'affection':7,'trust':4}
   assert (game/c['texture'][6:]).is_file()
   page.click('#newStory');page.fill('#storyId','cross_day');page.fill('#storyName','跨日探索');page.select_option('#storyContext','exploration');page.select_option('#priorNpc','browser_guest');page.select_option('#priorStory','story_1');page.fill('#priorDays','1');page.click('#addDependency');page.fill('#affectionMin','7');page.fill('#trustMin','4');page.click('#saveAll')
   page.wait_for_function("document.getElementById('dirty').textContent.includes('已保存')")
   c=json.loads((game/'content/customers.json').read_text())['customers'][-1]
   assert c['stories'][1]['after']==[{'npc':'browser_guest','story':'story_1','days':1}] and c['stories'][1]['contexts']==['exploration']
   assert c['stories'][1]['conditions']['affection_min']==7
   page.screenshot(path=str(output/'customer-saved.png'),full_page=True)
   page.click('#levelTab');page.select_option('#stations','南京东路');page.wait_for_function("document.getElementById('levelName').value==='南京东路街区'")
   page.locator('#entityFields input[data-key=name]').fill('浏览器建筑');page.click('#applyEntity')
   page.select_option('#entityType','vehicles');page.click('#addEntity')
   canvas=page.locator('#map');canvas.scroll_into_view_if_needed();box=canvas.bounding_box()
   x=box['x']+220/1000*box['width'];y=box['y']+474/510*box['height']
   page.mouse.move(x,y);page.mouse.down();page.mouse.move(x+50,y,steps=8);page.mouse.up()
   assert float(page.locator('#entityFields input[data-key=x]').input_value())>350
   page.click('#addColumn');page.click('#addRow');page.select_option('#entityType','npcs');page.click('#addEntity');page.locator('#entityFields select[data-key=npc]').select_option('browser_guest');page.click('#applyEntity');page.uncheck('#snap');page.click('#previewMap');assert page.locator('#mapPreview').is_visible();page.click('#closePreview')
   page.click('#saveLevel');page.wait_for_function("document.getElementById('status').textContent.includes('关卡已保存')")
   registry=json.loads((game/'content/registry.json').read_text());entry=registry['stations']['南京东路'];level=json.loads((game/entry['level'][6:]).read_text())
   assert level['buildings'][0]['name']=='浏览器建筑' and len(level['vehicles'])==5 and level['vehicles'][-1]['x']>350
   assert len(level['cell_names'])==4 and len(level['cell_names'][0])==4 and level['npcs'][0]['npc']=='browser_guest',level
   assert (game/entry['scene'][6:]).is_file();assert not errors,errors
   page.click('#settingsTab');page.fill('#godotPath','/workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64');page.click('#saveSettings');page.click('#probeGodot');page.wait_for_function("document.getElementById('status').textContent.includes('Godot 连接成功')");assert '4.7.2' in page.locator('#godotResult').inner_text();page.click('#levelTab')
   page.screenshot(path=str(output/'level-saved.png'),full_page=True)
   print('BROWSER_EDITOR_FLOW_OK: upload, customer, budget, weight, dialogue branch, station map drag, scene export; no page errors')
   browser.close()
 finally:server.terminate();server.wait(timeout=10)
