#!/usr/bin/env python3
"""Exercise actual Godot dock button callbacks and HTTP handshake in a disposable editor project."""
import json,os,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
GODOT=os.environ.get('METRO_GODOT','/workspace/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64')
OUTPUT=ROOT/'test/results/network-editor';OUTPUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='metro-godot-bridge-') as scratch:
 base=Path(scratch);game=base/'Game';game.mkdir()
 shutil.copytree(ROOT/'Game/addons/metro_content_editor',game/'addons/metro_content_editor')
 shutil.copytree(ROOT/'tools/editors',base/'tools/editors',ignore=shutil.ignore_patterns('__pycache__'))
 driver=game/'addons/bridge_test';driver.mkdir()
 (driver/'plugin.cfg').write_text('[plugin]\nname="Bridge test driver"\nauthor="Metro test"\nversion="1"\nscript="driver.gd"\n')
 result=OUTPUT/'godot-bridge.json'
 if result.exists():result.unlink()
 (driver/'driver.gd').write_text('''@tool
extends EditorPlugin
var timer:Timer
var ticks:=0
var phase:=0
var server_pid:=-1
var dock:Node
func _enter_tree():
 timer=Timer.new();timer.wait_time=.2;timer.timeout.connect(step);add_child(timer);timer.start()
func finish(ok:bool,message:String):
 var f=FileAccess.open(RESULT,FileAccess.WRITE);f.store_string(JSON.stringify({"passed":ok,"message":message,"pid":server_pid}));f.close();timer.stop();get_tree().quit(0 if ok else 1)
func step():
 ticks+=1
 if ticks>100:finish(false,"Timed out waiting for dock handshake: "+str(dock.get_child(dock.get_child_count()-3).text if dock else "missing dock"));return
 dock=EditorInterface.get_base_control().find_child("Metro内容编辑器",true,false)
 if dock==null:return
 var status=""
 for child in dock.get_children():
  if child is Label:status=child.text
 if phase==0:
  for child in dock.get_children():
   if child is Button and child.text=="启动内容编辑器":child.pressed.emit();phase=1;return
 if phase==1 and status.contains("已连接 Metro 接口 v1"):
  var info=JSON.parse_string(FileAccess.get_file_as_string("res://.godot/metro_editor_connection.json"));server_pid=int(info.pid)
  if not OS.is_process_running(server_pid):finish(false,"Started server is missing");return
  for child in dock.get_children():
   if child is Button and child.text=="停止本面板启动的服务":child.pressed.emit();phase=2;return
 if phase==2 and status.contains("服务已停止"):finish(true,"Godot dock started Python, verified project/protocol via HTTP, and stopped only its own service")
'''.replace('RESULT',json.dumps(str(result))),encoding='utf-8')
 (game/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Metro Bridge Test"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/metro_content_editor/plugin.cfg", "res://addons/bridge_test/plugin.cfg")\n',encoding='utf-8')
 env=os.environ.copy();env.update(XDG_CONFIG_HOME=str(base/'config'),XDG_DATA_HOME=str(base/'data'),XDG_CACHE_HOME=str(base/'cache'),GODOT_AI_DISABLE_TELEMETRY='true')
 run=subprocess.run([GODOT,'--headless','--editor','--path',str(game)],env=env,capture_output=True,text=True,timeout=45)
 (OUTPUT/'godot-bridge.log').write_text(run.stdout+run.stderr,encoding='utf-8')
 assert result.exists(),run.stdout+run.stderr
 report=json.loads(result.read_text());assert run.returncode==0 and report['passed'],report
 assert 'ERROR:' not in run.stderr,run.stderr
 if os.name=='posix':
  try:os.kill(report['pid'],0)
  except ProcessLookupError:pass
  else:raise AssertionError('Godot left its server running')
 print('GODOT_EDITOR_BRIDGE_OK: '+report['message'])
