#!/usr/bin/env python3
"""Native Qt test console. No browser or WebEngine is used."""
import argparse,json,os,subprocess,sys,urllib.request
from pathlib import Path
import service

def activate(project):
    info=service.read(project/'.godot/metro_tester_connection.json');url=info.get('url','')
    if not service.re.fullmatch(r'http://127\.0\.0\.1:[0-9]{1,5}',url):return False
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args,**kwargs):return None
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    try:
        with opener.open(url+'/api/bridge',timeout=1) as r:data=json.load(r)
        if data.get('protocol')!='metro-tester' or data.get('session_id')!=info.get('session_id') or data.get('project')!=str(project):return False
        request=urllib.request.Request(url+'/api/show',data=b'{}',headers={'X-Metro-Token':info['token']})
        with opener.open(request,timeout=2) as r:return json.load(r).get('ok',False)
    except (OSError,ValueError,KeyError):return False

def run(project,godot):
    from PySide6.QtCore import Qt,QTimer,QObject,Signal,QLockFile
    from PySide6.QtWidgets import QApplication,QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,QPushButton,QLabel,QLineEdit,QTreeWidget,QTreeWidgetItem,QComboBox,QSpinBox,QFileDialog,QAbstractItemView,QStyledItemDelegate
    app=QApplication.instance() or QApplication(sys.argv[:1]);app.setApplicationName('Metro Tester')
    lockpath=project/'.godot/metro-tester/window.lock';lockpath.parent.mkdir(parents=True,exist_ok=True)
    lock=QLockFile(str(lockpath));lock.setStaleLockTime(0)
    if not lock.tryLock(0):activate(project);return 0
    backend=service.Service(project,godot)
    class Events(QObject):
        show=Signal();close=Signal()
    events=Events()
    class ValueDelegate(QStyledItemDelegate):
        def createEditor(self,parent,option,index):return super().createEditor(parent,option,index) if index.column()==1 else None
    class Window(QMainWindow):
        def __init__(self):
            super().__init__();self.setWindowTitle('Metro · 游戏测试器');self.resize(1150,850)
            central=QWidget();self.setCentralWidget(central);layout=QVBoxLayout(central)
            self.paths=QLabel();self.paths.setWordWrap(True);layout.addWidget(self.paths)
            row=QHBoxLayout();layout.addLayout(row)
            for name,callback in [('选择Godot程序',self.choose),('启动测试游戏',self.launch_game),('打开Godot编辑器',lambda:self.launch(True))]:
                b=QPushButton(name);b.clicked.connect(callback);row.addWidget(b)
            self.run=QComboBox();self.run.currentIndexChanged.connect(self.reload_tree);row.addWidget(self.run)
            self.search=QLineEdit();self.search.setPlaceholderText('筛选数值路径（如 state.health、exploration.player_x）');self.search.textChanged.connect(self.filter);layout.addWidget(self.search)
            self.tree=QTreeWidget();self.tree.setItemDelegate(ValueDelegate(self.tree));self.tree.setHeaderLabels(['数值路径','当前值（双击修改，回车提交）','类型']);self.tree.setColumnWidth(0,620);self.tree.setColumnWidth(1,200);self.tree.itemChanged.connect(self.changed);layout.addWidget(self.tree)
            direct=QHBoxLayout();layout.addLayout(direct);self.directPath=QLineEdit();self.directPath.setPlaceholderText('指定路径，例如 state.account 或 monsters.0.x');self.directValue=QLineEdit();self.directValue.setPlaceholderText('数值或 true/false');apply=QPushButton('修改指定路径');apply.clicked.connect(self.set_direct);direct.addWidget(self.directPath);direct.addWidget(self.directValue);direct.addWidget(apply)
            form=QHBoxLayout();layout.addLayout(form);self.items=QComboBox();form.addWidget(self.items)
            for item in service.read(project/'content/items.json').get('items',[]):
                if not item.get('deleted'):self.items.addItem(item.get('name',item['id'])+' · '+item['id'],item['id'])
            self.count=QSpinBox();self.count.setRange(1,100);form.addWidget(self.count);self.target=QComboBox();self.target.addItems(['bag','locker']);form.addWidget(self.target)
            spawn=QPushButton('生成物品');spawn.clicked.connect(lambda:self.send({'kind':'spawn','item':self.items.currentData(),'count':self.count.value(),'target':self.target.currentText()}));form.addWidget(spawn)
            save=QPushButton('保存到测试存档');save.clicked.connect(lambda:self.send({'kind':'save'}));form.addWidget(save)
            self.info=QLabel('等待游戏连接。数值修改仅用于测试；首次修改前会隔离存档。');self.info.setWordWrap(True);layout.addWidget(self.info)
            self.values={};self.schema=None;self.seen=set();self.timer=QTimer(self);self.timer.timeout.connect(self.poll);self.timer.start(500);self.poll()
        def choose(self):
            path,_=QFileDialog.getOpenFileName(self,'选择 Godot 可执行文件')
            if path:backend.godot=path;backend.register();self.poll()
        def launch(self,editor=False):
            if not backend.godot:self.info.setText('请从 Godot 插件启动一次以自动登记引擎，或选择 Godot 程序。');return
            args=[backend.godot,'--path',str(project)]+(['--editor'] if editor else ['--','--metro-tester'])
            log=project/'.godot/metro-tester/game.log';log.parent.mkdir(parents=True,exist_ok=True)
            try:
                with log.open('ab') as output:subprocess.Popen(args,stdout=output,stderr=output)
                self.info.setText('已启动，日志：'+str(log))
            except OSError as error:self.info.setText(str(error))
        def launch_game(self):self.launch(False)
        def reload_tree(self,*_args):self.schema=None
        def filter(self,*_args):
            query=self.search.text().lower()
            for item in self.values.values():item.setHidden(query not in item.text(0).lower())
        def send(self,command):
            try:self.info.setText('已发送指令：'+backend.queue(self.run.currentData(),command))
            except ValueError as error:self.info.setText(str(error))
        def set_direct(self):
            try:
                value=json.loads(self.directValue.text())
                if not isinstance(value,(int,float,bool)):raise ValueError('只接受数值或 true/false')
                parts=[int(v) if v.isdigit() else v for v in self.directPath.text().split('.')]
                self.send({'kind':'set','path':parts,'value':value})
            except ValueError as error:self.info.setText(str(error))
        def changed(self,item,column):
            if column!=1:return
            try:
                value=json.loads(item.text(1))
                if not isinstance(value,(int,float,bool)):raise ValueError('只接受数值或 true/false')
                self.send({'kind':'set','path':item.data(0,Qt.ItemDataRole.UserRole),'value':value})
            except ValueError as error:self.info.setText(str(error))
        def poll(self):
            runtimes,results=backend.snapshot();selected=self.run.currentData()
            self.paths.setText('项目：'+str(project)+'\nGodot：'+backend.godot+'\n测试器：'+str(service.TOOL)+'\n服务：'+backend.url)
            if [self.run.itemData(i) for i in range(self.run.count())]!=list(runtimes):
                self.run.blockSignals(True);self.run.clear()
                for key,data in runtimes.items():self.run.addItem(key+' · '+data.get('screen',''),key)
                index=self.run.findData(selected);self.run.setCurrentIndex(max(0,index));self.run.blockSignals(False)
            for i in range(self.run.count()):
                entry=runtimes[self.run.itemData(i)];self.run.setItemText(i,self.run.itemData(i)+' · '+entry.get('screen','')+(' · 已断开' if service.time.time()-entry['updated']>10 else ''))
            data=runtimes.get(self.run.currentData(),{});rows=data.get('values',[])
            if self.tree.state()!=QAbstractItemView.State.EditingState:
                self.tree.blockSignals(True);schema=[row['path'] for row in rows]
                if schema!=self.schema:
                    self.tree.clear();self.values={};self.schema=schema
                    for row in rows:
                        key=json.dumps(row['path']);item=QTreeWidgetItem(['.'.join(map(str,row['path'])),'',row['type']]);item.setData(0,Qt.ItemDataRole.UserRole,row['path']);item.setFlags(item.flags()|Qt.ItemFlag.ItemIsEditable);self.tree.addTopLevelItem(item);self.values[key]=item
                for row in rows:self.values[json.dumps(row['path'])].setText(1,json.dumps(row['value']))
                self.tree.blockSignals(False);self.filter()
            for key,result in results.items():
                if key not in self.seen:self.seen.add(key);self.info.setText(('完成：' if result.get('ok') else '失败：')+str(result.get('message','')))
        def foreground(self):self.showNormal();self.raise_();self.activateWindow()
    window=Window();events.show.connect(window.foreground);events.close.connect(window.close);backend.show=events.show.emit;backend.close=events.close.emit;window.show();backend.native_window_id=int(window.winId());backend.register()
    print('Metro tester: '+backend.url,flush=True)
    try:return app.exec()
    finally:backend.stop();lock.unlock()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--project',type=Path);parser.add_argument('--godot-executable',default='');args=parser.parse_args();project=(args.project or service.project_default()).resolve()
    if getattr(sys,'frozen',False) and not (project/'project.godot').is_file():
        from PySide6.QtWidgets import QApplication,QFileDialog
        app=QApplication.instance() or QApplication(sys.argv[:1]);selected,_=QFileDialog.getOpenFileName(None,'选择 Metro 的 project.godot',str(Path.home()),'Godot project (project.godot)')
        if not selected:return 0
        project=Path(selected).parent.resolve()
    if activate(project):return 0
    try:return run(project,args.godot_executable)
    except Exception as error:
        log=project/'.godot/metro-tester/desktop-error.log';log.parent.mkdir(parents=True,exist_ok=True);import traceback;log.write_text(traceback.format_exc(),encoding='utf-8');print(str(error)+'\n'+str(log),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
