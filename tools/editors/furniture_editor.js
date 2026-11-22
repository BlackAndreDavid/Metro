'use strict';
// Furniture definitions share the catalogue, document save flow and item texture registry.
catalogTitles.furniture='家具';
const furnitureTab=button('家具',()=>viewCatalog('furniture'));furnitureTab.id='furnitureTab';$('buildingTab').after(furnitureTab);
const F={cellType:1,start:null,end:null,scale:32,textureMode:'move',drag:null,frameRects:new WeakMap()};

// A cell is stored once: 0 empty, 1 physical, 2 wall. Hanging reference cells are view-only.
function normalizeFurnitureGrid(d){
 if(d.placement_type==='hanging'){d.reference_cells??=Array.from({length:d.width*d.height},(_,i)=>[i%d.width,Math.floor(i/d.width)]);d.occupancy_grid=[];d.hanging_anchor??={x:.5,y:.5}}
 else{delete d.hanging_anchor;const old=d.occupancy_grid;d.occupancy_grid=Array.from({length:d.height},(_,y)=>Array.from({length:d.width},(_,x)=>old?.[y]?.[x]||0));if(!old){for(const [key,state]of [['wall_cells',2],['floor_cells',1]])for(const [x,y]of d[key]||[])if(d.occupancy_grid[y]&&x<d.width)d.occupancy_grid[y][x]=state}d.reference_cells=[]}
 delete d.floor_cells;delete d.wall_cells;delete d.support_surface;
}
function furniturePaintCells(d){return d.placement_type==='hanging'?(d.reference_cells||[]).map(([x,y])=>[x,y,3]):(d.occupancy_grid||[]).flatMap((row,y)=>row.flatMap((state,x)=>state?[[x,y,state]]:[]))}
function furnitureCellColor(state){return ['#514b67','#e2b778','#659fdc','#ffffff'][state]}

