#!/usr/bin/env python3
"""Exercise Godot's lightweight launcher with a real independent Qt editor window."""
import json,os,shutil,subprocess,tempfile,time,signal,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
GODOT=os.environ.get('METRO_GODOT','/workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')
PYTHON=os.environ.get('METRO_EDITOR_PYTHON',sys.executable)
OUTPUT=Path(os.environ['METRO_TEST_RESULTS'])/'desktop-bridge' if os.environ.get('METRO_TEST_RESULTS') else ROOT/'test/results/desktop-bridge'
OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-godot-desktop-') as scratch:
 base=Path(scratch);game=base/'Game';game.mkdir()
 shutil.copytree(ROOT/'Game/addons/metro_content_editor',game/'addons/metro_content_editor')
 for folder in ['content','assets/textures','assets/maps','assets/icons']:shutil.copytree(ROOT/'Game'/folder,game/folder)
 (game/'assets/source/temp').mkdir(parents=True);shutil.copy2(ROOT/'Game/assets/source/temp/manifest.json',game/'assets/source/temp/manifest.json')
 shutil.copytree(ROOT/'tools/editors',base/'tools/editors',ignore=shutil.ignore_patterns('__pycache__','.projects.local.json'))
 # A relocated repository-local environment should win without a machine-specific setting.
 subprocess.run([PYTHON,'-m','venv','--without-pip','--system-site-packages',str(base/'.venv-editor')],check=True)
 site=json.loads(subprocess.check_output([PYTHON,'-c','import json,site;print(json.dumps(site.getsitepackages()))'],text=True))
 runtime=base/'.venv-editor'/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
 local_sites=json.loads(subprocess.check_output([str(runtime),'-c','import json,site;print(json.dumps(site.getsitepackages()))'],text=True))
 for folder in local_sites:
  if Path(folder).is_relative_to(base/'.venv-editor'):Path(folder,'metro-test-runtime.pth').write_text('\n'.join(site)+'\n')
 driver=game/'addons/bridge_test';driver.mkdir()
 (driver/'plugin.cfg').write_text('[plugin]\nname="Desktop bridge test"\nauthor="Metro test"\nversion="1"\nscript="driver.gd"\n')
 shutil.copy2(ROOT/'test/tools/desktop_plugin_driver.gd',driver/'driver.gd')
 (game/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Metro Desktop Test"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/metro_content_editor/plugin.cfg", "res://addons/bridge_test/plugin.cfg")\n',encoding='utf-8')
 browser=subprocess.Popen([PYTHON,str(base/'tools/editors/server.py'),'--project',str(game),'--port','0','--no-browser'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 assert browser.stdout.readline().startswith('Metro editors: ')
 result=OUTPUT/'desktop-bridge.json';result.unlink(missing_ok=True)
 env=os.environ.copy();env.update(XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_CACHE_HOME=str(base/'cache'),GODOT_AI_DISABLE_TELEMETRY='true',METRO_DESKTOP_REPORT=str(result),METRO_EDITOR_PYTHON=PYTHON,QT_QPA_PLATFORM='xcb' if os.environ.get('DISPLAY') else 'offscreen',QTWEBENGINE_DISABLE_SANDBOX='1',QTWEBENGINE_CHROMIUM_FLAGS='--disable-gpu')
 log_path=OUTPUT/'godot-bridge.log'
 with log_path.open('w',encoding='utf-8') as log:
  process=subprocess.Popen([GODOT,'--headless','--editor','--path',str(game)],env=env,stdout=log,stderr=subprocess.STDOUT,text=True)
  started=time.monotonic()
  try:
   while process.poll() is None:
    text=log_path.read_text(encoding='utf-8',errors='replace')
    if 'ERROR:' in text or time.monotonic()-started>70:process.terminate();process.wait(timeout=5);break
    time.sleep(.1)
  finally:
   if process.poll() is None:process.kill();process.wait()
   browser.terminate();browser.wait(timeout=5)
   desktop_log=game/'.godot/metro_editor_desktop.log'
   if desktop_log.exists():shutil.copy2(desktop_log,OUTPUT/'desktop.log')
   if not result.exists():
    connection=game/'.godot/metro_editor_connection.json'
    if connection.exists():
     try:os.kill(int(json.loads(connection.read_text())['pid']),signal.SIGTERM)
     except ProcessLookupError:pass
 text=log_path.read_text(encoding='utf-8')
 assert result.exists(),text
 report=json.loads(result.read_text());assert process.returncode==0 and report['passed'],report
 assert 'ERROR:' not in text,text
 if os.name=='posix' and report['pid']>0:
  try:os.kill(report['pid'],0)
  except ProcessLookupError:pass
  else:raise AssertionError('Desktop failed to close its own process')
 print('GODOT_EDITOR_BRIDGE_OK: '+report['message'])
