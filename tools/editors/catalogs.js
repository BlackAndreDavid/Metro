'use strict';
// Shared visual catalogue editors: definitions stay separate from level placements.
const C={kind:'enemies',data:null,point:0,instance:null,images:new Map(),drag:null};
const catalogTitles={enemies:'怪物',items:'物品',building_templates:'建筑'};
function catalogEntries(){return S.project[C.kind]||[]}
function imageFor(path){if(!path)return null;if(!C.images.has(path)){const image=new Image();image.onload=()=>{drawCatalogPreview();drawMap()};image.src='/asset?path='+encodeURIComponent(path);C.images.set(path,image)}return C.images.get(path)}
function field(object,key,label,type='number',min=null,max=null){const wrap=document.createElement('label'),input=document.createElement('input');wrap.textContent=label;input.type=type;if(type==='checkbox')input.checked=object[key]===true;else input.value=object[key]??'';input.dataset.field=key;if(min!==null)input.min=min;if(max!==null)input.max=max;if(type==='number')input.step='any';input.oninput=()=>{object[key]=type==='checkbox'?input.checked:type==='number'?+input.value:input.value;dirty();drawCatalogPreview()};input.onchange=()=>{if(C.kind==='building_templates'&&object===C.data&&['width','floors'].includes(key)&&C.data.width>=1&&C.data.floors>=1){for(const point of C.data.loot_points||[]){point.x=Math.min(point.x,C.data.width);point.floor=Math.min(point.floor,C.data.floors-1)}renderLootPoints();drawCatalogPreview()}};wrap.append(input);return wrap}
function group(title,items){const section=document.createElement('fieldset'),legend=document.createElement('legend');legend.textContent=title;section.append(legend);const fields=document.createElement('div');fields.className='fields';for(const element of items)fields.append(element);section.append(fields);return section}
function viewCatalog(kind){C.kind=kind;C.instance=null;view('catalogView');$('catalogHeading').textContent=catalogTitles[kind]+'目录';const first=catalogEntries().find(e=>!e.deleted)||catalogEntries()[0];if(first)selectCatalog(first);else newCatalog();renderCatalogCards()}
const baseView=view;view=function(id){baseView(id);$('catalogView').hidden=id!=='catalogView'};
$('enemyTab').onclick=()=>viewCatalog('enemies');$('itemTab').onclick=()=>viewCatalog('items');$('buildingTab').onclick=()=>viewCatalog('building_templates');
function renderCatalogCards(){const box=$('catalogCards');box.replaceChildren();for(const data of catalogEntries().filter(e=>!e.deleted||$('showArchived').checked)){const card=button((data.deleted?'已删除 · ':'')+data.name,()=>selectCatalog(data),'customer-card'+(C.data?.id===data.id?' selected':''));card.dataset.catalogId=data.id;const texture=data.sprite?.texture||data.texture;if(texture){const image=document.createElement('img');image.src='/asset?path='+encodeURIComponent(texture);image.alt=data.name;card.prepend(image)}box.append(card)}}
function selectCatalog(data){delete C.outdoor;C.data=clone(data);C.point=0;C.instance=null;C.previewRotated=false;C.previewMirrored=false;renderCatalogForm();renderCatalogCards()}
function renderCatalogForm(){
 const data=C.data;if(!data)return;const outdoor=C.outdoor!==undefined;const form=$('catalogForm');form.hidden=outdoor;$('catalogPreview').hidden=outdoor;$('contentUpload').parentElement.hidden=outdoor;$('artChoices').parentElement.hidden=outdoor;form.replaceChildren();$('catalogTitle').textContent=catalogTitles[C.kind]+' · '+data.name;$('archiveCatalog').textContent=C.instance!==null?'－ 删除此建筑':data.deleted?'恢复条目':'－ 删除（归档）';$('returnToLevel').hidden=C.instance===null&&!outdoor;if(outdoor){$('catalogTitle').textContent='室外物资生成点';$('archiveCatalog').textContent='－ 删除此生成点';}
 const id=field(data,'id','稳定ID','text');id.querySelector('input').readOnly=catalogEntries().some(e=>e.id===data.id)||C.instance!==null;form.append(id,field(data,'name','名称','text'),field(data,'enabled','启用','checkbox'));
 if(C.kind==='enemies'){
  const s=data.sprite,m=data.movement,a=data.alert,k=data.attack;
  form.append(group('素材与碰撞',[field(s,'texture','贴图路径','text'),...['frames','fps','width','height','collision_width','collision_height'].map((key,i)=>field(s,key,['帧数','帧率','显示宽','显示高','碰撞宽','碰撞高'][i], 'number',1)),field(s,'faces_left','原图朝左','checkbox')]),group('行动',[...['patrol_speed','patrol_min','patrol_max','wait_seconds','chase_speed','chase_seconds'].map((key,i)=>field(m,key,['巡逻速度','最短移动秒数','最长移动秒数','停留秒数','追踪速度','警觉移动秒数'][i],'number',0))]),group('警觉',[...['cone_length','cone_angle','circle_radius','visual_gain','sound_gain','decay_per_second'].map((key,i)=>field(a,key,['前向视锥长度','视锥角度','圆形半径','每0.1秒视觉增长','每0.1秒声音增长','每秒警觉下降'][i],'number',0))]),group('扑击',[...['range','speed','duration','time_penalty','slow_seconds','slow_multiplier','recovery','jump_height'].map((key,i)=>field(k,key,['触发距离','扑击速度','扑击秒数','扣除探索秒数','减速持续秒数','速度倍率','攻击后停留秒数','扑起高度'][i],'number',0))]));
 }else if(C.kind==='items'){
  form.append(field(data,'texture','物品贴图','text'),field(data,'price','基础价格','number',0),field(data,'rarity','稀有度0～3','number',0,3));data.active_use??={action:'none',amount:25};const effects=document.createElement('div');for(const [action,label]of Object.entries({none:'无主动效果',drink:'饮水',eat:'进食',heal:'治疗'}))effects.append(button(label,()=>{data.active_use.action=action;renderCatalogForm();dirty()},data.active_use.action===action?'selected':''));effects.append(field(data.active_use,'amount','效果数值（治疗生命）','number',1,100));form.append(effects);const types=document.createElement('div');types.className='object-palette';for(const category of ['none',...Object.keys(S.project.categories)])types.append(button(category==='none'?'非交易物品':S.project.categories[category],()=>{data.category=category;renderCatalogForm();dirty()},data.category===category?'selected':''));form.append(types);renderItemFootprint(form);
 }else{
  data.light_level??=0.15;data.loot_points??=[];data.collision??={x:0,y:0,width:data.width,height:data.floors*110};
  form.append(field(data,'texture','建筑贴图（空为程序绘图）','text'),field(data,'width','建筑宽','number',100),field(data,'floors','楼层1～2','number',1,2),field(data,'wall','墙色','color'),field(data,'light_level','室内光照（0～1，≥0.6自动关灯）','number',0,1),group('碰撞箱',[...['x','y','width','height'].map((key,i)=>field(data.collision,key,['局部横向偏移','局部纵向偏移','碰撞宽','碰撞高'][i]))]));
 }
 $('lootEditor').hidden=C.kind!=='building_templates';$('clearBuildingTexture').hidden=C.kind!=='building_templates';renderArtChoices();renderLootPoints();drawCatalogPreview();
}
function newCatalog(){delete C.outdoor;let number=1;const prefix=C.kind==='enemies'?'enemy':C.kind==='items'?'item':'building';while(catalogEntries().some(e=>e.id===prefix+'_'+number))number++;const id=prefix+'_'+number;
 if(C.kind==='enemies')C.data={...clone(S.project.enemies[0]),id,name:'新怪物',deleted:false,enabled:true};
 else if(C.kind==='items')C.data={id,name:'新物品',enabled:true,texture:'res://assets/textures/temp/items/supply_crate.png',price:20,width:1,height:1,rarity:0,category:'materials'};
 else C.data={id,name:'新建筑',enabled:true,width:180,floors:1,wall:'#736163',texture:'',collision:{x:0,y:0,width:180,height:110},loot_points:[]};
 C.instance=null;C.point=0;C.previewRotated=false;C.previewMirrored=false;renderCatalogForm();dirty();
}
$('newCatalog').onclick=newCatalog;$('showArchived').onchange=renderCatalogCards;
$('archiveCatalog').onclick=run(async()=>{if(C.outdoor!==undefined){checkpoint();S.level.spawn_points.splice(C.outdoor,1);delete C.outdoor;S.entity=-1;refreshMap();view('levelView');status('物资点已删除；请保存关卡。');return}if(C.instance!==null){checkpoint();const id=S.level.buildings[C.instance].id;S.level.buildings.splice(C.instance,1);S.level.loot=S.level.loot.filter(p=>p.building!==id);C.instance=null;S.entity=0;refreshMap();view('levelView');status('已删除建筑及其柜子；请保存关卡，可撤销恢复。');return}if(!catalogEntries().some(e=>e.id===C.data.id)){const first=catalogEntries().find(e=>!e.deleted)||catalogEntries()[0];if(first)selectCatalog(first);status('新建草稿已移除。');return}await api('/api/catalog/archive',{catalog:C.kind,id:C.data.id,deleted:!C.data.deleted});S.project=await api('/api/project');const entry=catalogEntries().find(e=>e.id===C.data.id);C.data=clone(entry);renderCatalogForm();renderCatalogCards();renderPalette();status('目录已更新；归档保留旧存档和已有引用，停止新增生成，可再次恢复。')});
$('saveCatalog').onclick=run(async()=>{
 if(C.outdoor!==undefined){S.level.spawn_points[C.outdoor]=clone(C.data.loot_points[0]);delete C.outdoor;refreshMap();view('levelView');status('物资点已更新；请保存关卡。');return}
 if(C.instance!==null){const old=S.level.buildings[C.instance];Object.assign(old,clone(C.data));refreshMap();view('levelView');status('建筑实例已更新；请保存关卡。');return}
 const path=C.kind==='enemies'?'/api/enemy':C.kind==='items'?'/api/item':'/api/building-template';await api(path,C.data);S.project=await api('/api/project');renderCatalogCards();renderPalette();$('dirty').textContent='✓ 已保存';status(catalogTitles[C.kind]+'已保存。重新进入探索时读取新定义。');
});
const catalogSaveAll=$('saveAll').onclick;$('saveAll').onclick=()=>{if(!$('catalogView').hidden)$('saveCatalog').click();else catalogSaveAll()};
function spritePath(){return C.kind==='enemies'?C.data.sprite.texture:C.data.texture}
function setSpritePath(path,frames=1){if(C.kind==='enemies'){C.data.sprite.texture=path;C.data.sprite.frames=frames}else C.data.texture=path;C.images.delete(path);renderCatalogForm();document.querySelector('details:has(#artChoices)').open=false;dirty()}
function renderArtChoices(){const box=$('artChoices');box.replaceChildren();const category=C.kind==='enemies'?'monsters':C.kind==='items'?'items':null;for(const art of S.project.art.filter(a=>!category||a.category===category)){const card=button(art.id,()=>setSpritePath(art.texture,art.frames),'customer-card');card.dataset.art=art.id;const image=document.createElement('img');image.src='/asset?path='+encodeURIComponent(art.texture);image.alt=art.id;card.prepend(image);box.append(card)}}
$('uploadContent').onclick=run(async()=>{const file=$('contentUpload').files[0];if(!file)throw Error('先选择PNG');const raw=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(file)});const response=await api('/api/content-image',{kind:C.kind==='building_templates'?'buildings':C.kind,id:C.data.id,data:raw});setSpritePath(response.texture,C.kind==='enemies'?C.data.sprite.frames:1)});
$('clearBuildingTexture').onclick=()=>setSpritePath('');
function buildingProjection(){const b=C.data,scale=Math.min(540/b.width,270/(b.floors*110));return {scale,left:30,base:310}}
function drawCatalogPreview(){
 if(!C.data)return;const canvas=$('catalogPreview'),ctx=canvas.getContext('2d');ctx.clearRect(0,0,600,340);ctx.fillStyle='#191927';ctx.fillRect(0,0,600,340);
 const image=imageFor(spritePath());
 if(C.kind==='building_templates'){
  const b=C.data,{scale,left,base}=buildingProjection(),height=b.floors*110*scale;ctx.fillStyle=b.wall;ctx.fillRect(left,base-height,b.width*scale,height);if(image?.complete&&image.naturalWidth)ctx.drawImage(image,left,base-height,b.width*scale,height);
  ctx.strokeStyle='#72d4df';ctx.lineWidth=2;const box=b.collision;ctx.strokeRect(left+box.x*scale,base-(box.height+box.y)*scale,box.width*scale,box.height*scale);
  for(let floor=0;floor<b.floors;floor++){ctx.strokeStyle='#bca79d';ctx.beginPath();ctx.moveTo(left,base-floor*110*scale);ctx.lineTo(left+b.width*scale,base-floor*110*scale);ctx.stroke()}
  for(const[point,index]of b.loot_points.entries()){ctx.fillStyle=index===C.point?'#f5d598':'#bba56c';ctx.fillRect(left+point.x*scale-8,base-point.floor*110*scale-27,16,27);ctx.fillStyle='#fff';ctx.font='12px sans-serif';ctx.fillText(point.id,left+point.x*scale-13,base-point.floor*110*scale-32)}
 }else if(C.kind==='items'){drawItemBoundPreview(ctx,image)}else if(image?.complete&&image.naturalWidth){const frames=C.kind==='enemies'?C.data.sprite.frames:1,w=image.naturalWidth/frames,h=image.naturalHeight,scale=Math.min(400/w,270/h);ctx.drawImage(image,0,0,w,h,300-w*scale/2,310-h*scale,w*scale,h*scale);if(C.kind==='enemies'){const s=C.data.sprite,fit=Math.min(400/s.width,270/s.height);ctx.strokeStyle='#ee8d81';ctx.strokeRect(300-s.collision_width*fit/2,310-s.collision_height*fit,s.collision_width*fit,s.collision_height*fit)}else{ctx.strokeStyle='#a6dccc';for(let y=0;y<C.data.height;y++)for(let x=0;x<C.data.width;x++)ctx.strokeRect(20+x*24,20+y*24,24,24)}}
}
function selectedPoint(){return C.data?.loot_points?.[C.point]}
function newPoint(x=null,floor=0){if(C.kind!=='building_templates')return;let number=1;while(C.data.loot_points.some(p=>p.id==='cabinet_'+number))number++;C.data.loot_points.push({id:'cabinet_'+number,x:x??Math.round(C.data.width/2),floor,chance:1,rolls:1,choices:[{kind:'water',weight:1}]});C.point=C.data.loot_points.length-1;renderLootPoints();drawCatalogPreview();dirty()}
$('addLootPoint').onclick=()=>newPoint();$('removeLootPoint').onclick=()=>{if(!selectedPoint())return;C.data.loot_points.splice(C.point,1);C.point=Math.max(0,C.point-1);renderLootPoints();drawCatalogPreview();dirty()};
function renderLootPoints(){
 $('addLootPoint').disabled=C.outdoor!==undefined;$('removeLootPoint').disabled=C.outdoor!==undefined;const cards=$('lootPointCards'),form=$('lootPointForm'),choices=$('lootChoices'),items=$('lootItemCards');for(const box of[cards,form,choices,items])box.replaceChildren();if(C.kind!=='building_templates')return;
 C.data.loot_points.forEach((point,index)=>cards.append(button('生成点 '+(index+1),()=>{C.point=index;renderLootPoints();drawCatalogPreview()},C.point===index?'selected':'')));
 const point=selectedPoint();if(point){if(point.outside===undefined)point.outside=false;const modes=document.createElement('div');for(const type of ['cabinet','loose'])modes.append(button(type==='cabinet'?'柜子':'散落物资',()=>{point.container=type;renderLootPoints();dirty()},(point.container||'cabinet')===type?'selected':''));form.append(modes,field(point,'outside','建筑外（地面）','checkbox'));if(point.outside===undefined)point.outside=false;for(const[key,label]of [['id','生成点ID'],['x','相对建筑横坐标'],['floor','楼层索引'],['chance','生成概率0～1'],['rolls','抽取次数']])form.append(field(point,key,label,key==='id'?'text':'number'));
  point.choices.forEach((choice,index)=>{const row=document.createElement('div');row.className='bar';const name=document.createElement('span');name.textContent=S.project.items.find(i=>i.id===choice.kind)?.name||choice.kind;row.append(name,field(choice,'weight','权重','number',0),button('－ 移除',()=>{point.choices.splice(index,1);renderLootPoints();dirty()}));choices.append(row)});
 }
 for(const item of S.project.items.filter(i=>!i.deleted)){const card=button('＋ '+item.name,()=>addLootChoice(item.id),'customer-card');card.dataset.lootItem=item.id;card.draggable=true;card.ondragstart=e=>e.dataTransfer.setData('application/x-metro-item',item.id);items.append(card)}
}
function addLootChoice(id){if(!selectedPoint())newPoint();const p=selectedPoint(),found=p.choices.find(c=>c.kind===id);if(found)found.weight++;else p.choices.push({kind:id,weight:1});renderLootPoints();dirty()}
$('catalogPreview').onpointerdown=e=>{if(C.kind!=='building_templates')return;const rect=$('catalogPreview').getBoundingClientRect(),x=(e.clientX-rect.left)*600/rect.width,y=(e.clientY-rect.top)*340/rect.height,{scale,left,base}=buildingProjection();const index=C.data.loot_points.findIndex(p=>Math.abs(x-(left+p.x*scale))<14&&Math.abs(y-(base-p.floor*110*scale-15))<24);if(index>=0){C.point=index;C.drag=true;$('catalogPreview').setPointerCapture(e.pointerId);renderLootPoints();drawCatalogPreview()}};
$('catalogPreview').onpointermove=e=>{if(!C.drag||!selectedPoint())return;const rect=$('catalogPreview').getBoundingClientRect(),x=(e.clientX-rect.left)*600/rect.width,y=(e.clientY-rect.top)*340/rect.height,{scale,left,base}=buildingProjection();selectedPoint().x=Math.round(Math.max(0,Math.min(C.data.width,(x-left)/scale)));selectedPoint().floor=Math.max(0,Math.min(C.data.floors-1,Math.floor((base-y)/scale/110)));renderLootPoints();drawCatalogPreview();dirty()};$('catalogPreview').onpointerup=()=>C.drag=false;
$('catalogPreview').ondragover=e=>{if(C.kind==='building_templates')e.preventDefault()};$('catalogPreview').ondrop=e=>{e.preventDefault();const id=e.dataTransfer.getData('application/x-metro-item');if(id)addLootChoice(id)};
$('returnToLevel').onclick=()=>view('levelView');
const inspectorForLoot=entityForm;entityForm=function(){inspectorForLoot();if(S.type==='buildings'&&S.level?.buildings[S.entity])$('entityFields').append(button('编辑此建筑 · 贴图/碰撞/柜子',()=>{delete C.outdoor;C.kind='building_templates';C.data=clone(S.level.buildings[S.entity]);C.instance=S.entity;C.point=0;view('catalogView');renderCatalogForm()}))};
const removePalette=renderPalette;renderPalette=function(){removePalette();if(!S.project)return;const used=$('buildingPalette');for(const card of [...used.querySelectorAll('[data-asset]')]){const id=card.dataset.asset;const remove=button('－ 删除素材',async()=>{await api('/api/catalog/archive',{catalog:'building_templates',id,deleted:true});S.project=await api('/api/project');renderPalette();status('建筑素材已归档，已摆放建筑保留。')});remove.className='delete-asset';card.after(remove)}};
// Customer indices remain stable for existing saves; removal is reversible archival.
const archiveCustomer=button('－ 删除当前顾客（归档）',async()=>{if(!S.project.customers.some(c=>c.id===S.customer.id)){showCustomer(S.project.customers.find(c=>!c.deleted)||S.project.customers[0]);status('新建顾客草稿已移除。');return}await api('/api/catalog/archive',{catalog:'customers',id:S.customer.id,deleted:!S.customer.deleted});S.project=await api('/api/project');showCustomer(S.project.customers.find(c=>c.id===S.customer.id));customerCards();status('顾客目录已更新；旧存档索引保留。')});$('newCustomer').after(archiveCustomer);
const archiveToggle=document.createElement('label'),archiveCheck=document.createElement('input');archiveCheck.type='checkbox';archiveToggle.textContent='显示已删除顾客';archiveToggle.append(archiveCheck);archiveCustomer.after(archiveToggle);
const originalCards=customerCards;customerCards=function(){const all=S.project.customers;S.project.customers=all.filter(c=>!c.deleted||archiveCheck.checked);originalCards();S.project.customers=all;archiveCustomer.textContent=S.customer?.deleted?'恢复当前顾客':'－ 删除当前顾客（归档）'};archiveCheck.onchange=customerCards;
if(S.project){renderPalette();customerCards()}

