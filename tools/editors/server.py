#!/usr/bin/env python3
"""Local customer and station editor. Binds only to loopback; writes validated game content."""
import argparse
import base64
import copy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import math
from pathlib import Path
import re
import secrets
import tempfile
import threading
import os
import sys
import subprocess
import shutil
from urllib.parse import parse_qs, urlparse
from PIL import Image, ImageSequence

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / 'Game'
WEB = Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parent))/'editors' if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
if getattr(sys,'frozen',False):
    ROOT=next((p for p in Path(sys.executable).resolve().parents if (p/'Game/project.godot').is_file()),ROOT)
    GAME=ROOT/'Game'
def tool_root():return Path(sys.executable).resolve().parent if getattr(sys,'frozen',False) else WEB
def projects_file():
    return Path(os.environ.get('LOCALAPPDATA',Path.home()/'.local/share'))/'MetroEditor/projects.json' if getattr(sys,'frozen',False) else WEB/'.projects.local.json'
SERVICE = {}
DESKTOP_STATE = None
DESKTOP_ACTION = None
CATEGORIES = {'supplies','power','materials','documents'}
ITEMS = {'computer','water','ration','meds','aaa','car_battery','powercore','copper','circuit','steel_plate','bolts','tire','engine','tools','book','relic'}
ID = re.compile(r'^[a-z][a-z0-9_-]{0,63}$')

def read(path): return json.loads(Path(path).read_text(encoding='utf-8'))
def atomic(path, value):
    path = Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    text = json.dumps(value,ensure_ascii=False,indent=2)+'\n' if not isinstance(value,str) else value
    with tempfile.NamedTemporaryFile('w',encoding='utf-8',dir=path.parent,delete=False) as file:
        file.write(text); temp = file.name
    os.replace(temp,path)
def require(ok, message):
    if not ok: raise ValueError(message)
def number(value, low, high):
    return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value) and low <= value <= high
def integer(value, low, high): return number(value,low,high) and int(value)==value
def resource(path):
    require(isinstance(path,str) and path.startswith('res://'),'资源路径必须以 res:// 开头')
    resolved = (GAME/path[6:]).resolve()
    require(resolved.is_relative_to(GAME.resolve()),'资源必须位于 Game 内')
    return resolved

def art_sprites():
    for path in [GAME/'assets/source/temp/manifest.json',ROOT/'Game/assets/source/temp/manifest.json']:
        if path.is_file():return read(path).get('sprites',[])
    return []

def catalog(name,key):
    path=GAME/'content'/(name+'.json')
    return read(path if path.exists() else ROOT/'Game/content'/(name+'.json')).get(key,[])
def item_ids(): return {name for v in catalog('items','items') for name in [v['id'],v.get('runtime_id',v['id']),*v.get('aliases',[])]}
def upsert_catalog(name,key,data):
    entries=catalog(name,key);old=next((e for e in entries if e['id']==data['id']),None)
    if old is not None: entries[entries.index(old)]=data
    else:entries.append(data)
    atomic(GAME/'content'/(name+'.json'),{'version':1,key:entries})
ITEM_LOCK=threading.RLock()
def save_item(raw):
    data=copy.deepcopy(raw);original=data.pop('_original_id',None)
    with ITEM_LOCK:
        entries=catalog('items','items')
        old=next((e for e in entries if e['id']==(original if original is not None else data.get('id'))),None)
        require(original is None or original=='' or old is not None,'原物品已变化，请重新读取目录')
        reserved={name for e in entries if e is not old for name in [e['id'],e.get('runtime_id',e['id']),*e.get('aliases',[])]}
        require(data.get('id') not in reserved,'物品ID重复或已被旧ID映射占用')
        data['runtime_id']=old.get('runtime_id',old['id']) if old else data.get('id')
        aliases=set(old.get('aliases',[])) if old else set()
        if old and old['id']!=data.get('id'):aliases.add(old['id'])
        aliases.discard(data.get('id'));data['aliases']=sorted(aliases)
        validate_item(data)
        if old:entries[entries.index(old)]=data
        else:entries.append(data)
        atomic(GAME/'content/items.json',{'version':1,'items':entries})
    return data

def validate_texture(path,optional=False):
    if optional and not path:return
    file=resource(path);require(file.is_file() and file.suffix.lower()=='.png','请选择工程内PNG或上传素材')
def validate_enemy(data):
    require(isinstance(data,dict) and ID.fullmatch(data.get('id','')) and isinstance(data.get('name'),str) and data['name'],'怪物ID或名称无效')
    require(isinstance(data.get('enabled',True),bool),'启用状态无效')
    sprite=data.get('sprite',{});validate_texture(sprite.get('texture',''))
    require(integer(sprite.get('frames'),1,64) and number(sprite.get('fps'),0.1,60),'动画帧数/帧率无效')
    with Image.open(resource(sprite['texture'])) as image: require(image.width%int(sprite['frames'])==0,'横向帧条宽度必须能被帧数整除')
    for key in ['width','height','collision_width','collision_height']:require(number(sprite.get(key),1,1024),'显示或碰撞尺寸无效')
    movement=data.get('movement',{})
    for key in ['patrol_speed','chase_speed']:require(number(movement.get(key),0,2000),'移动速度无效')
    for key in ['patrol_min','patrol_max','wait_seconds','chase_seconds']:require(number(movement.get(key),0.05,60),'移动/停留时间无效')
    require(movement['patrol_min']<=movement['patrol_max'],'最短巡逻时间不能大于最长时间')
    alert=data.get('alert',{})
    for key in ['cone_length','circle_radius']:require(number(alert.get(key),0,4096),'警觉距离无效')
    require(number(alert.get('cone_angle'),0,360),'视锥角度无效')
    for key in ['visual_gain','sound_gain','decay_per_second']:require(number(alert.get(key),0,100),'警觉增减量无效')
    attack=data.get('attack',{})
    require(number(attack.get('jump_height',24),0,256),'扑起高度无效')
    for key in ['range','speed']:require(number(attack.get(key),0,4096),'攻击距离/速度无效')
    for key in ['duration','recovery']:require(number(attack.get(key),0.05,60),'攻击时间无效')
    require(number(attack.get('time_penalty'),0,90) and number(attack.get('slow_seconds'),0,60) and number(attack.get('slow_multiplier'),0.05,1),'攻击效果无效')
