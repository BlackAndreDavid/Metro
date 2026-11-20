'use strict';
// Shared geometry authoring: item masks/bindings and building art/physics/drop paths.
const G={layer:'physics',mode:'move',floor:0,maskMode:'add',drag:null};
function itemCells(){return C.data.cells??Array.from({length:C.data.width*C.data.height},(_,i)=>[i%C.data.width,Math.floor(i/C.data.width)])}
function ensureBinding(){
 if(!C.data.texture_binding){C.data.texture_binding={x:0,y:0,width:C.kind==='items'?2:C.data.width,height:C.kind==='items'?2:buildingHeight(),rotation:0};if(C.kind==='items')C.bindingPending={binding:C.data.texture_binding,path:spritePath()}}
 const binding=C.data.texture_binding,pending=C.bindingPending;if(pending?.binding===binding){const image=imageFor(pending.path);if(image?.complete&&image.naturalWidth){C.bindingPending=null;binding.width=image.naturalWidth/32;binding.height=image.naturalHeight/32;for(const input of document.querySelectorAll('#bindingFields input'))input.value=binding[input.dataset.field]}}
 return binding;
}
function ensureFloors(){return C.data.floor_positions??=Array.from({length:C.data.floors},(_,i)=>i*110)}
function buildingHeight(){return Math.max(...(C.data.floor_positions||Array.from({length:C.data.floors},(_,i)=>i*110)))+110}
function floorY(i){return (C.data.floor_positions||[])[i]??i*110}
function buildProjection(){return {scale:Math.min(540/Math.max(100,C.data.width),270/buildingHeight()),left:30,base:310}}
function itemProjection(){return {scale:32,left:130,base:32}}
function stagePoint(e){const rect=$('catalogPreview').getBoundingClientRect();return [(e.clientX-rect.left)*600/rect.width,(e.clientY-rect.top)*340/rect.height]}
function localStage(point){const p=C.kind==='items'?itemProjection():buildProjection();return [(point[0]-p.left)/p.scale,(C.kind==='items'?point[1]-p.base:p.base-point[1])/p.scale]}
function stageXY(point){const p=C.kind==='items'?itemProjection():buildProjection();return [p.left+point[0]*p.scale,p.base+(C.kind==='items'?point[1]:-point[1])*p.scale]}
function bindingToolbar(box){
 const bar=document.createElement('div');bar.className='bar geometry-tools';
 for(const [mode,text]of [['move','拖动贴图'],['scale','缩放贴图'],['rotate','旋转贴图']])bar.append(button(text,()=>{G.mode=mode;C.previewRotated=false;C.previewMirrored=false;drawCatalogPreview();bar.querySelectorAll('button').forEach(b=>b.classList.toggle('selected',b.dataset.transform===mode))},G.mode===mode?'selected':''));
 [...bar.children].forEach((b,i)=>b.dataset.transform=['move','scale','rotate'][i]);box.append(bar);
 const values=document.createElement('div');values.className='fields';values.id='bindingFields';const binding=ensureBinding();for(const [key,text]of [['x','横向位置'],['y','纵向位置'],['width','贴图宽度'],['height','贴图高度'],['rotation','贴图角度']])values.append(field(binding,key,text));box.append(values);
}
function updateBindingFields(){for(const input of document.querySelectorAll('#bindingFields input'))if(document.activeElement!==input)input.value=ensureBinding()[input.dataset.field]}
function renderItemFootprint(form){
 const box=document.createElement('fieldset');const title=document.createElement('legend');title.textContent='不规则占位 · 选择添加/删除后框选格子';box.append(title);
 for(const [mode,text]of [['add','＋ 添加格子'],['remove','－ 删除格子']]){const b=button(text,()=>{G.maskMode=mode;box.querySelectorAll('[data-mask-mode]').forEach(e=>e.classList.toggle('selected',e.dataset.maskMode===mode))},G.maskMode===mode?'selected':'');b.dataset.maskMode=mode;box.append(b)}
 const grid=document.createElement('div');grid.id='itemFootprint';grid.className='item-mask-grid';let start=null,end=null;
 const caption=document.createElement('p');caption.id='itemFootprintSize';
 function cellAt(e){const r=grid.getBoundingClientRect();return [Math.max(0,Math.min(7,Math.floor((e.clientX-r.left)/28))),Math.max(0,Math.min(7,Math.floor((e.clientY-r.top)/28)))]}
 function paint(){const cells=new Set(itemCells().map(c=>c.join(',')));for(const cell of grid.children){const x=+cell.dataset.x,y=+cell.dataset.y;cell.classList.toggle('occupied',cells.has(`${x},${y}`));cell.classList.toggle('mask-selection',Boolean(start&&x>=Math.min(start[0],end[0])&&x<=Math.max(start[0],end[0])&&y>=Math.min(start[1],end[1])&&y<=Math.max(start[1],end[1])))}caption.textContent=`${cells.size} 个占位格 · 外框 ${C.data.width} × ${C.data.height}`}
 for(let y=0;y<8;y++)for(let x=0;x<8;x++){const cell=document.createElement('div');cell.dataset.x=x;cell.dataset.y=y;grid.append(cell)}
 grid.onpointerdown=e=>{if(e.button!==0)return;e.preventDefault();start=end=cellAt(e);grid.setPointerCapture(e.pointerId);paint()};grid.onpointermove=e=>{if(start){end=cellAt(e);paint()}};
 grid.onpointerup=e=>{if(!start)return;end=cellAt(e);const cells=new Map(itemCells().map(c=>[c.join(','),c]));for(let y=Math.min(start[1],end[1]);y<=Math.max(start[1],end[1]);y++)for(let x=Math.min(start[0],end[0]);x<=Math.max(start[0],end[0]);x++){if(G.maskMode==='add')cells.set(`${x},${y}`,[x,y]);else cells.delete(`${x},${y}`)}start=end=null;if(!cells.size){status('至少保留一个占位格',true);paint();return}C.data.cells=[...cells.values()];C.data.width=1+Math.max(...C.data.cells.map(c=>c[0]));C.data.height=1+Math.max(...C.data.cells.map(c=>c[1]));paint();drawCatalogPreview();dirty()};grid.onpointercancel=()=>{start=end=null;paint()};
 box.append(grid,caption);paint();box.append(button('旋转预览',()=>{C.previewRotated=!C.previewRotated;drawCatalogPreview()}),button('镜像预览',()=>{C.previewMirrored=!C.previewMirrored;drawCatalogPreview()}));form.append(box);
 const art=document.createElement('fieldset'),legend=document.createElement('legend');legend.textContent='贴图绑定 · 使用预览中的贴图/控制柄移动、缩放、旋转';art.append(legend);bindingToolbar(art);form.append(art);
}
function drawBinding(ctx,image){
 const b=ensureBinding(),p=C.kind==='items'?itemProjection():buildProjection(),center=stageXY([b.x+b.width/2,b.y+b.height/2]);
 ctx.save();ctx.translate(...center);ctx.rotate(b.rotation*Math.PI/180);ctx.strokeStyle='#efc488';ctx.lineWidth=2;
 if(image?.complete&&image.naturalWidth)ctx.drawImage(image,-b.width*p.scale/2,-b.height*p.scale/2,b.width*p.scale,b.height*p.scale);
 ctx.strokeRect(-b.width*p.scale/2,-b.height*p.scale/2,b.width*p.scale,b.height*p.scale);ctx.fillStyle='#efc488';ctx.fillRect(b.width*p.scale/2-5,b.height*p.scale/2-5,10,10);ctx.beginPath();ctx.arc(0,-b.height*p.scale/2-18,6,0,Math.PI*2);ctx.fill();ctx.restore();
}
function drawItemBoundPreview(ctx,image){
 const p=itemProjection(),w=C.data.width,h=C.data.height;ctx.imageSmoothingEnabled=false;ctx.save();
 if(C.previewRotated||C.previewMirrored){ctx.translate(p.left+(C.previewRotated?h:w)*p.scale/2,p.base+(C.previewRotated?w:h)*p.scale/2);ctx.rotate(C.previewRotated?Math.PI/2:0);ctx.scale(C.previewMirrored?-1:1,1);ctx.translate(-p.left-w*p.scale/2,-p.base-h*p.scale/2)}
 ctx.fillStyle='#35504c';for(const[x,y]of itemCells())ctx.fillRect(p.left+x*p.scale,p.base+y*p.scale,p.scale,p.scale);
 drawBinding(ctx,image);ctx.strokeStyle='#a6dccc';for(const[x,y]of itemCells())ctx.strokeRect(p.left+x*p.scale,p.base+y*p.scale,p.scale,p.scale);ctx.restore();
 ctx.fillStyle='#f2eadd';ctx.font='14px sans-serif';ctx.fillText(`${itemCells().length} 个占位格 · 贴图手动绑定`,20,326);
}
function changeFloor(delta){
 const floors=ensureFloors();if(delta>0&&floors.length<8){floors.push(floors.at(-1)+110);G.floor=floors.length-1}else if(delta<0&&floors.length>1){const removed=Math.min(G.floor,floors.length-1);floors.splice(removed,1);for(const point of C.data.loot_points){if(point.floor>=removed)point.floor=Math.max(0,point.floor-1)}G.floor=Math.min(removed,floors.length-1)}else return;
 C.data.floors=floors.length;renderCatalogForm();dirty();
}
function setFloorHeight(index,y){const floors=ensureFloors();floors[index]=Math.round(Math.max(index?floors[index-1]+24:0,Math.min(index<floors.length-1?floors[index+1]-24:2000,y)));drawCatalogPreview();dirty()}
const geometryCatalogForm=renderCatalogForm;renderCatalogForm=function(){
 if(C.kind==='building_templates'&&C.data){ensureFloors();G.floor=Math.min(G.floor,C.data.floors-1)}geometryCatalogForm();if(C.kind!=='building_templates'||C.outdoor!==undefined)return;
 const form=$('catalogForm');
 const layers=document.createElement('div');layers.className='bar';for(const[layer,text]of [['textures','贴图层'],['physics','物理层']]){const b=button(text,()=>{G.layer=layer;renderCatalogForm()},G.layer===layer?'selected':'');b.dataset.buildingLayer=layer;layers.append(b)}form.prepend(layers);
 if(G.layer==='textures')bindingToolbar(form);
 else{
  const floors=document.createElement('fieldset'),legend=document.createElement('legend');legend.textContent='楼层地板 · 可直接拖动预览中的水平线';floors.append(legend,button('＋ 添加楼层',()=>changeFloor(1)),button('－ 减少楼层',()=>changeFloor(-1)));
  ensureFloors().forEach((height,index)=>{const row=document.createElement('div');row.className='bar';row.append(button(`第${index+1}层`,()=>{G.floor=index;renderCatalogForm()},G.floor===index?'selected':''));const input=document.createElement('input');input.type='number';input.value=height;input.dataset.floorIndex=index;input.onchange=()=>{setFloorHeight(index,+input.value);input.value=ensureFloors()[index]};row.append(input);floors.append(row)});form.append(floors);
 }
 // Keep combined preview while each layer exposes its own controls.
 for(const label of form.querySelectorAll(':scope > label')){const key=label.querySelector('input')?.dataset.field;if(key==='texture')label.hidden=G.layer!=='textures';if(['width','wall','light_level'].includes(key))label.hidden=G.layer!=='physics'}
 const collision=[...form.querySelectorAll('fieldset')].find(f=>f.querySelector('legend')?.textContent==='碰撞箱');if(collision)collision.hidden=G.layer!=='physics';
 drawCatalogPreview();
};
const geometryLootPoints=renderLootPoints;renderLootPoints=function(){geometryLootPoints();const point=selectedPoint();if(C.kind!=='building_templates'||!point)return;const outside=$('lootPointForm').querySelector('input[data-field=outside]');if(outside)outside.onchange=()=>{if(outside.checked)point.floor=0;renderLootPoints();drawCatalogPreview()};const bar=document.createElement('div');bar.className='bar';
 for(const[type,text]of [['point','固定点'],['line','直线掉落区域'],['arc','弧线掉落区域']]){const b=button(text,()=>{if(type==='point')delete point.region;else{const x=point.x;point.region={type,start:[Math.max(0,x-30),0],end:[Math.min(C.data.width,x+30),0],control:[x,40]}}renderLootPoints();drawCatalogPreview();dirty()},(point.region?.type||'point')===type?'selected':'');b.dataset.dropRegion=type;bar.append(b)}$('lootPointForm').append(bar);};
