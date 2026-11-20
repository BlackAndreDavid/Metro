#!/usr/bin/env python3
"""Real Qt desktop window plus its embedded editor, without launching a browser application."""
import base64,json,os,shutil,socket,subprocess,tempfile,time,urllib.request,sys
from pathlib import Path
from websockets.sync.client import connect
ROOT=Path(__file__).resolve().parents[2]
PYTHON=os.environ.get('METRO_EDITOR_PYTHON',sys.executable)
OUTPUT=ROOT/'test/results/desktop-editor';OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-desktop-ui-') as scratch:
 base=Path(scratch);game=base/'Game'
 for folder in ['content','assets/textures','assets/maps','assets/icons']:shutil.copytree(ROOT/'Game'/folder,game/folder)
 shutil.copy2(ROOT/'Game/project.godot',game/'project.godot')
 (game/'assets/source/temp').mkdir(parents=True);shutil.copy2(ROOT/'Game/assets/source/temp/manifest.json',game/'assets/source/temp/manifest.json')
 shutil.copytree(ROOT/'tools/editors',base/'tools/editors',ignore=shutil.ignore_patterns('__pycache__','.projects.local.json'))
 with socket.socket() as port:port.bind(('127.0.0.1',0));debug=port.getsockname()[1]
 env=os.environ.copy();env.update(QT_QPA_PLATFORM='xcb' if os.environ.get('DISPLAY') else 'offscreen',QTWEBENGINE_DISABLE_SANDBOX='1',QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu',QTWEBENGINE_REMOTE_DEBUGGING='127.0.0.1:'+str(debug),XDG_CONFIG_HOME=str(base/'config'),XDG_CACHE_HOME=str(base/'cache'),XDG_DATA_HOME=str(base/'data'))
 connection=game/'.godot/metro_editor_connection.json';command=[PYTHON,str(base/'tools/editors/desktop.py'),'--project',str(game),'--godot-executable','/test/godot']
 with (OUTPUT/'desktop.log').open('w',encoding='utf-8') as log:
  process=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT)
  try:
   deadline=time.monotonic()+40
   while time.monotonic()<deadline:
    if process.poll() is not None:raise AssertionError((OUTPUT/'desktop.log').read_text())
    if connection.exists():break
    time.sleep(.1)
   assert connection.exists(),(OUTPUT/'desktop.log').read_text()
   info=json.loads(connection.read_text());assert info['kind']=='desktop',info
   url=info['url']
   with urllib.request.urlopen(url+'/api/bridge') as r:bridge=json.load(r)
   assert bridge['window']['kind']=='desktop' and bridge['window']['native_window_id']>0
   assert bridge['window']['pid']==process.pid
   forward=json.loads((game/'content/editor-settings.local.json').read_text());reverse=json.loads((base/'tools/editors/.projects.local.json').read_text())
   assert forward['project']==reverse['active_project']==str(game) and forward['integration']=='desktop'
   # Embedded Qt Chromium is controlled for tests; no browser executable is launched.
   target=None
   while time.monotonic()<deadline:
    try:
     with urllib.request.urlopen('http://127.0.0.1:'+str(debug)+'/json/list',timeout=1) as r:targets=json.load(r)
     target=next((p for p in targets if p.get('type')=='page'),None)
     if target:break
    except OSError:pass
    time.sleep(.1)
   assert target is not None,(OUTPUT/'desktop.log').read_text()
   with connect(target['webSocketDebuggerUrl'],proxy=None,open_timeout=5,max_size=16*1024*1024) as ws:
    def call(method,params):
     global_sequence[0]+=1;number=global_sequence[0];ws.send(json.dumps({'id':number,'method':method,'params':params}))
     while True:
      response=json.loads(ws.recv(timeout=10))
      if response.get('id')==number:
       assert 'error' not in response,response
       return response['result']
    global_sequence=[0]
    def evaluate(expression):
     result=call('Runtime.evaluate',{'expression':expression,'returnByValue':True,'awaitPromise':True})
     assert 'exceptionDetails' not in result,result
     return result.get('result',{}).get('value')
    def wait(expression):
     until=time.monotonic()+15
     while time.monotonic()<until:
      if evaluate(expression):return
      time.sleep(.1)
     raise AssertionError(expression+' / '+str(evaluate('document.getElementById("status")?.textContent')))
    def click(selector):evaluate('document.querySelector('+json.dumps(selector)+').click()')
    def fill(selector,value):evaluate('(()=>{const e=document.querySelector('+json.dumps(selector)+');e.value='+json.dumps(value)+';e.dispatchEvent(new Event("input",{bubbles:true}));e.dispatchEvent(new Event("change",{bubbles:true}));})()')
    wait('Boolean(document.querySelector("#customerCards button"))')
    # Settings must refresh a Godot path learned after the web page initially loaded.
    token=evaluate('S.project.token')
    request=urllib.request.Request(url+'/api/link',data=json.dumps({'project':str(game),'godot_executable':'/newly-linked/godot'}).encode(),headers={'Content-Type':'application/json','X-Editor-Token':token})
    with urllib.request.urlopen(request,timeout=5) as r:assert json.load(r)['ok']
    click('#settingsTab');wait('document.querySelector("#godotPath").value==="/newly-linked/godot"')
    assert evaluate('document.querySelector("#editorService").value')==url
    assert evaluate('document.querySelector("#editorPath").value')==str(base/'tools/editors')
    def link_godot(path):
     request=urllib.request.Request(url+'/api/link',data=json.dumps({'project':str(game),'godot_executable':path}).encode(),headers={'Content-Type':'application/json','X-Editor-Token':token})
     with urllib.request.urlopen(request,timeout=5) as r:assert json.load(r)['ok']
    link_godot('/auto-refilled/godot')
    wait('document.querySelector("#godotPath").value==="/auto-refilled/godot"')
    fill('#godotPath','/manual-draft/godot')
    link_godot('/changed-while-editing/godot')
    wait('S.project.settings.godot_executable==="/changed-while-editing/godot"')
    assert evaluate('document.querySelector("#godotPath").value')=='/manual-draft/godot'
    click('#saveSettings');wait('document.querySelector("#dirty").textContent.includes("已保存")')
    click('#networkTab');wait('Boolean(document.querySelector("#networkCanvas svg"))')
    fill('#networkWidth','1550');click('#networkSave');wait('!N.dirty')
    assert json.loads((game/'content/network_map.json').read_text())['canvas']['width']==1550
    (OUTPUT/'desktop-map.png').write_bytes(base64.b64decode(call('Page.captureScreenshot',{'format':'png'})['data']))
    click('#itemTab');click('#newCatalog');fill('#catalogForm input[data-field=id]','desktop_item');fill('#catalogForm input[data-field=name]','桌面物资');click('#saveCatalog');wait('Boolean(document.querySelector("#catalogCards [data-catalog-id=desktop_item]"))')
    assert any(i['id']=='desktop_item' for i in json.loads((game/'content/items.json').read_text())['items'])
    click('#customerTab');click('#newCustomer');fill('#customerId','desktop_guest');fill('#customerName','桌面客户');click('#saveCustomer');wait('Boolean(document.querySelector("#customerCards [data-customer=desktop_guest]"))')
    assert any(c['id']=='desktop_guest' for c in json.loads((game/'content/customers.json').read_text())['customers'])
    second=subprocess.run(command,env=env,capture_output=True,text=True,timeout=15);assert second.returncode==0,second.stderr
    assert json.loads(connection.read_text())['pid']==process.pid
    token=evaluate('S.project.token')
    request=urllib.request.Request(url+'/api/desktop/close',data=b'{}',headers={'Content-Type':'application/json','X-Editor-Token':token})
    with urllib.request.urlopen(request,timeout=5) as r:assert json.load(r)['ok']
    process.wait(timeout=15);assert process.returncode==0,(OUTPUT/'desktop.log').read_text()
   assert not connection.exists()
   print('DESKTOP_EDITOR_OK: independent Qt window, full embedded editor, map/item/customer save, bidirectional paths, single instance, clean close')
  finally:
   if process.poll() is None:process.terminate();process.wait(timeout=5)