const furnitureNew=newCatalog;newCatalog=function(){
 if(C.kind!=='furniture')return furnitureNew();
 let index=1;while(S.project.furniture.some(v=>v.id==='furniture_'+index))index++;
 C.data={id:'furniture_'+index,name:'新家具',enabled:true,texture:'res://assets/textures/Locker.png',animation:{frames:1,columns:1,fps:6},width:2,height:2,occupancy_grid:[[1,1],[1,1]],placement_type:'floor',interaction:'none',function_text:'查看家具',storage:null,item_id:'',effects:[],distance_rules:[],default_placement:null,default_owned:true,known:true,required_technology:{},build_cost:{steel_plate:1,bolts:2},dismantle_cost:{tools:1},salvage:{steel_plate:1}};
 C.originalId='';C.instance=null;delete C.outdoor;renderCatalogForm();dirty();
};
function furnitureSelect(object,key,label,entries){const wrap=document.createElement('label'),select=document.createElement('select');wrap.textContent=label;for(const [value,text]of entries)option(select,value,text);select.value=key==='item_id'?(S.project.items.find(v=>itemNames(v).includes(object[key]))?.id||object[key]||''):(object[key]??'');select.dataset.field=key;select.onchange=()=>{object[key]=select.value;renderCatalogForm();dirty()};wrap.append(select);return wrap}
const furnitureForm=renderCatalogForm;renderCatalogForm=function(){
 if(C.kind!=='furniture'){furnitureTextureTools.hidden=true;return furnitureForm()}
 const d=C.data,form=$('catalogForm');if(!d)return;d.known??=true;normalizeFurnitureGrid(d);const hanging=d.placement_type==='hanging';if(!hanging&&![1,2].includes(F.cellType))F.cellType=1;form.hidden=false;form.replaceChildren();$('catalogPreview').hidden=false;$('contentUpload').parentElement.hidden=false;$('contentUpload').accept='image/png,image/gif';$('artChoices').parentElement.hidden=false;$('lootEditor').hidden=true;$('clearBuildingTexture').hidden=true;$('returnToLevel').hidden=true;
 $('catalogTitle').textContent='家具 · '+d.name;$('archiveCatalog').textContent=d.deleted?'恢复条目':'－ 删除（归档）';
 const id=field(d,'id','稳定ID','text');id.querySelector('input').readOnly=!!C.originalId;
 form.append(id,field(d,'name','名称','text'),field(d,'enabled','启用','checkbox'),field(d,'default_owned','基地拥有此家具','checkbox'),field(d,'texture','PNG贴图 / 动画帧表','text'));
 d.animation??={frames:1,columns:1,fps:6};
 form.append(group('2D动画（PNG帧表，或导入GIF自动转换）',['frames','columns','fps'].map((key,i)=>field(d.animation,key,['总帧数','帧表列数','每秒帧数'][i],'number',1))));
 const suspended=document.createElement('label'),suspendToggle=document.createElement('input');suspended.textContent='悬挂物（居中挂在挂点，参考格不参与占位）';suspendToggle.type='checkbox';suspendToggle.id='furnitureHanging';suspendToggle.checked=hanging;suspendToggle.onchange=()=>{if(suspendToggle.checked){d.reference_cells=furniturePaintCells(d).map(([x,y])=>[x,y]);d.occupancy_grid=[];d.placement_type='hanging'}else{d.occupancy_grid=Array.from({length:d.height},()=>Array(d.width).fill(0));for(const [x,y]of d.reference_cells||[])d.occupancy_grid[y][x]=1;d.reference_cells=[];d.placement_type='floor'}if(d.default_placement){if(suspendToggle.checked)d.default_placement={car:d.default_placement.car,mount:0,x:0,y:0};else d.default_placement=null}renderCatalogForm();dirty()};suspended.append(suspendToggle);form.append(suspended);
 const masks=document.createElement('fieldset'),legend=document.createElement('legend');legend.textContent=hanging?'白色参考格 · 仅帮助理解实机尺寸，不占用挂点空间':'格子状态 · 空置 / 实物 / 墙面';masks.append(legend);
 const help=document.createElement('p');help.id='furnitureCellHelp';help.textContent='左键添加所选类型，右键删除；支持拖拽批量编辑。';masks.append(help);const types=document.createElement('div');types.id='furnitureCellTypes';types.className='bar';for(const [value,title]of (hanging?[[3,'参考格']]:[[1,'实物格'],[2,'墙面格']]))types.append(button(title,()=>{F.cellType=value;renderCatalogForm()},(hanging||F.cellType===value)?'selected':''));masks.append(types);
 masks.append(field(d,'width',hanging?'参考范围宽':'网格宽','number',1,35),field(d,'height',hanging?'参考范围高':'网格高','number',1,12));
 const grid=document.createElement('canvas');grid.id='furnitureMask';grid.width=560;grid.height=192;grid.style.maxWidth='840px';masks.append(grid);form.append(masks);
 function cell(e){const r=grid.getBoundingClientRect();return [Math.max(0,Math.min(34,Math.floor((e.clientX-r.left)*560/r.width/16))),Math.max(0,Math.min(11,Math.floor((e.clientY-r.top)*192/r.height/16)))]}
 function paint(){const c=grid.getContext('2d');c.clearRect(0,0,560,192);for(let y=0;y<12;y++)for(let x=0;x<35;x++){c.strokeStyle='#514b67';c.strokeRect(x*16,y*16,16,16)}for(const [x,y,state]of furniturePaintCells(d)){c.fillStyle=furnitureCellColor(state);c.fillRect(x*16+2,y*16+2,12,12)}if(F.start&&F.end){c.strokeStyle=furnitureCellColor(F.nextState);c.strokeRect(Math.min(F.start[0],F.end[0])*16,Math.min(F.start[1],F.end[1])*16,(Math.abs(F.start[0]-F.end[0])+1)*16,(Math.abs(F.start[1]-F.end[1])+1)*16)}}
 grid.oncontextmenu=e=>e.preventDefault();grid.onpointerdown=e=>{if(![0,2].includes(e.button))return;F.start=F.end=cell(e);F.nextState=e.button===2?0:(hanging?3:F.cellType);grid.setPointerCapture(e.pointerId);paint()};grid.onpointermove=e=>{if(F.start){F.end=cell(e);paint()}};
 grid.onpointerup=e=>{if(!F.start)return;F.end=cell(e);const end=[Math.max(F.start[0],F.end[0]),Math.max(F.start[1],F.end[1])],width=Math.max(d.width,end[0]+1),height=Math.max(d.height,end[1]+1);const next=Array.from({length:height},(_,y)=>Array.from({length:width},(_,x)=>hanging?(d.reference_cells.some(p=>p[0]===x&&p[1]===y)?3:0):(d.occupancy_grid[y]?.[x]||0)));for(let y=Math.min(F.start[1],F.end[1]);y<=end[1];y++)for(let x=Math.min(F.start[0],F.end[0]);x<=end[0];x++)next[y][x]=F.nextState;F.start=F.end=null;if(!hanging&&!next.some(row=>row.some(Boolean))){status('家具至少保留一个实物格或墙面格',true);paint();return}d.width=width;d.height=height;if(hanging)d.reference_cells=next.flatMap((row,y)=>row.flatMap((value,x)=>value?[[x,y]]:[]));else d.occupancy_grid=next;renderCatalogForm();dirty()};grid.onpointercancel=()=>{F.start=F.end=null;paint()};paint();
 for(const input of masks.querySelectorAll('input[data-field]')){const key=input.dataset.field;input.oninput=()=>{const value=+input.value,limit=key==='width'?35:12,index=key==='width'?0:1;if(!Number.isInteger(value)||value<1||value>limit)return;if(furniturePaintCells(d).some(cell=>cell[index]>=value)){status('请先清空超出新范围的格子',true);return}d[key]=value;normalizeFurnitureGrid(d);paint();dirty();drawCatalogPreview()}}
 form.append(furnitureSelect(d,'interaction','互动功能',Object.entries({none:'无主动互动',rest:'睡觉',news:'电脑',gear:'出站',locker:'储物',trade:'交易窗口',map:'线路图',preparation:'预备仓库储物',storage:'通用储物'})),field(d,'function_text','悬浮功能说明','text'),furnitureSelect(d,'item_id','兼有物品属性（保留物品自己的贴图）',[['','仅家具'],...S.project.items.filter(v=>!v.deleted).map(v=>[v.id,v.name])]));
 form.append(storageFields(d));
 const effects=document.createElement('label'),tags=document.createElement('input');effects.textContent='提供效果标签（逗号分隔，例如 light,heat）';tags.value=(d.effects||[]).join(',');tags.oninput=()=>{d.effects=tags.value.split(/[,，]/).map(v=>v.trim()).filter(Boolean);dirty()};effects.append(tags);form.append(effects);
 const rules=document.createElement('fieldset');rules.id='furnitureRules';rules.append(document.createTextNode('需求 / 排斥距离（同车厢，格子间最近边缘距离）'));
 for(const [index,rule]of (d.distance_rules||[]).entries()){
  const row=document.createElement('div');row.className='bar';row.append(furnitureSelect(rule,'target_type','目标类型',[['furniture','其他家具'],['effect','效果标签']]),rule.target_type==='furniture'?furnitureSelect(rule,'target','目标家具',S.project.furniture.filter(v=>v.id!==d.id).map(v=>[v.id,v.name])):field(rule,'target','效果标签','text'),furnitureSelect(rule,'relation','关系',[['require','需求：必须在范围内'],['exclude','排斥：不能在范围内']]),field(rule,'distance','距离（家具格）','number',0,100),button('－ 删除规则',()=>{d.distance_rules.splice(index,1);renderCatalogForm();dirty()}));rules.append(row);
 }
 rules.append(button('＋ 距离规则',()=>{d.distance_rules??=[];d.distance_rules.push({target_type:'furniture',target:S.project.furniture.find(v=>v.id!==d.id)?.id||'door',relation:'require',distance:3});renderCatalogForm();dirty()}));form.append(rules);
 const binding=document.createElement('fieldset'),summary=document.createElement('legend');summary.textContent='贴图绑定 · 在预览中拖动、缩放与旋转';binding.id='furnitureBindingFields';binding.append(summary);
 const values=furnitureBinding();
 for(const [key,title]of Object.entries({x:'贴图横偏移（格）',y:'贴图纵偏移（格）',width:'贴图宽（格）',height:'贴图高（格）',rotation:'贴图旋转（度）'})){
  const input=field(values,key,title);input.querySelector('input').oninput=e=>{d.texture_binding={...furnitureBinding(),[key]:+e.target.value};dirty();drawCatalogPreview()};binding.append(input);
 }
 form.append(binding);furnitureTextureTools.hidden=false;furnitureTextureTools.querySelector('[data-texture-mode="anchor"]').hidden=!hanging;if(!hanging&&F.textureMode==='anchor')F.textureMode='move';for(const control of furnitureTextureTools.querySelectorAll('button'))control.classList.toggle('selected',control.dataset.textureMode===F.textureMode);
 form.append(field(d,'known','默认已知建造方式','checkbox'));
 d.required_technology??={};const technologies=document.createElement('fieldset');technologies.id='requiredTechnology';technologies.append(document.createTextNode('所需技术（ID与最低等级）'));
 for(const id of Object.keys(d.required_technology)){const row=document.createElement('div');row.className='bar';row.append(field(d.required_technology,id,id+' 最低等级','number',0,100),button('－ 技术',()=>{delete d.required_technology[id];renderCatalogForm();dirty()}));technologies.append(row)}
 const techId=document.createElement('input');techId.placeholder='技术ID，例如 auto_repair';technologies.append(techId,button('＋ 技术',()=>{if(!/^[a-z][a-z0-9_-]*$/.test(techId.value)){status('请输入有效技术ID',true);return}d.required_technology[techId.value]=1;renderCatalogForm();dirty()}));form.append(technologies);

 for(const [key,title]of [['build_cost','建造成本'],['dismantle_cost','分解成本'],['salvage','分解返还']]){
  d[key]??={};const box=document.createElement('fieldset'),legend=document.createElement('legend');legend.textContent=title;box.append(legend);
  for(const id of Object.keys(d[key])){const row=document.createElement('div');row.className='bar';row.append(field(d[key],id,S.project.items.find(item=>itemNames(item).includes(id))?.name||id,'number',0,1000),button('移除',()=>{delete d[key][id];renderCatalogForm();dirty()}));box.append(row)}
  const select=document.createElement('select');for(const item of S.project.items.filter(v=>!v.deleted))option(select,item.id,item.name);box.append(select,button('＋ 材料',()=>{d[key][select.value]=1;renderCatalogForm();dirty()}));form.append(box);
 }
 renderArtChoices();drawCatalogPreview();
};
const furniturePreview=drawCatalogPreview;drawCatalogPreview=function(){
 if(C.kind!=='furniture')return furniturePreview();if(!C.data)return;
 const d=C.data,c=$('catalogPreview').getContext('2d'),scale=32;F.scale=scale;c.save();c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,600,340);c.fillStyle='#191927';c.fillRect(0,0,600,340);c.setTransform(G.viewZoom,0,0,G.viewZoom,...G.viewPan);

 const image=imageFor(d.texture),a=d.animation||{frames:1,columns:1,fps:6},b=furnitureBinding();
 if(image?.complete&&image.naturalWidth){
  const frame=furnitureAnimationFrame(a,performance.now()/1000),source=furnitureFrameRect(image,a,frame);c.save();c.translate(30+(b.x+b.width/2)*scale,28+(b.y+b.height/2)*scale);c.rotate(b.rotation*Math.PI/180);c.imageSmoothingEnabled=false;c.drawImage(image,...source,-b.width*scale/2,-b.height*scale/2,b.width*scale,b.height*scale);
  c.strokeStyle='#f5d598';c.lineWidth=1/G.viewZoom;c.strokeRect(-b.width*scale/2,-b.height*scale/2,b.width*scale,b.height*scale);
  c.fillStyle='#fff';c.fillRect(b.width*scale/2-5,b.height*scale/2-5,10,10);c.beginPath();c.moveTo(0,-b.height*scale/2);c.lineTo(0,-b.height*scale/2-18);c.stroke();c.beginPath();c.arc(0,-b.height*scale/2-18,5,0,Math.PI*2);c.fill();c.restore();
 }
 if(d.placement_type==='hanging'){const point=furnitureAnchorPoint();c.strokeStyle='#ffffff';c.lineWidth=2/G.viewZoom;c.beginPath();c.arc(...point,7/G.viewZoom,0,Math.PI*2);c.moveTo(point[0]-11/G.viewZoom,point[1]);c.lineTo(point[0]+11/G.viewZoom,point[1]);c.moveTo(point[0],point[1]-11/G.viewZoom);c.lineTo(point[0],point[1]+11/G.viewZoom);c.stroke()}
 if(PreviewVisibility.cells){for(const [x,y,state]of furniturePaintCells(d)){const color=furnitureCellColor(state);c.fillStyle=color+'55';c.fillRect(30+x*scale,28+y*scale,scale,scale);c.strokeStyle=color;c.strokeRect(30+x*scale,28+y*scale,scale,scale)}}
 c.restore();updateFurnitureBindingFields();

};
const furnitureUpload=$('uploadContent').onclick;$('uploadContent').onclick=run(async()=>{if(C.kind!=='furniture')return furnitureUpload();const file=$('contentUpload').files[0];if(!file)throw Error('请选择PNG或GIF');const data=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(file)});const result=await api('/api/furniture-image',{id:C.data.id,data});C.data.texture=result.texture;C.data.animation=result.animation;C.images.delete(result.texture);renderCatalogForm();dirty()});
const furnitureItemForm=renderItemFootprint;renderItemFootprint=function(form){furnitureItemForm(form);const linked=S.project.furniture?.find(v=>itemNames(C.data).includes(v.item_id));const label=document.createElement('p');label.textContent=linked?'兼有家具属性：'+linked.name+'。物品贴图保持独立，家具贴图只用于摆放与装修。':'可在家具编辑页关联此物品，使其同时具有物品与家具属性。';form.append(label)};
function animateFurniturePreview(){if(!$('catalogView').hidden&&C.kind==='furniture'&&C.data?.animation?.frames>1)drawCatalogPreview();requestAnimationFrame(animateFurniturePreview)}requestAnimationFrame(animateFurniturePreview);

