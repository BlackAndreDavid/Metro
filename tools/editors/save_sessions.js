'use strict';
// A session owns a whole editable document, including its nested inspectors.
const EditSession={key:null,baseline:null,metadata:null,depth:0,pending:null,busy:false,closeDecision:'idle'};
function lockSessionUI(){const elements=[...document.querySelectorAll('main,header,dialog:not(#unsavedDialog)')].map(element=>[element,element.inert]);for(const [element] of elements)element.inert=true;return ()=>{for(const [element,inert]of elements)element.inert=inert}}
function sessionKey(viewId){
 if(viewId==='levelView'||viewId==='catalogView'&&(C.instance!==null||C.outdoor!==undefined))return 'level/'+S.station;
 if(viewId==='catalogView')return 'catalog/'+C.kind+'/'+(C.originalId||C.data?.id||'new');
 if(viewId==='customerView')return 'customer/'+S.customer?.id;
 return viewId;
}
function sessionView(){return ['customerView','levelView','catalogView','networkView','settingsView'].find(id=>!$(id).hidden)}
function flushLevelDetail(){
 if(sessionView()!=='catalogView'||EditSession.detailObject!==C.data||JSON.stringify(C.data)===EditSession.detailBaseline)return;
 if(C.outdoor!==undefined)S.level.spawn_points[C.outdoor]=clone(C.data.loot_points[0]);
 else if(C.instance!==null&&S.level.buildings[C.instance])Object.assign(S.level.buildings[C.instance],clone(C.data));
}
function flushInspector(){
 if(sessionView()!=='levelView')return;
 const entity=EditSession.inspectedEntity;if(!entity||!entityTypes.some(type=>S.level?.[type]?.includes(entity)))return;
 const old=clone(entity);
 for(const input of $('entityFields').querySelectorAll('input[data-key],select[data-key]'))entity[input.dataset.key]=input.dataset.type==='boolean'?input.checked:input.dataset.type==='number'?+input.value:input.value;
 if(EditSession.inspectedType==='buildings')for(const point of S.level.loot||[])if(point.building===old.id){point.building=entity.id;point.row=entity.row;point.x=Math.max(entity.x+12,Math.min(entity.x+entity.width-12,point.x+entity.x-old.x));point.floor=Math.min(point.floor,entity.floors-1)}
}
function sessionData(){
 if(EditSession.key?.startsWith('customer/')){readCustomer();return {deleted:false,...clone(S.customer)}}
 if(EditSession.key?.startsWith('catalog/'))return {deleted:false,...clone(C.data)};
 if(EditSession.key?.startsWith('level/')){readLevel();flushInspector();flushLevelDetail();return clone(S.level)}
 if(EditSession.key==='networkView')return clone(N.data);
 if(EditSession.key==='settingsView')return {godot_executable:$('godotPath').value.trim()};
 return null;
}
EditSession.hasChanges=function(){
 if(!this.key||this.baseline===null)return false;
 try{return this.metadata?.fresh||JSON.stringify(sessionData())!==JSON.stringify(this.baseline)}catch(_error){return true}
};
EditSession.refresh=function(){
 if(!this.key||this.depth)return;
 try{const changed=this.hasChanges();$('dirty').textContent=(changed?'● 未保存 · ':'✓ 已保存 · ')+this.title();if(this.key==='networkView')N.dirty=changed}catch(error){$('dirty').textContent='● 未保存';}
};
EditSession.title=function(){
 if(this.key?.startsWith('level/'))return S.station+' · 关卡';
 if(this.key?.startsWith('catalog/'))return catalogTitles[C.kind]+' · '+(C.data?.name||C.data?.id);
 if(this.key?.startsWith('customer/'))return '顾客 · '+S.customer?.name;
 return this.key==='networkView'?'线路地图':'总设置';
};
EditSession.enter=function(key){
 this.key=key;this.metadata={kind:C.kind,originalId:C.originalId,fresh:key.startsWith('catalog/')?!C.originalId:key.startsWith('customer/')?S.customer?._create===true:false};
 this.baseline=sessionData();this.refresh();
};
EditSession.execute=function(key,action){
 this.depth++;let result;
 try{result=action()}catch(error){this.depth--;throw error}
 const finish=value=>{this.enter(typeof key==='function'?key():key);return value};
 if(result?.then){const unlock=lockSessionUI();return result.finally(()=>{this.depth--;unlock()}).then(finish)}
 this.depth--;return finish(result);
};
EditSession.discard=function(){
 const value=clone(this.baseline);this.depth++;
 try{
  if(this.key.startsWith('catalog/')){selectCatalog(value);C.originalId=this.metadata.originalId}
  else if(this.key.startsWith('customer/'))showCustomer(value);
  else if(this.key.startsWith('level/')){showLevel(value);W.undo=[];if(sessionView()==='catalogView'){if(C.outdoor!==undefined)C.data.loot_points=[clone(value.spawn_points[C.outdoor])];else if(C.instance!==null)C.data=clone(value.buildings[C.instance]);}}
  else if(this.key==='networkView'){N.data=value;N.history=[];N.dirty=false;N.selection=null;renderNetwork()}
  else $('godotPath').value=value.godot_executable;
 }finally{this.depth--}
 this.metadata.fresh=false;this.baseline=sessionData();this.refresh();
};
EditSession.save=async function(){
 if(this.busy)throw Error('正在保存，请稍候。');this.busy=true;status('正在保存当前编辑项…');const unlock=lockSessionUI();
 try{
  const data=sessionData(),key=this.key;
  if(key.startsWith('catalog/')){
   if(C.kind==='items'&&!checkItemId())throw Error('请修正重复或无效的物品ID');
   await api(C.kind==='items'?'/api/item':C.kind==='enemies'?'/api/enemy':'/api/building-template',C.kind==='items'?{...data,_original_id:C.originalId??''}:data);
   C.originalId=data.id;
  }else if(key.startsWith('customer/')){await api('/api/customer',data);delete S.customer._create}
  else if(key.startsWith('level/')){
   await api('/api/level',{station:S.station,definition:data});
  }else if(key==='networkView'){
   const result=await api('/api/network-map',{definition:data,revision:N.revision});N.revision=result.revision;N.dirty=false;
  }else if(key==='settingsView'){const result=await api('/api/settings',data);S.project.settings=result.settings;godotPathEdited=false}
  S.project=await api('/api/project');
  if(key.startsWith('catalog/')){renderCatalogCards();renderPalette()}
  if(key.startsWith('customer/')){listCustomers();$('customerId').readOnly=true}
  if(key==='networkView'){const station=S.station;$('stations').replaceChildren();for(const name of S.project.stations)option($('stations'),name,name);$('stations').value=station;updateStationBanner();$('networkState').textContent='✓ 地图已保存'}
  if(key.startsWith('level/')&&sessionView()==='catalogView'){sessionViewBase('levelView');C.instance=null;delete C.outdoor;listEntities();drawMap()}
  this.enter(sessionKey(sessionView()));this.metadata.fresh=false;this.refresh();status((key.startsWith('level/')?'关卡':key.startsWith('customer/')?'顾客':key.startsWith('catalog/')?catalogTitles[C.kind]:'设置')+'已保存：'+this.title());return true;
 }finally{unlock();this.busy=false}
};
const saveDialog=document.createElement('dialog');saveDialog.id='unsavedDialog';saveDialog.innerHTML='<h2>保存当前编辑项？</h2><p id="unsavedMessage"></p><p id="unsavedError" role="alert"></p><div class="bar"><button id="unsavedSave" class="primary">保存并离开</button><button id="unsavedDiscard">放弃修改</button><button id="unsavedCancel">取消</button></div>';document.body.append(saveDialog);
EditSession.ask=function(){
 if(this.pending)return this.pending;
 $('unsavedMessage').textContent=this.title()+' 有未保存的内容。';$('unsavedError').textContent='';
 this.pending=new Promise(resolve=>{
  const done=value=>{saveDialog.close();this.pending=null;if(!value){$('stations').value=S.station;$('customers').value=S.project.customers.findIndex(c=>c.id===S.customer?.id)}resolve(value)};
  $('unsavedSave').onclick=async()=>{for(const b of saveDialog.querySelectorAll('button'))b.disabled=true;try{await this.save();done(true)}catch(error){$('unsavedError').textContent='保存失败：'+error.message;status(error.message,true)}finally{for(const b of saveDialog.querySelectorAll('button'))b.disabled=false}};
  $('unsavedDiscard').onclick=()=>{this.discard();done(true)};
  $('unsavedCancel').onclick=()=>done(false);
  saveDialog.oncancel=e=>{e.preventDefault();if(!this.busy)done(false)};
  saveDialog.showModal();$('unsavedCancel').focus();
 });return this.pending;
};
EditSession.navigate=function(key,action,force=false){
 if(this.depth)return action();
 if(this.pending||this.busy)return;
 const target=typeof key==='function'?key():key;
 if(!force&&target===this.key)return action();
 const proceed=()=>this.execute(key,action);
 if(this.hasChanges())return this.ask().then(ok=>ok?proceed():undefined);
 return proceed();
};
EditSession.requestClose=function(){
 if(this.closeDecision==='waiting')return;
 this.closeDecision='waiting';
 try{Promise.resolve(this.hasChanges()?this.ask():true).then(ok=>{this.closeDecision=ok?'approved':'cancelled'})}catch(error){this.closeDecision='cancelled';status(error.message,true)}
};
window.EditorSession=EditSession;
// Guard document entry points, not individual field changes or nested dialogue turns.
const sessionViewBase=view;view=function(id){
 const target=sessionKey(id);
 return EditSession.navigate(target,()=>{flushInspector();flushLevelDetail();if(id!=='levelView')EditSession.inspectedEntity=null;sessionViewBase(id);if(id==='levelView'){C.instance=null;delete C.outdoor;listEntities();drawMap()}});
};
const sessionCatalogView=viewCatalog;viewCatalog=function(kind){
 if(sessionView()==='catalogView'&&C.kind===kind&&C.instance===null&&C.outdoor===undefined)return;
 return EditSession.navigate(()=>sessionKey('catalogView'),()=>sessionCatalogView(kind),true);
};
const sessionSelectCatalog=selectCatalog;selectCatalog=function(data){if(!EditSession.depth&&sessionView()==='catalogView'&&EditSession.key==='catalog/'+C.kind+'/'+data.id)return;return EditSession.navigate('catalog/'+C.kind+'/'+data.id,()=>sessionSelectCatalog(data))};
const sessionNewCatalog=newCatalog;newCatalog=function(){return EditSession.navigate(()=>sessionKey('catalogView'),()=>sessionNewCatalog(),true)};$('newCatalog').onclick=run(newCatalog);
const sessionCustomer=showCustomer;showCustomer=function(data){if(!EditSession.depth&&sessionView()==='customerView'&&EditSession.key==='customer/'+data.id)return;return EditSession.navigate('customer/'+data.id,()=>sessionCustomer(data))};
const sessionNewCustomer=$('newCustomer').onclick;$('newCustomer').onclick=run(()=>EditSession.navigate(()=>sessionKey('customerView'),sessionNewCustomer,true));
const sessionStation=selectStation;selectStation=function(name){if(!EditSession.depth&&EditSession.key==='level/'+name){$('stations').value=S.station;$('stationDialog').close();return}return EditSession.navigate('level/'+name,()=>sessionStation(name))};$('stations').onchange=run(()=>selectStation($('stations').value));
// These tab handlers must await the guard before performing asynchronous loads.
$('customerTab').onclick=run(()=>view('customerView'));$('levelTab').onclick=run(()=>view('levelView'));
$('networkTab').onclick=run(()=>EditSession.navigate('networkView',async()=>{sessionViewBase('networkView');if(!N.data)await loadNetwork();else renderNetwork()}));
$('settingsTab').onclick=run(()=>EditSession.navigate('settingsView',async()=>{sessionViewBase('settingsView');godotPathEdited=false;await syncIntegrationPaths()}));
$('networkReload').onclick=run(()=>EditSession.navigate('networkView',loadNetwork,true));
$('cloneLevel').onclick=run(async()=>{let applied=false;await EditSession.navigate('level/'+S.station,async()=>{const result=await api('/api/level?station='+encodeURIComponent('邮电新村'));showLevel(cloneTemplate(result.template));applied=true},true);if(applied){EditSession.metadata.fresh=true;EditSession.refresh()}});
for(const id of ['saveAll','saveCatalog','saveCustomer','saveLevel','saveSettings','networkSave'])$(id).onclick=run(()=>EditSession.save());
$('returnToLevel').onclick=run(()=>view('levelView'));
// Sub-inspectors belong to the map, so their edits are applied as one map draft.
$('saveCatalog').textContent='保存当前编辑项';$('saveAll').textContent='保存当前编辑项';
$('archiveCatalog').onclick=run(()=>{if(C.instance!==null||C.outdoor!==undefined){checkpoint();if(C.outdoor!==undefined){S.level.spawn_points.splice(C.outdoor,1);delete C.outdoor}else{const id=S.level.buildings[C.instance].id;S.level.buildings.splice(C.instance,1);S.level.loot=S.level.loot.filter(p=>p.building!==id);C.instance=null}sessionViewBase('levelView');S.entity=-1;refreshMap()}else{C.data.deleted=!C.data.deleted;renderCatalogForm();dirty()}});
archiveCustomer.onclick=run(()=>{S.customer.deleted=!S.customer.deleted;archiveCustomer.textContent=S.customer.deleted?'恢复当前顾客':'－ 删除当前顾客（归档）';dirty()});
$('previewGodot').onclick=run(async()=>{await EditSession.save();await api('/api/godot',{action:'preview',station:S.station});status('当前关卡已保存并启动 Godot 预览。')});
dirty=function(){queueMicrotask(()=>EditSession.refresh())};
for(const type of ['input','change','click','pointerup'])document.addEventListener(type,()=>queueMicrotask(()=>EditSession.refresh()));
document.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='s'){e.preventDefault();run(()=>EditSession.save())()}});
window.addEventListener('beforeunload',e=>{if(EditSession.hasChanges()){e.preventDefault();e.returnValue=''}});
// Initial data arrives asynchronously after script loading.
if(S.project&&S.customer)EditSession.enter(sessionKey(sessionView()));

