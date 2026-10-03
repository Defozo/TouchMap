import { Diagram, Manifest, Question, Review } from './types';
import { diagramShape, manifestShape, portablePath, questionShape, reviewShape, validPolygon } from './validationShape';
export interface Readiness { ready: boolean; missing: string[] }
export function reviewed(r: Review, revision: number = 0): boolean { return reviewShape(r) && r.status === 'reviewed' && (revision === 0 || r.revision === revision); }
export function safePath(path: string): boolean {
  return portablePath(path);
}
export function validateManifest(m: Manifest): string[] {
  if(!manifestShape(m))return ['Malformed manifest, author declaration or asset metadata'];
  const paths=m.assets.map(a=>a.path.toLowerCase());
  if(new Set(paths).size!==paths.length||paths.includes('manifest.json'))return ['Manifest contains duplicate, colliding or reserved asset paths'];
  if(m.assets.reduce((sum,a)=>sum+a.bytes,0)>200*1024*1024)return ['Manifest expanded asset size exceeds limit'];
  return [];
}
export function validateQuestion(d: Diagram, q: Question): string[] {
  if(!diagramShape(d)||!questionShape(q)) return ['Malformed diagram or question structure'];
  return questionIssues(d,q);
}
function questionIssues(d: Diagram, q: Question): string[] {
  const errors: string[] = [], options = q.options.map(o => o.id);
  if (!q.prompt.trim() || !q.explanation.trim() || !q.factIds.length) errors.push(`${q.id}: question needs prompt, explanation and referenced facts`);
  if (q.requiredRevision !== d.revision || q.review.revision !== d.revision) errors.push(`${q.id}: question revision is stale`);
  if(q.options.some(o=>!o.label.trim())) errors.push(`${q.id}: answer options need labels`);
  if (!q.acceptedAnswers.length || q.acceptedAnswers.some(a => !options.includes(a))) errors.push(`${q.id}: accepted answers must name options`);
  if (new Set(options).size !== options.length || options.length < 2) errors.push(`${q.id}: distinct answer options required`);
  if (new Set(q.acceptedAnswers).size !== q.acceptedAnswers.length) errors.push(`${q.id}: duplicate accepted answer`);
  q.factIds.forEach(id => {
    const region = d.regions.find(r => r.id === id), relation = d.relations.find(r => r.id === id), chart = d.charts.find(c => c.id === id);
    let known = !!region || !!relation || !!chart;
    if (region && !reviewed(region.meaningReview,d.revision)) errors.push(`${q.id}: region meaning is unreviewed`);
    if (relation && (!reviewed(relation.review,d.revision) || (['direction','sequence'].includes(q.type) && relation.direction === 'unknown'))) errors.push(`${q.id}: relation is unreviewed or direction unknown`);
    if (chart && !reviewed(chart.review,d.revision)) errors.push(`${q.id}: chart is unreviewed`);
    for (const c of d.charts) for (const s of c.series) for (const v of s.values) if (v.id === id) {
      known = true;
      if (!reviewed(c.review,d.revision) || (['value','comparison'].includes(q.type) && v.value === null)) errors.push(`${q.id}: unknown or unreviewed chart value cannot be an exact fact`);
    }
    if (!known) errors.push(`${q.id}: missing fact ${id}`);
  });
  return errors;
}
export function validateDiagram(d: Diagram): string[] {
  if(!diagramShape(d)) return ['Malformed diagram structure, coordinate, field type or content limit'];
  const errors: string[] = [], ids = new Set<string>([d.packageId]);
  const id = (value: string): void => { if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/.test(value) || ids.has(value)) errors.push(`Invalid or duplicate ID: ${value}`); ids.add(value); };
  if (d.schemaVersion !== 1) errors.push('Unsupported schema version');
  if (!Number.isInteger(d.revision) || d.revision < 1) errors.push('Invalid revision');
  if (!d.title.trim() || !d.packageId.trim() || !d.language.trim()) errors.push('Missing identity fields');
  if (![d.source.width,d.source.height].every(n => Number.isFinite(n) && n > 0 && n <= 100000)) errors.push('Invalid source dimensions');
  if (d.source.viewBox.length !== 4 || !d.source.viewBox.every(Number.isFinite) || d.source.viewBox[2] <= 0 || d.source.viewBox[3] <= 0) errors.push('Invalid viewBox');
  if (!safePath(d.source.path) || !/^[a-f0-9]{64}$/.test(d.source.sha256)) errors.push('Invalid source path/hash');
  if (d.regions.length > 500 || d.relations.length > 2000) errors.push('Diagram exceeds object limit');
  let points = 0;
  d.regions.forEach(r=>{points+=r.line.length;r.polygons.forEach(p=>{points+=p.outer.length;p.holes.forEach(h=>points+=h.length);});});
  d.relations.forEach(r=>points+=(r.path||[]).length);
  if(points>100000) return ['Geometry exceeds point limit'];
  points=0;
  d.regions.forEach(r => {
    id(r.id);
    if (!r.label.trim() || (!r.polygons.length && r.line.length < 2)) errors.push(`${r.id}: missing label or geometry`);
    if (!Number.isFinite(r.lineWidth) || r.lineWidth < 0 || !Number.isFinite(r.zIndex) || !Number.isFinite(r.readingOrder)) errors.push(`${r.id}: invalid geometry metadata`);
    const rings = r.polygons.flatMap(p => [p.outer, ...p.holes]);
    if(r.polygons.some(p=>!validPolygon(p))) errors.push(`${r.id}: invalid polygon topology or topology complexity limit`);
    rings.forEach(ring => { if (ring.length < 3 || new Set(ring.map(p => `${p.x},${p.y}`)).size < 3) errors.push(`${r.id}: invalid polygon ring`); });
    const all = [...r.line,...rings.flat()]; points += all.length;
    if (all.some(p => !Number.isFinite(p.x) || !Number.isFinite(p.y) || Math.abs(p.x)>1000000 || Math.abs(p.y)>1000000)) errors.push(`${r.id}: invalid coordinate`);
    if (r.line.length === 1 || (r.line.length > 0 && r.lineWidth <= 0)) errors.push(`${r.id}: invalid line`);
    r.evidence.forEach(e => { if (e.sourceId !== d.source.id) errors.push(`${r.id}: invalid evidence source`); });
  });
  d.relations.forEach(r => {
    id(r.id);
    if(!r.label.trim()||!r.type.trim()) errors.push(`${r.id}: missing relationship meaning`);
    if (![r.fromId,r.toId].every(v => d.regions.some(x => x.id === v))) errors.push(`${r.id}: dangling relationship`);
    if (!['forward','both','unknown'].includes(r.direction)) errors.push(`${r.id}: invalid direction`);
    if (r.path !== null) { points += r.path.length; if(r.path.length < 2 || r.path.some(p => !Number.isFinite(p.x)||!Number.isFinite(p.y))) errors.push(`${r.id}: invalid path`); }
    r.evidence.forEach(e => { if (e.sourceId !== d.source.id) errors.push(`${r.id}: invalid evidence source`); });
  });
  d.charts.forEach(c => {
    id(c.id);
    if(c.evidence.some(e=>e.sourceId!==d.source.id)) errors.push(`${c.id}: invalid evidence source`);
    [c.xAxis,c.yAxis].forEach(a => {
      if (!['linear','log','category'].includes(a.scale) || a.domain.some(n=>!Number.isFinite(n)) || (a.scale !== 'category' && (a.domain.length !== 2 || a.domain[0] >= a.domain[1]))) errors.push(`${c.id}: invalid axis`);
      if(a.scale==='log' && (a.domain.some(n=>n<=0)||a.ticks.some(t=>t.value<=0))) errors.push(`${c.id}: log domain and ticks must be positive`);
      if(a.ticks.some(t=>!Number.isFinite(t.value))) errors.push(`${c.id}: invalid ticks`);
    });
    c.series.forEach(s => { id(s.id); s.values.forEach(v => { id(v.id); if(v.evidence.some(e=>e.sourceId!==d.source.id)) errors.push(`${v.id}: invalid evidence source`); if(v.value!==null&&!Number.isFinite(v.value)) errors.push(`${v.id}: invalid value`); if (!d.regions.some(r=>r.id===v.regionId)) errors.push(`${v.id}: missing region`); if (!Number.isInteger(v.precision)||v.precision<0||v.precision>10) errors.push(`${v.id}: invalid precision`); }); });
  });
  d.questions.forEach(q => { id(q.id); if(reviewed(q.review)) errors.push(...questionIssues(d,q)); else if(new Set(q.options.map(o=>o.id)).size!==q.options.length||q.acceptedAnswers.some(a=>!q.options.some(o=>o.id===a))||new Set(q.acceptedAnswers).size!==q.acceptedAnswers.length) errors.push(`${q.id}: inconsistent answer options`); });
  const audioTargets=new Set<string>();
  d.audio.forEach(a=>{
    const target=`${a.targetId}:${a.kind}:${a.language}`;
    if(audioTargets.has(target)) errors.push(`${a.id}: duplicate audio target`);audioTargets.add(target);
    if(!(a.kind==='overview'&&a.targetId===d.packageId || a.kind==='question'&&d.questions.some(q=>q.id===a.targetId) || ['label','description'].includes(a.kind)&&d.regions.some(r=>r.id===a.targetId) || a.kind==='label'&&d.relations.some(r=>r.id===a.targetId))) errors.push(`${a.id}: invalid audio target or kind`);
  });
  d.audio.forEach(a => { id(a.id); if (!safePath(a.path) || !/^[a-f0-9]{64}$/.test(a.sha256) || !/^[a-f0-9]{64}$/.test(a.textHash) || !Number.isFinite(a.durationMs)||a.durationMs<=0) errors.push(`${a.id}: invalid audio`); });
  if(points>100000) errors.push('Geometry exceeds point limit');
  return errors;
}
export function publicationIssues(d: Diagram): string[] {
  const issues = validateDiagram(d);
  if(!diagramShape(d)) return issues;
  if(!d.regions.length) issues.push('A learning material needs at least one region');
  if(!d.source.attribution.trim()||d.source.attribution.startsWith('Author must')||!d.source.license.trim()||d.source.license==='Unspecified') issues.push('Source attribution and license require an author declaration');
  d.regions.forEach(r => { if(!reviewed(r.geometryReview,d.revision)||!reviewed(r.meaningReview,d.revision)) issues.push(`${r.id}: geometry and meaning need review for current revision`); });
  d.relations.forEach(r => { if(!reviewed(r.review,d.revision)) issues.push(`${r.id}: relation needs review for current revision`); });
  d.charts.forEach(c => { if(!reviewed(c.review,d.revision)) issues.push(`${c.id}: chart needs review for current revision`); });
  d.questions.forEach(q => { if(!reviewed(q.review,d.revision)) issues.push(`${q.id}: question needs review for current revision`); issues.push(...questionIssues(d,q)); });
  [...d.regions,...d.relations,...d.charts,...d.charts.flatMap(c=>c.series.flatMap(s=>s.values))].forEach(f=>{if(!f.evidence.length||f.evidence.some(e=>!e.reference.trim()))issues.push(`${f.id}: source-linked evidence needs review`);});
  return Array.from(new Set(issues));
}
export function offlineReadiness(d: Diagram, availablePaths: string[]): Readiness {
  if(!diagramShape(d)) return {ready:false,missing:['Malformed diagram structure']};
  const missing: string[] = publicationIssues(d);
  if(!availablePaths.includes(d.source.path)) missing.push(d.source.path);
  if(d.source.previewPath&&!availablePaths.includes(d.source.previewPath)) missing.push(d.source.previewPath);
  const required = d.regions.map(r=>({id:r.id,kind:'label'})).concat(d.relations.map(r=>({id:r.id,kind:'label'}))).concat(d.questions.map(q=>({id:q.id,kind:'question'})));
  required.push({id:d.packageId,kind:'overview'});
  d.regions.filter(r=>r.description.trim()).forEach(r=>required.push({id:r.id,kind:'description'}));
  required.forEach(t => { const a=d.audio.find(a=>a.targetId===t.id&&a.kind===t.kind&&a.language===d.language); if(!a) missing.push(`audio:${t.id}:${t.kind}`); else if(!availablePaths.includes(a.path)) missing.push(a.path); });
  d.audio.forEach(a=>{if(!availablePaths.includes(a.path)&&!missing.includes(a.path))missing.push(a.path);});
  d.audio.forEach(a=>{if(a.language!==d.language)missing.push(`${a.id}: wrong audio language`);});
  return { ready: missing.length===0, missing };
}
