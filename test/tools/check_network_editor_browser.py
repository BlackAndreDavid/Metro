#!/usr/bin/env python3
"""Mouse-based network edits, texture transforms, persistence and stale-write protection."""
import json, shutil, subprocess, tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'test/results/network-editor';OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-network-browser-') as scratch:
 game=Path(scratch)/'Game'
 for folder in ['content','assets/textures','assets/maps']:shutil.copytree(ROOT/'Game'/folder,game/folder)
 shutil.copy2(ROOT/'Game/project.godot',game/'project.godot')
 connection=game/'connection.json'
 server=subprocess.Popen(['python3','tools/editors/server.py','--project',str(game),'--port','0','--no-browser','--connection-file',str(connection)],cwd=ROOT,stdout=subprocess.PIPE,text=True)
 try:
  url=server.stdout.readline().strip().split('Metro editors: ',1)[1]
  with sync_playwright() as p:
   browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=browser.new_page(viewport={'width':1600,'height':1100});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
   page.goto(url);page.wait_for_selector('#customerCards button');page.click('#networkTab');page.wait_for_selector('#networkCanvas svg')
   assert page.locator('#networkLines').get_attribute('class')=='selected'
   original=page.evaluate('structuredClone(N.data)')
   def canvas_at(x,y):
    return page.evaluate('([x,y])=>{const p=N.svg.createSVGPoint();p.x=x;p.y=y;const s=p.matrixTransform(N.svg.getScreenCTM());return [s.x,s.y]}',[x,y])
   def click_at(x,y):
    page.locator('#networkCanvas').scroll_into_view_if_needed();a,b=canvas_at(x,y);page.mouse.click(a,b)
   def drag_at(x,y,dx,dy):
    page.locator('#networkCanvas').scroll_into_view_if_needed();a,b=canvas_at(x,y);c,d=canvas_at(x+dx,y+dy);page.mouse.move(a,b);page.mouse.down();page.mouse.move(c,d,steps=12);page.mouse.up()
   # Drag one real station; referenced route nodes follow the shared station coordinate.
   x,y=original['stations']['邮电新村']['position'];drag_at(x,y,38,22)
   moved=page.evaluate('N.data.stations["邮电新村"].position');assert abs(moved[0]-x-38)<=2 and abs(moved[1]-y-22)<=2,moved
   width=page.evaluate('N.box.w');page.click('#networkZoomIn');assert page.evaluate('N.box.w')<width
   page.locator('#networkCanvas').scroll_into_view_if_needed();box=page.locator('#networkCanvas').bounding_box();before=page.evaluate('N.box.x');cx=box['x']+box['width']/2;cy=box['y']+box['height']/2
   page.mouse.move(cx,cy);page.mouse.down(button='middle');page.mouse.move(cx+65,cy+35,steps=10);page.mouse.up(button='middle');assert page.evaluate('N.box.x')<before-20
   page.click('#networkFit')
   # Select the 10 line, then insert a new bend directly on a segment.
   li=next(i for i,l in enumerate(original['lines']) if l[0]==10)
   page.locator(f'#networkPalette button[data-network-line="{li}"]').click();page.click('#networkInsert')
   route=page.evaluate('N.data.lines[N.line][2]');a=page.evaluate('networkPoint(N.data.lines[N.line][2][0])');b=page.evaluate('networkPoint(N.data.lines[N.line][2][1])');count=len(route)
   click_at((a[0]+b[0])/2,(a[1]+b[1])/2)
   assert page.evaluate('N.data.lines[N.line][2].length')==count+1
   inserted=page.evaluate('networkPoint(N.data.lines[N.line][2][N.selection.index])');page.click('#networkSelect');drag_at(*inserted,15,12)
   page.click('#networkDelete');assert page.evaluate('N.data.lines[N.line][2].length')==count
   # New route and station, connected with existing stops by mouse.
   page.click('#networkNewLine');click_at(794+38,235+22);page.click('#networkStation');click_at(400,120)
   page.locator('[data-network-field="站名"]').fill('编辑测试站');page.locator('[data-network-field="站名"]').press('Tab')
   page.click('#networkAppend');x,y=original['stations']['四平路']['position'];click_at(x,y)
   assert page.evaluate('N.data.lines[N.line][2]')==['邮电新村','编辑测试站','四平路']
   page.click('#networkRemoveLine');page.click('#networkUndo')
   assert page.evaluate('N.data.lines[N.line][2]')==['邮电新村','编辑测试站','四平路']
   page.click('#networkSave');page.wait_for_function('!N.dirty')
   saved=json.loads((game/'content/network_map.json').read_text());assert saved['stations']['邮电新村']['position']==moved and '编辑测试站' in json.loads((game/'content/stations.json').read_text())
   # Existing background is a normal texture asset; import another independent map image.
   page.click('#networkTextures');page.set_input_files('#networkUpload',str(ROOT/'Game/assets/textures/customers/commuter.png'));page.click('#networkImport');page.wait_for_function('N.data.textures.length===2')
   image=page.evaluate('structuredClone(N.data.textures[1])');drag_at(95,95,90,55)
   after=page.evaluate('N.data.textures[1].position');assert after[0]>image['position'][0]+70,after
   w,h=image['size'];x,y=after;drag_at(x+w-3,y+h-3,35,25)
   assert page.evaluate('N.data.textures[1].size[0]')>w+20
   page.locator('[data-network-field="旋转角度"]').fill('25');page.locator('[data-network-field="旋转角度"]').press('Tab')
   page.locator('[data-network-field="透明度"]').fill('0.55');page.locator('[data-network-field="透明度"]').press('Tab');page.click('#networkLower');page.click('#networkRaise')
   page.click('#networkSave');page.wait_for_function('!N.dirty');page.screenshot(path=str(OUTPUT/'texture-layer.png'),full_page=True)
   # Reload into a fresh browser page and verify disk state, then conflict with the first page.
   other=browser.new_page(viewport={'width':1600,'height':1100});other.goto(url);other.wait_for_selector('#customerCards button');other.click('#networkTab');other.wait_for_selector('#networkCanvas svg')
   assert other.evaluate('N.data.textures[1].rotation')==25
   other.locator('#networkWidth').fill('1600');other.locator('#networkWidth').press('Tab');other.click('#networkSave');other.wait_for_function('!N.dirty')
   page.locator('#networkWidth').fill('1700');page.locator('#networkWidth').press('Tab');page.click('#networkSave');page.wait_for_function("document.getElementById('status').textContent.includes('其他窗口')")
   assert json.loads((game/'content/network_map.json').read_text())['canvas']['width']==1600
   other.click('#networkLines');other.screenshot(path=str(OUTPUT/'line-layer.png'),full_page=True)
   manifest=page.request.get(url+'/api/bridge').json();assert manifest['protocol']=='metro-editor' and manifest['layers']==['textures','lines']
   assert json.loads(connection.read_text())['url']==url
   assert not errors,errors
   print('NETWORK_EDITOR_BROWSER_OK: node drag/insert/delete, route CRUD, station creation, texture import/move/resize/rotate/order, save/reload/conflict, bridge handshake')
   browser.close()
 finally:server.terminate();server.wait(timeout=5)