def validate_binding(data):
    if 'texture_binding' not in data:return
    binding=data['texture_binding']
    require(isinstance(binding,dict) and all(number(binding.get(k),-4096 if k in ['x','y'] else 0.01,4096) for k in ['x','y','width','height']) and number(binding.get('rotation',0),-360,360),'贴图绑定位置、尺寸或角度无效')

def validate_building_geometry(data):
    validate_binding(data)
    if data.get('collision'):require(isinstance(data['collision'],dict) and all(number(data['collision'].get(k),-4096 if k in ['x','y'] else 1,4096) for k in ['x','y','width','height']),'建筑碰撞箱无效')
    if 'floor_positions' in data:
        floors=data['floor_positions']
        require(isinstance(floors,list) and len(floors)==data['floors'] and all(number(y,0,2000) for y in floors) and all(b-a>=24 for a,b in zip(floors,floors[1:])),'地板位置须逐层上升且间距至少24')

def item_names(item):
    return [item['id'],item.get('runtime_id',item['id']),*item.get('aliases',[])]

def validate_furniture(data):
    require(isinstance(data,dict) and ID.fullmatch(data.get('id','')) and isinstance(data.get('name'),str) and 0<len(data['name'])<=80,'家具ID或名称无效')
    require(integer(data.get('width'),1,35) and integer(data.get('height'),1,12),'家具占位范围须在35×12内')
    validate_texture(data.get('texture',''))
    require(all(isinstance(data[key],bool) for key in ['enabled','default_owned','support_surface','fill_grid','initial_placed'] if key in data),'家具开关字段须为布尔值')
    require(isinstance(data.get('function_text',''),str) and len(data.get('function_text',''))<=200,'家具功能说明无效')
    require(data.get('placement_type','floor') in ['floor','hanging'],'家具摆放类型无效')
    for plane in ['floor_cells','wall_cells']:
        cells=data.get(plane,[])
        require(isinstance(cells,list) and all(isinstance(c,list) and len(c)==2 and integer(c[0],0,data['width']-1) and integer(c[1],0,data['height']-1) for c in cells) and len({tuple(c) for c in cells})==len(cells),'家具墙面/地面占位格无效或重复')
    require(data.get('floor_cells') or data.get('wall_cells') or data.get('placement_type')=='hanging','家具至少需要一种占位格')
    if data.get('placement_type')=='hanging':require(data['width']<=4 and data['height']<=3,'吊杆挂件不能超过4×3')
    require(data.get('interaction','none') in ['none','rest','news','gear','locker','trade','map','preparation','storage'],'家具互动功能无效')
    animation=data.get('animation',{'frames':1,'columns':1,'fps':6})
    require(isinstance(animation,dict) and integer(animation.get('frames'),1,128) and integer(animation.get('columns'),1,animation['frames']) and number(animation.get('fps'),.1,60),'动画帧数、列数或帧率无效')
    with Image.open(resource(data['texture'])) as source_image:image_width,image_height=source_image.size
    require(image_width*image_height<=16*1024*1024,'家具贴图过大');rows=math.ceil(animation['frames']/animation['columns'])
    require(image_width%animation['columns']==0 and image_height%rows==0,'动画帧表宽高必须能被列数和行数整除')
    durations=animation.get('durations')
    if durations is not None:require(isinstance(durations,list) and len(durations)==animation['frames'] and all(number(v,1,60000) for v in durations),'动画帧时长无效')
    storage=data.get('storage')
    if data['id'] in ['locker','preparation']:require(storage is not None,'基地柜子与预备仓库须保留储物功能，避免丢失现有物品')
    if storage is not None:require(isinstance(storage,dict) and integer(storage.get('width'),1,16) and integer(storage.get('height'),1,16),'储物格尺寸须为1～16')
    require(isinstance(data.get('effects',[]),list) and all(isinstance(v,str) and 0<len(v)<=80 for v in data.get('effects',[])),'家具效果标签无效')
    definitions={v['id']:v for v in catalog('furniture','furniture')};definitions[data['id']]=data
    require(isinstance(data.get('distance_rules',[]),list),'距离规则无效')
    for rule in data.get('distance_rules',[]):
        require(isinstance(rule,dict) and rule.get('target_type') in ['furniture','effect'] and isinstance(rule.get('target'),str) and 0<len(rule['target'])<=80 and rule.get('relation') in ['require','exclude'] and number(rule.get('distance'),0,100),'需求/排斥距离规则无效')
        if rule['target_type']=='furniture':require(rule['target'] in definitions and rule['target']!=data['id'],'需求/排斥家具不存在或引用自身')
    item_id=data.get('item_id','')
    require(isinstance(item_id,str),'家具物品属性无效')
    if item_id:
        items={name:item for item in catalog('items','items') for name in item_names(item)}
        require(item_id in items,'关联物品不存在，请先创建物品')
        for other in definitions.values():require(other['id']==data['id'] or not other.get('item_id') or other.get('item_id') not in item_names(items[item_id]),'该物品已关联其他家具')
    placement=data.get('default_placement')
    if placement is not None:
        require(isinstance(placement,dict) and integer(placement.get('car'),0,2) and integer(placement.get('x'),0,35-data['width']) and integer(placement.get('y'),0,12-data['height']),'默认家具位置超出车厢')
        if data.get('placement_type')=='hanging':require(integer(placement.get('mount'),0,3) and placement['x']+data['width']<=4 and placement['y']+data['height']<=3,'默认挂点位置无效')
    if 'texture_binding' in data:validate_binding(data)

