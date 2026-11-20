#!/usr/bin/env python3
"""Smoke-test actual target-OS bundles, without Python/Qt imports in child processes."""
import json,os,subprocess,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];GAME=ROOT/'Game';OUTPUT=ROOT/'test/results/packaging-smoke.json'
reports=[]
for name,file,token_header,kind in [('MetroEditor','metro_editor_connection.json','X-Editor-Token','editor'),('MetroTester','metro_tester_connection.json','X-Metro-Token','tester')]:
 exe=ROOT/'tools/bin'/name/(name+('.exe' if os.name=='nt' else ''));connection=GAME/'.godot'/file;connection.unlink(missing_ok=True)
 env=os.environ.copy();env.update(QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu')
 process=subprocess.Popen([str(exe),'--project',str(GAME)],env=env)
 try:
  info={};deadline=time.monotonic()+60
  while time.monotonic()<deadline:
   if process.poll() is not None:raise AssertionError(f'{name} exited: {process.returncode}')
   try:info=json.loads(connection.read_text())
   except (OSError,ValueError):pass
   if info.get('url') and info.get('kind') in ['desktop','native']:break
   time.sleep(.2)
  assert info.get('url'),name
  with urllib.request.urlopen(info['url']+'/api/bridge',timeout=5) as response:bridge=json.load(response)
  assert bridge.get('window',{}).get('native_window_id',0)>0 if kind=='editor' else bridge.get('native_window_id',0)>0
  if kind=='editor':
   with urllib.request.urlopen(info['url']+'/api/project',timeout=5) as response:token=json.load(response)['token']
   endpoint='/api/desktop/close'
  else:token=info['token'];endpoint='/api/close'
  req=urllib.request.Request(info['url']+endpoint,data=b'{}',headers={token_header:token})
  with urllib.request.urlopen(req,timeout=5) as response:assert json.load(response)['ok']
  process.wait(timeout=15);assert process.returncode==0
  reports.append({'application':name,'native_window':True,'passed':True})
 finally:
  if process.poll() is None:process.terminate();process.wait(timeout=5)
OUTPUT.parent.mkdir(parents=True,exist_ok=True);OUTPUT.write_text(json.dumps(reports,indent=2));print('PACKAGED_TOOLS_OK')
