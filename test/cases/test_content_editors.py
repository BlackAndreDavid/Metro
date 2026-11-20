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
        shutil.copytree(ROOT/'Game/assets/textures',self.game/'assets/textures')
        shutil.copytree(ROOT/'Game/assets/maps',self.game/'assets/maps')
        self.original=editor.GAME;editor.GAME=self.game
    def tearDown(self):
        editor.GAME=self.original;self.temp.cleanup()
    def customer(self):
        customer=copy.deepcopy(editor.read(self.game/'content/customers.json')['customers'][0])
        customer.update(faction='red',id='editor_test',name='编辑器客户',base_budget=77,weight=1000,buy_categories=['supplies'],sell_categories=['documents'])
        customer['buy_item_weights']={'supplies':{'water':1,'ration':0}}
        customer['stories']=[dict(id='test_story',name='分支测试',priority=20,once=True,conditions={'day_min':1,'has_items':{'water':1}},start='greeting',nodes={
            'greeting':dict(speaker='编辑器客户',text='先聊聊再交易。',choices=[dict(text='听消息',next='thanks',conditions={},effects={'affection':3,'trust':5}),dict(text='先告别',next='',conditions={})]),
            'thanks':dict(effects={'affection':7,'trust':6},speaker='编辑器客户',text='谢谢你听我说。',set_flags=['editor_story_done'],next='more',choices=[]),
            'more':dict(speaker='编辑器客户',text='还有第二个问题。',choices=[dict(text='继续聊',next='last',conditions={}),dict(text='暂时告别',next='',conditions={})]),
            'last':dict(speaker='编辑器客户',text='本次见面结束。',choices=[])})]
        customer['stories'].append(dict(id='explore_followup',name='跨日探索后续',contexts=['exploration'],after=[dict(npc='editor_test',story='test_story',days=1)],conditions={'affection_min':10,'trust_min':11},once=True,start='hello',nodes={'hello':dict(text='昨天的消息有了后续。',effects={'affection':2,'trust':3})}))
        return customer
    def level(self):
        level=editor.read(self.game/'content/levels/postal.json')
        level.update(loot_station='南京东路',stations=[{'name':'南京东路','row':2,'x':88}])
        level['buildings'][0]['name']='编辑建筑'
        level['npcs']=[dict(npc='editor_test',row=3,x=330)]
        level['cell_names']=[['短街'],['中街'+str(i) for i in range(4)],['南街'+str(i) for i in range(3)],['第四街'+str(i) for i in range(2)]]
        level['street_starts']=[0,0,0,0]
        level['buildings']=[b for b in level['buildings'] if b['x']+b['width']<=level['segment']*len(level['cell_names'][b['row']])]
        for building in level['buildings']:building['loot_points']=[]
        level['buildings'][0]['loot_points']=[dict(id='test_cabinet',x=40,floor=0,chance=1,rolls=1,legacy_slot=0,choices=[dict(kind='book',weight=1)])]
        level['loot']=[]
        level['vehicles']=[v for v in level['vehicles'] if v['x']<=level['segment']*len(level['cell_names'][v['row']])-24]
        level['junctions']=[j for j in level['junctions'] if j['x']<=min(level['segment']*len(level['cell_names'][j['row']]),level['segment']*len(level['cell_names'][j['row']+1]))-24]
        level['junctions'].append(dict(row=2,x=330))
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
        editor.save_customer(self.customer())
        result=editor.save_level('南京东路',self.level())
        self.assertIn('exploration.tscn',editor.resource(result['scene']).read_text())
        self.assertEqual(editor.read(self.game/'content/registry.json')['stations']['南京东路'],result)
        self.assertEqual(editor.read(editor.resource(result['level']))['buildings'][0]['name'],'编辑建筑')
        bad=self.level();bad['buildings'][0]['loot_points'][0]['choices'][0]['kind']='missing'
        with self.assertRaises(ValueError):editor.save_level('南京东路',bad)
        bad=self.level();bad['buildings'][0]['x']=100000
        with self.assertRaises(ValueError):editor.save_level('南京东路',bad)
    def test_social_schema_new_ids_npcs_and_godot_interface(self):
        customer=self.customer();editor.save_customer(customer)
        duplicate=copy.deepcopy(customer);duplicate['_create']=True
        with self.assertRaises(ValueError):editor.save_customer(duplicate)
        bad=copy.deepcopy(customer);bad['faction']='unknown'
        with self.assertRaises(ValueError):editor.save_customer(bad)
        bad=copy.deepcopy(customer);bad['stories'][0]['nodes']['thanks']['effects']['trust']=101
        with self.assertRaises(ValueError):editor.save_customer(bad)
        level=self.level();editor.validate_level('南京东路',level)
        level['npcs'][0]['npc']='missing'
        with self.assertRaises(ValueError):editor.validate_level('南京东路',level)
        godot=os.environ.get('METRO_GODOT')
        if godot:
            editor.atomic(self.game/'content/editor-settings.local.json',{'godot_executable':godot})
            self.assertIn('4.7',editor.godot_action({'action':'probe'})['version'])

    def test_ragged_streets_validate_each_row_and_junction_overlap(self):
        editor.save_customer(self.customer());level=self.level();editor.validate_level('南京东路',level)
        self.assertEqual([len(r) for r in level['cell_names']],[1,4,3,2])
        bad=copy.deepcopy(level);bad['vehicles'].append(dict(id='outside',row=0,x=700,color='#677378'))
        with self.assertRaises(ValueError):editor.validate_level('南京东路',bad)
        bad=copy.deepcopy(level);bad['junctions'].append(dict(row=0,x=700))
        with self.assertRaises(ValueError):editor.validate_level('南京东路',bad)
        bad=copy.deepcopy(level);bad['buildings'][0]['width']=500
        with self.assertRaises(ValueError):editor.validate_level('南京东路',bad)
        geometry=editor.station_map()
        self.assertEqual(set(geometry['stations']),set(editor.read(self.game/'content/stations.json')))
        self.assertEqual(geometry['stations']['邮电新村']['position'],[794,235])

    def test_building_and_meeting_models_preserve_instances_and_answers(self):
        node=shutil.which('node')
        if not node:self.skipTest('Node.js required for editor model checks')
        source=(ROOT/'tools/editors/models.js').read_text()
        checks="""
const check=(ok,message)=>{if(!ok)throw Error(message)};
const level={segment:560,cell_names:[['short'],['a','b','c']],buildings:[],loot:[]};
const template={id:'shop',name:'shop',width:200,floors:1,wall:'#736163'};
const model=new BuildingDefinition(template),first=model.instantiate(level,0,500,20);level.buildings.push(first);
const second=model.instantiate(level,1,900,20);check(first.id!==second.id,'unique building instances');
check(first.x+first.width<=560&&template.id==='shop','row bounds and immutable template');
level.loot.push({building:first.id,x:first.x+20,row:0});BuildingDefinition.move(level,first,1,900);
check(level.loot[0].x===920&&level.loot[0].row===1,'contained loot follows building');
const story={start:'a',nodes:{a:{text:'question',next:'end',choices:[{text:'answer',next:'end',effects:{trust:3}}]},end:{text:'end',choices:[]}}};
const conversation=new MeetingDialogue(story),speech=conversation.appendSpeech('a','NPC');
check(story.nodes.a.next===speech&&story.nodes.a.choices.length===0,'continuous speech inserted before answers');
check(story.nodes[speech].choices[0].effects.trust===3,'existing answers and effects preserved');
const reply=conversation.appendReply(speech,'NPC','second answer');
check(story.nodes[speech].choices.length===2&&story.nodes[reply].text,'multiple answers lead to independent turns');
console.log('EDITOR_MODELS_OK');
"""
        result=subprocess.run([node,'-e',source+checks],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr);self.assertIn('EDITOR_MODELS_OK',result.stdout)

    def test_item_enemy_catalogues_and_offset_weighted_buildings(self):
        item=copy.deepcopy(editor.catalog('items','items')[0]);item.update(id='editor_part',name='编辑零件',texture='res://assets/textures/temp/items/scrap_metal.png',price=17.25,width=2,height=1,category='materials',rarity=1)
        editor.validate_item(item);editor.upsert_catalog('items','items',item)
        self.assertIn('editor_part',editor.item_ids())
        bad=copy.deepcopy(item);bad['width']=0
        with self.assertRaises(ValueError):editor.validate_item(bad)
        enemy=copy.deepcopy(editor.catalog('enemies','enemies')[0]);enemy.update(id='editor_rat')
        editor.validate_enemy(enemy);editor.upsert_catalog('enemies','enemies',enemy)
        bad=copy.deepcopy(enemy);bad['movement']['patrol_min']=4;bad['movement']['patrol_max']=2
        with self.assertRaises(ValueError):editor.validate_enemy(bad)
        editor.save_customer(self.customer());level=self.level();level['street_starts'][0]=300
        for key in ['buildings','vehicles','stations']:
            for entry in level[key]:
                if entry['row']==0:entry['x']+=300
        level['junctions']=[j for j in level['junctions'] if j['row']!=0]
        level['monsters']=[dict(id='placed_rat',enemy='editor_rat',row=0,x=400)]
        level['buildings'][0]['loot_points'][0]['choices']=[dict(kind='editor_part',weight=9),dict(kind='water',weight=1)]
        editor.validate_level('南京东路',level)
        bad=copy.deepcopy(level);bad['monsters'][0]['x']=330
        with self.assertRaises(ValueError):editor.validate_level('南京东路',bad)
        bad=copy.deepcopy(level);bad['buildings'][0]['loot_points'][0]['choices'][0]['weight']=-1
        with self.assertRaises(ValueError):editor.validate_level('南京东路',bad)
        self.assertEqual(editor.migrate_level(level)['street_starts'][0],300)
        old=copy.deepcopy(level)
        for building in old['buildings']:building['loot_points']=[]
        old['loot']=[dict(x=650,row=0,building='',floor=0,kind='water')]
        migrated=editor.migrate_level(old)
        self.assertEqual(migrated['loot'],[]);self.assertEqual(migrated['buildings'][0]['loot_points'][0]['legacy_slot'],0)

    def test_http_api_requires_token_and_writes_validated_content(self):
        editor.Handler.token='test-token'
        server=editor.ThreadingHTTPServer(('127.0.0.1',0),editor.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url=f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(url+'/api/project') as response:
                project=json.load(response);self.assertEqual(project['token'],'test-token');self.assertEqual(len(project['station_map']['stations']),74);self.assertGreater(len(project['building_templates']),0)
            template={'id':'test_shop','name':'新商店','width':160,'floors':1,'wall':'#736163'}
            request=urllib.request.Request(url+'/api/building-template',data=json.dumps(template).encode(),headers={'Content-Type':'application/json','X-Editor-Token':'test-token'})
            with urllib.request.urlopen(request) as response:self.assertTrue(json.load(response)['ok'])
            self.assertEqual(editor.read(self.game/'content/building_templates.json')['templates'][-1],template)
            request=urllib.request.Request(url+'/api/customer',data=json.dumps(self.customer()).encode(),headers={'Content-Type':'application/json'})
            with self.assertRaises(urllib.error.HTTPError):urllib.request.urlopen(request)
            request.add_header('X-Editor-Token','test-token')
            with urllib.request.urlopen(request) as response:self.assertTrue(json.load(response)['ok'])
            for deleted in [True,False]:
                request=urllib.request.Request(url+'/api/catalog/archive',data=json.dumps({'catalog':'customers','id':'editor_test','deleted':deleted}).encode(),headers={'Content-Type':'application/json','X-Editor-Token':'test-token'})
                with urllib.request.urlopen(request) as response:self.assertTrue(json.load(response)['ok'])
                saved=next(c for c in editor.catalog('customers','customers') if c['id']=='editor_test');self.assertEqual(saved['deleted'],deleted)
        finally:server.shutdown();server.server_close();thread.join()
    def test_bidirectional_editor_path_discovery(self):
        original=editor.WEB
        try:
            editor.WEB=Path(self.temp.name)/'tools/editors';editor.WEB.mkdir(parents=True)
            (self.game/'project.godot').write_text('config_version=5\n',encoding='utf-8')
            editor.atomic(editor.WEB/'.projects.local.json',{'version':1,'active_project':str(self.game),'projects':{}})
            self.assertEqual(editor.linked_project(),self.game)
            editor.atomic(self.game/'content/editor-settings.local.json',{'godot_executable':'/local/godot','custom_preference':42})
            settings=editor.register_project('/local/godot');self.assertEqual(settings['editor_root'],str(editor.WEB));self.assertEqual(settings['project'],str(self.game));self.assertEqual(settings['integration'],'desktop');self.assertEqual(settings['custom_preference'],42)
            reverse=editor.read(editor.WEB/'.projects.local.json');self.assertEqual(reverse['active_project'],str(self.game));self.assertEqual(len(reverse['projects']),1)
            (editor.WEB/'.projects.local.json').write_text('broken json',encoding='utf-8')
            self.assertEqual(editor.linked_project(),ROOT/'Game')
        finally:editor.WEB=original

    def test_customer_item_weights_validation(self):
        customer=self.customer();customer['sell_categories']=['supplies'];customer['sell_item_weights']={'supplies':{'water':5,'ration':0}}
        editor.validate_customer(customer)
        for weights in [{'water':-1},{'unknown_item':3},{'circuit':2},{'water':0}]:
            invalid=copy.deepcopy(customer);invalid['sell_item_weights']['supplies']=weights
            with self.assertRaises(ValueError):editor.validate_customer(invalid)

    def test_browser_service_registration_and_link_validation(self):
        original=editor.WEB;previous=dict(editor.SERVICE)
        service=None;thread=None
        try:
            editor.WEB=Path(self.temp.name)/'tools/editors';editor.WEB.mkdir(parents=True)
            connection=self.game/'.godot/metro_browser_connection.json'
            editor.publish_service('http://127.0.0.1:8765','browser',connection)
            manifest=editor.bridge_manifest()
            self.assertEqual(manifest['kind'],'browser')
            self.assertEqual(editor.read(connection)['session_id'],manifest['session_id'])
            self.assertEqual(editor.read(self.game/'content/editor-settings.local.json')['integration'],'browser')
            editor.Handler.token='link-test'
            service=editor.ThreadingHTTPServer(('127.0.0.1',0),editor.Handler)
            thread=threading.Thread(target=service.serve_forever,daemon=True);thread.start()
            url=f'http://127.0.0.1:{service.server_port}'
            def post(path,data,token='link-test'):
                request=urllib.request.Request(url+path,data=json.dumps(data).encode(),headers={'Content-Type':'application/json','X-Editor-Token':token})
                with urllib.request.urlopen(request) as response:return json.load(response)
            payload={'project':str(self.game),'godot_executable':'/local/godot'}
            with self.assertRaises(urllib.error.HTTPError):post('/api/link',payload,'wrong-token')
            with self.assertRaises(urllib.error.HTTPError):post('/api/link',{**payload,'project':str(self.game.parent)})
            result=post('/api/link',{**payload,'editor_root':'/untrusted/injected'})
            self.assertEqual(result['settings']['editor_root'],str(editor.WEB))
            reverse=editor.read(editor.WEB/'.projects.local.json')
            self.assertEqual(next(iter(reverse['projects'].values()))['godot_executable'],'/local/godot')
            post('/api/settings',{'godot_executable':'/updated/godot'})
            self.assertEqual(next(iter(editor.read(editor.WEB/'.projects.local.json')['projects'].values()))['godot_executable'],'/updated/godot')
            editor.atomic(connection,{'session_id':'another-session'})
            editor.unpublish_service(connection);self.assertTrue(connection.exists())
            editor.atomic(connection,manifest)
            editor.unpublish_service(connection);self.assertFalse(connection.exists())
            for invalid in ['http://127.0.0.1:80@other.test','http://127.0.0.1:0','http://127.0.0.1:65536','http://localhost:8765']:
                self.assertFalse(editor.valid_service_url(invalid))
        finally:
            if service:service.shutdown();service.server_close();thread.join()
            editor.WEB=original;editor.SERVICE.clear();editor.SERVICE.update(previous)

    def test_network_roundtrip_conflicts_and_validation(self):
        document=editor.network_document();revision=editor.network_revision()
        document['stations']['编辑测试站']={'position':[300,250],'label':[10,-20]}
        document['lines'].append([99,'aabbcc',['邮电新村',[100,100],'编辑测试站','四平路']])
        document['textures'][0].update(rotation=15,opacity=.5)
        result=editor.save_network(document,revision)
        self.assertNotEqual(result['revision'],revision)
        self.assertEqual(editor.station_map(),document)
        self.assertIn('编辑测试站',editor.read(self.game/'content/stations.json'))
        with self.assertRaises(ValueError):editor.save_network(document,revision)
        for mutate in [lambda d:d['lines'][-1][2].append('不存在站点'),lambda d:d['stations'].pop('邮电新村'),lambda d:d['textures'][0].update(texture='res://../outside.png'),lambda d:d['textures'][0].update(opacity=2),lambda d:d['lines'][-1].__setitem__(2,['邮电新村','邮电新村','四平路']),lambda d:d['textures'][0].update(rotation=float('nan'))]:
            bad=copy.deepcopy(document);mutate(bad)
            with self.assertRaises(ValueError):editor.validate_network(bad)
        self.assertEqual(editor.bridge_manifest()['resources']['network'],'res://content/network_map.json')

    def test_saved_network_is_consumed_by_godot(self):
        godot=os.environ.get('METRO_GODOT')
        if not godot:self.skipTest('METRO_GODOT required')
        # Only this isolated project's data changes; no write to the live Game tree.
        doc=editor.network_document();doc['stations']['编辑测试站']={'position':[120,140],'label':[10,-20]}
        doc['lines']=[[99,'aabbcc',['邮电新村',[100,100],'编辑测试站','四平路']]]
        editor.save_network(doc,editor.network_revision())
        scripts=self.game/'scripts/content';scripts.mkdir(parents=True)
        shutil.copy2(ROOT/'Game/scripts/content/network_catalog.gd',scripts/'network_catalog.gd')
        (self.game/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Network Contract Test"\n',encoding='utf-8')
        test=self.game/'contract.gd';test.write_text('extends SceneTree\nfunc _initialize():\n var map=load("res://scripts/content/network_catalog.gd").read_network()\n assert(map.stations["编辑测试站"][0]==Vector2(120,140))\n assert(map.lines[0][2][1]==Vector2(100,100))\n assert(map.lines[0][2][2]=="编辑测试站")\n print("NETWORK_CONTRACT_OK")\n quit()\n',encoding='utf-8')
        result=subprocess.run([godot,'--headless','--path',str(self.game),'--script',str(test)],capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('NETWORK_CONTRACT_OK',result.stdout)
        self.assertNotIn('SCRIPT ERROR',result.stderr)

    def test_loose_outdoor_points_and_active_effect_validation(self):
        level=self.level();level['npcs']=[]
        level['spawn_points']=[dict(id='street_drop',row=2,x=400,container='loose',chance=1,rolls=1,choices=[dict(kind='water',weight=1)])]
        editor.validate_level('南京东路',level)
        bad=copy.deepcopy(level);bad['spawn_points'][0]['x']=-1
        with self.assertRaises(ValueError):editor.validate_level('南京东路',bad)
        bad=copy.deepcopy(level);bad['spawn_points'][0]['choices'][0]['weight']=0
        with self.assertRaises(ValueError):editor.validate_level('南京东路',bad)
        point=level['buildings'][0]['loot_points'][0];point.update(container='loose',outside=True)
        editor.validate_level('南京东路',level)
        item=editor.read(self.game/'content/items.json')['items'][0];item['active_use']={'action':'unknown','amount':25}
        with self.assertRaises(ValueError):editor.validate_item(item)

    def test_authored_content_runs_in_isolated_game(self):
        godot=os.environ.get('METRO_GODOT')
        if not godot:self.skipTest('METRO_GODOT required for runtime integration')
        # Copy source only: never mutate the user's live content or caches.
        shutil.copytree(ROOT/'Game',self.game,dirs_exist_ok=True,ignore=lambda folder,names: {name for name in names if name in {'.godot','__pycache__'} or (Path(folder)==ROOT/'Game' and name in {'runtime','build','saves'})})
        data=editor.read(self.game/'content/customers.json')
        for customer in data['customers']:customer['weight']=0
        editor.atomic(self.game/'content/customers.json',data)
        custom=copy.deepcopy(editor.catalog('items','items')[0]);custom.update(id='editor_part',name='编辑零件',texture='res://assets/textures/temp/items/scrap_metal.png',price=17.25,width=2,height=1,category='materials',rarity=1)
        editor.validate_item(custom);editor.upsert_catalog('items','items',custom)
        editor.save_customer(self.customer());editor.save_level('南京东路',self.level())
        output=Path(os.environ['METRO_TEST_RESULTS'])
        env=os.environ.copy()
        for name,folder in [('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data'),('XDG_CACHE_HOME','cache')]:
            path=Path(self.temp.name)/folder;path.mkdir(exist_ok=True);env[name]=str(path)
        for name,args in [('editor_content_import',['--editor','--import']),('editor_level_preview',['--script','res://scripts/content/preview_level.gd','--quit-after','3','--','--preview-station=南京东路']),('editor_content_runtime',['--script',str(ROOT/'test/cases/test_content_runtime.gd'),'--','--save-file='+str(output/'editor_runtime_home.json')])]:
            result=subprocess.run([godot,'--headless','--path',str(self.game)]+args,env=env,capture_output=True,text=True,timeout=100)
            log=result.stdout+result.stderr;(output/(name+'.log')).write_text(log)
            self.assertEqual(result.returncode,0,log);self.assertNotIn('SCRIPT ERROR:',log);self.assertNotIn('ERROR:',log)
            if name.endswith('runtime'):self.assertIn('CONTENT_RUNTIME_OK',log)

if __name__=='__main__':unittest.main()