def validate_item(data):
    require(isinstance(data,dict) and ID.fullmatch(data.get('id','')) and isinstance(data.get('name'),str) and data['name'],'物品ID或名称无效')
    require(integer(data.get('width'),1,8) and integer(data.get('height'),1,8),'物品占格必须为1～8')
    require(number(data.get('price'),0,1000000) and integer(data.get('rarity'),0,3) and data.get('category') in CATEGORIES|{'none'},'物品价格、稀有度或类别无效')
    effect=data.get('active_use',{'action':'none','amount':1})
    require(isinstance(effect,dict) and effect.get('action') in ('none','drink','eat','heal') and number(effect.get('amount',1),1,100),'主动使用效果无效')
    if 'cells' in data:
        cells=data['cells']
        require(isinstance(cells,list) and 0<len(cells)<=64 and all(isinstance(c,list) and len(c)==2 and integer(c[0],0,data['width']-1) and integer(c[1],0,data['height']-1) for c in cells) and len({tuple(c) for c in cells})==len(cells),'不规则占位格无效、为空或重复')
    validate_binding(data)
    validate_texture(data.get('texture',''))
def validate_points(building):
    validate_building_geometry(building)
    require(number(building.get('light_level',0.15),0,1),'建筑光照须为0～1')
    points=building.get('loot_points',[]);require(isinstance(points,list) and len(points)<=32,'每栋建筑最多32个柜子点位')
    ids=set()
    for point in points:
        require(ID.fullmatch(point.get('id','')) and point['id'] not in ids,'柜子ID无效或重复');ids.add(point['id'])
        require(number(point.get('x'),0,building['width']) and integer(point.get('floor',0),0,building['floors']-1),'物资点位置/楼层无效')
        if 'region' in point:
            region=point['region'];require(isinstance(region,dict) and region.get('type') in ('line','arc'),'掉落区域类型无效')
            for key in (['start','end','control'] if region['type']=='arc' else ['start','end']):
                coord=region.get(key);require(isinstance(coord,list) and len(coord)==2 and number(coord[0],0,building['width']) and number(coord[1],0,200),'掉落区域控制点超出范围')
        require(point.get('container','cabinet') in ('cabinet','loose') and isinstance(point.get('outside',False),bool),'物资点类型无效')
        require(number(point.get('chance'),0,1) and integer(point.get('rolls'),1,8),'生成概率或抽取次数无效')
        choices=point.get('choices',[])
        require(isinstance(choices,list) and 0<len(choices)<=100 and all(c.get('kind') in item_ids() and number(c.get('weight'),0,100000) for c in choices) and sum(c['weight'] for c in choices)>0,'掉落物品或权重无效')
def migrate_level(data):
    data=copy.deepcopy(data)
    for i,point in enumerate(data.get('loot',[])):
        owner=next((b for b in data['buildings'] if b['id']==point.get('building')),None)
        if owner is None:
            candidates=[b for b in data['buildings'] if b['row']==point['row']]
            if candidates:owner=min(candidates,key=lambda b:abs(b['x']+b['width']/2-point['x']))
            else:
                starts=data.get('street_starts',[0]*len(data['cell_names']));lo=starts[point['row']];hi=lo+data['segment']*len(data['cell_names'][point['row']])
                owner={'id':'cache_house_'+str(i),'name':'储物间','row':point['row'],'x':max(lo+24,min(hi-124,point['x']-50)),'width':100,'floors':1,'wall':'#625957'};data['buildings'].append(owner)
        kind=point.get('kind','')
        choices=[{'kind':kind,'weight':1}] if kind else [{'kind':'book','weight':45},{'kind':'copper','weight':35},{'kind':'water','weight':20}]
        owner.setdefault('loot_points',[]).append({'id':'legacy_'+str(i),'x':max(12,min(owner['width']-12,point['x']-owner['x'])),'floor':min(point.get('floor',0),owner['floors']-1),'chance':1,'rolls':1,'choices':choices,'legacy_slot':i})
    data['loot']=[]
    data.setdefault('monsters',[])
    data.setdefault('street_starts',[0]*len(data['cell_names']))
    return data

def conditions(value):
    require(isinstance(value,dict),'条件必须是对象')
    allowed={'stations','day_min','day_max','account_min','account_max','debt_min','debt_max','completed_min','has_items','flags_all','flags_none','blackout','affection_min','affection_max','trust_min','trust_max','events_all'}
    require(set(value)<=allowed,'未知条件字段')
    for key,term in value.items():
        if key=='stations': require(isinstance(term,list) and set(term)<=set(read(GAME/'content/stations.json')),'条件站点无效')
        elif key in ['flags_all','flags_none','events_all']: require(isinstance(term,list) and all(isinstance(x,str) and 0<len(x)<=128 for x in term),'标记条件须为字符串数组')
        elif key=='has_items': require(isinstance(term,dict) and all(k in item_ids() and integer(v,1,1000) for k,v in term.items()),'物品条件无效')
        elif key=='blackout': require(isinstance(term,bool),'停电条件须为布尔值')
        else: require(number(term,-100 if key.startswith(('affection','trust')) else 0,1000000),'数值条件超出范围')

def effects(value):
    require(isinstance(value,dict) and set(value)<= {'affection','trust','set_flags'},'效果字段无效')
    for key in ['affection','trust']: require(number(value.get(key,0),-100,100),'好感/信任变化须在 -100～100')
    require(isinstance(value.get('set_flags',[]),list) and all(isinstance(x,str) and 0<len(x)<=128 for x in value.get('set_flags',[])),'效果标记无效')

