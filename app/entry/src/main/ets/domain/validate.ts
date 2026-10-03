import { tr } from './i18n';
import { Diagram, Manifest, Question, Review } from './types';
import { diagramShape, manifestShape, portablePath, questionShape, reviewShape, validPolygon } from './validationShape';
export interface Readiness { ready: boolean; missing: string[] }
export function reviewed(r: Review, revision: number = 0): boolean { return reviewShape(r) && r.status === 'reviewed' && (revision === 0 || r.revision === revision); }
export function safePath(path: string): boolean {
  return portablePath(path);
}
export function validateManifest(m: Manifest): string[] {
  if(!manifestShape(m))return [tr('tm_1e621d6ef824')];
  const paths=m.assets.map(a=>a.path.toLowerCase());
  if(new Set(paths).size!==paths.length||paths.includes('manifest.json'))return [tr('tm_82ea0d40b405')];
  if(m.assets.reduce((sum,a)=>sum+a.bytes,0)>200*1024*1024)return [tr('tm_c67f2a65967e')];
  return [];
}
export function validateQuestion(d: Diagram, q: Question): string[] {
  if(!diagramShape(d)||!questionShape(q)) return [tr('tm_7792ab2f9b1f')];
  return questionIssues(d,q);
}
function questionIssues(d: Diagram, q: Question): string[] {
  const errors: string[] = [], options = q.options.map(o => o.id);
  if (!q.prompt.trim() || !q.explanation.trim() || !q.factIds.length) errors.push(tr('tm_95f2539f171d', [String(q.id)]));
  if (q.requiredRevision !== d.revision || q.review.revision !== d.revision) errors.push(tr('tm_df6246cbc9fb', [String(q.id)]));
  if(q.options.some(o=>!o.label.trim())) errors.push(tr('tm_6e83af23c6cd', [String(q.id)]));
  if (!q.acceptedAnswers.length || q.acceptedAnswers.some(a => !options.includes(a))) errors.push(tr('tm_1dbd8ae96c8e', [String(q.id)]));
  if (new Set(options).size !== options.length || options.length < 2) errors.push(tr('tm_a3b18785fa1c', [String(q.id)]));
  if (new Set(q.acceptedAnswers).size !== q.acceptedAnswers.length) errors.push(tr('tm_d8af9734eeca', [String(q.id)]));
  q.factIds.forEach(id => {
    const region = d.regions.find(r => r.id === id), relation = d.relations.find(r => r.id === id), chart = d.charts.find(c => c.id === id);
    let known = !!region || !!relation || !!chart;
    if (region && !reviewed(region.meaningReview,d.revision)) errors.push(tr('tm_f67b3ce7587c', [String(q.id)]));
    if (relation && (!reviewed(relation.review,d.revision) || (['direction','sequence'].includes(q.type) && relation.direction === 'unknown'))) errors.push(tr('tm_f9056c045106', [String(q.id)]));
    if (chart && !reviewed(chart.review,d.revision)) errors.push(tr('tm_7f8ba3046443', [String(q.id)]));
    for (const c of d.charts) for (const s of c.series) for (const v of s.values) if (v.id === id) {
      known = true;
      if (!reviewed(c.review,d.revision) || (['value','comparison'].includes(q.type) && v.value === null)) errors.push(tr('tm_f2f99863fcb8', [String(q.id)]));
    }
    if (!known) errors.push(tr('tm_9befa54b44f7', [String(q.id), String(id)]));
  });
  return errors;
}
export function validateDiagram(d: Diagram): string[] {
  if(!diagramShape(d)) return [tr('tm_8d7b76167ded')];
  const errors: string[] = [], ids = new Set<string>([d.packageId]);
  const id = (value: string): void => { if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/.test(value) || ids.has(value)) errors.push(tr('tm_78c1e0e0911e', [String(value)])); ids.add(value); };
  if (d.schemaVersion !== 1) errors.push(tr('tm_952bda65dd89'));
  if (!Number.isInteger(d.revision) || d.revision < 1) errors.push(tr('tm_3e52aac3bcb4'));
  if (!d.title.trim() || !d.packageId.trim() || !d.language.trim()) errors.push(tr('tm_ea34a32c0364'));
  if (![d.source.width,d.source.height].every(n => Number.isFinite(n) && n > 0 && n <= 100000)) errors.push(tr('tm_3288260dcee3'));
  if (d.source.viewBox.length !== 4 || !d.source.viewBox.every(Number.isFinite) || d.source.viewBox[2] <= 0 || d.source.viewBox[3] <= 0) errors.push(tr('tm_c8bfe9d7ec8f'));
  if (!safePath(d.source.path) || !/^[a-f0-9]{64}$/.test(d.source.sha256)) errors.push(tr('tm_430f6896ab0a'));
  if (d.regions.length > 500 || d.relations.length > 2000) errors.push(tr('tm_7b9d712f906e'));
  let points = 0;
  d.regions.forEach(r=>{points+=r.line.length;r.polygons.forEach(p=>{points+=p.outer.length;p.holes.forEach(h=>points+=h.length);});});
  d.relations.forEach(r=>points+=(r.path||[]).length);
  if(points>100000) return [tr('tm_5d4d8cc52be0')];
  points=0;
  d.regions.forEach(r => {
    id(r.id);
    if (!r.label.trim() || (!r.polygons.length && r.line.length < 2)) errors.push(tr('tm_f2627e1c1ae3', [String(r.id)]));
    if (!Number.isFinite(r.lineWidth) || r.lineWidth < 0 || !Number.isFinite(r.zIndex) || !Number.isFinite(r.readingOrder)) errors.push(tr('tm_bebf86f6c07b', [String(r.id)]));
    const rings = r.polygons.flatMap(p => [p.outer, ...p.holes]);
    if(r.polygons.some(p=>!validPolygon(p))) errors.push(tr('tm_ae08f0af8840', [String(r.id)]));
    rings.forEach(ring => { if (ring.length < 3 || new Set(ring.map(p => `${p.x},${p.y}`)).size < 3) errors.push(tr('tm_6903d2f80a02', [String(r.id)])); });
    const all = [...r.line,...rings.flat()]; points += all.length;
    if (all.some(p => !Number.isFinite(p.x) || !Number.isFinite(p.y) || Math.abs(p.x)>1000000 || Math.abs(p.y)>1000000)) errors.push(tr('tm_bd7f332ac0f1', [String(r.id)]));
    if (r.line.length === 1 || (r.line.length > 0 && r.lineWidth <= 0)) errors.push(tr('tm_a4354460c104', [String(r.id)]));
    r.evidence.forEach(e => { if (e.sourceId !== d.source.id) errors.push(tr('tm_bba180062158', [String(r.id)])); });
  });
  d.relations.forEach(r => {
    id(r.id);
    if(!r.label.trim()||!r.type.trim()) errors.push(tr('tm_758710e903df', [String(r.id)]));
    if (![r.fromId,r.toId].every(v => d.regions.some(x => x.id === v))) errors.push(tr('tm_c339728bd429', [String(r.id)]));
    if (!['forward','both','unknown'].includes(r.direction)) errors.push(tr('tm_9770d687964e', [String(r.id)]));
    if (r.path !== null) { points += r.path.length; if(r.path.length < 2 || r.path.some(p => !Number.isFinite(p.x)||!Number.isFinite(p.y))) errors.push(tr('tm_1dac3b2cd3db', [String(r.id)])); }
    r.evidence.forEach(e => { if (e.sourceId !== d.source.id) errors.push(tr('tm_bba180062158', [String(r.id)])); });
  });
  d.charts.forEach(c => {
    id(c.id);
    if(c.evidence.some(e=>e.sourceId!==d.source.id)) errors.push(tr('tm_bba180062158', [String(c.id)]));
    [c.xAxis,c.yAxis].forEach(a => {
      if (!['linear','log','category'].includes(a.scale) || a.domain.some(n=>!Number.isFinite(n)) || (a.scale !== 'category' && (a.domain.length !== 2 || a.domain[0] >= a.domain[1]))) errors.push(tr('tm_721dbbb89329', [String(c.id)]));
      if(a.scale==='log' && (a.domain.some(n=>n<=0)||a.ticks.some(t=>t.value<=0))) errors.push(tr('tm_e4c0d3ccf523', [String(c.id)]));
      if(a.ticks.some(t=>!Number.isFinite(t.value))) errors.push(tr('tm_f11fc7036e00', [String(c.id)]));
    });
    c.series.forEach(s => { id(s.id); s.values.forEach(v => { id(v.id); if(v.evidence.some(e=>e.sourceId!==d.source.id)) errors.push(tr('tm_bba180062158', [String(v.id)])); if(v.value!==null&&!Number.isFinite(v.value)) errors.push(tr('tm_36760a833be5', [String(v.id)])); if (!d.regions.some(r=>r.id===v.regionId)) errors.push(tr('tm_78ac40b0c8c9', [String(v.id)])); if (!Number.isInteger(v.precision)||v.precision<0||v.precision>10) errors.push(tr('tm_6bddbae40759', [String(v.id)])); }); });
  });
  d.questions.forEach(q => { id(q.id); if(reviewed(q.review)) errors.push(...questionIssues(d,q)); else if(new Set(q.options.map(o=>o.id)).size!==q.options.length||q.acceptedAnswers.some(a=>!q.options.some(o=>o.id===a))||new Set(q.acceptedAnswers).size!==q.acceptedAnswers.length) errors.push(tr('tm_e49c2811840e', [String(q.id)])); });
  const audioTargets=new Set<string>();
  d.audio.forEach(a=>{
    const target=`${a.targetId}:${a.kind}:${a.language}`;
    if(audioTargets.has(target)) errors.push(tr('tm_9389f6b8ec21', [String(a.id)]));audioTargets.add(target);
    if(!(a.kind==='overview'&&a.targetId===d.packageId || a.kind==='question'&&d.questions.some(q=>q.id===a.targetId) || ['label','description'].includes(a.kind)&&d.regions.some(r=>r.id===a.targetId) || a.kind==='label'&&d.relations.some(r=>r.id===a.targetId))) errors.push(tr('tm_5bbf6f973f8f', [String(a.id)]));
  });
  d.audio.forEach(a => { id(a.id); if (!safePath(a.path) || !/^[a-f0-9]{64}$/.test(a.sha256) || !/^[a-f0-9]{64}$/.test(a.textHash) || !Number.isFinite(a.durationMs)||a.durationMs<=0) errors.push(tr('tm_1a54c2d4dc5c', [String(a.id)])); });
  if(points>100000) errors.push(tr('tm_5d4d8cc52be0'));
  return errors;
}
export function publicationIssues(d: Diagram): string[] {
  const issues = validateDiagram(d);
  if(!diagramShape(d)) return issues;
  if(!d.regions.length) issues.push(tr('tm_3bd088fa88a7'));
  if(!d.source.attribution.trim()||d.source.attribution.startsWith('Author must')||!d.source.license.trim()||d.source.license==='Unspecified') issues.push(tr('tm_0ea48fd44136'));
  d.regions.forEach(r => { if(!reviewed(r.geometryReview,d.revision)||!reviewed(r.meaningReview,d.revision)) issues.push(tr('tm_ed1bcdb8fdf5', [String(r.id)])); });
  d.relations.forEach(r => { if(!reviewed(r.review,d.revision)) issues.push(tr('tm_546f469fae01', [String(r.id)])); });
  d.charts.forEach(c => { if(!reviewed(c.review,d.revision)) issues.push(tr('tm_fdaddd84b305', [String(c.id)])); });
  d.questions.forEach(q => { if(!reviewed(q.review,d.revision)) issues.push(tr('tm_e24d49070d9b', [String(q.id)])); issues.push(...questionIssues(d,q)); });
  [...d.regions,...d.relations,...d.charts,...d.charts.flatMap(c=>c.series.flatMap(s=>s.values))].forEach(f=>{if(!f.evidence.length||f.evidence.some(e=>!e.reference.trim()))issues.push(tr('tm_1ab9c8a8b1bc', [String(f.id)]));});
  return Array.from(new Set(issues));
}
export function offlineReadiness(d: Diagram, availablePaths: string[]): Readiness {
  if(!diagramShape(d)) return {ready:false,missing:[tr('tm_0d785ded3b10')]};
  const missing: string[] = publicationIssues(d);
  if(!availablePaths.includes(d.source.path)) missing.push(d.source.path);
  if(d.source.previewPath&&!availablePaths.includes(d.source.previewPath)) missing.push(d.source.previewPath);
  const required = d.regions.map(r=>({id:r.id,kind:'label'})).concat(d.relations.map(r=>({id:r.id,kind:'label'}))).concat(d.questions.map(q=>({id:q.id,kind:'question'})));
  required.push({id:d.packageId,kind:'overview'});
  d.regions.filter(r=>r.description.trim()).forEach(r=>required.push({id:r.id,kind:'description'}));
  required.forEach(t => { const a=d.audio.find(a=>a.targetId===t.id&&a.kind===t.kind&&a.language===d.language); if(!a) missing.push(tr('tm_ad1d78617079', [String(t.id), String(t.kind)])); else if(!availablePaths.includes(a.path)) missing.push(a.path); });
  d.audio.forEach(a=>{if(!availablePaths.includes(a.path)&&!missing.includes(a.path))missing.push(a.path);});
  d.audio.forEach(a=>{if(a.language!==d.language)missing.push(tr('tm_dbe54fbe4fc4', [String(a.id)]));});
  return { ready: missing.length===0, missing };
}
