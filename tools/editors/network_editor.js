'use strict';
// Same document and coordinate system are consumed by Godot's NetworkCatalog.
const N={data:null,revision:null,layer:'lines',tool:'select',line:0,selection:null,history:[],grid:false,snap:false,gridSize:20,dirty:false,box:null,svg:null,drag:null};
const beforeNetworkView=view;view=function(id){beforeNetworkView(id);$('networkView').hidden=id!=='networkView'};
const beforeNetworkSave=$('saveAll').onclick;$('saveAll').onclick=()=>{if(!$('networkView').hidden)$('networkSave').click();else beforeNetworkSave()};
function networkChanged(){N.dirty=true;dirty();$('networkState').textContent='● 地图尚未保存'}
function networkCheckpoint(){N.history.push({data:clone(N.data),line:N.line,selection:clone(N.selection)});if(N.history.length>40)N.history.shift()}
function networkPoint(point){return typeof point==='string'?N.data.stations[point].position:point}
function networkSelected(){const s=N.selection;if(!s)return null;if(s.kind==='texture')return N.data.textures[s.index];if(s.kind==='station')return N.data.stations[s.name];if(s.kind==='point'){const p=N.data.lines[s.line]?.[2][s.index];return typeof p==='string'?N.data.stations[p]:p}return null}
async function loadNetwork(){const result=await api('/api/network-map');N.data=result.definition;N.revision=result.revision;N.line=0;N.selection=null;N.history=[];N.dirty=false;networkFit();renderNetwork();$('networkState').textContent='已读取已保存地图'}
$('networkTab').onclick=run(async()=>{view('networkView');if(!N.data)await loadNetwork();else renderNetwork()});
function networkFit(){if(!N.data)return;N.box={x:-30,y:-30,w:N.data.canvas.width+60,h:N.data.canvas.height+60};if(N.svg)N.svg.setAttribute('viewBox',`${N.box.x} ${N.box.y} ${N.box.w} ${N.box.h}`)}
function networkZoom(scale){const w=Math.max(100,Math.min(16000,N.box.w*scale)),ratio=w/N.box.w;N.box.x+=(N.box.w-w)/2;N.box.y+=N.box.h*(1-ratio)/2;N.box.w=w;N.box.h*=ratio;N.svg.setAttribute('viewBox',`${N.box.x} ${N.box.y} ${N.box.w} ${N.box.h}`)}
function networkAt(e){const p=N.svg.createSVGPoint();p.x=e.clientX;p.y=e.clientY;const local=p.matrixTransform(N.svg.getScreenCTM().inverse());return [Math.round(local.x),Math.round(local.y)]}
function snapNetwork(p){return N.layer==='lines'&&N.snap?p.map(v=>Math.round(v/N.gridSize)*N.gridSize):p}
function clampNetwork(p){return [Math.max(0,Math.min(8000,p[0])),Math.max(0,Math.min(8000,p[1]))]}
function networkSVG(tag,attrs={}){return svgElement(tag,attrs)}
function networkTool(tool){N.tool=tool;for(const[id,value]of Object.entries({networkSelect:'select',networkAppend:'append',networkInsert:'insert',networkStation:'station'}))$(id).classList.toggle('selected',tool===value)}
function networkSetLayer(layer){N.layer=layer;N.selection=null;networkTool('select');renderNetwork()}
$('networkLines').onclick=()=>networkSetLayer('lines');$('networkTextures').onclick=()=>networkSetLayer('textures');
for(const[id,tool]of Object.entries({networkSelect:'select',networkAppend:'append',networkInsert:'insert',networkStation:'station'}))$(id).onclick=()=>networkTool(tool);
function renderNetwork(){
 if(!N.data)return;
 $('networkLines').classList.toggle('selected',N.layer==='lines');$('networkTextures').classList.toggle('selected',N.layer==='textures');$('networkUploadBar').hidden=N.layer!=='textures';
 $('networkHint').textContent=N.layer==='lines'?'拖动站点或折点调整位置。插入折点后点击线段；追加结点时点击已有站点可接入当前线路。':'拖动素材移动，拖右下方方块缩放；侧栏可调整角度、透明度及显示状态。线路层保持可见供对齐。';
 for(const id of ['networkAppend','networkInsert','networkStation','networkNewLine','networkRemoveLine'])$(id).disabled=N.layer!=='lines';
 $('networkWidth').value=N.data.canvas.width;$('networkHeight').value=N.data.canvas.height;
 const palette=$('networkPalette');palette.replaceChildren();
 if(N.layer==='lines')N.data.lines.forEach((line,i)=>{const b=button(`${line[0]}号线 · ${line[2].length}结点`,()=>{N.line=i;N.selection=null;renderNetwork()},N.line===i?'selected':'');b.style.setProperty('--line-color','#'+line[1]);b.dataset.networkLine=i;palette.append(b)});
 else {N.data.textures.forEach((asset,i)=>{const b=button(asset.id,()=>{N.selection={kind:'texture',index:i};renderNetwork()},N.selection?.index===i?'selected':'');b.dataset.networkTexture=i;const img=document.createElement('img');img.src='/asset?path='+encodeURIComponent(asset.texture);b.prepend(img);palette.append(b)});palette.append(button('＋ 从现有素材添加',()=>{const cards=document.createElement('div');cards.className='object-palette';for(const art of S.project.art){const card=button(art.id,()=>{networkAddTexture(art.texture,[96,96]);cards.remove()});const img=document.createElement('img');img.src='/asset?path='+encodeURIComponent(art.texture);card.prepend(img);cards.append(card)}palette.append(cards)}))}
 renderNetworkInspector();renderNetworkCanvas();
}
function networkField(box,label,value,change,type='number'){const wrap=document.createElement('label');wrap.textContent=label;const input=document.createElement('input');input.type=type;input.value=value;if(type==='checkbox')input.checked=value;input.dataset.networkField=label;input.onchange=run(()=>{networkCheckpoint();change(type==='checkbox'?input.checked:type==='number'?+input.value:input.value);networkChanged();renderNetwork()});wrap.append(input);box.append(wrap);return input}
function renderNetworkInspector(){
 const box=$('networkInspector');box.replaceChildren();const line=N.data.lines[N.line];
 if(N.layer==='lines'&&line){networkField(box,'线路编号',line[0],v=>line[0]=v);networkField(box,'线路颜色','#'+line[1],v=>line[1]=v.slice(1),'color')}
 const s=N.selection;if(!s)return;
 if(s.kind==='texture'){
  const image=networkSelected();for(const[key,label]of [['position','位置'],['size','尺寸']])for(const[i,axis]of ['X','Y'].entries())networkField(box,label+axis,image[key][i],v=>image[key][i]=v);
  networkField(box,'旋转角度',image.rotation||0,v=>image.rotation=v);networkField(box,'透明度',image.opacity??1,v=>image.opacity=v);networkField(box,'显示贴图',image.visible!==false,v=>image.visible=v,'checkbox');return;
 }
 const point=s.kind==='station'?s.name:N.data.lines[s.line][2][s.index],name=typeof point==='string'?point:null;
 const position=networkPoint(point);for(const[i,axis]of ['X','Y'].entries())networkField(box,'结点'+axis,position[i],v=>position[i]=v);
 if(name){const input=networkField(box,'站名',name,v=>{if(!v||N.data.stations[v])throw Error('站名不能为空或重复');N.data.stations[v]=N.data.stations[name];delete N.data.stations[name];for(const route of N.data.lines)route[2]=route[2].map(p=>p===name?v:p);s.name=v},'text');input.readOnly=S.project.stations.includes(name);for(const[i,axis]of ['X','Y'].entries())networkField(box,'站名偏移'+axis,N.data.stations[name].label[i],v=>N.data.stations[name].label[i]=v)}
}
function renderNetworkCanvas(detached=false){
 const svg=networkSVG('svg',{viewBox:`${N.box.x} ${N.box.y} ${N.box.w} ${N.box.h}`,'aria-label':'地图双层编辑画布',tabindex:0});if(!detached)N.svg=svg;
 svg.append(networkSVG('rect',{x:0,y:0,width:N.data.canvas.width,height:N.data.canvas.height,fill:'#faf9f3',stroke:'#9b93a4','stroke-width':2}));
 N.data.textures.forEach((image,index)=>{if(image.visible===false)return;const [x,y]=image.position,[w,h]=image.size,g=networkSVG('g',{transform:`translate(${x},${y}) rotate(${image.rotation||0})`,'data-network-texture':index,opacity:image.opacity??1});g.append(networkSVG('image',{href:'/asset?path='+encodeURIComponent(image.texture),width:w,height:h,preserveAspectRatio:'none'}));if(N.layer==='textures'&&N.selection?.kind==='texture'&&N.selection.index===index){g.append(networkSVG('rect',{width:w,height:h,fill:'none',stroke:'#5b3d98','stroke-width':3}));g.append(networkSVG('rect',{x:w-9,y:h-9,width:18,height:18,fill:'#5b3d98','data-network-resize':index}))}if(N.layer!=='textures')g.style.pointerEvents='none';svg.append(g)});
 if(N.layer==='lines'&&N.grid){const defs=networkSVG('defs'),pattern=networkSVG('pattern',{id:'metro-line-grid',width:N.gridSize,height:N.gridSize,patternUnits:'userSpaceOnUse'});pattern.append(networkSVG('path',{d:`M ${N.gridSize} 0 H 0 V ${N.gridSize}`,fill:'none',stroke:'#81758e','stroke-opacity':.45,'stroke-width':1}));defs.append(pattern);svg.append(defs,networkSVG('rect',{width:N.data.canvas.width,height:N.data.canvas.height,fill:'url(#metro-line-grid)','pointer-events':'none','data-line-grid':'true'}))}
 N.data.lines.forEach((line,li)=>{
  const points=line[2].map(networkPoint);const g=networkSVG('g',{opacity:N.layer==='textures'?.45:1});g.append(networkSVG('polyline',{points:points.map(p=>p.join(',')).join(' '),fill:'none',stroke:'#'+line[1],'stroke-width':li===N.line?8:5,'stroke-linejoin':'round'}));
  if(N.layer==='lines')for(let i=0;i<points.length-1;i++)g.append(networkSVG('line',{x1:points[i][0],y1:points[i][1],x2:points[i+1][0],y2:points[i+1][1],stroke:'transparent','stroke-width':20,'data-network-segment':i,'data-network-line':li,class:'network-segment'}));
  if(N.layer==='lines'&&li===N.line)points.forEach((p,index)=>{if(typeof line[2][index]==='string')return;g.append(networkSVG('circle',{cx:p[0],cy:p[1],r:7,fill:N.selection?.kind==='point'&&N.selection.index===index?'#f0cc91':'#fff',stroke:'#'+line[1],'stroke-width':3,'data-network-point':index,'data-network-line':li,class:'network-node'}))});svg.append(g);
 });
 for(const[name,station]of Object.entries(N.data.stations)){const [x,y]=station.position,g=networkSVG('g',{'data-network-station':name,class:'network-node'});g.append(networkSVG('circle',{cx:x,cy:y,r:8,fill:N.selection?.name===name?'#f0cc91':'#fff',stroke:'#292a36','stroke-width':3}));const label=networkSVG('text',{x:x+station.label[0],y:y+station.label[1]+12,fill:'#292a36','font-size':14,'paint-order':'stroke',stroke:'#faf9f3','stroke-width':3});label.textContent=name;g.append(label);if(N.layer!=='lines')g.style.pointerEvents='none';svg.append(g)}
 if(detached)return svg;
 $('networkCanvas').replaceChildren(svg);svg.onpointerdown=networkDown;svg.onpointermove=networkMove;svg.onpointerup=networkUp;svg.onpointercancel=()=>N.drag=null;svg.oncontextmenu=e=>e.preventDefault();svg.onwheel=e=>{e.preventDefault();networkZoom(e.deltaY<0?.85:1.18)};svg.onkeydown=e=>{if(e.key==='Delete'){e.preventDefault();networkDelete()}};
}
function networkDown(e){
 N.svg.focus();
 if(e.button===1||e.button===2){e.preventDefault();N.drag={kind:'pan',at:networkAt(e),inverse:N.svg.getScreenCTM().inverse(),box:{...N.box}};N.svg.setPointerCapture(e.pointerId);return}if(e.button!==0)return;
 const rawAt=clampNetwork(networkAt(e)),at=clampNetwork(snapNetwork(rawAt)),station=e.target.closest('[data-network-station]')?.dataset.networkStation,point=e.target.closest('[data-network-point]'),segment=e.target.closest('[data-network-segment]'),image=e.target.closest('[data-network-texture]');
 if(N.layer==='lines'){
  if(N.tool==='station'){networkCheckpoint();let i=1;while(N.data.stations['新站'+i])i++;const name='新站'+i;N.data.stations[name]={position:at,label:[10,-20]};if(N.data.lines[N.line])N.data.lines[N.line][2].push(name);N.selection={kind:'station',name};networkChanged();renderNetwork();return}
  if(N.tool==='append'){if(!N.data.lines[N.line]){status('请先新增或选择线路',true);return}networkCheckpoint();N.data.lines[N.line][2].push(station||at);N.selection={kind:'point',line:N.line,index:N.data.lines[N.line][2].length-1};networkChanged();renderNetwork();return}
  if(N.tool==='insert'&&segment){networkCheckpoint();N.line=+segment.dataset.networkLine;const index=+segment.dataset.networkSegment+1;N.data.lines[N.line][2].splice(index,0,at);N.selection={kind:'point',line:N.line,index};networkChanged();renderNetwork();return}
  if(station){const index=N.data.lines[N.line]?.[2].indexOf(station)??-1;N.selection=index>=0?{kind:'point',line:N.line,index}:{kind:'station',name:station};N.selection.name=station}
  else if(point){N.line=+point.dataset.networkLine;N.selection={kind:'point',line:N.line,index:+point.dataset.networkPoint}}
  else if(segment){N.line=+segment.dataset.networkLine;N.selection=null;renderNetwork();return}else{N.selection=null;renderNetwork();return}
 }else{if(!image){N.selection=null;renderNetwork();return}N.selection={kind:'texture',index:+image.dataset.networkTexture}}
 const selected=networkSelected();const start=N.layer==='textures'?selected.position:('position'in selected?selected.position:selected);N.drag={kind:e.target.hasAttribute('data-network-resize')?'resize':'move',at:rawAt,checkpoint:false,start:[...start],size:selected.size?[...selected.size]:null};renderNetworkInspector();N.svg.setPointerCapture(e.pointerId);
}
function networkMove(e){
 const d=N.drag;if(!d)return;let at=networkAt(e);
 if(d.kind==='pan'){const p=N.svg.createSVGPoint();p.x=e.clientX;p.y=e.clientY;const fixed=p.matrixTransform(d.inverse);at=[fixed.x,fixed.y]}
 if(d.kind==='pan'){N.box.x=d.box.x-(at[0]-d.at[0]);N.box.y=d.box.y-(at[1]-d.at[1]);N.svg.setAttribute('viewBox',`${N.box.x} ${N.box.y} ${N.box.w} ${N.box.h}`);return}
 const selected=networkSelected(),dx=at[0]-d.at[0],dy=at[1]-d.at[1];if(!dx&&!dy)return;if(!d.checkpoint){networkCheckpoint();d.checkpoint=true}
 if(d.kind==='resize'){const angle=-(selected.rotation||0)*Math.PI/180;selected.size=[Math.max(1,Math.min(8000,Math.round(d.size[0]+dx*Math.cos(angle)-dy*Math.sin(angle)))),Math.max(1,Math.min(8000,Math.round(d.size[1]+dx*Math.sin(angle)+dy*Math.cos(angle))))]}
 else{const next=N.layer==='textures'?[Math.max(-8000,Math.min(8000,d.start[0]+dx)),Math.max(-8000,Math.min(8000,d.start[1]+dy))]:clampNetwork(snapNetwork([d.start[0]+dx,d.start[1]+dy]));if(Array.isArray(selected)){selected[0]=next[0];selected[1]=next[1]}else selected.position=next}
 networkChanged(); // Keep the capture-owning SVG alive; update its visual children only.
 const fresh=renderNetworkCanvas(true);N.svg.replaceChildren(...fresh.childNodes);renderNetworkInspector();
}
function networkUp(){if(!N.drag)return;N.drag=null;renderNetwork()}
function networkDelete(){if(!N.selection)return;networkCheckpoint();const s=N.selection;if(s.kind==='texture')N.data.textures.splice(s.index,1);else if(s.kind==='point')N.data.lines[s.line][2].splice(s.index,1);else{if(S.project.stations.includes(s.name)){status('已有游戏站点需保留，可选中它在线路上的节点移除连接。',true);N.history.pop();return}delete N.data.stations[s.name];for(const line of N.data.lines)line[2]=line[2].filter(p=>p!==s.name)}N.selection=null;networkChanged();renderNetwork()}
function networkUndo(){if(!N.history.length)return;N.drag=null;const previous=N.history.pop();N.data=previous.data;N.selection=previous.selection;N.line=previous.line;networkChanged();renderNetwork()}
$('networkDelete').onclick=networkDelete;$('networkUndo').onclick=networkUndo;
$('networkNewLine').onclick=()=>{networkCheckpoint();let number=1;while(N.data.lines.some(l=>l[0]===number))number++;N.data.lines.push([number,'7a62a3',[]]);N.line=N.data.lines.length-1;N.selection=null;networkTool('append');networkChanged();renderNetwork()};
$('networkRemoveLine').onclick=()=>{if(!N.data.lines[N.line])return;networkCheckpoint();N.data.lines.splice(N.line,1);N.line=Math.max(0,N.line-1);N.selection=null;networkChanged();renderNetwork()};
function networkAddTexture(path,size){networkCheckpoint();N.data.textures.push({id:'map_'+Date.now().toString(36),texture:path,position:[80,80],size,rotation:0,opacity:1,visible:true});N.selection={kind:'texture',index:N.data.textures.length-1};networkChanged();renderNetwork()}
$('networkImport').onclick=run(async()=>{const file=$('networkUpload').files[0];if(!file)throw Error('请选择PNG地图素材');const data=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(file)});const result=await api('/api/network-image',{id:'map_'+Date.now().toString(36),data});networkAddTexture(result.texture,result.size)});
function networkReorder(delta){if(N.selection?.kind!=='texture')return;const from=N.selection.index,to=from+delta;if(to<0||to>=N.data.textures.length)return;networkCheckpoint();const image=N.data.textures.splice(from,1)[0];N.data.textures.splice(to,0,image);N.selection.index=to;networkChanged();renderNetwork()}
$('networkRaise').onclick=()=>networkReorder(1);$('networkLower').onclick=()=>networkReorder(-1);
$('networkSave').onclick=run(async()=>{const result=await api('/api/network-map',{definition:N.data,revision:N.revision});N.revision=result.revision;N.dirty=false;S.project=await api('/api/project');$('stations').replaceChildren();for(const station of S.project.stations)option($('stations'),station,station);$('stations').value=S.station;updateStationBanner();$('dirty').textContent='✓ 已保存';$('networkState').textContent='✓ 地图已保存，Godot 重新打开线路图时读取';status('线路与贴图已保存，游戏路径计算使用更新后的连接。')});
$('networkReload').onclick=run(async()=>{if(N.dirty&&!confirm('放弃当前未保存的地图修改并重新读取？'))return;await loadNetwork()});
for(const[key,id]of Object.entries({width:'networkWidth',height:'networkHeight'}))$(id).onchange=()=>{networkCheckpoint();N.data.canvas[key]=+$(id).value;networkChanged();networkFit();renderNetwork()};
$('networkZoomIn').onclick=()=>networkZoom(.8);$('networkZoomOut').onclick=()=>networkZoom(1.25);$('networkFit').onclick=()=>{networkFit();renderNetworkCanvas()};

window.addEventListener("beforeunload",e=>{if(N.dirty){e.preventDefault();e.returnValue=""}});

// Page-level shortcuts survive SVG replacement and toolbar focus; text keeps native undo.
document.addEventListener('keydown',e=>{if($('networkView').hidden||e.target.closest('input,textarea,select,[contenteditable=true]'))return;if((e.ctrlKey||e.metaKey)&&!e.shiftKey&&e.key.toLowerCase()==='z'){e.preventDefault();networkUndo()}});
for(const[id,key]of [['networkGrid','grid'],['networkSnap','snap']])$(id).onchange=()=>{N[key]=$(id).checked;renderNetworkCanvas()};
$('networkGridSize').onchange=()=>{N.gridSize=Math.max(2,Math.min(500,Math.round(+$('networkGridSize').value||20)));$('networkGridSize').value=N.gridSize;renderNetworkCanvas()};
