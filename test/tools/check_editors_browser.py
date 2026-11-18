#!/usr/bin/env python3
"""Exercise mouse-based authoring in an isolated project, including ragged maps and meetings."""
from pathlib import Path
import tempfile, shutil, subprocess, json, os
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[2]
output=root/'test/results/editor-ui';output.mkdir(parents=True,exist_ok=True)
godot=os.environ.get('METRO_GODOT','/workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')
with tempfile.TemporaryDirectory(prefix='metro-editor-browser-') as scratch:
 game=Path(scratch)/'Game'
 shutil.copytree(root/'Game/content',game/'content');shutil.copytree(root/'Game/assets/textures',game/'assets/textures');shutil.copy2(root/'Game/project.godot',game/'project.godot')
 server=subprocess.Popen(['python3','tools/editors/server.py','--project',str(game),'--port','0','--no-browser'],cwd=root,stdout=subprocess.PIPE,text=True)
 try:
  url=server.stdout.readline().strip().split('Metro editors: ',1)[1]
  with sync_playwright() as p:
   browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
   page=browser.new_page(viewport={'width':1550,'height':1150});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   def canvas_click(selector,x,y):
    canvas=page.locator(selector);canvas.scroll_into_view_if_needed();box=canvas.bounding_box();height=int(canvas.get_attribute('height'));canvas.click(position={'x':x/1000*box['width'],'y':y/height*box['height']})
   def drag_graph(x1,y1,x2,y2):
    canvas=page.locator('#graph');canvas.scroll_into_view_if_needed();box=canvas.bounding_box();height=int(canvas.get_attribute('height'))
    page.mouse.move(box['x']+x1/1000*box['width'],box['y']+y1/height*box['height']);page.mouse.down();page.mouse.move(box['x']+x2/1000*box['width'],box['y']+y2/height*box['height'],steps=12);page.mouse.up()
   def drag_asset(selector,x,y):
    canvas=page.locator('#map');canvas.scroll_into_view_if_needed();box=canvas.bounding_box();page.locator(selector).drag_to(canvas,target_position={'x':x/1000*box['width'],'y':y/510*box['height']})
   page.goto(url);page.wait_for_selector('#customerCards button');assert not page.locator('#customers').is_visible()
   page.click('#newCustomer');page.fill('#customerId','browser_guest');page.fill('#customerName','浏览器客户');page.fill('#budget','88');page.fill('#weight','3');page.select_option('#faction','red')
   page.set_input_files('#upload',str(root/'Game/assets/textures/customers/commuter.png'));page.click('#uploadButton');page.wait_for_function("document.getElementById('status').textContent.includes('贴图已导入')")
   page.click('#newStory');page.fill('#storyName','一次见面的多轮对话');page.fill('#nodeText','您好。\n今天有新消息。');page.click('#appendSpeech');page.fill('#nodeText','你想了解什么？')
   page.click('#appendReply');page.locator('.bubble.player [contenteditable]').fill('告诉我消息');page.fill('#nodeText','这就是第一条消息。')
   page.click('#appendReply');page.locator('.bubble.player [contenteditable]').fill('还有其他消息吗？');page.fill('#nodeText','这是第二条消息。');page.fill('#nodeAffection','7');page.fill('#nodeTrust','4')
   page.click('#restartMeeting');assert '今天有新消息' in page.locator('#chatLog').inner_text();page.locator('#chatReplies button').click();page.locator('#chatReplies button').click();assert '第一条消息' in page.locator('#chatLog').inner_text();page.locator('#chatReplies button').click();assert '第二条消息' in page.locator('#chatLog').inner_text()
   page.click('#saveCustomer');page.wait_for_selector('#customerCards [data-customer=browser_guest]')
   c=json.loads((game/'content/customers.json').read_text())['customers'][-1];story=c['stories'][0]
   assert c['faction']=='red' and len(story['nodes'])==4 and story['nodes']['node_2']['choices'][0]['text']=='还有其他消息吗？',c
   assert story['nodes']['node_3']['effects']=={'affection':7,'trust':4}
   # A second answer is authored through the graph and a dragged output port.
   canvas_click('#graph',390,65) # node_1 in the three-column graph
   page.click('#appendReply');page.locator('.bubble.player [contenteditable]').fill('先告别');page.fill('#nodeText','下次见。');page.click('#saveCustomer');page.wait_for_function("document.getElementById('status').textContent.includes('已保存')")
   c=json.loads((game/'content/customers.json').read_text())['customers'][-1];assert len(c['stories'][0]['nodes']['node_1']['choices'])==2
   canvas_click('#graph',390,65);page.locator('#choices > div').nth(1).get_by_role('button',name='以此回答结束').click();page.click('#saveCustomer');page.wait_for_function("document.getElementById('status').textContent.includes('已保存')")
   c=json.loads((game/'content/customers.json').read_text())['customers'][-1];assert c['stories'][0]['nodes']['node_1']['choices'][1]['next']==''
   drag_graph(575,158,130,300);page.click('#saveCustomer');page.wait_for_function("document.getElementById('status').textContent.includes('已保存')")
   c=json.loads((game/'content/customers.json').read_text())['customers'][-1];assert c['stories'][0]['nodes']['node_1']['choices'][1]['next']=='node_3'
   drag_graph(575,158,450,300);page.click('#saveCustomer');page.wait_for_function("document.getElementById('status').textContent.includes('已保存')")
   c=json.loads((game/'content/customers.json').read_text())['customers'][-1];assert c['stories'][0]['nodes']['node_1']['choices'][1]['next']=='node_4'
   # Retain the event line; select meetings through the canvas instead of a list.
   page.click('#newStory');page.fill('#storyId','cross_day');page.fill('#storyName','跨日探索');page.select_option('#storyContext','exploration');page.select_option('#priorNpc','browser_guest');page.select_option('#priorStory','meeting_1');page.fill('#priorDays','1');page.click('#addDependency');page.fill('#affectionMin','7');page.fill('#trustMin','4');page.click('#saveAll');page.wait_for_function("document.getElementById('dirty').textContent.includes('已保存')")
   c=json.loads((game/'content/customers.json').read_text())['customers'][-1];assert c['stories'][1]['after'][0]['story']=='meeting_1'
   canvas_click('#timeline',290,60);assert page.locator('#meetingTitle').inner_text()=='跨日探索'
   page.locator('#meetingPane').scroll_into_view_if_needed();page.screenshot(path=str(output/'meeting-editor.png'),full_page=True)
   page.click('#levelTab');page.click('#chooseStation');page.fill('#stationSearch','南京东路');page.locator('g[data-station="南京东路"] circle').last.click();page.wait_for_function("document.getElementById('stationBadge').textContent.includes('南京东路')")
   assert not page.locator('#stations').is_visible();assert not page.locator('#entities').is_visible()
   canvas_click('#map',850,30);page.click('#removeCell');canvas_click('#map',600,30);page.click('#removeCell') # first street: one cell, others: three
   page.click('#addColumn');page.click('#removeCell') # increment/decrement only the selected street
   canvas_click('#map',100,360);page.click('#addRow');page.click('#addColumn');page.click('#removeRow');page.click('#undoMap')
   # Reusable building cards are actually dragged from the palette, twice.
   drag_asset('#buildingPalette [data-asset=small_shop]',80,90)
   drag_asset('#buildingPalette [data-asset=small_shop]',210,220)
   page.locator('#entityFields input[data-key=name]').fill('可复用商店');page.click('#applyEntity');page.get_by_role('button',name='＋ 选中建筑存为素材卡').click();page.wait_for_selector('#buildingPalette [data-asset=small_shop_2]')
   drag_asset('#objectPalette [data-asset=browser_guest]',140,455)
   page.screenshot(path=str(output/'npc-drag-debug.png'),full_page=True)
   assert json.loads(page.locator('#levelJson').input_value())['npcs'],page.locator('#status').inner_text()
   page.click('#previewMap');assert page.locator('#mapPreview').is_visible();page.click('#closePreview');page.click('#saveLevel');page.wait_for_function("document.getElementById('status').textContent.includes('关卡已保存')")
   registry=json.loads((game/'content/registry.json').read_text());entry=registry['stations']['南京东路'];level=json.loads((game/entry['level'][6:]).read_text())
   assert [len(r) for r in level['cell_names']]==[1,3,3,2],level['cell_names']
   assert len([b for b in level['buildings'] if b.get('template_id')=='small_shop'])==2
   assert level['npcs'][0]['npc']=='browser_guest' and level['npcs'][0]['row']==3
   assert (game/entry['scene'][6:]).is_file();page.locator('#map').scroll_into_view_if_needed();page.screenshot(path=str(output/'ragged-map-editor.png'),full_page=True)
   page.click('#chooseStation');page.click('#stationReset');page.screenshot(path=str(output/'station-map.png'));page.click('#closeStations')
   page.click('#settingsTab');page.fill('#godotPath',godot);page.click('#saveSettings');page.click('#probeGodot');page.wait_for_function("document.getElementById('status').textContent.includes('Godot 连接成功')");assert '4.7.2' in page.locator('#godotResult').inner_text()
   assert not errors,errors
   print('BROWSER_EDITOR_FLOW_OK: avatar cards, meeting turns/replies, event selection, station diagram, ragged add/remove, undo, native building/NPC drags, save/reload, Godot connection')
   browser.close()
 finally:server.terminate();server.wait(timeout=10)