function furnitureAnimationFrame(animation,seconds){
 if(animation.durations?.length){let at=seconds*1000%animation.durations.reduce((sum,value)=>sum+value,0);for(let i=0;i<animation.durations.length;i++){at-=animation.durations[i];if(at<0)return i}}
 return Math.floor(seconds*animation.fps)%animation.frames;
}

const furnitureSpritePath=setSpritePath;
setSpritePath=function(path,frames=1){
 if(C.kind==='furniture')C.data.animation={frames,columns:frames,fps:6};
 return furnitureSpritePath(path,frames);
};

function furnitureFrameRect(image,animation,frame=0){
 const columns=Math.max(1,+animation.columns||1),rows=Math.max(1,Math.ceil((+animation.frames||1)/columns)),w=image.naturalWidth/columns,h=image.naturalHeight/rows,index=Number.isFinite(frame)?frame:0;
 const rect=[index%columns*w,Math.floor(index/columns)*h,w,h];
 if(C.data.id!=='preparation')return rect;
 let cache=F.frameRects.get(image);if(!cache){cache=new Map();F.frameRects.set(image,cache)}const key=`${index}/${columns}/${rows}`;if(cache.has(key))return cache.get(key);
 // The legacy preparation artwork is cropped by the runtime; match that frame here.
 const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.floor(w));canvas.height=Math.max(1,Math.floor(h));const context=canvas.getContext('2d');context.drawImage(image,...rect,0,0,canvas.width,canvas.height);const pixels=context.getImageData(0,0,canvas.width,canvas.height).data;let left=canvas.width,top=canvas.height,right=0,bottom=0;
 for(let y=0;y<canvas.height;y++)for(let x=0;x<canvas.width;x++)if(pixels[(y*canvas.width+x)*4+3]){left=Math.min(left,x);right=Math.max(right,x+1);top=Math.min(top,y);bottom=Math.max(bottom,y+1)}
 const result=right>left?[rect[0]+left,rect[1]+top,right-left,bottom-top]:rect;cache.set(key,result);return result;
}
function furnitureBinding(){
 if(C.data.texture_binding)return C.data.texture_binding;
 const image=imageFor(C.data.texture),source=image?.complete&&image.naturalWidth?furnitureFrameRect(image,C.data.animation||{frames:1,columns:1},0):[0,0,32,32];
 return {x:0,y:0,width:source[2]/32,height:source[3]/32,rotation:0};
}
function updateFurnitureBindingFields(){
 if(C.kind!=='furniture'||!C.data)return;const binding=furnitureBinding();
 for(const input of document.querySelectorAll('#furnitureBindingFields input[data-field]'))if(input!==document.activeElement)input.value=binding[input.dataset.field];
}
function furnitureCenter(binding){return [30+(binding.x+binding.width/2)*32,28+(binding.y+binding.height/2)*32]}
function furnitureTextureHit(at,binding){
 const center=furnitureCenter(binding),angle=-binding.rotation*Math.PI/180,dx=at[0]-center[0],dy=at[1]-center[1],x=dx*Math.cos(angle)-dy*Math.sin(angle),y=dx*Math.sin(angle)+dy*Math.cos(angle),tolerance=10/G.viewZoom;
 if(Math.hypot(x,y+binding.height*16+18)<tolerance)return 'rotate';
 if(Math.hypot(x-binding.width*16,y-binding.height*16)<tolerance)return 'scale';
 return Math.abs(x)<=binding.width*16&&Math.abs(y)<=binding.height*16?F.textureMode:null;
}
const furnitureTextureTools=document.createElement('div');furnitureTextureTools.id='furnitureTextureTools';furnitureTextureTools.className='bar';furnitureTextureTools.hidden=true;
for(const [mode,title]of [['move','拖动家具贴图'],['scale','缩放家具贴图'],['rotate','旋转家具贴图'],['anchor','调节悬挂点']]){const control=button(title,()=>{F.textureMode=mode;for(const b of furnitureTextureTools.querySelectorAll('button'))b.classList.toggle('selected',b.dataset.textureMode===mode);$('catalogPreview').style.cursor=mode==='move'?'move':mode==='scale'?'nwse-resize':'crosshair';drawCatalogPreview()},mode===F.textureMode?'selected':'');control.dataset.textureMode=mode;furnitureTextureTools.append(control)}
const textureHint=document.createElement('span');textureHint.textContent='白色角点缩放 · 圆点旋转 · Shift旋转按15°吸附；修改占位不改变贴图绑定';furnitureTextureTools.append(textureHint);$('catalogPreview').before(furnitureTextureTools);
const furniturePointerDown=$('catalogPreview').onpointerdown,furniturePointerMove=$('catalogPreview').onpointermove,furniturePointerUp=$('catalogPreview').onpointerup;
$('catalogPreview').onpointerdown=e=>{
 if(C.kind!=='furniture'||e.button!==0)return furniturePointerDown(e);
 const at=stagePoint(e),binding=furnitureBinding(),mode=C.data.placement_type==='hanging'&&F.textureMode==='anchor'?'anchor':furnitureTextureHit(at,binding);if(!mode)return;
 F.drag={mode,before:clone(binding),at,center:furnitureCenter(binding)};G.drag=null;$('catalogPreview').setPointerCapture(e.pointerId);e.preventDefault();
};
$('catalogPreview').onpointermove=e=>{
 if(C.kind!=='furniture'||!F.drag)return furniturePointerMove(e);
 const drag=F.drag,at=stagePoint(e),before=drag.before,binding={...before};
 if(drag.mode==='anchor'){const center=furnitureCenter(binding),angle=-binding.rotation*Math.PI/180,dx=at[0]-center[0],dy=at[1]-center[1];C.data.hanging_anchor={x:Math.max(0,Math.min(1,.5+(dx*Math.cos(angle)-dy*Math.sin(angle))/(binding.width*32))),y:Math.max(0,Math.min(1,.5+(dx*Math.sin(angle)+dy*Math.cos(angle))/(binding.height*32)))};drawCatalogPreview();dirty();return}
 if(drag.mode==='move'){binding.x+=(at[0]-drag.at[0])/32;binding.y+=(at[1]-drag.at[1])/32}
 else if(drag.mode==='scale'){
  const start=Math.max(1,Math.hypot(drag.at[0]-drag.center[0],drag.at[1]-drag.center[1])),ratio=Math.max(.01/Math.min(before.width,before.height),Math.min(4096/Math.max(before.width,before.height),Math.hypot(at[0]-drag.center[0],at[1]-drag.center[1])/start));
  binding.width=before.width*ratio;binding.height=before.height*ratio;binding.x=before.x+(before.width-binding.width)/2;binding.y=before.y+(before.height-binding.height)/2;
 }else{
  let angle=before.rotation+(Math.atan2(at[1]-drag.center[1],at[0]-drag.center[0])-Math.atan2(drag.at[1]-drag.center[1],drag.at[0]-drag.center[0]))*180/Math.PI;
  if(e.shiftKey)angle=Math.round(angle/15)*15;binding.rotation=((angle+540)%360)-180;
 }
 C.data.texture_binding=binding;updateFurnitureBindingFields();drawCatalogPreview();dirty();
};
$('catalogPreview').onpointerup=$('catalogPreview').onpointercancel=e=>{F.drag=null;furniturePointerUp(e)};

function furnitureAnchorPoint(){const b=furnitureBinding(),anchor=C.data.hanging_anchor||{x:.5,y:.5},center=furnitureCenter(b),angle=b.rotation*Math.PI/180,x=(anchor.x-.5)*b.width*32,y=(anchor.y-.5)*b.height*32;return [center[0]+x*Math.cos(angle)-y*Math.sin(angle),center[1]+x*Math.sin(angle)+y*Math.cos(angle)]}
