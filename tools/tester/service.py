"""Loopback-only command queue; the Godot main thread owns all game mutations."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import sys,argparse,copy,json,math,os,re,secrets,shutil,threading,time
ROOT=Path(__file__).resolve().parents[2]
TOOL=Path(sys.executable).resolve().parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parent
if getattr(sys,'frozen',False):ROOT=next((p for p in TOOL.parents if (p/'Game/project.godot').is_file()),ROOT)
def projects_file():return Path(os.environ.get('LOCALAPPDATA',Path.home()/'.local/share'))/'MetroTester/projects.json' if getattr(sys,'frozen',False) else TOOL/'.projects.local.json'
LOCK=threading.RLock()

def read(path,default=None):
    try:return json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError,ValueError):return {} if default is None else default

def atomic(path,data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+'.'+secrets.token_hex(6)+'.tmp')
    temp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if os.name!='nt':temp.chmod(0o600)
    os.replace(temp,path)

def project_default():
    if (ROOT/'Game/project.godot').is_file():return ROOT/'Game'
    return Path(read(projects_file()).get('active_project',ROOT/'Game'))

class Service:
    def __init__(self,project,godot=''):
        self.project=Path(project).resolve()
        if not (self.project/'project.godot').is_file():raise ValueError('找不到项目 project.godot')
        self.token=secrets.token_urlsafe(32);self.session=secrets.token_hex(16)
        self.godot=godot or read(self.project/'content/editor-settings.local.json').get('godot_executable') or shutil.which('godot') or shutil.which('godot4') or ''
        self.runtimes={};self.commands={};self.results={};self.show=None;self.close=None
        owner=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def reply(self,data,code=200):
                body=json.dumps(data,ensure_ascii=False,allow_nan=False).encode()
                self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(body)
            def do_GET(self):
                if self.path=='/api/bridge':return self.reply(owner.manifest())
                self.reply({'error':'not found'},404)
            def do_POST(self):
                try:
                    if self.headers.get('X-Metro-Token')!=owner.token:return self.reply({'error':'token'},403)
                    size=int(self.headers.get('Content-Length','0'))
                    if not 0<size<=4*1024*1024:raise ValueError('请求体大小无效')
                    data=json.loads(self.rfile.read(size))
                    if self.path=='/api/link':
                        if Path(data.get('project','')).resolve()!=owner.project:raise ValueError('项目不匹配')
                        owner.godot=str(data.get('godot_executable',owner.godot));owner.register();return self.reply({'ok':True})
                    if self.path=='/api/runtime':
                        run=str(data.get('run_id',''))
                        if not run or Path(str(data.get('project',''))).resolve()!=owner.project:raise ValueError('运行项目不匹配')
                        with LOCK:
                            for result in data.get('results',[]):
                                key=str(result.get('id',''))
                                if key in owner.commands and owner.commands[key]['run_id']==run:
                                    owner.results[key]=result;owner.commands.pop(key,None)
                                    if len(owner.results)>512:owner.results.pop(next(iter(owner.results)))
                            owner.runtimes[run]={**data,'updated':time.time()}
                            pending=[v for v in owner.commands.values() if v['run_id']==run][:32]
                        return self.reply({'commands':pending,'ok':True})
                    if self.path=='/api/status':
                        runtimes,results=owner.snapshot();return self.reply({'runtimes':runtimes,'results':results})
                    if self.path=='/api/command':return self.reply({'ok':True,'id':owner.queue(data['run_id'],data['command'])})
                    if self.path=='/api/show' and owner.show:owner.show();return self.reply({'ok':True})
                    if self.path=='/api/close' and owner.close:owner.close();return self.reply({'ok':True})
                    self.reply({'error':'not found'},404)
                except (ValueError,TypeError,KeyError,OSError) as error:self.reply({'error':str(error)},400)
        self.http=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.http.daemon_threads=True
        self.url=f'http://127.0.0.1:{self.http.server_port}'
        self.thread=threading.Thread(target=self.http.serve_forever,daemon=True);self.thread.start()
        self.connection=self.project/'.godot/metro_tester_connection.json';self.register()
    def manifest(self):
        return {'protocol':'metro-tester','version':1,'kind':'native','session_id':self.session,'project':str(self.project),'tool_root':str(TOOL),'url':self.url,'pid':os.getpid(),'godot_executable':self.godot,'native_window_id':getattr(self,'native_window_id',0)}
    def register(self):
        info=self.manifest();atomic(self.connection,{**info,'token':self.token})
        atomic(self.project/'content/tester-settings.local.json',info)
        reverse=read(projects_file());reverse.update(active_project=str(self.project));reverse.setdefault('projects',{})[str(self.project)]=info;atomic(projects_file(),reverse)
    def queue(self,run,command):
        with LOCK:
            if run not in self.runtimes or time.time()-self.runtimes[run]['updated']>10:raise ValueError('游戏尚未连接或已停止')
            if not isinstance(command,dict) or command.get('kind') not in ['set','spawn','save']:raise ValueError('未知指令')
            kind=command['kind']
            if kind=='set':
                value=command.get('value');path=command.get('path')
                if not isinstance(value,(bool,int,float)) or (isinstance(value,float) and not math.isfinite(value)) or (type(value) is int and abs(value)>9007199254740991):raise ValueError('数值无效或超出安全范围')
                if not isinstance(path,list) or not 1<=len(path)<=32 or not all((isinstance(k,str) and len(k)<=256) or (type(k) is int and 0<=k<=100000) for k in path):raise ValueError('路径无效')
                command={'kind':kind,'path':path,'value':value}
            elif kind=='spawn':
                if not isinstance(command.get('item'),str) or command.get('target','bag') not in ['bag','locker'] or type(command.get('count',1)) is not int or not 1<=command.get('count',1)<=100:raise ValueError('物品数量或容器无效')
                command={'kind':kind,'item':command['item'],'target':command.get('target','bag'),'count':command.get('count',1)}
            else:command={'kind':kind}
            if len(self.commands)>256:raise ValueError('待执行指令过多')
            key=secrets.token_hex(12);self.commands[key]={**copy.deepcopy(command),'id':key,'run_id':run};return key
    def snapshot(self):
        with LOCK:return copy.deepcopy((self.runtimes,self.results))
    def stop(self):
        self.http.shutdown();self.http.server_close();self.thread.join(timeout=3)
        if read(self.connection).get('session_id')==self.session:self.connection.unlink(missing_ok=True)