def validate_customer(data):
    require(isinstance(data,dict) and ID.fullmatch(data.get('id','')),'顾客ID须为英文小写、数字、短横线或下划线')
    require(isinstance(data.get('name'),str) and 0<len(data['name'])<=80,'顾客名称不能为空')
    texture=resource(data.get('texture',''))
    require(texture.is_file() and texture.suffix.lower()=='.png','请选择 Game 内的 PNG 贴图或先上传')
    require(number(data.get('base_budget'),0,1000000),'基础预算无效')
    require(number(data.get('weight'),0,100000),'出现权重无效')
    require(isinstance(data.get('enabled'),bool),'启用字段无效')
    for key in ['buy_categories','sell_categories']:
        require(isinstance(data.get(key),list) and set(data[key])<=CATEGORIES,'买卖类别无效')
    items={name:v for v in catalog('items','items') for name in [v['id'],v.get('runtime_id',v['id']),*v.get('aliases',[])]}
    for side in ['buy','sell']:
        groups=data.get(side+'_item_weights',{})
        require(isinstance(groups,dict) and set(groups)<=CATEGORIES,'物品权重类别无效')
        for category,weights in groups.items():
            require(isinstance(weights,dict) and all(kind in items and items[kind].get('category')==category and number(weight,0,100000) for kind,weight in weights.items()),'具体物品或权重无效')
            if category in data[side+'_categories'] and data.get('enabled') and data.get('trade_enabled',True):require(any(weight>0 for weight in weights.values()),'启用的买卖类别至少需要一个正权重物品')
    quantities=data.get('sell_item_counts',{})
    require(isinstance(quantities,dict) and set(quantities)<=CATEGORIES,'出售数量类别无效')
    for category,entries in quantities.items():
        require(isinstance(entries,dict),'出售数量配置无效')
        for kind,bounds in entries.items():
            require(kind in items and items[kind].get('category')==category and isinstance(bounds,dict) and integer(bounds.get('min'),0,100) and integer(bounds.get('max'),0,100) and bounds['min']<=bounds['max'],'出售数量须为0～100且下限不大于上限')
    require(data['buy_categories'] or data['sell_categories'] or not data['enabled'] or not data.get('trade_enabled',True),'启用顾客至少需要一个买入或卖出类别')
    require(set(data.get('stations',[]))<=set(read(GAME/'content/stations.json')),'顾客站点无效')
    require(isinstance(data.get('stories',[]),list),'剧情须为数组')
    require(data.get('faction','none') in ['red','yellow','blue','none'],'阵营无效')
    require(isinstance(data.get('trade_enabled',True),bool),'交易启用字段无效')
    ids=set()
    for story in data.get('stories',[]):
        require(isinstance(story,dict) and ID.fullmatch(story.get('id','')) and story['id'] not in ids,'剧情ID无效或重复'); ids.add(story['id'])
        require(integer(story.get('priority',0),-1000,1000) and isinstance(story.get('once',True),bool),'剧情优先级/单次字段无效')
        conditions(story.get('conditions',{}))
        require(isinstance(story.get('contexts',['trade']),list) and bool(story.get('contexts',['trade'])) and set(story.get('contexts',['trade'])) <= {'trade','exploration'},'互动场景无效')
        require(isinstance(story.get('after',[]),list),'前置事件须为数组')
        for event in story.get('after',[]):
            require(isinstance(event,dict) and ID.fullmatch(event.get('npc',data['id'])) and ID.fullmatch(event.get('story','')) and integer(event.get('days',1),0,10000),'前置事件或间隔天数无效')
        nodes=story.get('nodes',{})
        require(isinstance(nodes,dict) and 0<len(nodes)<=200 and story.get('start') in nodes,'剧情必须包含有效的起始节点')
        for key,node in nodes.items():
            require(ID.fullmatch(key) and isinstance(node,dict) and isinstance(node.get('text'),str),'节点ID或文本无效')
            require(isinstance(node.get('set_flags',[]),list) and all(isinstance(x,str) and 0<len(x)<=128 for x in node.get('set_flags',[])),'节点标记无效')
            effects(node.get('effects',{}))
            choices=node.get('choices',[]); require(isinstance(choices,list) and len(choices)<=12,'分支数量无效')
            require(not node.get('next') or node['next'] in nodes,'继续节点不存在')
            for choice in choices:
                require(isinstance(choice,dict) and isinstance(choice.get('text'),str) and bool(choice['text']),'分支文字不能为空')
                require(not choice.get('next') or choice['next'] in nodes,'分支目标不存在')
                conditions(choice.get('conditions',{}))
                effects(choice.get('effects',{}))
        # Every reachable node must have a path to an ending; cycles with no exit are rejected.
        ending={k for k,n in nodes.items() if (not n.get('choices') and not n.get('next')) or any(not c.get('next') for c in n.get('choices',[]))}
        for _ in nodes:
            ending |= {k for k,n in nodes.items() if n.get('next') in ending or any(c.get('next') in ending for c in n.get('choices',[]))}
        require(set(nodes)<=ending,'剧情中存在无法结束的循环/节点，请增加结束分支')
    known={c['id']:c for c in read(GAME/'content/customers.json')['customers']}; known[data['id']]=data
    for story in data.get('stories',[]):
        for event in story.get('after',[]):
            parent=known.get(event.get('npc',data['id']),{})
            require(any(s['id']==event['story'] for s in parent.get('stories',[])),'前置 NPC 或剧情不存在，请先保存前置角色与事件')

