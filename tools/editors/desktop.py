#!/usr/bin/env python3
"""Metro desktop editor: a native Qt application window sharing the existing editor UI/API.
Does not launch a browser. Qt supplies the window, file chooser, menus and web view.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import sys
import threading
import traceback
import urllib.request
import urllib.error
import server


def activate_existing(connection, project):
    try:
        info=server.read(connection)
        url=info['url']
        if info.get('kind')!='desktop' or not server.valid_service_url(url):return False
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self,*args,**kwargs):return None
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
        with opener.open(url+'/api/bridge',timeout=1) as response:bridge=json.load(response)
        if bridge.get('protocol')!='metro-editor' or bridge.get('version')!=1 or bridge.get('session_id')!=info.get('session_id') or Path(bridge['project']).resolve()!=project or not isinstance(bridge.get('window'),dict) or bridge['window'].get('kind')!='desktop':return False
        with opener.open(url+'/api/project',timeout=1) as response:token=json.load(response)['token']
        request=urllib.request.Request(url+'/api/desktop/show',data=b'{}',headers={'Content-Type':'application/json','X-Editor-Token':token})
        with opener.open(request,timeout=2) as response:return json.load(response).get('ok',False)
    except (OSError,ValueError,KeyError,TypeError,AttributeError):return False


def run_window(project,connection):
    from PySide6.QtCore import QObject,QSettings,QUrl,Signal,QEvent,Qt,QLockFile,QTimer
    from PySide6.QtGui import QAction,QIcon,QKeySequence
    from PySide6.QtWidgets import QApplication,QMainWindow,QMessageBox
    from PySide6.QtWebEngineCore import QWebEnginePage,QWebEngineProfile
    from PySide6.QtWebEngineWidgets import QWebEngineView

    app=QApplication.instance() or QApplication(sys.argv[:1]);app.setApplicationName('Metro Content Editor');app.setOrganizationName('Metro');app.setApplicationVersion('2.0')
    lock_path=project/'.godot/metro-editor/instance.lock';lock_path.parent.mkdir(parents=True,exist_ok=True)
    lock=QLockFile(str(lock_path));lock.setStaleLockTime(0)
    if not lock.tryLock(0):
        activate_existing(connection,project)
        return 0
    service=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler);service.daemon_threads=True
    server.Handler.token=secrets.token_urlsafe(24)
    url=f'http://127.0.0.1:{service.server_port}'
    worker=threading.Thread(target=service.serve_forever,daemon=True);worker.start()

    class Actions(QObject):
        show=Signal()
        close=Signal()
    actions=Actions()
    profile=QWebEngineProfile('metro-editor',app)
    cache=project/'.godot/metro-editor'
    profile.setCachePath(str(cache/'cache'));profile.setPersistentStoragePath(str(cache/'storage'))
    profile.setPersistentCookiesPolicy(QWebEngineProfile.PersistentCookiesPolicy.NoPersistentCookies)

    class EditorWindow(QMainWindow):
        def __init__(self):
            super().__init__();self.setWindowTitle('Metro · 内容编辑器');self.setWindowIcon(QIcon(str(project/'assets/icons/icon.svg')))
            self.settings=QSettings(str(cache/'window.ini'),QSettings.Format.IniFormat)
            self.view=QWebEngineView(self);self.view.setContextMenuPolicy(Qt.ContextMenuPolicy.NoContextMenu)
            self.page=QWebEnginePage(profile,self.view);self.view.setPage(self.page);self.setCentralWidget(self.view)
            self.loaded=False;self.approved=False;self.checking_close=False;self.renderer_lost=False
            self.view.loadFinished.connect(lambda ok:setattr(self,'loaded',ok))
            self.page.renderProcessTerminated.connect(self.render_failed)
            menu=self.menuBar().addMenu('文件')
            save=QAction('保存当前编辑',self);save.setShortcut(QKeySequence.StandardKey.Save)
            save.triggered.connect(lambda:self.page.runJavaScript("document.getElementById('saveAll')?.click()"));menu.addAction(save)
            menu.addSeparator()
            close=QAction('退出编辑器',self);close.setShortcut(QKeySequence.StandardKey.Quit);close.triggered.connect(self.close);menu.addAction(close)
            view_menu=self.menuBar().addMenu('视图')
            reload=QAction('重新加载界面',self);reload.setShortcut(QKeySequence.StandardKey.Refresh);reload.triggered.connect(self.request_reload);view_menu.addAction(reload)
            self.statusBar().showMessage('正在编辑：'+str(project))
            self.resize(1440,960)
            geometry=self.settings.value('geometry')
            if geometry:self.restoreGeometry(geometry)
            self.view.setUrl(QUrl(url))
        def request_reload(self):
            self.page.runJavaScript("window.EditorSession ? (window.EditorSession.closeDecision='idle',window.EditorSession.requestClose(),true) : false",self.begin_reload)
        def begin_reload(self,waiting):
            if waiting:QTimer.singleShot(100,self.poll_reload)
            else:self.view.reload()
        def poll_reload(self):
            self.page.runJavaScript("window.EditorSession.closeDecision",self.reload_result)
        def reload_result(self,decision):
            if decision=='approved':self.view.reload()
            elif decision!='cancelled':QTimer.singleShot(100,self.poll_reload)
        def render_failed(self,*_args):
            self.renderer_lost=True;self.statusBar().showMessage('界面进程已停止，已保存的内容不受影响；可从视图菜单重新加载。')
        def foreground(self):
            if self.isMinimized():self.showNormal()
            else:self.show()
            self.raise_();self.activateWindow()
        def closeEvent(self,event):
            if self.approved or not self.loaded or self.renderer_lost:
                self.settings.setValue('geometry',self.saveGeometry());event.accept();return
            event.ignore()
            if self.checking_close:return
            self.checking_close=True
            self.page.runJavaScript("Boolean(window.EditorSession)",self.begin_close)
        def begin_close(self,available):
            if not available:
                self.page.runJavaScript("document.getElementById('dirty')?.textContent.includes('未保存')",self.confirm_close)
                return
            self.page.runJavaScript("window.EditorSession.requestClose()")
            QTimer.singleShot(100,self.poll_close)
        def poll_close(self):
            self.page.runJavaScript("window.EditorSession.closeDecision",self.close_result)
        def close_result(self,decision):
            if decision=='approved':
                self.checking_close=False;self.approved=True;self.close()
            elif decision=='cancelled':self.checking_close=False
            else:QTimer.singleShot(100,self.poll_close)
        def confirm_close(self,dirty):
            self.checking_close=False
            if dirty:
                choice=QMessageBox.question(self,'尚未保存','有尚未保存的编辑。继续编辑并保存，或放弃修改后关闭？',QMessageBox.StandardButton.Discard|QMessageBox.StandardButton.Cancel,QMessageBox.StandardButton.Cancel)
                if choice!=QMessageBox.StandardButton.Discard:return
            self.approved=True;self.close()

    window=EditorWindow()
    actions.show.connect(window.foreground);actions.close.connect(window.close)
    server.DESKTOP_ACTION=lambda action:actions.show.emit() if action=='show' else actions.close.emit()
    server.DESKTOP_STATE={'kind':'desktop','pid':os.getpid(),'title':window.windowTitle(),'native_window_id':int(window.winId())}
    server.publish_service(url,'desktop',connection)
    window.show()
    try:
        return app.exec()
    finally:
        service.shutdown();service.server_close();worker.join(timeout=2)
        window.page.deleteLater();app.sendPostedEvents(None,QEvent.Type.DeferredDelete)
        profile.deleteLater();app.sendPostedEvents(None,QEvent.Type.DeferredDelete)
        server.unpublish_service(connection)
        server.DESKTOP_ACTION=None;server.DESKTOP_STATE=None;lock.unlock()


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path)
    parser.add_argument('--godot-executable',default='')
    parser.add_argument('--connection-file',type=Path)
    args=parser.parse_args(argv)
    project=(args.project or server.linked_project()).resolve()
    if getattr(sys,'frozen',False) and not (project/'project.godot').is_file():
        from PySide6.QtWidgets import QApplication,QFileDialog
        app=QApplication.instance() or QApplication(sys.argv[:1])
        selected,_=QFileDialog.getOpenFileName(None,'选择 Metro 的 project.godot',str(Path.home()),'Godot project (project.godot)')
        if not selected:return 0
        project=Path(selected).parent.resolve()
    server.require((project/'project.godot').is_file(),'找不到游戏 project.godot')
    server.GAME=project
    if getattr(sys,"frozen",False):server.ROOT=project.parent
    connection=(args.connection_file or project/'.godot/metro_editor_connection.json').resolve()
    server.require(connection.is_relative_to(project),'连接文件必须位于工程内')
    if activate_existing(connection,project):return 0
    connection.unlink(missing_ok=True)
    try:
        log_path=project/".godot/metro_editor_desktop.log";log_path.parent.mkdir(parents=True,exist_ok=True)
        log=log_path.open("a",encoding="utf-8",buffering=1);sys.stdout=log;sys.stderr=log
        try:os.dup2(log.fileno(),1);os.dup2(log.fileno(),2)
        except OSError:pass
        server.register_project(args.godot_executable or None)
        return run_window(project,connection)
    except Exception as error:
        log=project/'.godot/metro_editor_desktop.log';log.parent.mkdir(parents=True,exist_ok=True)
        log.write_text(traceback.format_exc(),encoding='utf-8')
        message=('缺少桌面编辑器依赖。请安装：python -m pip install -r tools/editors/requirements-desktop.txt' if isinstance(error,ImportError) else str(error))
        server.atomic(connection,{'kind':'desktop-error','pid':os.getpid(),'error':message,'log':str(log)})
        print(message,file=sys.stderr)
        return 2
if __name__=='__main__':raise SystemExit(main())
