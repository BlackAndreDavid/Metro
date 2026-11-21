'use strict';
// Furniture definitions share the catalogue, document save flow and item texture registry.
catalogTitles.furniture='家具';
const furnitureTab=button('家具',()=>viewCatalog('furniture'));furnitureTab.id='furnitureTab';$('buildingTab').after(furnitureTab);
const F={plane:'floor_cells',mode:'add',start:null,end:null,scale:1};
const furnitureNew=newCatalog;newCatalog=function(){
 if(C.kind!=='furniture')return furnitureNew();
 let index=1;while(S.project.furniture.some(v=>v.id==='furniture_'+index))index++;
 C.data={id:'furniture_'+index,name:'新家具',enabled:true,texture:'res://assets/textures/Locker.png',animation:{frames:1,columns:1,fps:6},width:2,height:2,floor_cells:[[0,0],[1,0],[0,1],[1,1]],wall_cells:[],placement_type:'floor',interaction:'none',function_text:'查看家具',support_surface:true,storage:null,item_id:'',effects:[],distance_rules:[],default_placement:null,default_owned:true};
 C.originalId='';C.instance=null;delete C.outdoor;renderCatalogForm();dirty();
};
function furnitureSelect(object,key,label,entries){const wrap=document.createElement('label'),select=document.createElement('select');wrap.textContent=label;for(const [value,text]of entries)option(select,value,text);select.value=key==='item_id'?(S.project.items.find(v=>itemNames(v).includes(object[key]))?.id||object[key]||''):(object[key]??'');select.dataset.field=key;select.onchange=()=>{object[key]=select.value;renderCatalogForm();dirty()};wrap.append(select);return wrap}
const furnitureForm=renderCatalogForm;renderCatalogForm=function(){
 if(C.kind!=='furniture')return furnitureForm();
 const d=C.data,form=$('catalogForm');if(!d)return;form.hidden=false;form.replaceChildren();$('catalogPreview').hidden=false;$('contentUpload').parentElement.hidden=false;$('contentUpload').accept='image/png,image/gif';$('artChoices').parentElement.hidden=false;$('lootEditor').hidden=true;$('clearBuildingTexture').hidden=true;$('returnToLevel').hidden=true;
 $('catalogTitle').textContent='家具 · '+d.name;$('archiveCatalog').textContent=d.deleted?'恢复条目':'－ 删除（归档）';
 const id=field(d,'id','稳定ID','text');id.querySelector('input').readOnly=!!C.originalId;
 form.append(id,field(d,'name','名称','text'),field(d,'enabled','启用','checkbox'),field(d,'default_owned','基地拥有此家具','checkbox'),field(d,'texture','PNG贴图 / 动画帧表','text'));
 d.animation??={frames:1,columns:1,fps:6};
 form.append(group('2D动画（PNG帧表，或导入GIF自动转换）',['frames','columns','fps'].map((key,i)=>field(d.animation,key,['总帧数','帧表列数','每秒帧数'][i],'number',1))));
 form.append(furnitureSelect(d,'placement_type','摆放位置',[['floor','车厢家具格（墙面 / 地面）'],['hanging','吊杆挂点（4×3）']]),field(d,'support_surface','可为上方家具提供平整支撑','checkbox'));
 const masks=document.createElement('fieldset'),legend=document.createElement('legend');legend.textContent='独立占位格 · 墙面和地面可同时存在';masks.append(legend);
 const bar=document.createElement('div');bar.className='bar';for(const [plane,title]of [['floor_cells','地面占位'],['wall_cells','墙面占位']])bar.append(button(title,()=>{F.plane=plane;renderCatalogForm()},F.plane===plane?'selected':''));for(const [mode,title]of [['add','＋ 添加格子'],['remove','－ 删除格子']])bar.append(button(title,()=>{F.mode=mode;renderCatalogForm()},F.mode===mode?'selected':''));masks.append(bar,field(d,'width','占位范围宽','number',1,35),field(d,'height','占位范围高','number',1,12));
 const grid=document.createElement('canvas');grid.id='furnitureMask';grid.width=560;grid.height=192;grid.style.maxWidth='840px';masks.append(grid);form.append(masks);
 function cell(e){const r=grid.getBoundingClientRect();return [Math.max(0,Math.min(34,Math.floor((e.clientX-r.left)*560/r.width/16))),Math.max(0,Math.min(11,Math.floor((e.clientY-r.top)*192/r.height/16)))]}
 function paint(){const c=grid.getContext('2d');c.clearRect(0,0,560,192);for(let y=0;y<12;y++)for(let x=0;x<35;x++){c.strokeStyle='#514b67';c.strokeRect(x*16,y*16,16,16)}for(const [plane,color]of [['wall_cells','#659fdc'],['floor_cells','#e2b778']])for(const [x,y]of d[plane]||[]){c.globalAlpha=plane===F.plane?.85:.35;c.fillStyle=color;c.fillRect(x*16+2,y*16+2,12,12)}c.globalAlpha=1;if(F.start&&F.end){c.strokeStyle='#fff';c.strokeRect(Math.min(F.start[0],F.end[0])*16,Math.min(F.start[1],F.end[1])*16,(Math.abs(F.start[0]-F.end[0])+1)*16,(Math.abs(F.start[1]-F.end[1])+1)*16)}}
 grid.onpointerdown=e=>{F.start=F.end=cell(e);grid.setPointerCapture(e.pointerId);paint()};grid.onpointermove=e=>{if(F.start){F.end=cell(e);paint()}};
 grid.onpointerup=e=>{if(!F.start)return;F.end=cell(e);const cells=new Map((d[F.plane]||[]).map(p=>[p.join(','),p]));for(let y=Math.min(F.start[1],F.end[1]);y<=Math.max(F.start[1],F.end[1]);y++)for(let x=Math.min(F.start[0],F.end[0]);x<=Math.max(F.start[0],F.end[0]);x++){if(F.mode==='add')cells.set(`${x},${y}`,[x,y]);else cells.delete(`${x},${y}`)}F.start=F.end=null;const other=F.plane==='floor_cells'?'wall_cells':'floor_cells';if(!cells.size&&!d[other]?.length&&d.placement_type!=='hanging'){status('家具至少保留一种占位格',true);paint();return}d[F.plane]=[...cells.values()];const all=[...(d.floor_cells||[]),...(d.wall_cells||[])];if(all.length){d.width=1+Math.max(...all.map(p=>p[0]));d.height=1+Math.max(...all.map(p=>p[1]))}renderCatalogForm();dirty()};grid.onpointercancel=()=>{F.start=F.end=null;paint()};paint();
 form.append(furnitureSelect(d,'interaction','互动功能',Object.entries({none:'无主动互动',rest:'睡觉',news:'电脑',gear:'出站',locker:'储物',trade:'交易窗口',map:'线路图',preparation:'出发整备',storage:'通用储物'})),field(d,'function_text','悬浮功能说明','text'),furnitureSelect(d,'item_id','兼有物品属性（保留物品自己的贴图）',[['','仅家具'],...S.project.items.filter(v=>!v.deleted).map(v=>[v.id,v.name])]),field(d,'fill_grid','贴图填满占位范围','checkbox'));
 const storage=document.createElement('div'),toggle=document.createElement('input');toggle.type='checkbox';toggle.checked=!!d.storage;const label=document.createElement('label');label.textContent='具有储物功能';label.append(toggle);storage.append(label);toggle.onchange=()=>{d.storage=toggle.checked?{width:4,height:4}:null;renderCatalogForm();dirty()};if(d.storage)storage.append(field(d.storage,'width','储物格宽','number',1,16),field(d.storage,'height','储物格高','number',1,16));form.append(storage);
 const effects=document.createElement('label'),tags=document.createElement('input');effects.textContent='提供效果标签（逗号分隔，例如 light,heat）';tags.value=(d.effects||[]).join(',');tags.oninput=()=>{d.effects=tags.value.split(/[,，]/).map(v=>v.trim()).filter(Boolean);dirty()};effects.append(tags);form.append(effects);
 const rules=document.createElement('fieldset');rules.id='furnitureRules';rules.append(document.createTextNode('需求 / 排斥距离（同车厢，格子间最近边缘距离）'));
 for(const [index,rule]of (d.distance_rules||[]).entries()){
  const row=document.createElement('div');row.className='bar';row.append(furnitureSelect(rule,'target_type','目标类型',[['furniture','其他家具'],['effect','效果标签']]),rule.target_type==='furniture'?furnitureSelect(rule,'target','目标家具',S.project.furniture.filter(v=>v.id!==d.id).map(v=>[v.id,v.name])):field(rule,'target','效果标签','text'),furnitureSelect(rule,'relation','关系',[['require','需求：必须在范围内'],['exclude','排斥：不能在范围内']]),field(rule,'distance','距离（家具格）','number',0,100),button('－ 删除规则',()=>{d.distance_rules.splice(index,1);renderCatalogForm();dirty()}));rules.append(row);
 }
 rules.append(button('＋ 距离规则',()=>{d.distance_rules??=[];d.distance_rules.push({target_type:'furniture',target:S.project.furniture.find(v=>v.id!==d.id)?.id||'door',relation:'require',distance:3});renderCatalogForm();dirty()}));form.append(rules);
 const binding=document.createElement('details'),summary=document.createElement('summary');summary.textContent='贴图与占位格绑定（家具形态独立于物品形态）';binding.append(summary);
 if(!d.texture_binding)binding.append(button('设置贴图绑定',()=>{d.texture_binding={x:0,y:0,width:d.width,height:d.height,rotation:0};renderCatalogForm();dirty()}));else for(const [key,title]of Object.entries({x:'贴图横偏移（格）',y:'贴图纵偏移（格）',width:'贴图宽（格）',height:'贴图高（格）',rotation:'贴图旋转（度）'}))binding.append(field(d.texture_binding,key,title));form.append(binding);
 renderArtChoices();drawCatalogPreview();
};
const furniturePreview=drawCatalogPreview;drawCatalogPreview=function(){
 if(C.kind!=='furniture')return furniturePreview();if(!C.data)return;
 const d=C.data,c=$('catalogPreview').getContext('2d'),scale=Math.min(540/d.width,270/d.height);F.scale=scale;c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,600,340);c.fillStyle='#191927';c.fillRect(0,0,600,340);
 for(const [plane,color]of [['wall_cells','#659fdc'],['floor_cells','#e2b778']])for(const [x,y]of d[plane]||[]){c.fillStyle=color+'55';c.fillRect(30+x*scale,28+y*scale,scale,scale);c.strokeStyle=color;c.strokeRect(30+x*scale,28+y*scale,scale,scale)}
 const image=imageFor(d.texture),a=d.animation||{frames:1,columns:1,fps:6};if(image?.complete&&image.naturalWidth){const frame=furnitureAnimationFrame(a,performance.now()/1000),columns=a.columns||1,rows=Math.ceil(a.frames/columns),w=image.naturalWidth/columns,h=image.naturalHeight/rows,b=d.texture_binding||{x:0,y:0,width:d.width,height:d.height,rotation:0};c.save();c.translate(30+(b.x+b.width/2)*scale,28+(b.y+b.height/2)*scale);c.rotate(b.rotation*Math.PI/180);c.imageSmoothingEnabled=false;c.drawImage(image,(frame%columns)*w,Math.floor(frame/columns)*h,w,h,-b.width*scale/2,-b.height*scale/2,b.width*scale,b.height*scale);c.restore()}
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