const geometryPreview=drawCatalogPreview;drawCatalogPreview=function(){
 if(C.kind!=='building_templates')return geometryPreview();if(!C.data)return;const ctx=$('catalogPreview').getContext('2d'),p=buildProjection();ctx.clearRect(0,0,600,340);ctx.fillStyle='#191927';ctx.fillRect(0,0,600,340);ctx.imageSmoothingEnabled=false;
 ctx.fillStyle=C.data.wall;ctx.fillRect(p.left,p.base-buildingHeight()*p.scale,C.data.width*p.scale,buildingHeight()*p.scale);drawBinding(ctx,imageFor(spritePath()));
 const box=C.data.collision;ctx.strokeStyle='#72d4df';ctx.lineWidth=2;ctx.strokeRect(p.left+box.x*p.scale,p.base-(box.y+box.height)*p.scale,box.width*p.scale,box.height*p.scale);ctx.fillStyle='#72d4df';ctx.fillRect(p.left+(box.x+box.width)*p.scale-4,p.base-(box.y+box.height)*p.scale-4,8,8);
 ensureFloors().forEach((y,index)=>{ctx.strokeStyle=index===G.floor?'#efc488':'#a6dccc';ctx.lineWidth=index===G.floor?3:1;ctx.beginPath();ctx.moveTo(p.left,p.base-y*p.scale);ctx.lineTo(p.left+C.data.width*p.scale,p.base-y*p.scale);ctx.stroke();ctx.fillStyle='#fff';ctx.fillText(`${index+1}F`,p.left+5,p.base-y*p.scale-5)});
 C.data.loot_points.forEach((point,index)=>{const y=floorY(point.outside?0:point.floor),region=point.region;ctx.strokeStyle=index===C.point?'#f5d598':'#bba56c';ctx.fillStyle=ctx.strokeStyle;ctx.lineWidth=3;
  if(region){const a=stageXY([region.start[0],y+region.start[1]]),b=stageXY([region.end[0],y+region.end[1]]);ctx.beginPath();ctx.moveTo(...a);if(region.type==='arc'){const c=stageXY([region.control[0],y+region.control[1]]);ctx.quadraticCurveTo(...c,...b)}else ctx.lineTo(...b);ctx.stroke();for(const key of region.type==='arc'?['start','end','control']:['start','end']){const at=stageXY([region[key][0],y+region[key][1]]);ctx.fillRect(at[0]-5,at[1]-5,10,10)}}
  else ctx.fillRect(p.left+point.x*p.scale-7,p.base-y*p.scale-20,14,20);
 });
};
function bindingHit(point){const b=ensureBinding(),p=C.kind==='items'?itemProjection():buildProjection(),c=stageXY([b.x+b.width/2,b.y+b.height/2]),a=-b.rotation*Math.PI/180,dx=point[0]-c[0],dy=point[1]-c[1],x=dx*Math.cos(a)-dy*Math.sin(a),y=dx*Math.sin(a)+dy*Math.cos(a);if(Math.hypot(x,y+b.height*p.scale/2+18)<12)return 'rotate';if(Math.abs(x-b.width*p.scale/2)<12&&Math.abs(y-b.height*p.scale/2)<12)return 'scale';if(Math.abs(x)<=b.width*p.scale/2&&Math.abs(y)<=b.height*p.scale/2)return G.mode;return null}
$('catalogPreview').onpointerdown=e=>{
 if(!['items','building_templates'].includes(C.kind)||e.button!==0)return;const at=stagePoint(e),local=localStage(at);G.drag=null;
 if(C.kind==='items'&&(C.previewRotated||C.previewMirrored)){status('先选择贴图移动、缩放或旋转工具，再调整绑定');return}
 if(C.kind==='building_templates'&&G.layer==='physics'){
  const p=buildProjection();for(const[index,point]of C.data.loot_points.entries())if(point.region)for(const key of point.region.type==='arc'?['start','end','control']:['start','end']){const handle=stageXY([point.region[key][0],floorY(point.outside?0:point.floor)+point.region[key][1]]);if(Math.hypot(at[0]-handle[0],at[1]-handle[1])<12){C.point=index;G.drag={kind:'region',point,key};break}}
  if(!G.drag){const index=ensureFloors().findIndex(y=>Math.abs(at[1]-(p.base-y*p.scale))<8);if(index>=0){G.floor=index;G.drag={kind:'floor',index}}}
  if(!G.drag){const index=C.data.loot_points.findIndex(point=>!point.region&&Math.hypot(at[0]-stageXY([point.x,floorY(point.outside?0:point.floor)])[0],at[1]-stageXY([point.x,floorY(point.outside?0:point.floor)])[1]+10)<18);if(index>=0){C.point=index;G.drag={kind:'point',point:C.data.loot_points[index]}}}
  if(!G.drag){const box=C.data.collision;if(Math.abs(local[0]-box.x-box.width)<12/p.scale&&Math.abs(local[1]-box.y-box.height)<12/p.scale)G.drag={kind:'collision-scale',before:clone(box)};else if(local[0]>=box.x&&local[0]<=box.x+box.width&&local[1]>=box.y&&local[1]<=box.y+box.height)G.drag={kind:'collision',before:clone(box)}}
 }else{const mode=bindingHit(at);if(mode)G.drag={kind:'binding',mode,before:clone(ensureBinding())}}
 if(G.drag){G.drag.start=local;G.drag.at=at;$('catalogPreview').setPointerCapture(e.pointerId);e.preventDefault();drawCatalogPreview()}
};
$('catalogPreview').onpointermove=e=>{
 const d=G.drag;if(!d)return;const at=stagePoint(e),local=localStage(at),dx=local[0]-d.start[0],dy=local[1]-d.start[1];
 if(d.kind==='binding'){C.bindingPending=null;const b=ensureBinding(),old=d.before,p=C.kind==='items'?itemProjection():buildProjection();if(d.mode==='move'){b.x=old.x+dx;b.y=old.y+dy}else if(d.mode==='scale'){const factor=Math.max(.05,1+(at[0]-d.at[0]+at[1]-d.at[1])/(Math.max(old.width,old.height)*p.scale));b.width=Math.min(4096,old.width*factor);b.height=Math.min(4096,old.height*factor)}else{const c=stageXY([old.x+old.width/2,old.y+old.height/2]);b.rotation=((old.rotation+(Math.atan2(at[1]-c[1],at[0]-c[0])-Math.atan2(d.at[1]-c[1],d.at[0]-c[0]))*180/Math.PI+540)%360)-180}updateBindingFields()}
 else if(d.kind==='floor'){setFloorHeight(d.index,local[1]);const input=document.querySelector(`[data-floor-index="${d.index}"]`);if(input)input.value=ensureFloors()[d.index]}
 else if(d.kind==='region'){d.point.region[d.key]=[Math.max(0,Math.min(C.data.width,local[0])),Math.max(0,Math.min(200,local[1]-floorY(d.point.outside?0:d.point.floor)))]}
 else if(d.kind==='point'){d.point.x=Math.max(0,Math.min(C.data.width,local[0]));d.point.floor=ensureFloors().reduce((best,y,index)=>Math.abs(local[1]-y)<Math.abs(local[1]-floorY(best))?index:best,0)}
 else if(d.kind==='collision'){C.data.collision.x=d.before.x+dx;C.data.collision.y=d.before.y+dy}
 else if(d.kind==='collision-scale'){C.data.collision.width=Math.max(1,local[0]-d.before.x);C.data.collision.height=Math.max(1,local[1]-d.before.y)}
 drawCatalogPreview();dirty();
};
$('catalogPreview').onpointerup=$('catalogPreview').onpointercancel=()=>{if(G.drag&&C.kind==='building_templates')renderCatalogForm();G.drag=null};