def validate_level(station,data):
    require(station in read(GAME/'content/stations.json'),'请选择已有地铁站')
    require(isinstance(data,dict) and ID.fullmatch(data.get('id','')),'关卡ID无效')
    require(number(data.get('segment'),256,1600) and number(data.get('ground'),200,480) and number(data.get('floor_height'),50,130),'地图尺寸无效')
    cells=data.get('cell_names',[])
    require(isinstance(cells,list) and 1<=len(cells)<=8 and all(isinstance(r,list) and 1<=len(r)<=8 for r in cells),'地图须为1–8条街道、每条1–8个分段')
    require(all(isinstance(n,str) and n for r in cells for n in r),'地图格名称无效')
    width=data['segment']*max(map(len,cells))
    starts=data.get('street_starts',[0]*len(cells))
    require(isinstance(starts,list) and len(starts)==len(cells) and all(number(x,0,8000) for x in starts),'街道起点须为0～8000，数量须与街道一致')
    def row_start(row):return starts[int(row)]
    def row_width(row): return row_start(row)+data['segment']*len(cells[int(row)])
    require(data.get('loot_station') in read(GAME/'content/stations.json'),'战利品来源站无效')
    for key in ['stations','buildings','junctions','loot','vehicles']:
        require(isinstance(data.get(key),list) and len(data[key])<=200,'地图对象列表无效')
        for entry in data[key]:
            require(isinstance(entry,dict) and integer(entry.get('row'),0,len(cells)-2 if key=='junctions' else len(cells)-1),'对象街道无效')
            limit=min(row_width(entry['row']),row_width(entry['row']+1)) if key=='junctions' else row_width(entry['row'])
            require(number(entry.get('x'),(max(row_start(entry['row']),row_start(entry['row']+1)) if key=='junctions' else row_start(entry['row']))+24,limit-24),'对象横坐标超出所在街道；巷口必须位于相邻街道共同范围')
    points=data.get('spawn_points',[])
    require(isinstance(points,list) and len(points)<=200,'室外物资点列表无效')
    ids=set()
    for point in points:
        require(integer(point.get('row'),0,len(cells)-1),'物资点街道无效')
        require(number(point.get('x'),row_start(point['row'])+24,row_width(point['row'])-24),'物资点超出街道')
        require(point.get('id') not in ids,'物资点ID重复');ids.add(point.get('id'))
        validate_points({'width':row_width(point['row']),'floors':1,'loot_points':[dict(point,floor=0)]})
    require(any(s.get('name')==station for s in data['stations']),'关卡必须有本站入口/撤离口')
    require(all(s.get('name') in read(GAME/'content/stations.json') for s in data['stations']),'撤离站点名称无效')
    require(number(data.get('grid_size',20),5,200),'栅格大小须在5～200')
    npcs=data.get('npcs',[])
    require(isinstance(npcs,list) and len(npcs)<=200,'NPC列表无效')
    known={c['id'] for c in read(GAME/'content/customers.json')['customers']}
    placed=set()
    for npc in npcs:
        require(isinstance(npc,dict) and npc.get('npc') in known and npc['npc'] not in placed,'NPC不存在或在关卡内重复'); placed.add(npc['npc'])
        require(integer(npc.get('row'),0,len(cells)-1) and number(npc.get('x'),row_start(npc['row'])+24,row_width(npc['row'])-24),'NPC位置无效')
    buildings={}
    for building in data['buildings']:
        require(ID.fullmatch(building.get('id','')) and building['id'] not in buildings,'建筑ID无效或重复')
        require(isinstance(building.get('name'),str) and building['name'] and number(building.get('width'),100,width) and building['x']+building['width']<=row_width(building['row']),'建筑名称、宽度或边界无效')
        require(integer(building.get('floors'),1,8),'建筑楼层须为1～8')
        require(re.fullmatch(r'#[0-9a-fA-F]{6}',building.get('wall','')),'墙体颜色须为#RRGGBB')
        validate_texture(building.get('texture',''),True)
        validate_points(building)
        collision=building.get('collision',{})
        if collision:require(all(number(collision.get(k),-4096 if k in ['x','y'] else 1,4096) for k in ['x','y','width','height']),'建筑碰撞箱无效')
        buildings[building['id']]=building
    vehicle_ids=set()
    for vehicle in data['vehicles']:
        require(ID.fullmatch(vehicle.get('id','')) and vehicle['id'] not in vehicle_ids,'汽车ID无效或重复'); vehicle_ids.add(vehicle['id'])
        require(re.fullmatch(r'#[0-9a-fA-F]{6}',vehicle.get('color','')),'汽车颜色须为#RRGGBB')
    for point in data['loot']:
        require(point.get('kind','') in item_ids()|{''},'物资种类无效')
        building=point.get('building','')
        require(not building or building in buildings,'物资引用的建筑不存在')
        require(integer(point.get('floor'),0,buildings[building]['floors']-1 if building else 0),'物资楼层无效')
        if building:
            b=buildings[building]; require(point['row']==b['row'] and b['x']<=point['x']<=b['x']+b['width'],'室内物资必须在对应建筑内')
    definitions={e['id']:e for e in catalog('enemies','enemies')}
    monsters=data.get('monsters',[]);require(isinstance(monsters,list) and len(monsters)<=200,'怪物布置无效')
    ids=set()
    for monster in monsters:
        require(ID.fullmatch(monster.get('id','')) and monster['id'] not in ids and monster.get('enemy') in definitions,'怪物布置ID重复或类型不存在');ids.add(monster['id'])
        require(integer(monster.get('row'),0,len(cells)-1) and monster.get('facing',-1) in [-1,1],'怪物街道或朝向无效')
        half=definitions[monster['enemy']]['sprite']['collision_width']/2
        require(number(monster.get('x'),row_start(monster['row'])+half,row_width(monster['row'])-half),'怪物碰撞箱超出所在街道')


def save_customer(data):
    data=copy.deepcopy(data); create=data.pop('_create',False)
    validate_customer(data)
    document=read(GAME/'content/customers.json'); entries=document['customers']
    require(not create or not any(c['id']==data['id'] for c in entries),'顾客ID已存在，请为新顾客使用独立ID')
    for index,old in enumerate(entries):
        if old['id']==data['id']: entries[index]=data; break
    else: entries.append(data)
    atomic(GAME/'content/customers.json',document)

def save_level(station,data):
    validate_level(station,data)
    data=migrate_level(data)
    validate_level(station,data)
    slug='station_'+hashlib.sha256(station.encode()).hexdigest()[:12]
    scene=f'res://scenes/exploration/stations/{slug}.tscn'
    level=f'res://content/levels/{slug}.json'
    data=copy.deepcopy(data); data['id']=slug
    atomic(resource(level),data)
    atomic(resource(scene),'[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://scenes/game/exploration.tscn" id="1"]\n[node name="Exploration" instance=ExtResource("1")]\n')
    registry=read(GAME/'content/registry.json'); registry['stations'][station]={'level':level,'scene':scene}
    atomic(GAME/'content/registry.json',registry)
    return registry['stations'][station]

NETWORK_LOCK = threading.Lock()
def network_document():
    path=GAME/'content/network_map.json'
    return read(path if path.exists() else ROOT/'Game/content/network_map.json')

def network_revision():
    path=GAME/'content/network_map.json'
    return hashlib.sha256((path if path.exists() else ROOT/'Game/content/network_map.json').read_bytes()).hexdigest()

def station_map():
    return network_document()

