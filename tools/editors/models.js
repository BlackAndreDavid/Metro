'use strict';
/** Reusable building definition. Instances own placement; templates are never mutated. */
class BuildingDefinition {
  constructor(data){this.data=structuredClone(data)}
  instantiate(level,row,x,snap=0){
    const data=structuredClone(this.data),limit=level.segment*level.cell_names[row].length;
    let serial=1;while(level.buildings.some(b=>b.id===`${data.id}_${serial}`))serial++;
    data.template_id=data.id;data.id=`${data.id}_${serial}`;data.row=row;
    data.width=Math.min(data.width,limit-48);data.x=Math.max(24,Math.min(limit-data.width,x));
    if(snap)data.x=Math.max(24,Math.min(limit-data.width,Math.round(data.x/snap)*snap));
    return data;
  }
  static move(level,building,row,x){
    const limit=level.segment*level.cell_names[row].length;
    if(building.width>limit-24)throw Error('该街道不足以容纳建筑，请缩小建筑或选择更长的街道');
    const oldX=building.x;building.x=Math.max(24,Math.min(limit-building.width,x));building.row=row;
    for(const loot of level.loot)if(loot.building===building.id){loot.x+=building.x-oldX;loot.row=row}
  }
}
/** One encounter contains a graph of NPC turns and player replies, not one sentence. */
class MeetingDialogue {
  constructor(story){this.story=story}
  node(id){return this.story.nodes[id]}
  createTurn(speaker,text='新的发言'){let index=1;while(this.story.nodes[`node_${index}`])index++;const id=`node_${index}`;this.story.nodes[id]={speaker,text,choices:[]};return id}
  appendSpeech(from,speaker){const previous=this.node(from);const id=this.createTurn(speaker);this.node(id).next=previous.next||'';this.node(id).choices=previous.choices||[];previous.choices=[];previous.next=id;return id}
  appendReply(from,speaker,text='新的回答'){const target=this.createTurn(speaker,'NPC 对这次回答的回应');this.node(from).choices??=[];this.node(from).choices.push({text,next:target,conditions:{},effects:{affection:0,trust:0}});return target}
  messages(id){const node=this.node(id);return (node.text||'').split('\n').filter(Boolean).map(text=>({speaker:node.speaker||'',text}))}
}
