'use strict';
// Scene canvas, reusable assets and encounter view. Exact values stay in the inspector.
const W={row:2,col:0,undo:[],tool:null,ghost:null,pendingLink:null,chat:[],story:null};
const entityTypes=['buildings','stations','junctions','loot','vehicles','npcs','monsters'];
const names={buildings:'建筑',stations:'站口',junctions:'巷口',loot:'物资',vehicles:'汽车',npcs:'NPC',monsters:'怪物'};
function dirty(){ $('dirty').textContent='● 未保存' }
function button(text,action,className=''){const b=document.createElement('button');b.textContent=text;b.className=className;b.onclick=run(action);return b}
function syncCells(){ $('cells').value=S.level.cell_names.map(r=>r.join(',')).join('\n') }
function checkpoint(){W.undo.push(clone(S.level));if(W.undo.length>30)W.undo.shift()}
function rowStart(row){return S.level.street_starts?.[row]||0}
function rowEnd(row){return rowStart(row)+rowWidth(row)}
function rowWidth(row){return S.level.segment*S.level.cell_names[row].length}
worldWidth=function(){return Math.max(...S.level.cell_names.map((r,i)=>rowEnd(i)))};
function canvasLocation(e){const[x,y]=mapPoint(e),row=Math.floor((y-20)/band());return {x:(x-20)/960*worldWidth(),row,canvas:[x,y]}}
function validLocation(at){return at.row>=0&&at.row<S.level.cell_names.length&&at.x>=rowStart(at.row)&&at.x<rowEnd(at.row)}
function limitFor(type,row){return type==='junctions'?Math.min(rowEnd(row),rowEnd(row+1)):rowEnd(row)}
function startFor(type,row){return type==='junctions'?Math.max(rowStart(row),rowStart(row+1)):rowStart(row)}
function repairJunctions(){S.level.junctions=S.level.junctions.filter(j=>{const low=startFor('junctions',j.row)+24,high=limitFor('junctions',j.row)-24;if(low>high)return false;j.x=Math.max(low,Math.min(high,j.x));return true})}
function selectCell(row,col){W.row=row;W.col=Math.max(0,Math.min(S.level.cell_names[row].length-1,col));if($('streetStart'))$('streetStart').value=rowStart(row);$('selectedCell').textContent=`第${row+1}街 · 第${W.col+1}格`}
function refreshMap(){syncCells();selectCell(Math.min(W.row,S.level.cell_names.length-1),W.col);listEntities();drawMap();dirty()}
function keepEntrance(){if(!S.level.stations.some(s=>s.name===S.station))S.level.stations.push({name:S.station,row:Math.min(W.row,S.level.cell_names.length-1),x:rowStart(Math.min(W.row,S.level.cell_names.length-1))+48})}
const workspaceShowLevel=showLevel;
showLevel=function(data){data=clone(data);data.monsters??=[];data.street_starts??=data.cell_names.map(()=>0);workspaceShowLevel(data);W.undo=[];W.tool=null;W.ghost=null;W.row=Math.min(W.row,S.level.cell_names.length-1);selectCell(W.row,0);renderPalette();updateStationBanner();drawMap()};
$('addColumn').onclick=run(()=>{readLevel();const row=S.level.cell_names[W.row];if(row.length>=8)throw Error('每条街道最多8格');checkpoint();row.push('新地图格');selectCell(W.row,row.length-1);refreshMap()});
$('removeCell').onclick=run(()=>{
  readLevel();const row=S.level.cell_names[W.row];if(row.length===1)throw Error('每条街道至少保留一个格子');checkpoint();
  const start=rowStart(W.row)+W.col*S.level.segment,end=start+S.level.segment,removed=new Set();
  for(const b of S.level.buildings)if(b.row===W.row&&b.x<end&&b.x+b.width>start)removed.add(b.id);
  row.splice(W.col,1);
  for(const type of entityTypes){S.level[type]=S.level[type].filter(e=>!((e.row===W.row&&e.x>=start&&e.x<end)||(type==='buildings'&&removed.has(e.id))||(type==='loot'&&removed.has(e.building))));for(const e of S.level[type])if(e.row===W.row&&e.x>=end)e.x-=S.level.segment}
  repairJunctions();
  keepEntrance();S.entity=0;refreshMap();status('已移除选中格及其中的对象，后续对象前移；可点击撤销恢复。');
});
$('addRow').onclick=run(()=>{
  readLevel();if(S.level.cell_names.length>=8)throw Error('最多8条街道');checkpoint();const index=W.row+1;
  for(const type of entityTypes)for(const e of S.level[type])if(e.row>=index)e.row++;
  S.level.cell_names.splice(index,0,['新街道']);S.level.street_starts.splice(index,0,rowStart(index-1));
  repairJunctions();
  for(const row of[index-1,index])if(row>=0&&row<S.level.cell_names.length-1&&!S.level.junctions.some(j=>j.row===row))S.level.junctions.push({row,x:(startFor('junctions',row)+limitFor('junctions',row))/2});
  repairJunctions();selectCell(index,0);refreshMap();
});
$('removeRow').onclick=run(()=>{
  readLevel();if(S.level.cell_names.length===1)throw Error('地图至少保留一条街道');checkpoint();const row=W.row;
  S.level.cell_names.splice(row,1);S.level.street_starts.splice(row,1);
  for(const type of entityTypes){S.level[type]=S.level[type].filter(e=>type==='junctions'?e.row!==row&&e.row!==row-1:e.row!==row);for(const e of S.level[type])if(e.row>row)e.row--}
  if(row>0&&row<S.level.cell_names.length)S.level.junctions.push({row:row-1,x:(startFor('junctions',row-1)+limitFor('junctions',row-1))/2});
  repairJunctions();W.row=Math.min(row,S.level.cell_names.length-1);keepEntrance();S.entity=0;refreshMap();status('已删除街道及其对象；本站入口已保留，可撤销恢复。');
});
$('undoMap').onclick=()=>{if(!W.undo.length)return;const history=W.undo,saved=history.pop();showLevel(saved);W.undo=history;dirty()};
function assetCard(label,tool,swatch=null){const b=button(label,()=>{W.tool=tool;S.type=tool.type;S.entity=0;$('entityType').value=S.type;listEntities();renderPalette();status('将素材拖入地图，或点击目标位置放置。')},'building-card');b.draggable=true;b.dataset.asset=tool.key||tool.type;if(swatch)b.prepend(swatch);b.ondragstart=e=>e.dataTransfer.setData('application/x-metro-object',JSON.stringify(tool));return b}
function renderPalette(){
  if(!S.project)return;
  const box=$('objectPalette');box.replaceChildren();box.append(button('↖ 选择 / 移动',()=>{W.tool=null;renderPalette()},W.tool?'object-chip':'object-chip selected'));
  for(const type of['stations','junctions','vehicles']){const card=assetCard(names[type],{type});card.className='object-chip'+(W.tool?.type===type?' selected':'');box.append(card)}
  for(const npc of S.project.customers.filter(c=>!c.deleted)){const card=assetCard('♟ '+npc.name,{type:'npcs',npc:npc.id,key:npc.id});card.className='object-chip';box.append(card)}
  for(const enemy of (S.project.enemies||[]).filter(e=>e.enabled&&!e.deleted)){const card=assetCard('⚠ '+enemy.name,{type:'monsters',enemy:enemy.id,key:enemy.id});card.className='object-chip monster-chip';box.append(card)}
  const buildings=$('buildingPalette');buildings.replaceChildren();
  for(const template of S.project.building_templates.filter(t=>!t.deleted)){const swatch=document.createElement('span');swatch.className='building-swatch';swatch.style.backgroundColor=template.wall;swatch.style.height=`${template.floors*20}px`;buildings.append(assetCard(`${template.name} · ${template.floors}层`,{type:'buildings',key:template.id,template},swatch))}
  buildings.append(button('＋ 选中建筑存为素材卡',async()=>{if(S.type!=='buildings'||!S.level.buildings[S.entity])throw Error('先在地图上选中建筑');const b=S.level.buildings[S.entity];const template=clone(b);delete template.x;delete template.row;delete template.template_id;for(const point of template.loot_points||[])delete point.legacy_slot;await api('/api/building-template',template);S.project=await api('/api/project');renderPalette();status('建筑素材已保存，可以重复拖入各个关卡。')}));
}
function placeAsset(tool,at){
  if(!validLocation(at))throw Error('请放置在实际存在的街道格子内');
  const row=at.row,snap=$('snap').checked?+$('gridSize').value:0;
  if(tool.type==='junctions'&&row===S.level.cell_names.length-1)throw Error('巷口连接下一条街道，请放在两条相邻街道的共同范围');
  if(tool.type==='npcs'&&S.level.npcs.some(n=>n.npc===tool.npc))throw Error('该 NPC 已在关卡中，请直接拖动它');
  if(tool.type==='monsters'&&S.project.enemies.find(e=>e.id===tool.enemy).sprite.collision_width>rowWidth(row))throw Error('该街道不足以容纳怪物碰撞箱');
  checkpoint();let data;
  if(tool.type==='buildings')data=new BuildingDefinition(tool.template||S.project.building_templates[0]).instantiate(S.level,row,at.x,snap);
  else {const half=tool.type==='monsters'?S.project.enemies.find(e=>e.id===tool.enemy).sprite.collision_width/2:24;const x=Math.max(startFor(tool.type,row)+half,Math.min(limitFor(tool.type,row)-half,snap?Math.round(at.x/snap)*snap:at.x));let index=1;while(S.level.vehicles.some(e=>e.id===`vehicle_${index}`))index++;
    data={stations:{name:S.station,row,x},junctions:{row,x},loot:{row,x,building:'',floor:0,kind:'book'},vehicles:{id:`vehicle_${index}`,row,x,color:'#677378'},npcs:{npc:tool.npc,row,x},monsters:{id:'monster_'+Date.now().toString(36),enemy:tool.enemy,row,x,facing:-1}}[tool.type]}
  S.level[tool.type].push(data);S.type=tool.type;S.entity=S.level[S.type].length-1;selectCell(row,Math.floor((data.x-rowStart(row))/S.level.segment));W.tool=null;W.ghost=null;$('entityType').value=S.type;listEntities();drawMap();renderPalette();dirty();
}
$('addEntity').onclick=run(()=>{if(!W.tool)W.tool=S.type==='buildings'?{type:'buildings',template:S.project.building_templates[0]}:S.type==='npcs'?{type:'npcs',npc:S.project.customers[0].id}:{type:S.type};status('点击地图上的目标格放置所选素材。')});
const workspaceRemoveEntity=$('removeEntity').onclick;$('removeEntity').onclick=()=>{checkpoint();workspaceRemoveEntity();dirty()};
const workspaceApplyEntity=applyEntity;applyEntity=function(){const e=S.level?.[S.type]?.[S.entity];if(!e)return;checkpoint();workspaceApplyEntity();if(S.type==='buildings')for(const point of e.loot_points||[]){point.x=Math.max(0,Math.min(e.width,point.x));point.floor=Math.min(point.floor,e.floors-1)}dirty()};$('applyEntity').onclick=run(applyEntity);
function entityRect(type,e){const scale=960/worldWidth(),x=20+e.x*scale,base=20+(e.row+1)*band()-14;if(type==='monsters'){const enemy=S.project.enemies.find(t=>t.id===e.enemy);const w=(enemy?.sprite.width||128)*scale;return[x-w/2,base-26,w,26]}if(type==='buildings'){const h=Math.min(band()-40,e.floors*28);return[x,base-h,e.width*scale,h]}return[x-10,base-34,20,34]}
drawMap=function(){
  const c=$('map').getContext('2d');c.clearRect(0,0,1000,510);if(!S.level)return;const d=S.level,scale=960/worldWidth(),height=band(),grid=Math.max(3,(+$('gridSize').value||20)*scale);c.font='12px sans-serif';
  for(let row=0;row<d.cell_names.length;row++){const y=20+row*height,width=rowWidth(row)*scale;c.fillStyle='#342f45';c.fillRect(20+rowStart(row)*scale,y,width,height-6);c.strokeStyle='#494355';c.lineWidth=.5;for(let x=20+rowStart(row)*scale;x<20+rowEnd(row)*scale;x+=grid){c.beginPath();c.moveTo(x,y);c.lineTo(x,y+height-6);c.stroke()}for(let gy=y;gy<y+height-6;gy+=grid){c.beginPath();c.moveTo(20+rowStart(row)*scale,gy);c.lineTo(20+rowEnd(row)*scale,gy);c.stroke()}c.lineWidth=1;for(let col=0;col<d.cell_names[row].length;col++){const x=20+(rowStart(row)+col*d.segment)*scale;c.strokeStyle=row===W.row&&col===W.col?'#efc488':'#81758e';c.lineWidth=row===W.row&&col===W.col?2:1;c.strokeRect(x,y,d.segment*scale,height-6);c.fillStyle='#d1bdad';c.fillText(`${col===0?'↔ ':''}${row+1}.${col+1} ${d.cell_names[row][col]}`,x+7,y+17)}}
  for(const type of entityTypes)(d[type]||[]).forEach((e,i)=>{const rect=entityRect(type,e);c.fillStyle=type==='buildings'?e.wall:{stations:'#a6dccc',junctions:'#a4b8e8',loot:'#f0cc91',vehicles:'#a98eac',npcs:'#ef9eae',monsters:'#ed8075'}[type];c.fillRect(...rect);if(type==='buildings'){c.fillStyle='#d5c8ab';for(let x=rect[0]+10;x<rect[0]+rect[2]-6;x+=20)c.fillRect(x,rect[1]+9,8,9)}if(type===S.type&&i===S.entity){c.strokeStyle='#fff';c.lineWidth=2;c.strokeRect(...rect)}c.fillStyle='#f2eadd';const npc=S.project.customers.find(n=>n.id===e.npc),enemy=S.project.enemies.find(n=>n.id===e.enemy);c.fillText((enemy?.name||npc?.name||e.name||e.id||names[type]).slice(0,16),rect[0],rect[1]-5)});
  if(W.ghost&&validLocation(W.ghost)){c.fillStyle='#a6dccc66';const x=20+W.ghost.x*scale,base=20+(W.ghost.row+1)*height-14;c.fillRect(x,base-45,Math.min(130,((W.tool?.template?.width)||160)*scale),45)}
  $('levelJson').value=JSON.stringify(d,null,2);
};
$('map').onpointerdown=e=>{
  try{if(!S.level)return;const at=canvasLocation(e);if(!validLocation(at))return;
    if(W.tool){placeAsset(W.tool,at);return}
    selectCell(at.row,Math.floor((at.x-rowStart(at.row))/S.level.segment));const[x,y]=at.canvas;if(x<=20+rowStart(at.row)*960/worldWidth()+24&&y<20+at.row*band()+25){checkpoint();S.drag={kind:'street',row:at.row,start:rowStart(at.row),pointer:at.canvas[0],scale:worldWidth()/960};$('map').setPointerCapture(e.pointerId);return}let found;
    for(const type of entityTypes)S.level[type].forEach((entity,i)=>{const[a,b,w,h]=entityRect(type,entity);if(x>=a&&x<=a+w&&y>=b&&y<=b+h)found={type,i}});
    if(found){S.type=found.type;S.entity=found.i;$('entityType').value=S.type;checkpoint();listEntities();S.drag={kind:'entity',offset:at.x-S.level[S.type][S.entity].x};$('map').setPointerCapture(e.pointerId)}else{S.entity=-1;entityForm()}
    drawMap();
  }catch(error){status(error.message,true)}
};
$('map').onpointermove=e=>{
  const at=canvasLocation(e);if(S.drag?.kind==='street'){setStreetStart(S.drag.row,S.drag.start+(at.canvas[0]-S.drag.pointer)*S.drag.scale,false);return}if(W.tool){W.ghost=at;drawMap()}
  if(S.drag?.kind!=='entity'||!validLocation(at))return;
  const entity=S.level[S.type][S.entity],row=at.row;if(S.type==='junctions'&&row===S.level.cell_names.length-1)return;
  let x=at.x-S.drag.offset;if($('snap').checked)x=Math.round(x/(+$('gridSize').value||20))*(+$('gridSize').value||20);
  try{if(S.type==='buildings')BuildingDefinition.move(S.level,entity,row,x);else{entity.row=row;entity.x=Math.max(startFor(S.type,row)+(S.type==='monsters'?S.project.enemies.find(e=>e.id===entity.enemy).sprite.collision_width/2:24),Math.min(limitFor(S.type,row)-(S.type==='monsters'?S.project.enemies.find(e=>e.id===entity.enemy).sprite.collision_width/2:24),x))}selectCell(row,Math.floor((entity.x-rowStart(row))/S.level.segment));entityForm();drawMap();dirty()}catch(error){status(error.message,true)}
};
$('map').onpointerup=()=>S.drag=null;$('map').onpointercancel=()=>S.drag=null;$('map').onpointerleave=()=>{W.ghost=null;drawMap()};
$('map').ondblclick=e=>{const at=canvasLocation(e);if(!validLocation(at))return;const col=Math.floor((at.x-rowStart(at.row))/S.level.segment),name=prompt('地图格名称',S.level.cell_names[at.row][col]);if(name?.trim()){checkpoint();S.level.cell_names[at.row][col]=name.trim();syncCells();drawMap();dirty()}};
$('map').ondragover=e=>{e.preventDefault();W.ghost=canvasLocation(e);drawMap()};$('map').ondragleave=()=>{W.ghost=null;drawMap()};
$('map').ondrop=e=>{e.preventDefault();try{placeAsset(JSON.parse(e.dataTransfer.getData('application/x-metro-object')),canvasLocation(e))}catch(error){status(error.message,true)}};
// The station picker uses the same line geometry and station coordinates as the game.
const svgNS='http://www.w3.org/2000/svg';
let diagram=null,diagramView={x:-50,y:-55,w:1370,h:1210},stationPan=null,stationLoad=0;
const mapDrafts=new Map();
function svgElement(tag,attrs={}){const element=document.createElementNS(svgNS,tag);for(const[k,v]of Object.entries(attrs))element.setAttribute(k,v);return element}
function applyDiagramView(){diagram?.setAttribute('viewBox',`${diagramView.x} ${diagramView.y} ${diagramView.w} ${diagramView.h}`)}
function updateStationBanner(){if(!S.project)return;const lines=S.project.station_map.lines.filter(l=>l[2].includes(S.station)).map(l=>`${l[0]}号线`).join(' / ');$('editingStation').textContent=S.station;$('stationBadge').textContent=`${S.station} · ${lines}`}
async function selectStation(name){
  if(S.level){readLevel();mapDrafts.set(S.station,clone(S.level))}
  const sequence=++stationLoad,result=await api('/api/level?station='+encodeURIComponent(name));if(sequence!==stationLoad)return;
  S.station=name;$('stations').value=name;showLevel(mapDrafts.get(name)||result.definition||cloneTemplate(result.template));$('levelPaths').textContent=JSON.stringify(S.project.registry.stations[name]||{},null,2);$('stationDialog').close();updateStationBanner();status(`正在编辑：${name}；切换前的地图草稿已在本页保留。`);
}
function renderStationMap(){
  if(!S.project)return;diagram=svgElement('svg',{'aria-label':'地铁站点选择地图'});const geometry=S.project.station_map;
  for(const[number,color,route]of geometry.lines){const points=route.map(p=>typeof p==='string'?geometry.stations[p].position:p);const path=svgElement('polyline',{points:points.map(p=>p.join(',')).join(' '),fill:'none',stroke:'#'+color,'stroke-width':8,'stroke-linejoin':'round'});diagram.append(path)}
  for(const[name,data]of Object.entries(geometry.stations)){
    const[x,y]=data.position,group=svgElement('g',{'data-station':name,class:'station-hit',role:'button',tabindex:0,'aria-label':`编辑${name}站`,transform:`translate(${x},${y})`});
    group.append(svgElement('circle',{r:21,fill:'transparent'}));
    if(S.project.registry.stations[name])group.append(svgElement('circle',{r:12,fill:'none',stroke:'#a6dccc','stroke-width':3}));
    group.append(svgElement('circle',{r:name===S.station?10:6,class:'station-dot',style:name===S.station?'fill:#efc488;stroke:#efc488':''}));
    const text=svgElement('text',{x:data.label[0],y:data.label[1],class:'station-label'});text.textContent=name;group.append(text);
    group.onclick=run(()=>selectStation(name));group.onkeydown=e=>{if(e.key==='Enter')selectStation(name).catch(error=>status(error.message,true))};diagram.append(group);
  }
  $('stationDiagram').replaceChildren(diagram);applyDiagramView();
  diagram.onwheel=e=>{e.preventDefault();zoomStations(e.deltaY<0?.8:1.25)};
  diagram.onpointerdown=e=>{if(e.target.closest('.station-hit'))return;stationPan={x:e.clientX,y:e.clientY,origin:{...diagramView}};diagram.setPointerCapture(e.pointerId)};
  diagram.onpointermove=e=>{if(!stationPan)return;const rect=diagram.getBoundingClientRect();diagramView.x=stationPan.origin.x-(e.clientX-stationPan.x)/rect.width*diagramView.w;diagramView.y=stationPan.origin.y-(e.clientY-stationPan.y)/rect.height*diagramView.h;applyDiagramView()};
  diagram.onpointerup=()=>stationPan=null;diagram.onpointercancel=()=>stationPan=null;
}
function zoomStations(scale){const width=Math.max(200,Math.min(2000,diagramView.w*scale)),ratio=width/diagramView.w;diagramView.x+=(diagramView.w-width)/2;diagramView.y+=diagramView.h*(1-ratio)/2;diagramView.w=width;diagramView.h*=ratio;applyDiagramView()}
$('chooseStation').onclick=()=>{renderStationMap();$('stationDialog').showModal()};$('closeStations').onclick=()=>$('stationDialog').close();$('stationZoomIn').onclick=()=>zoomStations(.8);$('stationZoomOut').onclick=()=>zoomStations(1.25);$('stationReset').onclick=()=>{diagramView={x:-50,y:-55,w:1370,h:1210};applyDiagramView()};
$('stationSearch').oninput=()=>{const query=$('stationSearch').value.trim(),entry=Object.entries(S.project.station_map.stations).find(([name])=>name.includes(query));if(!query||!entry)return;const[x,y]=entry[1].position;diagramView={x:x-250,y:y-220,w:500,h:440};applyDiagramView()};
// Thumbnail cards replace the former customer directory list.
const workspaceListCustomers=listCustomers,workspaceShowCustomer=showCustomer;
function customerCards(){const box=$('customerCards');box.replaceChildren();for(const c of S.project.customers){const card=button(c.name,()=>{readCustomer();if(S.customer&&!S.customer._create){const index=S.project.customers.findIndex(n=>n.id===S.customer.id);if(index>=0)S.project.customers[index]=clone(S.customer)}showCustomer(c)},'customer-card'+(S.customer?.id===c.id?' selected':''));card.dataset.customer=c.id;const image=document.createElement('img');image.src='/asset?path='+encodeURIComponent(c.texture);image.alt=c.name;card.prepend(image);box.append(card)}}
listCustomers=function(){workspaceListCustomers();customerCards();renderPalette()};
showCustomer=function(c){workspaceShowCustomer(c);customerCards()};
// Encounter preview: every story owns an independent conversation graph.
const workspaceShowStories=showStories,workspaceShowNode=showNode,workspaceReadNode=readNode,workspaceAddChoice=addChoice;
showStories=function(index=0){workspaceShowStories(index);W.story=S.story;W.chat=[];W.pendingLink=null;$('meetingPane').hidden=!S.story;if(S.story){W.chat=[{node:S.story.start}];$('meetingTitle').textContent=S.story.name||S.story.id;$('selectedMeeting').textContent='本次见面：'+(S.story.name||S.story.id);renderChat()}else $('selectedMeeting').textContent='点击新增见面，开始编排对话'};
showNode=function(id){workspaceShowNode(id);document.querySelectorAll('.bubble').forEach(b=>b.classList.toggle('selected',b.dataset.node===id));updateLinkHint()};
readNode=function(){workspaceReadNode();if(S.story&&S.node){[...$('choices').children].forEach((row,i)=>{const choice=S.story.nodes[S.node].choices[i];choice.effects={...row._effects,...choice.effects}});updateLinkHint()}};
addChoice=function(choice){workspaceAddChoice(choice);const row=$('choices').lastElementChild,select=row.querySelector('select');row._effects=clone(choice?.effects||{});select.hidden=true;const target=button('连到 '+(select.value||'结束'),()=>{readNode();W.pendingLink={node:S.node,index:[...$('choices').children].indexOf(row)};updateLinkHint();$('graph').scrollIntoView({block:'center',behavior:'smooth'})},'choice-target');target.draggable=true;target.ondragstart=e=>e.dataTransfer.setData('application/x-metro-link',JSON.stringify({node:S.node,index:[...$('choices').children].indexOf(row)}));row.insertBefore(target,select);row.append(button('以此回答结束',()=>{readNode();const index=[...$('choices').children].indexOf(row);S.story.nodes[S.node].choices[index].next='';select.value='';target.textContent='连到 结束';drawGraph();renderChat();dirty()}));row.append(button('新一轮回应',()=>{readNode();const from=S.node,index=[...$('choices').children].indexOf(row),meeting=new MeetingDialogue(S.story),id=meeting.createTurn(S.customer.name);S.story.nodes[from].choices[index].next=id;showNode(id);W.chat=[{node:from},{reply:true,from,index},{node:id}];renderChat();dirty()}));};
function updateLinkHint(){if(!$('linkHint'))return;$('linkHint').textContent=W.pendingLink?'点击目标节点或把连接端点拖到节点上':S.node?'下一轮：'+(S.story.nodes[S.node]?.next||'结束'):''}
function syncChatEdit(entry,value){if(entry.reply){const choice=S.story.nodes[entry.from].choices[entry.index];choice.text=value;if(S.node===entry.from){const row=$('choices').children[entry.index];if(row)row.querySelector('input').value=value}}else{S.story.nodes[entry.node].text=value;if(S.node===entry.node)$('nodeText').value=value}dirty();drawGraph()}
function renderChat(){
  if(!S.story)return;const log=$('chatLog');log.replaceChildren();
  for(const entry of W.chat){const node=entry.reply?S.story.nodes[entry.from]:S.story.nodes[entry.node];if(!node)continue;const bubble=document.createElement('div');bubble.className='bubble'+(entry.reply?' player':'')+(!entry.reply&&entry.node===S.node?' selected':'');bubble.dataset.node=entry.reply?entry.from:entry.node;const speaker=document.createElement('small');speaker.textContent=entry.reply?'玩家':node.speaker||S.customer.name;const text=document.createElement('div');text.contentEditable='true';text.setAttribute('aria-label',entry.reply?'玩家回答文本':'NPC发言文本');text.textContent=entry.reply?node.choices[entry.index]?.text||'':node.text;text.oninput=()=>syncChatEdit(entry,text.innerText);bubble.append(speaker,text);bubble.onclick=()=>{if(S.node!==bubble.dataset.node){readNode();showNode(bubble.dataset.node)}};log.append(bubble)}
  const replies=$('chatReplies');replies.replaceChildren();const last=W.chat.at(-1);if(!last||last.reply)return;const node=S.story.nodes[last.node];if(!node)return;
  for(const[choice,index]of(node.choices||[]).map((c,i)=>[c,i]))replies.append(button(choice.text||'玩家回答',()=>previewAdvance(choice.next,{reply:true,from:last.node,index})));
  if(!(node.choices||[]).length)replies.append(button(node.next?'继续 NPC 发言':'结束本次见面',()=>previewAdvance(node.next)));
  log.scrollTop=log.scrollHeight;
}
function previewAdvance(next,reply=null){readNode();if(W.chat.length>200){status('当前路径过长，点击从头预览重新开始。',true);return}if(reply)W.chat.push(reply);if(next&&S.story.nodes[next]){W.chat.push({node:next});showNode(next);renderChat()}else{renderChat();$('chatReplies').replaceChildren(button('本次见面结束 · 从头预览',restartMeeting))}}
function restartMeeting(){readNode();W.chat=[{node:S.story.start}];showNode(S.story.start);renderChat()}
$('restartMeeting').onclick=restartMeeting;
$('appendSpeech').onclick=run(()=>{readNode();const from=S.node,id=new MeetingDialogue(S.story).appendSpeech(from,S.customer.name);showNode(id);W.chat=[{node:from},{node:id}];renderChat();dirty()});
$('appendReply').onclick=run(()=>{readNode();const from=S.node,id=new MeetingDialogue(S.story).appendReply(from,S.customer.name),index=S.story.nodes[from].choices.length-1;showNode(id);W.chat=[{node:from},{reply:true,from,index},{node:id}];renderChat();dirty()});
$('linkNext').onclick=()=>{readNode();W.pendingLink={node:S.node,index:-1};updateLinkHint()};$('clearNext').onclick=()=>{S.story.nodes[S.node].next='';$('nodeNext').value='';W.pendingLink=null;drawGraph();updateLinkHint();dirty()};
// Conversation graph: drag nodes to arrange; drag output dots to connect turns.
const originalGraph=$('graph');originalGraph.replaceWith(originalGraph.cloneNode(true));
nodePos=function(id,index){return S.story.nodes[id].editor_position||[30+(index%3)*320,35+Math.floor(index/3)*240]};
function nodeHeight(node){return 110+Math.max(1,(node.choices||[]).length)*25}
function graphNodeAt(x,y){for(const[id,index]of Object.keys(S.story?.nodes||{}).map((id,i)=>[id,i])){const[a,b]=nodePos(id,index);if(x>=a-8&&x<=a+235&&y>=b&&y<=b+nodeHeight(S.story.nodes[id]))return id}return null}
function outputPorts(id,index){const[x,y]=nodePos(id,index),node=S.story.nodes[id];const ports=(node.choices||[]).map((c,i)=>({node:id,index:i,x:x+225,y:y+98+i*25,label:c.text||'玩家回答',target:c.next}));ports.push({node:id,index:-1,x:x+225,y:y+nodeHeight(node)-12,label:'NPC 继续',target:node.next});return ports}
function linkTurn(link,target){if(!target)return;const node=S.story.nodes[link.node];if(link.index===-1)node.next=target;else node.choices[link.index].next=target;W.pendingLink=null;showNode(link.node);drawGraph();renderChat();dirty()}
drawGraph=function(){
  if(!S.story)return;const ids=Object.keys(S.story.nodes),canvas=$('graph'),ctx=canvas.getContext('2d');canvas.height=Math.max(340,...ids.map((id,i)=>nodePos(id,i)[1]+nodeHeight(S.story.nodes[id])+35));ctx.clearRect(0,0,1000,canvas.height);ctx.lineWidth=2;
  ids.forEach((id,i)=>{for(const port of outputPorts(id,i)){if(!S.story.nodes[port.target])continue;const targetIndex=ids.indexOf(port.target),[x,y]=nodePos(port.target,targetIndex),bend=port.x+25;ctx.strokeStyle=port.index<0?'#a6dccc':'#dcb4d7';ctx.beginPath();ctx.moveTo(port.x,port.y);ctx.lineTo(bend,port.y);ctx.lineTo(bend,y-15);ctx.lineTo(x-15,y-15);ctx.lineTo(x-15,y+25);ctx.lineTo(x,y+25);ctx.stroke();ctx.fillStyle=ctx.strokeStyle;ctx.beginPath();ctx.moveTo(x,y+25);ctx.lineTo(x-9,y+20);ctx.lineTo(x-9,y+30);ctx.fill()}});
  ids.forEach((id,i)=>{const[x,y]=nodePos(id,i),node=S.story.nodes[id],height=nodeHeight(node);ctx.fillStyle=id===S.node?'#5d4967':'#323746';ctx.fillRect(x,y,225,height);ctx.strokeStyle=id===S.story.start?'#efc488':'#87798e';ctx.strokeRect(x,y,225,height);ctx.fillStyle='#f3dfc2';ctx.font='15px sans-serif';ctx.fillText((id===S.story.start?'▶ ':'')+(node.speaker||S.customer.name).slice(0,14),x+10,y+22);ctx.font='12px sans-serif';ctx.fillStyle='#c2b6ce';ctx.fillText(id,x+10,y+42);ctx.fillStyle='#f1e8df';ctx.fillText((node.text||'').replaceAll('\n',' ').slice(0,18),x+10,y+66);for(const port of outputPorts(id,i)){ctx.fillStyle=port.index<0?'#a6dccc':'#dfb5da';ctx.beginPath();ctx.arc(port.x,port.y,7,0,Math.PI*2);ctx.fill();ctx.fillText(port.label.slice(0,15),x+10,port.y+4)}});
};
$('graph').onpointerdown=e=>{try{readNode();const[x,y]=graphPoint(e),ids=Object.keys(S.story?.nodes||{});for(const[id,i]of ids.map((id,i)=>[id,i]))for(const port of outputPorts(id,i))if(Math.hypot(x-port.x,y-port.y)<=12){S.drag={kind:'graphLink',link:{node:id,index:port.index}};$('graph').setPointerCapture(e.pointerId);return}const id=graphNodeAt(x,y);if(!id)return;if(W.pendingLink){linkTurn(W.pendingLink,id);return}showNode(id);const[a,b]=nodePos(id,ids.indexOf(id));S.drag={kind:'node',id,offset:[x-a,y-b]};$('graph').setPointerCapture(e.pointerId)}catch(error){status(error.message,true)}};
$('graph').onpointermove=e=>{if(S.drag?.kind==='graphLink'){drawGraph();const[x,y]=graphPoint(e),ids=Object.keys(S.story.nodes),link=S.drag.link,port=outputPorts(link.node,ids.indexOf(link.node)).find(p=>p.index===link.index),ctx=$('graph').getContext('2d');ctx.strokeStyle='#efc488';ctx.setLineDash([6,4]);ctx.beginPath();ctx.moveTo(port.x,port.y);ctx.lineTo(x,y);ctx.stroke();ctx.setLineDash([])}if(S.drag?.kind==='node'){const[x,y]=graphPoint(e);S.story.nodes[S.drag.id].editor_position=[Math.max(0,Math.min(755,x-S.drag.offset[0])),Math.max(0,y-S.drag.offset[1])];drawGraph();dirty()}};
$('graph').onpointerup=e=>{if(S.drag?.kind==='graphLink'){const[x,y]=graphPoint(e);linkTurn(S.drag.link,graphNodeAt(x,y))}S.drag=null};$('graph').onpointercancel=()=>S.drag=null;
$('graph').ondragover=e=>e.preventDefault();$('graph').ondrop=e=>{e.preventDefault();try{readNode();const[x,y]=graphPoint(e);linkTurn(JSON.parse(e.dataTransfer.getData('application/x-metro-link')),graphNodeAt(x,y))}catch(error){status(error.message,true)}};
$('autoLayout').onclick=()=>{Object.values(S.story.nodes).forEach(n=>delete n.editor_position);drawGraph();dirty()};
// Create unique encounter IDs and select encounters from the retained event-line canvas.
$('newStory').onclick=run(()=>{readStory();let index=1;while(S.customer.stories.some(s=>s.id===`meeting_${index}`))index++;S.customer.stories.push({id:`meeting_${index}`,name:'新的见面',kind:'meeting',priority:10,once:true,contexts:['trade'],conditions:{},start:'start',nodes:{start:{speaker:S.customer.name,text:'你好。',choices:[]}}});showStories(S.customer.stories.length-1);dirty()});
$('newStory').textContent='＋ 新增见面对话';
for(const id of['nodeText','speaker'])$(id).addEventListener('change',()=>{readNode();renderChat();drawGraph();dirty()});
document.addEventListener('keydown',e=>{if(e.key==='Escape'){W.tool=null;W.pendingLink=null;updateLinkHint();renderPalette();drawMap()}if(e.key==='Delete'&&!e.target.closest('input,textarea,[contenteditable=true]')&&!$('levelView').hidden)$('removeEntity').click()});
if(S.project){listCustomers();showCustomer(S.customer);if(S.level)showLevel(S.level);renderStationMap()}