function renderCustomerTradeItems(){
 if(!S.customer||!S.project)return;
 for(const side of ['buy','sell']){
  const box=$(side+'Categories');box.querySelectorAll('details').forEach(e=>{const label=e.querySelector('label[data-trade-category-label]');if(label)box.append(label);e.remove()});
  for(const category of Object.keys(S.project.categories)){
   const details=document.createElement('details'),summary=document.createElement('summary');const label=box.querySelector(`input[data-category][value="${category}"]`)?.closest('label');if(label){label.dataset.tradeCategoryLabel=category;summary.append(label)}summary.append(document.createTextNode(' · 具体物品与权重'));details.dataset.tradeCategory=category;details.append(summary);
   const configured=S.customer[side+'_item_weights']?.[category];
   for(const item of S.project.items.filter(i=>i.category===category&&!i.deleted&&i.enabled!==false)){
    const label=document.createElement('label'),weight=document.createElement('input');weight.type='number';weight.min=0;weight.max=100000;weight.step=.1;weight.value=configured?configured[item.id]??0:1;weight.dataset.tradeItem=item.id;weight.dataset.tradeSide=side;
    label.textContent=item.name;weight.oninput=()=>{S.customer[side+'_item_weights']??={};const weights=S.customer[side+'_item_weights'];if(!weights[category]){weights[category]={};for(const input of details.querySelectorAll('input[data-trade-item]'))weights[category][input.dataset.tradeItem]=+input.value}weights[category][item.id]=+weight.value;dirty()};label.append(weight);details.append(label);
   }
   const hint=document.createElement('p');hint.textContent='0 表示不买卖；每个订单按权重抽取3次，出售同种最多2件。未调整的类别沿用全部物品。';details.append(hint);box.append(details);
  }
 }
}
const tradeDetailsCustomer=showCustomer;showCustomer=function(c){tradeDetailsCustomer(c);renderCustomerTradeItems()};
if(S.project)renderCustomerTradeItems();

