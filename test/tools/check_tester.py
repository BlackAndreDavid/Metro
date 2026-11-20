#!/usr/bin/env python3
"""Real native Qt tester, Godot runtime commands, sandbox saves and editor plugin launch."""
import json,os,shutil,subprocess,sys,tempfile,time,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
GODOT=os.environ.get('METRO_GODOT','/workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')
PYTHON=os.environ.get('METRO_EDITOR_PYTHON',sys.executable)
OUTPUT=Path(os.environ.get('METRO_TEST_RESULTS',ROOT/'test/results'))/'tester';OUTPUT.mkdir(parents=True,exist_ok=True)
def wait(check,seconds=40):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  result=check()
  if result:return result
  time.sleep(.1)
 raise AssertionError('timed out')
def read(path):
 try:return json.loads(path.read_text())
 except (OSError,ValueError):return {}
with tempfile.TemporaryDirectory(prefix='metro-tester-') as scratch:
 base=Path(scratch);game=base/'Game';shutil.copytree(ROOT/'Game',game,ignore=lambda folder,names:{n for n in names if n=='.godot' or (Path(folder)==ROOT/'Game' and n in {'saves','runtime','build'})})
 shutil.copytree(ROOT/'tools/tester',base/'tools/tester',ignore=shutil.ignore_patterns('__pycache__','.projects.local.json'))
 env=os.environ.copy();env.update(QT_QPA_PLATFORM='offscreen',XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_CACHE_HOME=str(base/'cache'),METRO_TESTER_READY=str(base/'ready.json'))
 connection=game/'.godot/metro_tester_connection.json'
 desktop_log=(OUTPUT/'native-window.log').open('w',encoding='utf-8')
 desktop=subprocess.Popen([PYTHON,str(base/'tools/tester/desktop.py'),'--project',str(game),'--godot-executable',GODOT],env=env,stdout=desktop_log,stderr=subprocess.STDOUT)
 processes=[desktop]
 try:
  info=wait(lambda:read(connection) if read(connection).get('native_window_id',0)>0 else None)
  assert info['kind']=='native' and info['pid']==desktop.pid
  assert read(base/'tools/tester/.projects.local.json')['active_project']==str(game)
  def post(path,data,token=None):
   request=urllib.request.Request(info['url']+path,data=json.dumps(data).encode(),headers={'Content-Type':'application/json','X-Metro-Token':token if token is not None else info['token']})
   with urllib.request.urlopen(request,timeout=5) as response:return json.load(response)
  try:post('/api/command',{},'wrong')
  except urllib.error.HTTPError as error:assert error.code==403
  else:raise AssertionError('unauthorized command accepted')
  # Repeat File Explorer launch activates the existing native window.
  assert subprocess.run([PYTHON,str(base/'tools/tester/desktop.py'),'--project',str(game)],env=env,capture_output=True,timeout=10).returncode==0
  assert read(connection)['pid']==desktop.pid
  imported=subprocess.run([GODOT,'--headless','--editor','--path',str(game),'--import'],env=env,capture_output=True,text=True,timeout=60)
  (OUTPUT/'import.log').write_text(imported.stdout+imported.stderr)
  assert imported.returncode==0 and 'ERROR:' not in imported.stdout+imported.stderr,(OUTPUT/'import.log').read_text()
  shutil.copy2(ROOT/'test/tools/tester_runtime_driver.gd',game/'tester_runtime_driver.gd')
  game_log=(OUTPUT/'runtime.log').open('w',encoding='utf-8')
  process=subprocess.Popen([GODOT,'--headless','--path',str(game),'--script','res://tester_runtime_driver.gd'],env=env,stdout=game_log,stderr=subprocess.STDOUT);processes.append(process)
  ready=wait(lambda:read(base/'ready.json'))
  # The interface publishes readable paths, then accepts main-thread mutations.
  # Runtime ID is exposed only in snapshots on the native service object; use a deterministic test ping via the driver process ID prefix.
  run_id=None
  # Connection cache intentionally contains no game state. Ask the service through its authenticated diagnostics API.
  def state():return post('/api/status',{})
  runtime=wait(lambda:next(iter(state().get('runtimes',{}).items()),None));run_id=runtime[0]
  assert any(v['path']==['state','account'] for v in runtime[1]['values'])
  try:post('/api/command',{'run_id':run_id,'command':{'kind':'set','path':['state','account'],'value':float('nan')}})
  except urllib.error.HTTPError as error:assert error.code==400
  else:raise AssertionError('nonfinite mutation accepted')
  ids=[]
  for command in [{'kind':'set','path':['state','account'],'value':987.5},{'kind':'set','path':['state','health'],'value':47},{'kind':'set','path':['home','pointer_position','x'],'value':123},{'kind':'spawn','item':'water','count':2,'target':'locker'},{'kind':'save'}]:
   ids.append(post('/api/command',{'run_id':run_id,'command':command})['id'])
  results=wait(lambda:state()['results'] if all(key in state()['results'] for key in ids) else None)
  assert all(results[key]['ok'] for key in ids),results
  bad=post('/api/command',{'run_id':run_id,'command':{'kind':'set','path':['state','unknown'],'value':1}})['id']
  wait(lambda:bad in state()['results']);assert not state()['results'][bad]['ok']
  (game/'.godot/tester-done').write_text('done');process.wait(timeout=10);game_log.close();assert process.returncode==0,(OUTPUT/'runtime.log').read_text()
  post('/api/close',{});desktop.wait(timeout=10);assert not connection.exists()
  # Give Godot the same portable project-local environment as the editor launcher.
  subprocess.run([PYTHON,'-m','venv','--without-pip','--system-site-packages',str(base/'.venv-editor')],check=True)
  runtime_python=base/'.venv-editor'/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
  sites=json.loads(subprocess.check_output([PYTHON,'-c','import json,site;print(json.dumps(site.getsitepackages()))'],text=True))
  local_sites=json.loads(subprocess.check_output([str(runtime_python),'-c','import json,site;print(json.dumps(site.getsitepackages()))'],text=True))
  for folder in local_sites:
   if Path(folder).is_relative_to(base/'.venv-editor'):Path(folder,'tester-runtime.pth').write_text('\n'.join(sites)+'\n')
  driver=game/'addons/tester_test';driver.mkdir();(driver/'plugin.cfg').write_text('[plugin]\nname="Tester checks"\nauthor="Metro"\nversion="1"\nscript="driver.gd"\n');shutil.copy2(ROOT/'test/tools/tester_plugin_driver.gd',driver/'driver.gd')
  project=(game/'project.godot').read_text();project=project.replace('"res://addons/metro_tester/plugin.cfg")','"res://addons/metro_tester/plugin.cfg", "res://addons/tester_test/plugin.cfg")');(game/'project.godot').write_text(project)
  with (OUTPUT/'plugin.log').open('w',encoding='utf-8') as log:
   process=subprocess.Popen([GODOT,'--headless','--editor','--path',str(game)],env=env,stdout=log,stderr=subprocess.STDOUT);processes.append(process)
   process.wait(timeout=65)
  assert process.returncode==0 and 'TESTER_PLUGIN_OK' in (OUTPUT/'plugin.log').read_text(),(OUTPUT/'plugin.log').read_text()
  for name in ['plugin.log','runtime.log']:assert 'ERROR:' not in (OUTPUT/name).read_text(),(OUTPUT/name).read_text()
  print('TESTER_OK: native window, single instance, plugin launch, bidirectional links, numeric/vector edits, item spawn, isolated save, authenticated bridge')
 finally:
  for process in processes:
   if process.poll() is None:process.terminate();process.wait(timeout=5)
  last=read(connection)
  if last.get('pid') and last['pid'] not in [p.pid for p in processes]:
   try:os.kill(last['pid'],15)
   except ProcessLookupError:pass
  desktop_log.close()
