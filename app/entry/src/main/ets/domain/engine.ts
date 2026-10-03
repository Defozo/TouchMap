import { tr } from './i18n';
import { Action, ActionResult, Diagram, Progress, Question, Region } from './types';
import { reviewed, validateQuestion } from './validate';
export function initialProgress(d: Diagram): Progress {
  return { packageId:d.packageId, revision:d.revision, stateRevision:0, status:'not_started', paused:false, lastRegionId:'', activeRelationId:'', activeQuestionId:'', selectedAnswers:[], submissions:[], viewport:{scale:1,offsetX:0,offsetY:0,rotation:0}, bookmarks:[], appliedEvents:[], updatedAt:0 };
}
export function orderedRegions(d: Diagram): Region[] { return d.regions.slice().sort((a,b)=>a.readingOrder-b.readingOrder||a.id.localeCompare(b.id)); }
function question(d:Diagram,id:string): Question { const q=d.questions.find(q=>q.id===id); if(!q)throw new Error(tr('tm_240aca2051bf')); return q; }
export function applyAction(d: Diagram, p: Progress, a: Action): ActionResult {
  if(p.packageId!==d.packageId||p.revision!==d.revision) throw new Error(tr('tm_fa7c5679324a'));
  if(!a.eventId || a.eventId.length>128) throw new Error(tr('tm_19e7a3976a86'));
  if(p.appliedEvents.includes(a.eventId)) return {state:p,feedback:tr('tm_748a428fafd8'),duplicate:true};
  if(a.expectedRevision!==p.stateRevision) throw new Error(tr('tm_121b587441f6'));
  const state:Progress=JSON.parse(JSON.stringify(p));
  let feedback='',correct:boolean|undefined;
  const target=a.targetId||'';
  const focus=(id:string):void=>{ const r=d.regions.find(r=>r.id===id);if(!r)throw new Error(tr('tm_5a2a7c0c7067'));state.lastRegionId=id; if(state.status==='not_started')state.status='exploring'; feedback=r.label; };
  switch(a.type) {
    case 'focusRegion': focus(target); break;
    case 'nextRegion': case 'previousRegion': {
      const regions=orderedRegions(d);if(!regions.length)throw new Error(tr('tm_d5ff31d5eead'));const index=regions.findIndex(r=>r.id===state.lastRegionId);
      const next=index<0?0:(index+(a.type==='nextRegion'?1:-1)+regions.length)%regions.length;focus(regions[next].id);break;
    }
    case 'selectRelation': {
      const r=d.relations.find(r=>r.id===target);if(!r)throw new Error(tr('tm_53a3b0b0d31c'));state.activeRelationId=r.id;
      feedback=tr('tm_3f4f403ebf04', [String(r.label), String(r.path ? tr('tm_f02ab8e9ae41') : tr('tm_899c2327ecbb'))]);break;
    }
    case 'followRelation': {
      const r=d.relations.find(r=>r.id===(target||state.activeRelationId));if(!r)throw new Error(tr('tm_4bdc35de4949'));
      if(r.direction==='unknown')throw new Error(tr('tm_dec2840d4a5b'));
      const destination=r.direction==='both'&&state.lastRegionId===r.toId?r.fromId:r.toId;focus(destination);state.activeRelationId=r.id;feedback=tr('tm_1bbbe18c538c', [String(r.label), String(feedback), String(r.path ? '' : tr('tm_30c9ebecc748'))]);break;
    }
    case 'describe': {const r=d.regions.find(r=>r.id===(target||state.lastRegionId));if(!r)throw new Error(tr('tm_b33dcbb92fb0'));feedback=r.description || r.label;break;}
    case 'openQuestion': {
      const q=question(d,target);const issues=validateQuestion(d,q);if(!reviewed(q.review)||issues.length)throw new Error(tr('tm_46abf34c16b1'));
      if (state.activeQuestionId !== q.id || state.status !== 'answering') state.selectedAnswers=[];
      state.activeQuestionId=q.id;state.status='answering';feedback=q.prompt;break;
    }
    case 'selectAnswer': {
      const q=question(d,state.activeQuestionId);const answers=a.answerIds||[target];
      if(new Set(answers).size!==answers.length||answers.some(id=>!q.options.some(o=>o.id===id)))throw new Error(tr('tm_7e0db4f03cfc'));
      state.selectedAnswers=answers.slice();state.status='answering';feedback=answers.length ? tr('tm_d9f739c6a31c') : tr('tm_3239e788923d');break;
    }
    case 'submitAnswer': {
      const q=question(d,state.activeQuestionId);if(validateQuestion(d,q).length||!reviewed(q.review))throw new Error(tr('tm_d65d2f43e0cd'));
      if(state.status!=='answering'||!state.selectedAnswers.length)throw new Error(tr('tm_9feaddf0ded0'));
      correct=q.type==='sequence'?state.selectedAnswers.join('\0')===q.acceptedAnswers.join('\0'):state.selectedAnswers.slice().sort().join('\0')===q.acceptedAnswers.slice().sort().join('\0');
      state.submissions.push({questionId:q.id,answers:state.selectedAnswers.slice(),correct,eventId:a.eventId,timestamp:a.timestamp||Date.now()});state.status='submitted';feedback=tr('tm_10866a9df5f8', [String(correct ? tr('tm_f6c1472e9afb') : tr('tm_1ce6da8dbe41')), String(q.explanation)]);break;
    }
    case 'pause':state.paused=true;feedback=state.status==='answering' ? tr('tm_976524a24341') : tr('tm_13d802933193');break;
    case 'resume':state.paused=false;feedback=resumeContext(d,state);break;
    case 'back':state.activeRelationId='';feedback=tr('tm_33cba843f9c6');break;
    case 'viewport':if(!a.viewport||a.viewport.scale<0.1||a.viewport.scale>8||![a.viewport.scale,a.viewport.offsetX,a.viewport.offsetY,a.viewport.rotation].every(Number.isFinite))throw new Error(tr('tm_d254d4785d5b'));else state.viewport=a.viewport;feedback=tr('tm_a48f13f6ef84');break;
    case 'bookmark':if(!d.regions.some(r=>r.id===target))throw new Error(tr('tm_13fcc156b6de'));else {const i=state.bookmarks.indexOf(target);if(i>=0)state.bookmarks.splice(i,1);else state.bookmarks.push(target);feedback=i>=0 ? tr('tm_9c9fc0c81045') : tr('tm_8295d8d1d05c');}break;
    case 'startAgain':{ const fresh=initialProgress(d);fresh.stateRevision=state.stateRevision;fresh.appliedEvents=state.appliedEvents;fresh.bookmarks=state.bookmarks;fresh.submissions=state.submissions;fresh.updatedAt=state.updatedAt;return finish(fresh,a,tr('tm_c15c014fa0f3')); }
    default:throw new Error(tr('tm_544ff00ac6df', [String(a.type)]));
  }
  return finish(state,a,feedback,correct);
}
function finish(state:Progress,a:Action,feedback:string,correct?:boolean):ActionResult {
  state.stateRevision++;state.appliedEvents.push(a.eventId);state.updatedAt=a.timestamp||Date.now();
  return {state,feedback,correct,duplicate:false};
}
export function resumeContext(d:Diagram,p:Progress):string {
  const region=d.regions.find(r=>r.id===p.lastRegionId),last=p.submissions[p.submissions.length-1];
  let text=region ? tr('tm_c6391baafa4e', [String(region.label)]) : tr('tm_0d3c8a892f75');
  if(last){const q=d.questions.find(q=>q.id===last.questionId);text+=tr('tm_366734abe864', [String(q ? q.prompt : last.questionId), String(last.correct ? tr('tm_f6c1472e9afb') : tr('tm_1c704bbd5483'))]);}
  if(p.status==='answering'&&p.activeQuestionId)text+=tr('tm_37bffddd8dfc', [String(question(d,p.activeQuestionId).prompt), String(p.selectedAnswers.length ? tr('tm_b7754e14b7da') : tr('tm_9067d3d7df54'))]);
  return text.trim();
}