def validate_network(data):
    require(isinstance(data,dict) and data.get('version')==1,'线路图版本无效')
    canvas=data.get('canvas',{})
    require(all(number(canvas.get(k),200,8000) for k in ('width','height')),'画布尺寸须为200～8000')
    def vector(value,low=-8000,high=8000):
        return isinstance(value,list) and len(value)==2 and all(number(v,low,high) for v in value)
    stations=data.get('stations',{})
    require(isinstance(stations,dict) and 1<=len(stations)<=500,'站点数量须为1～500')
    for name,entry in stations.items():
        require(isinstance(name,str) and 0<len(name)<=40 and isinstance(entry,dict),'站点名称无效')
        require(vector(entry.get('position'),0,8000) and vector(entry.get('label',[]),-500,500),'站点位置或文字偏移无效')
    # Existing gameplay references and save destinations must remain resolvable.
    require(set(read(GAME/'content/stations.json'))<=set(stations),'已有游戏站点不能删除或更名；可从线路移除连接节点')
    lines=data.get('lines',[]);require(isinstance(lines,list) and len(lines)<=100,'线路最多100条')
    numbers=set()
    for line in lines:
        require(isinstance(line,list) and len(line)==3 and integer(line[0],1,999) and line[0] not in numbers,'线路编号须为1～999且不可重复');numbers.add(line[0])
        require(isinstance(line[1],str) and re.fullmatch(r'[0-9a-fA-F]{6}',line[1]),'线路颜色须为六位色值')
        route=line[2];require(isinstance(route,list) and 2<=len(route)<=1000,'每条线路至少两个节点，最多1000个')
        require(all((point in stations if isinstance(point,str) else vector(point,0,8000)) for point in route),'线路引用了不存在的站点或无效坐标')
        stops=[point for point in route if isinstance(point,str)]
        unique=stops[:-1] if len(stops)>1 and stops[0]==stops[-1] else stops
        require(len(unique)==len(set(unique)),'同一线路不可重复经过同一站点（首尾闭环除外）')
    textures=data.get('textures',[]);require(isinstance(textures,list) and len(textures)<=100,'地图贴图最多100张')
    ids=set()
    for image in textures:
        require(isinstance(image,dict) and ID.fullmatch(image.get('id','')) and image['id'] not in ids,'贴图ID无效或重复');ids.add(image['id'])
        validate_texture(image.get('texture',''))
        require(vector(image.get('position')) and vector(image.get('size'),1,8000),'贴图位置或尺寸无效')
        require(number(image.get('rotation',0),-360,360) and number(image.get('opacity',1),0,1) and isinstance(image.get('visible',True),bool),'贴图旋转、透明度或显示状态无效')

def save_network(data,revision):
    with NETWORK_LOCK:
        require(revision==network_revision(),'线路图已被其他窗口修改，请重新读取后再编辑')
        validate_network(data)
        atomic(GAME/'content/network_map.json',data)
        atomic(GAME/'content/stations.json',list(data['stations']))
        return {'ok':True,'revision':network_revision(),'definition':data}

def bridge_manifest():
    return {**SERVICE,'editor_root':str(tool_root()),'window':DESKTOP_STATE,'protocol':'metro-editor','version':1,'project':str(GAME),'network':'/api/network-map','resources':{'network':'res://content/network_map.json','stations':'res://content/stations.json','registry':'res://content/registry.json'},'layers':['textures','lines'],'writes':'X-Editor-Token required','runtime':'Godot reads local JSON directly; reload when reopening map'}

def linked_project():
    path=projects_file()
    if path.exists():
        try:
            linked=read(path).get('active_project','')
            if isinstance(linked,str) and linked and (Path(linked)/'project.godot').is_file():return Path(linked)
        except (OSError,ValueError,AttributeError):pass
    return ROOT/'Game'

def editor_settings():
    path=GAME/'content/editor-settings.local.json'
    settings=read(path) if path.exists() else {'godot_executable':shutil.which('godot') or shutil.which('godot4') or ''}
    return {**settings,'project':str(GAME),'editor_root':str(tool_root())}

def register_project(godot_executable=None, integration=None):
    """One shared implementation of the persisted project <-> editor relationship."""
    settings=editor_settings()
    if godot_executable is not None:settings['godot_executable']=godot_executable
    settings.update(project=str(GAME),editor_root=str(tool_root()),integration=integration or SERVICE.get('kind','desktop'),protocol_version=1)
    if SERVICE:settings.setdefault('services',{})[SERVICE['kind']]=dict(SERVICE)
    atomic(GAME/'content/editor-settings.local.json',settings)
    reverse_path=projects_file()
    try:reverse=read(reverse_path) if reverse_path.exists() else {}
    except (OSError,ValueError):reverse={}
    projects=reverse.get('projects',{})
    projects[hashlib.sha256(str(GAME).encode()).hexdigest()]={'project':str(GAME),'editor_root':str(tool_root()),'godot_executable':settings.get('godot_executable',''),'services':settings.get('services',{})}
    reverse.update(version=1,active_project=str(GAME),projects=projects)
    atomic(reverse_path,reverse)
    return settings

def valid_service_url(url):
    return isinstance(url,str) and re.fullmatch(r'http://127\.0\.0\.1:[0-9]{1,5}',url) is not None and 0<int(url.rsplit(':',1)[1])<=65535

def publish_service(url, kind, connection):
    """Publish only this process's actual loopback listener and paths; never execute them."""
    import sys
    require(valid_service_url(url),'仅允许本机服务地址')
    require(connection.resolve().is_relative_to(GAME.resolve()),'连接文件必须位于工程内')
    SERVICE.clear()
    SERVICE.update(url=url,kind=kind,pid=os.getpid(),project=str(GAME),editor_root=str(tool_root()),python_executable=sys.executable,protocol='metro-editor',version=1,session_id=secrets.token_hex(16))
    register_project(integration=kind)
    atomic(connection,SERVICE)

def unpublish_service(connection):
    try:
        if read(connection).get('session_id')==SERVICE.get('session_id'):connection.unlink(missing_ok=True)
    except (OSError,ValueError):pass
    # Persistent paths remain useful after exit. Godot verifies the listener before linking.