// Removing a reusable building asset is staged in its own document as well.
async function stageBuildingArchive(id){
 let selected=false;
 await EditSession.navigate('catalog/building_templates/'+id,()=>{
  C.kind='building_templates';C.instance=null;delete C.outdoor;sessionViewBase('catalogView');
  sessionSelectCatalog(S.project.building_templates.find(entry=>entry.id===id));selected=true;
 });
 if(selected){C.data.deleted=true;renderCatalogForm();dirty();status('建筑素材已标记归档；保存当前建筑后生效。')}
}

const sessionCatalogForm=renderCatalogForm;
renderCatalogForm=function(){
 const result=sessionCatalogForm();
 if((C.instance!==null||C.outdoor!==undefined)&&EditSession.detailObject!==C.data){EditSession.detailObject=C.data;EditSession.detailBaseline=JSON.stringify(C.data)}
 return result;
};

// Inspector changes stay in the map draft even when another object is selected.
const sessionEntityForm=entityForm;
entityForm=function(){
 flushInspector();const result=sessionEntityForm();
 EditSession.inspectedEntity=S.level?.[S.type]?.[S.entity];EditSession.inspectedType=S.type;
 return result;
};
if(S.level&&sessionView()==='levelView'){EditSession.inspectedEntity=S.level?.[S.type]?.[S.entity];EditSession.inspectedType=S.type}
