import { Action, ActionResult, Diagram, Progress, Question, Region } from './types';
import { reviewed, validateQuestion } from './validate';
export function initialProgress(d: Diagram): Progress {
  return { packageId:d.packageId, revision:d.revision, stateRevision:0, status:'not_started', paused:false, lastRegionId:'', activeRelationId:'', activeQuestionId:'', selectedAnswers:[], submissions:[], viewport:{scale:1,offsetX:0,offsetY:0,rotation:0}, bookmarks:[], appliedEvents:[], updatedAt:0 };
}
export function orderedRegions(d: Diagram): Region[] { return d.regions.slice().sort((a,b)=>a.readingOrder-b.readingOrder||a.id.localeCompare(b.id)); }
function question(d:Diagram,id:string): Question { const q=d.questions.find(q=>q.id===id); if(!q)throw new Error('Question does not exist'); return q; }
export function applyAction(d: Diagram, p: Progress, a: Action): ActionResult {
  if(p.packageId!==d.packageId||p.revision!==d.revision) throw new Error('Content revision changed. Accept it explicitly before starting a new attempt.');
  if(!a.eventId || a.eventId.length>128) throw new Error('A bounded event ID is required');
  if(p.appliedEvents.includes(a.eventId)) return {state:p,feedback:'Already saved',duplicate:true};
  if(a.expectedRevision!==p.stateRevision) throw new Error('Progress changed. Reload before applying this action.');
  const state:Progress=JSON.parse(JSON.stringify(p));
  let feedback='',correct:boolean|undefined;
  const target=a.targetId||'';
  const focus=(id:string):void=>{ const r=d.regions.find(r=>r.id===id);if(!r)throw new Error('Region does not exist');state.lastRegionId=id; if(state.status==='not_started')state.status='exploring'; feedback=r.label; };
  switch(a.type) {
    case 'focusRegion': focus(target); break;
    case 'nextRegion': case 'previousRegion': {
      const regions=orderedRegions(d);if(!regions.length)throw new Error('No regions to explore');const index=regions.findIndex(r=>r.id===state.lastRegionId);
      const next=index<0?0:(index+(a.type==='nextRegion'?1:-1)+regions.length)%regions.length;focus(regions[next].id);break;
    }
    case 'selectRelation': {
      const r=d.relations.find(r=>r.id===target);if(!r)throw new Error('Connection does not exist');state.activeRelationId=r.id;
      feedback=`${r.label}. ${r.path?'Follow the displayed path.':'Route in the picture is unspecified.'}`;break;
    }
    case 'followRelation': {
      const r=d.relations.find(r=>r.id===(target||state.activeRelationId));if(!r)throw new Error('Choose a connection first');
      if(r.direction==='unknown')throw new Error('Connection direction is unknown');
      const destination=r.direction==='both'&&state.lastRegionId===r.toId?r.fromId:r.toId;focus(destination);state.activeRelationId=r.id;feedback=`${r.label}. ${feedback}${r.path?'':'. Route in the picture is unspecified.'}`;break;
    }
    case 'describe': {const r=d.regions.find(r=>r.id===(target||state.lastRegionId));if(!r)throw new Error('Choose an object first');feedback=r.description||r.label;break;}
    case 'openQuestion': {
      const q=question(d,target);const issues=validateQuestion(d,q);if(!reviewed(q.review)||issues.length)throw new Error('This question requires review on the current material revision');
      if (state.activeQuestionId !== q.id || state.status !== 'answering') state.selectedAnswers=[];
      state.activeQuestionId=q.id;state.status='answering';feedback=q.prompt;break;
    }
    case 'selectAnswer': {
      const q=question(d,state.activeQuestionId);const answers=a.answerIds||[target];
      if(new Set(answers).size!==answers.length||answers.some(id=>!q.options.some(o=>o.id===id)))throw new Error('Choose valid answer options');
      state.selectedAnswers=answers.slice();state.status='answering';feedback=answers.length?'Answer selected. Submit when you are ready.':'Selection cleared. Choose an answer when ready.';break;
    }
    case 'submitAnswer': {
      const q=question(d,state.activeQuestionId);if(validateQuestion(d,q).length||!reviewed(q.review))throw new Error('Question no longer matches reviewed facts');
      if(state.status!=='answering'||!state.selectedAnswers.length)throw new Error('Select an answer before submitting');
      correct=q.type==='sequence'?state.selectedAnswers.join('\0')===q.acceptedAnswers.join('\0'):state.selectedAnswers.slice().sort().join('\0')===q.acceptedAnswers.slice().sort().join('\0');
      state.submissions.push({questionId:q.id,answers:state.selectedAnswers.slice(),correct,eventId:a.eventId,timestamp:a.timestamp||Date.now()});state.status='submitted';feedback=`${correct?'Correct.':'Try exploring this relationship again.'} ${q.explanation}`;break;
    }
    case 'pause':state.paused=true;feedback=state.status==='answering'?'Progress saved. Your unfinished answer has not been submitted.':'Progress saved.';break;
    case 'resume':state.paused=false;feedback=resumeContext(d,state);break;
    case 'back':state.activeRelationId='';feedback='Exploration stopped.';break;
    case 'viewport':if(!a.viewport||a.viewport.scale<0.1||a.viewport.scale>8||![a.viewport.scale,a.viewport.offsetX,a.viewport.offsetY,a.viewport.rotation].every(Number.isFinite))throw new Error('Invalid viewport');else state.viewport=a.viewport;feedback='View updated';break;
    case 'bookmark':if(!d.regions.some(r=>r.id===target))throw new Error('Bookmark target does not exist');else {const i=state.bookmarks.indexOf(target);if(i>=0)state.bookmarks.splice(i,1);else state.bookmarks.push(target);feedback=i>=0?'Bookmark removed':'Bookmark saved';}break;
    case 'startAgain':{ const fresh=initialProgress(d);fresh.stateRevision=state.stateRevision;fresh.appliedEvents=state.appliedEvents;fresh.bookmarks=state.bookmarks;fresh.submissions=state.submissions;fresh.updatedAt=state.updatedAt;return finish(fresh,a,'Started a new exploration. Previous submitted attempts remain in history.'); }
    default:throw new Error(`Unknown action: ${a.type}`);
  }
  return finish(state,a,feedback,correct);
}
function finish(state:Progress,a:Action,feedback:string,correct?:boolean):ActionResult {
  state.stateRevision++;state.appliedEvents.push(a.eventId);state.updatedAt=a.timestamp||Date.now();
  return {state,feedback,correct,duplicate:false};
}
export function resumeContext(d:Diagram,p:Progress):string {
  const region=d.regions.find(r=>r.id===p.lastRegionId),last=p.submissions[p.submissions.length-1];
  let text=region?`Last explored: ${region.label}. `:'Exploration has not started. ';
  if(last){const q=d.questions.find(q=>q.id===last.questionId);text+=`Last submitted question: ${q?q.prompt:last.questionId}. ${last.correct?'Correct.':'Review suggested.'} `;}
  if(p.status==='answering'&&p.activeQuestionId)text+=`Unfinished question: ${question(d,p.activeQuestionId).prompt}. ${p.selectedAnswers.length?'Your selection is saved but not submitted.':'No answer selected.'}`;
  return text.trim();
}