// A drag from the anchored upper-left cell sets rectangular storage bounds (1..8).
function renderItemFootprint(form){
 const box=document.createElement('fieldset'),legend=document.createElement('legend');legend.textContent='拖拽占位格 · 从左上角确定宽高（最大8×8）';box.append(legend);
 const grid=document.createElement('div');grid.id='itemFootprint';grid.style.cssText='display:grid;grid-template-columns:repeat(8,28px);width:224px;touch-action:none';
 let dragging=false;
 function update(e){const rect=grid.getBoundingClientRect();C.data.width=Math.max(1,Math.min(8,Math.floor((e.clientX-rect.left)/28)+1));C.data.height=Math.max(1,Math.min(8,Math.floor((e.clientY-rect.top)/28)+1));paint();drawCatalogPreview();dirty()}
 function paint(){for(const cell of grid.children)cell.style.background=+cell.dataset.x<C.data.width&&+cell.dataset.y<C.data.height?'#648d84':'#282837';caption.textContent=`${C.data.width} × ${C.data.height} 格`}
 for(let y=0;y<8;y++)for(let x=0;x<8;x++){const cell=document.createElement('div');cell.dataset.x=x;cell.dataset.y=y;cell.style.cssText='width:28px;height:28px;border:1px solid #81758e;box-sizing:border-box';grid.append(cell)}
 grid.onpointerdown=e=>{if(e.button!==0)return;e.preventDefault();dragging=true;grid.setPointerCapture(e.pointerId);update(e)};grid.onpointermove=e=>{if(dragging)update(e)};grid.onpointerup=grid.onpointercancel=()=>dragging=false;
 const caption=document.createElement('p');caption.id='itemFootprintSize';box.append(grid,caption);paint();
 box.append(button('旋转预览',()=>{C.previewRotated=!C.previewRotated;drawCatalogPreview()}),button('镜像预览',()=>{C.previewMirrored=!C.previewMirrored;drawCatalogPreview()}));form.append(box);
}
function drawItemBoundPreview(ctx,image){
 const w=C.previewRotated?C.data.height:C.data.width,h=C.previewRotated?C.data.width:C.data.height,cell=Math.min(64,260/Math.max(w,h)),left=300-w*cell/2,top=170-h*cell/2;
 ctx.fillStyle='#35504c';ctx.fillRect(left,top,w*cell,h*cell);
 if(image?.complete&&image.naturalWidth){const rw=image.naturalWidth,rh=image.naturalHeight,fit=Math.min((w*cell-12)/(C.previewRotated?rh:rw),(h*cell-12)/(C.previewRotated?rw:rh));ctx.save();ctx.translate(300,170);ctx.rotate(C.previewRotated?Math.PI/2:0);ctx.scale(C.previewMirrored?-1:1,1);ctx.drawImage(image,-rw*fit/2,-rh*fit/2,rw*fit,rh*fit);ctx.restore()}
 ctx.strokeStyle='#a6dccc';for(let y=0;y<h;y++)for(let x=0;x<w;x++)ctx.strokeRect(left+x*cell,top+y*cell,cell,cell);
 ctx.fillStyle='#f2eadd';ctx.font='14px sans-serif';ctx.fillText(`${w} × ${h} · 贴图与占位同步${C.previewMirrored?' · 镜像':''}`,20,326);
}