def godot_action(data):
    settings=editor_settings(); executable=settings.get('godot_executable','')
    require(isinstance(executable,str) and bool(executable),'请先在总设置填写 Godot 可执行文件路径')
    resolved=shutil.which(executable) or str(Path(executable).expanduser().resolve())
    require(Path(resolved).is_file(),'Godot 可执行文件不存在')
    action=data.get('action','probe')
    require(action in ['probe','editor','game','preview'],'未知 Godot 操作')
    probe=subprocess.run([resolved,'--version'],capture_output=True,text=True,timeout=10,check=True)
    if action=='probe': return {'ok':True,'version':probe.stdout.strip(),'project':str(GAME)}
    args=[resolved,'--path',str(GAME)]
    if action=='editor': args+=['--editor']
    if action=='preview':
        station=data.get('station',''); require(station in read(GAME/'content/registry.json')['stations'],'请先保存关卡')
        args+=['--script','res://scripts/content/preview_level.gd','--','--preview-station='+station]
    log=ROOT/'test/results/logs/content-editor-godot.log'; log.parent.mkdir(parents=True,exist_ok=True)
    with log.open('ab') as output: subprocess.Popen(args,stdout=output,stderr=output,start_new_session=True)
    return {'ok':True,'version':probe.stdout.strip(),'log':str(log)}

