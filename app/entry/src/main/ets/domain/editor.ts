import { tr } from './i18n';
import { Chart, Diagram, Question, Region, Relation, Review, Source } from './types';
import { publicationIssues } from './validate';
function clone(d:Diagram):Diagram {return JSON.parse(JSON.stringify(d));}
function pending(revision:number):Review{return {status:'needs_review',revision,reviewer:'',issues:[]};}
export class DraftEditor {
  private current:Diagram;
  private undoStack:Diagram[]=[];
  private redoStack:Diagram[]=[];
  constructor(diagram:Diagram){this.current=clone(diagram);}
  get diagram():Diagram{return clone(this.current);}
  get canUndo():boolean{return this.undoStack.length>0;}
  get canRedo():boolean{return this.redoStack.length>0;}
  clone():DraftEditor {
    const copy=new DraftEditor(this.current);
    copy.undoStack=this.undoStack.map(d=>clone(d));
    copy.redoStack=this.redoStack.map(d=>clone(d));
    return copy;
  }
  adoptSaved(diagram:Diagram):void {
    if(diagram.packageId!==this.current.packageId||diagram.source.sha256!==this.current.source.sha256)throw new Error(tr('tm_1a1efe142c95'));
    this.current=clone(diagram);
  }
  private edit(change:(d:Diagram)=>void,affected:string[],all:boolean=false):void {
    const next=clone(this.current);next.revision++;
    change(next);
    next.audio=next.audio.filter(a=>!all&&!affected.includes(a.targetId)&&a.targetId!==next.packageId);
    next.questions.forEach(q=>{
      q.requiredRevision=next.revision;
      if(all||q.factIds.some(id=>affected.includes(id))||affected.includes(q.id)){q.review=pending(next.revision);next.audio=next.audio.filter(a=>a.targetId!==q.id);}
      else q.review.revision=next.revision;
    });
    next.regions.forEach(r=>{if(!affected.includes(r.id)&&!all){r.geometryReview.revision=next.revision;r.meaningReview.revision=next.revision;}});
    next.relations.forEach(r=>{if(!affected.includes(r.id)&&!all)r.review.revision=next.revision;});
    next.charts.forEach(c=>{if(!affected.includes(c.id)&&!all)c.review.revision=next.revision;});
    this.undoStack.push(clone(this.current));if(this.undoStack.length>100)this.undoStack.shift();this.redoStack=[];this.current=next;
  }
  updateRegion(region:Region):void {
    if(!this.current.regions.some(r=>r.id===region.id))throw new Error(tr('tm_228572008a81'));
    const affected=[region.id,...this.current.relations.filter(r=>r.fromId===region.id||r.toId===region.id).map(r=>r.id)];
    this.edit(d=>{const r:Region=JSON.parse(JSON.stringify(region));r.geometryReview=pending(d.revision);r.meaningReview=pending(d.revision);d.regions=d.regions.map(x=>x.id===r.id?r:x);d.relations.forEach(x=>{if(affected.includes(x.id))x.review=pending(d.revision);});},affected);
  }
  addRegion(region:Region):void {if(this.current.regions.some(r=>r.id===region.id))throw new Error(tr('tm_943da120aeb5'));this.edit(d=>{const r:Region=JSON.parse(JSON.stringify(region));r.geometryReview=pending(d.revision);r.meaningReview=pending(d.revision);d.regions.push(r);},[region.id]);}
  removeRegion(id:string):void {
    const affected=[id,...this.current.relations.filter(r=>r.fromId===id||r.toId===id).map(r=>r.id)];
    this.edit(d=>{d.regions=d.regions.filter(r=>r.id!==id);d.relations=d.relations.filter(r=>!affected.includes(r.id));d.charts.forEach(c=>{c.series.forEach(s=>{const removed=s.values.filter(v=>v.regionId===id);removed.forEach(v=>affected.push(v.id));s.values=s.values.filter(v=>v.regionId!==id);});c.review=pending(d.revision);});},affected);
  }
  updateRelation(relation:Relation):void {this.edit(d=>{const r:Relation=JSON.parse(JSON.stringify(relation));r.review=pending(d.revision);const index=d.relations.findIndex(x=>x.id===r.id);if(index<0)d.relations.push(r);else d.relations[index]=r;},[relation.id]);}
  removeRelation(id:string):void{this.edit(d=>{d.relations=d.relations.filter(r=>r.id!==id);},[id]);}
  updateQuestion(question:Question):void{this.edit(d=>{const q:Question=JSON.parse(JSON.stringify(question));q.requiredRevision=d.revision;q.review=pending(d.revision);const index=d.questions.findIndex(x=>x.id===q.id);if(index<0)d.questions.push(q);else d.questions[index]=q;},[question.id]);}
  removeQuestion(id:string):void{this.edit(d=>{d.questions=d.questions.filter(q=>q.id!==id);},[id]);}
  updateChart(chart:Chart):void {
    const old=this.current.charts.find(c=>c.id===chart.id);const affected=[chart.id];if(old)old.series.forEach(s=>s.values.forEach(v=>affected.push(v.id)));chart.series.forEach(s=>s.values.forEach(v=>affected.push(v.id)));
    this.edit(d=>{const c:Chart=JSON.parse(JSON.stringify(chart));c.review=pending(d.revision);const i=d.charts.findIndex(x=>x.id===c.id);if(i<0)d.charts.push(c);else d.charts[i]=c;},affected);
  }
  removeChart(id:string):void {
    const chart=this.current.charts.find(c=>c.id===id);if(!chart)throw new Error(tr('tm_36a944022749'));
    const affected=[id];chart.series.forEach(s=>s.values.forEach(v=>affected.push(v.id)));
    this.edit(d=>{d.charts=d.charts.filter(c=>c.id!==id);},affected);
  }
  setTitle(title:string):void{this.edit(d=>{d.title=title;},[this.current.packageId]);}
  setDescription(description:string):void{this.edit(d=>{d.description=description;},[this.current.packageId]);}
  markReviewed(id:string,kind:string,reviewer:string):void {
    if(!reviewer.trim())throw new Error(tr('tm_054579dc9272'));
    const next=clone(this.current),review:Review={status:'reviewed',revision:next.revision,reviewer:reviewer.trim(),issues:[]};
    const region=next.regions.find(r=>r.id===id);
    if(region){if(kind==='geometry')region.geometryReview=review;else if(kind==='meaning')region.meaningReview=review;else throw new Error(tr('tm_63ea0d656839'));}
    else {const fact=next.relations.find(r=>r.id===id)||next.charts.find(c=>c.id===id)||next.questions.find(q=>q.id===id);if(!fact)throw new Error(tr('tm_4f7ef923b337'));fact.review=review;}
    this.undoStack.push(clone(this.current));this.redoStack=[];this.current=next;
  }
  publish(reviewer:string):Diagram {if(!reviewer.trim())throw new Error(tr('tm_fafddbe02e19'));const issues=publicationIssues(this.current);if(issues.length)throw new Error(issues.join('\n'));return clone(this.current);}
  replaceFromJob(result:Diagram,sourceHash:string,baseRevision:number):boolean {
    if(this.current.source.sha256!==sourceHash||this.current.revision!==baseRevision)return false;
    if(result.source.sha256!==sourceHash||result.packageId!==this.current.packageId)throw new Error(tr('tm_3df43576f612'));
    if(result.source.width!==this.current.source.width||result.source.height!==this.current.source.height)throw new Error(tr('tm_9e03c1a35893'));
    const source=JSON.parse(JSON.stringify(this.current.source)) as Source;
    if(result.source.previewPath&&result.source.previewSha256){source.previewPath=result.source.previewPath;source.previewSha256=result.source.previewSha256;}
    this.edit(d=>{d.source=source;d.regions=result.regions;d.relations=result.relations;d.charts=result.charts;d.questions=[];d.audio=[];d.regions.forEach(r=>{r.geometryReview=pending(d.revision);r.meaningReview=pending(d.revision);});d.relations.forEach(r=>r.review=pending(d.revision));d.charts.forEach(c=>c.review=pending(d.revision));},[],true);return true;
  }
  undo():boolean{const previous=this.undoStack.pop();if(!previous)return false;this.redoStack.push(clone(this.current));this.current=previous;return true;}
  redo():boolean{const next=this.redoStack.pop();if(!next)return false;this.undoStack.push(clone(this.current));this.current=next;return true;}
}