const deleteTurn=$('deleteNode').onclick;$('deleteNode').onclick=()=>{deleteTurn();W.pendingLink=null;W.chat=[{node:S.story.start}];renderChat();dirty()};

const editorHeader=document.querySelector('header');
function sizeHeader(){document.documentElement.style.setProperty('--editor-header-height',editorHeader.offsetHeight+'px')}
new ResizeObserver(sizeHeader).observe(editorHeader);sizeHeader();

const renameTurn=$('renameNode').onclick;$('renameNode').onclick=async()=>{await renameTurn();W.pendingLink=null;W.chat=[{node:S.story.start}];renderChat();dirty()};

const workspaceInspector=entityForm;entityForm=function(){workspaceInspector();for(const input of $('entityFields').querySelectorAll('input'))if(['collision','loot_points'].includes(input.dataset.key))input.closest('label').remove();const selected=Boolean(S.level?.[S.type]?.[S.entity]);$('removeEntity').disabled=!selected;$('applyEntity').disabled=!selected};

function setStreetStart(row,value,snapshot=true){
  if(snapshot)checkpoint();const grid=$('snap').checked?(+$('gridSize').value||20):1,start=Math.max(0,Math.min(8000,Math.round(value/grid)*grid)),delta=start-rowStart(row);
  S.level.street_starts[row]=start;
  for(const type of entityTypes)if(type!=='junctions')for(const e of S.level[type])if(e.row===row)e.x+=delta;
  repairJunctions();selectCell(row,W.col);drawMap();entityForm();dirty();
}
$('streetStart').onchange=()=>setStreetStart(W.row,+$('streetStart').value);
$('startEarlier').onclick=()=>setStreetStart(W.row,rowStart(W.row)-(+$('gridSize').value||20));
$('startLater').onclick=()=>setStreetStart(W.row,rowStart(W.row)+(+$('gridSize').value||20));