class Handler(BaseHTTPRequestHandler):
    token=''
    def log_message(self,*args): pass
    def respond(self,value,code=200):
        data=json.dumps(value,ensure_ascii=False).encode(); self.send_response(code); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        route=urlparse(self.path)
        try:
            if route.path=='/api/network-map':return self.respond({'definition':network_document(),'revision':network_revision()})
            if route.path=='/api/bridge':return self.respond(bridge_manifest())
            if route.path=='/api/settings':return self.respond({'settings':editor_settings(),'service':dict(SERVICE)})
            if route.path=='/api/project': return self.respond({'furniture':catalog('furniture','furniture'),'enemies':catalog('enemies','enemies'),'items':catalog('items','items'),'art':art_sprites(),'station_map':station_map(),'building_templates':read(GAME/'content/building_templates.json' if (GAME/'content/building_templates.json').exists() else ROOT/'Game/content/building_templates.json')['templates'],'settings':editor_settings(),'token':self.token,'stations':read(GAME/'content/stations.json'),'customers':read(GAME/'content/customers.json')['customers'],'registry':read(GAME/'content/registry.json'),'categories':{'supplies':'生活补给','power':'电力用品','materials':'工业材料','documents':'文书旧物'}})
            if route.path=='/api/level':
                station=parse_qs(route.query).get('station',['邮电新村'])[0]; entry=read(GAME/'content/registry.json')['stations'].get(station)
                return self.respond({'definition':migrate_level(read(resource(entry['level']))) if entry else None,'template':migrate_level(read(GAME/'content/levels/postal.json'))})
            if route.path=='/asset':
                path=resource(parse_qs(route.query).get('path',[''])[0]); require(path.suffix.lower()=='.png','只能预览PNG'); data=path.read_bytes(); mime='image/png'
            else:
                file={'/':'index.html','/editor.js':'editor.js','/style.css':'style.css','/enhancements.js':'enhancements.js','/models.js':'models.js','/workspace.js':'workspace.js','/catalogs.js':'catalogs.js','/network_editor.js':'network_editor.js','/geometry_editor.js':'geometry_editor.js','/save_sessions.js':'save_sessions.js','/furniture_editor.js':'furniture_editor.js'}.get(route.path)
                if not file: return self.respond({'error':'未找到'},404)
                path=WEB/file; data=path.read_bytes(); mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8'}[path.suffix]
            self.send_response(200); self.send_header('Content-Type',mime); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
        except (ValueError,KeyError,TypeError,FileNotFoundError) as error: self.respond({'error':str(error)},400)
    def do_POST(self):
        try:
            require(self.headers.get('X-Editor-Token')==self.token,'编辑令牌无效，请刷新页面')
            length=int(self.headers.get('Content-Length','0')); require(0<length<=16*1024*1024,'请求体过大或为空')
            data=json.loads(self.rfile.read(length))
            if self.path in ['/api/desktop/show','/api/desktop/close']:
                require(DESKTOP_ACTION is not None,'当前服务不是独立编辑器程序')
                DESKTOP_ACTION(self.path.rsplit('/',1)[1]);return self.respond({'ok':True})
            if self.path=='/api/network-map':return self.respond(save_network(data.get('definition'),data.get('revision')))
            if self.path=='/api/network-image':
                require(ID.fullmatch(data.get('id','')),'贴图ID无效')
                image=Image.open(io.BytesIO(base64.b64decode(data.get('data','').split(',')[-1],validate=True)))
                require(0<image.width*image.height<=16*1024*1024,'图片尺寸过大')
                path='res://assets/maps/'+data['id']+'.png';target=resource(path);target.parent.mkdir(parents=True,exist_ok=True);image.convert('RGBA').save(target)
                return self.respond({'ok':True,'texture':path,'size':list(image.size)})
            if self.path=='/api/furniture':
                original=data.pop('_original_id',data.get('id'))
                entries=catalog('furniture','furniture')
                require(original==data.get('id') or not original,'已有家具ID不可改名')
                require(original or not any(v['id']==data.get('id') for v in entries),'家具ID已存在')
                validate_furniture(data)
                upsert_catalog('furniture','furniture',data)
                items=catalog('items','items')
                for item in items:
                    if data.get('item_id') in item_names(item):item['furniture_kind']=data['id']
                    elif item.get('furniture_kind')==data['id']:item['furniture_kind']=''
                atomic(GAME/'content/items.json',{'version':1,'items':items})
                return self.respond({'ok':True})
            if self.path=='/api/furniture-image':
                require(ID.fullmatch(data.get('id','')),'家具素材ID无效')
                image=Image.open(io.BytesIO(base64.b64decode(data['data'].split(',')[-1],validate=True)))
                count=getattr(image,'n_frames',1);require(1<=count<=128 and image.width*image.height*count<=16*1024*1024,'动画或图片过大')
                frames=[];durations=[]
                for frame in ImageSequence.Iterator(image):frames.append(frame.convert('RGBA').copy());durations.append(max(1,int(frame.info.get('duration',100))))
                columns=math.ceil(math.sqrt(count));rows=math.ceil(count/columns)
                sheet=Image.new('RGBA',(image.width*columns,image.height*rows))
                for index,frame in enumerate(frames):sheet.paste(frame,((index%columns)*image.width,(index//columns)*image.height))
                path='res://assets/textures/furniture/'+data['id']+'.png';target=resource(path);target.parent.mkdir(parents=True,exist_ok=True);sheet.save(target)
                return self.respond({'texture':path,'animation':{'frames':count,'columns':columns,'fps':min(60,max(.1,1000/(sum(durations)/count))),'durations':durations}})
            if self.path=='/api/enemy':validate_enemy(data);upsert_catalog('enemies','enemies',data);return self.respond({'ok':True})
            if self.path=='/api/item':return self.respond({'ok':True,'item':save_item(data)})
            if self.path=='/api/catalog/archive':
                name=data.get('catalog');require(name in ['customers','items','enemies','building_templates'],'目录无效')
                key={'building_templates':'templates'}.get(name,name);entries=catalog(name,key)
                target=next((v for v in entries if v['id']==data.get('id')),None);require(target is not None,'条目不存在')
                target['deleted']=bool(data.get('deleted',True));target['enabled']=not target['deleted']
                atomic(GAME/'content'/(name+'.json'),{'version':1,key:entries});return self.respond({'ok':True})
            if self.path=='/api/content-image':
                require(ID.fullmatch(data.get('id','')) and data.get('kind') in ['enemies','items','buildings'],'素材ID/类型无效')
                image=Image.open(io.BytesIO(base64.b64decode(data['data'].split(',')[-1],validate=True))).convert('RGBA')
                require(image.width*image.height<=16*1024*1024 and image.getchannel('A').getbbox() is not None,'图片过大或完全透明')
                suffix=data['kind']+'/'+data['id']+'.png';source=GAME/'assets/source/temp/custom'/suffix;runtime=GAME/'assets/textures/temp/custom'/suffix
                source.parent.mkdir(parents=True,exist_ok=True);runtime.parent.mkdir(parents=True,exist_ok=True);image.save(source);image.save(runtime)
                return self.respond({'ok':True,'texture':'res://assets/textures/temp/custom/'+suffix})
            if self.path=='/api/building-template':
                require(ID.fullmatch(data.get('id','')) and isinstance(data.get('name'),str) and 0<len(data['name'])<=80,'建筑素材ID或名称无效')
                require(number(data.get('width'),100,1600) and integer(data.get('floors'),1,8) and re.fullmatch(r'#[0-9a-fA-F]{6}',data.get('wall','')),'建筑素材尺寸、楼层或颜色无效')
                validate_texture(data.get('texture',''),True);validate_points(data)
                path=GAME/'content/building_templates.json'
                template_document=read(path if path.exists() else ROOT/'Game/content/building_templates.json')
                template_document['templates']=[t for t in template_document['templates'] if t['id']!=data['id']]+[data]
                atomic(path,template_document)
                return self.respond({'ok':True})
            if self.path=='/api/link':
                require(isinstance(data.get('project'),str) and Path(data['project']).resolve()==GAME.resolve(),'项目不匹配')
                require(isinstance(data.get('godot_executable'),str) and len(data['godot_executable'])<=1024,'Godot路径无效')
                return self.respond({'ok':True,'settings':register_project(data['godot_executable'])})
            if self.path=='/api/settings':
                require(isinstance(data.get('godot_executable'),str) and len(data['godot_executable'])<=1024,'Godot路径无效')
                register_project(data['godot_executable'],integration=SERVICE.get('kind','browser'))
                return self.respond({'ok':True,'settings':editor_settings()})
            if self.path=='/api/godot': return self.respond(godot_action(data))
            if self.path=='/api/customer': save_customer(data); return self.respond({'ok':True})
            if self.path=='/api/level': return self.respond({'ok':True,**save_level(data['station'],data['definition'])})
            if self.path=='/api/upload':
                require(ID.fullmatch(data.get('id','')),'请先填写顾客ID')
                image=Image.open(io.BytesIO(base64.b64decode(data['data'].split(',')[-1],validate=True))).convert('RGBA')
                require(image.width*image.height<=16*1024*1024,'贴图尺寸过大')
                source=GAME/'assets/source/customers'/('editor_'+data['id']+'.png'); source.parent.mkdir(parents=True,exist_ok=True); image.save(source)
                box=image.getchannel('A').getbbox(); require(box is not None,'贴图完全透明'); image=image.crop(box)
                scale=min(46/image.width,78/image.height); image=image.resize((max(1,round(image.width*scale)),max(1,round(image.height*scale))),Image.Resampling.NEAREST)
                runtime=Image.new('RGBA',(48,80)); runtime.alpha_composite(image,((48-image.width)//2,79-image.height))
                path='res://assets/textures/customers/editor_'+data['id']+'.png'; runtime.save(resource(path))
                return self.respond({'ok':True,'texture':path})
            self.respond({'error':'未找到'},404)
        except (ValueError,KeyError,TypeError,OSError,subprocess.SubprocessError) as error: self.respond({'error':str(error)},400)

def main():
    global GAME
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--connection-file',type=Path); parser.add_argument('--port',type=int,default=8765); parser.add_argument('--no-browser',action='store_true'); parser.add_argument('--project',type=Path,default=None); args=parser.parse_args()
    if not args.no_browser:
        import desktop
        return desktop.main(['--project',str(args.project)] if args.project else [])
    GAME=(args.project or linked_project()).resolve()
    require((GAME/'project.godot').is_file(),'项目目录内找不到 project.godot')
    Handler.token=secrets.token_urlsafe(24)
    server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler)
    url=f'http://127.0.0.1:{server.server_port}'; print('Metro editors: '+url,flush=True)
    connection=(args.connection_file or GAME/'.godot/metro_browser_connection.json').resolve()
    publish_service(url,'browser',connection)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        server.server_close();unpublish_service(connection)
if __name__=='__main__': raise SystemExit(main())
