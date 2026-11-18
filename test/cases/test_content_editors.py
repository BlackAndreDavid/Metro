"""Author content through editor API, then run it in an isolated Godot project copy."""
import base64
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('content_editor',ROOT/'tools/editors/server.py')
editor=importlib.util.module_from_spec(spec);spec.loader.exec_module(editor)

class ContentEditors(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='metro-editors-')
        self.game=Path(self.temp.name)/'Game'
        shutil.copytree(ROOT/'Game/content',self.game/'content')
        (self.game/'assets/textures/customers').mkdir(parents=True)
        for p in (ROOT/'Game/assets/textures/customers').glob('*.png'):
            shutil.copy2(p,self.game/'assets/textures/customers'/p.name)
        self.original=editor.GAME;editor.GAME=self.game
    def tearDown(self):
        editor.GAME=self.original;self.temp.cleanup()
    def customer(self):
        customer=copy.deepcopy(editor.read(self.game/'content/customers.json')['customers'][0])
        customer.update(id='editor_test',name='编辑器客户',base_budget=77,weight=1000,buy_categories=['supplies'],sell_categories=['documents'])
        customer['stories']=[dict(id='test_story',name='分支测试',priority=20,once=True,conditions={'day_min':1,'has_items':{'water':1}},start='greeting',nodes={
            'greeting':dict(speaker='编辑器客户',text='先聊聊再交易。',choices=[dict(text='听消息',next='thanks',conditions={}),dict(text='先告别',next='',conditions={})]),
            'thanks':dict(speaker='编辑器客户',text='谢谢你听我说。',set_flags=['editor_story_done'],choices=[])})]
        return customer
    def level(self):
        level=editor.read(self.game/'content/levels/postal.json')
        level.update(loot_station='南京东路',stations=[{'name':'南京东路','row':2,'x':88}])
        level['buildings'][0]['name']='编辑建筑';level['loot'][0]['kind']='book'
        return level
    def test_customer_fields_branch_validation_and_stable_order(self):
        original=editor.read(self.game/'content/customers.json')['customers']
        c=self.customer();editor.save_customer(c)
        records=editor.read(self.game/'content/customers.json')['customers']
        self.assertEqual(records[:4],original);self.assertEqual(records[4]['base_budget'],77)
        c['name']='修改客户';editor.save_customer(c)
        self.assertEqual(len(editor.read(self.game/'content/customers.json')['customers']),5)
        bad=copy.deepcopy(c);bad['stories'][0]['nodes']['greeting']['choices'][0]['next']='missing'
        with self.assertRaises(ValueError):editor.save_customer(bad)
        bad=copy.deepcopy(c);bad['stories'][0]['nodes']={'greeting':{'text':'loop','next':'greeting'}}
        with self.assertRaises(ValueError):editor.save_customer(bad)
        bad=copy.deepcopy(c);bad['texture']='res://../outside.png'
        with self.assertRaises(ValueError):editor.save_customer(bad)
    def test_station_scene_export_and_reference_validation(self):
        result=editor.save_level('南京东路',self.level())
        self.assertIn('exploration.tscn',editor.resource(result['scene']).read_text())
        self.assertEqual(editor.read(self.game/'content/registry.json')['stations']['南京东路'],result)
        self.assertEqual(editor.read(editor.resource(result['level']))['buildings'][0]['name'],'编辑建筑')
        bad=self.level();bad['loot'][1]['building']='missing'
        with self.assertRaises(ValueError):editor.save_level('南京东路',bad)
        bad=self.level();bad['buildings'][0]['x']=100000
        with self.assertRaises(ValueError):editor.save_level('南京东路',bad)
    def test_http_api_requires_token_and_writes_validated_content(self):
        editor.Handler.token='test-token'
        server=editor.ThreadingHTTPServer(('127.0.0.1',0),editor.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(url+'/api/project') as response:self.assertEqual(json.load(response)['token'],'test-token')
            request=urllib.request.Request(url+'/api/customer',data=json.dumps(self.customer()).encode(),headers={'Content-Type':'application/json'})
            with self.assertRaises(urllib.error.HTTPError):urllib.request.urlopen(request)
            request.add_header('X-Editor-Token','test-token')
            with urllib.request.urlopen(request) as response:self.assertTrue(json.load(response)['ok'])
        finally:server.shutdown();server.server_close();thread.join()
    def test_authored_content_runs_in_isolated_game(self):
        godot=os.environ.get('METRO_GODOT')
        if not godot:self.skipTest('METRO_GODOT required for runtime integration')
        # Copy source only: never mutate the user's live content or caches.
        shutil.copytree(ROOT/'Game',self.game,dirs_exist_ok=True,ignore=lambda folder,names: {name for name in names if name in {'.godot','__pycache__'} or (Path(folder)==ROOT/'Game' and name in {'runtime','build','saves'})})
        data=editor.read(self.game/'content/customers.json')
        for customer in data['customers']:customer['weight']=0
        editor.atomic(self.game/'content/customers.json',data)
        editor.save_customer(self.customer());editor.save_level('南京东路',self.level())
        output=Path(os.environ['METRO_TEST_RESULTS'])
        env=os.environ.copy()
        for name,folder in [('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data'),('XDG_CACHE_HOME','cache')]:
            path=Path(self.temp.name)/folder;path.mkdir(exist_ok=True);env[name]=str(path)
        for name,args in [('editor_content_import',['--editor','--import']),('editor_content_runtime',['--script',str(ROOT/'test/cases/test_content_runtime.gd'),'--','--save-file='+str(output/'editor_runtime_home.json')])]:
            result=subprocess.run([godot,'--headless','--path',str(self.game)]+args,env=env,capture_output=True,text=True,timeout=100)
            log=result.stdout+result.stderr;(output/(name+'.log')).write_text(log)
            self.assertEqual(result.returncode,0,log);self.assertNotIn('SCRIPT ERROR:',log);self.assertNotIn('ERROR:',log)
            if name.endswith('runtime'):self.assertIn('CONTENT_RUNTIME_OK',log)

if __name__=='__main__':unittest.main()
