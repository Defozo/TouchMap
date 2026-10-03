import { Diagram, Question, Review } from './types';
export interface Readiness { ready: boolean; missing: string[] }
export function reviewed(r: Review): boolean { return r.status === 'reviewed' && r.reviewer.trim().length > 0 && r.issues.length === 0; }
export function safePath(path: string): boolean {
  return path.length > 0 && path.length <= 240 && !path.startsWith('/') && !/[\\:\x00-\x1f]/.test(path) && path.split('/').every(p => p !== '' && p !== '.' && p !== '..' && !/[. ]$/.test(p));
}
export function validateQuestion(d: Diagram, q: Question): string[] {
  const errors: string[] = [], options = q.options.map(o => o.id);
  if (!q.prompt.trim() || !q.explanation.trim() || !q.factIds.length) errors.push(`${q.id}: question needs prompt, explanation and referenced facts`);
  if (q.requiredRevision !== d.revision) errors.push(`${q.id}: question revision is stale`);
  if (!q.acceptedAnswers.length || q.acceptedAnswers.some(a => !options.includes(a))) errors.push(`${q.id}: accepted answers must name options`);
  if (new Set(options).size !== options.length || options.length < 2) errors.push(`${q.id}: distinct answer options required`);
  if (new Set(q.acceptedAnswers).size !== q.acceptedAnswers.length) errors.push(`${q.id}: duplicate accepted answer`);
  q.factIds.forEach(id => {
    const region = d.regions.find(r => r.id === id), relation = d.relations.find(r => r.id === id), chart = d.charts.find(c => c.id === id);
    let known = !!region || !!relation || !!chart;
    if (region && !reviewed(region.meaningReview)) errors.push(`${q.id}: region meaning is unreviewed`);
    if (relation && (!reviewed(relation.review) || (['direction','sequence','adjacency'].includes(q.type) && relation.direction === 'unknown'))) errors.push(`${q.id}: relation is unreviewed or direction unknown`);
    if (chart && !reviewed(chart.review)) errors.push(`${q.id}: chart is unreviewed`);
    for (const c of d.charts) for (const s of c.series) for (const v of s.values) if (v.id === id) {
      known = true;
      if (!reviewed(c.review) || v.value === null) errors.push(`${q.id}: unknown or unreviewed chart value cannot be an exact fact`);
    }
    if (!known) errors.push(`${q.id}: missing fact ${id}`);
  });
  return errors;
}
export function validateDiagram(d: Diagram): string[] {
  const errors: string[] = [], ids = new Set<string>();
  const id = (value: string): void => { if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/.test(value) || ids.has(value)) errors.push(`Invalid or duplicate ID: ${value}`); ids.add(value); };
  if (d.schemaVersion !== 1) errors.push('Unsupported schema version');
  if (!Number.isInteger(d.revision) || d.revision < 1) errors.push('Invalid revision');
  if (!d.title.trim() || !d.packageId.trim() || !d.language.trim()) errors.push('Missing identity fields');
  if (![d.source.width,d.source.height].every(n => Number.isFinite(n) && n > 0 && n <= 100000)) errors.push('Invalid source dimensions');
  if (d.source.viewBox.length !== 4 || !d.source.viewBox.every(Number.isFinite) || d.source.viewBox[2] <= 0 || d.source.viewBox[3] <= 0) errors.push('Invalid viewBox');
  if (!safePath(d.source.path) || !/^[a-f0-9]{64}$/.test(d.source.sha256)) errors.push('Invalid source path/hash');
  if (d.regions.length > 500 || d.relations.length > 2000) errors.push('Diagram exceeds object limit');
  let points = 0;
  d.regions.forEach(r => {
    id(r.id);
    if (!r.label.trim() || (!r.polygons.length && r.line.length < 2)) errors.push(`${r.id}: missing label or geometry`);
    if (!Number.isFinite(r.lineWidth) || r.lineWidth < 0 || !Number.isFinite(r.zIndex) || !Number.isFinite(r.readingOrder)) errors.push(`${r.id}: invalid geometry metadata`);
    const rings = r.polygons.flatMap(p => [p.outer, ...p.holes]);
    rings.forEach(ring => { if (ring.length < 3 || new Set(ring.map(p => `${p.x},${p.y}`)).size < 3) errors.push(`${r.id}: invalid polygon ring`); });
    const all = [...r.line,...rings.flat()]; points += all.length;
    if (all.some(p => !Number.isFinite(p.x) || !Number.isFinite(p.y) || Math.abs(p.x)>1000000 || Math.abs(p.y)>1000000)) errors.push(`${r.id}: invalid coordinate`);
    if (r.line.length === 1 || (r.line.length > 0 && r.lineWidth <= 0)) errors.push(`${r.id}: invalid line`);
    r.evidence.forEach(e => { if (e.sourceId !== d.source.id) errors.push(`${r.id}: invalid evidence source`); });
  });
  d.relations.forEach(r => {
    id(r.id);
    if (![r.fromId,r.toId].every(v => d.regions.some(x => x.id === v))) errors.push(`${r.id}: dangling relationship`);
    if (!['forward','both','unknown'].includes(r.direction)) errors.push(`${r.id}: invalid direction`);
    if (r.path !== null) { points += r.path.length; if(r.path.length < 2 || r.path.some(p => !Number.isFinite(p.x)||!Number.isFinite(p.y))) errors.push(`${r.id}: invalid path`); }
    r.evidence.forEach(e => { if (e.sourceId !== d.source.id) errors.push(`${r.id}: invalid evidence source`); });
  });
  d.charts.forEach(c => {
    id(c.id);
    [c.xAxis,c.yAxis].forEach(a => {
      if (!['linear','log','category'].includes(a.scale) || a.domain.some(n=>!Number.isFinite(n)) || (a.scale !== 'category' && (a.domain.length !== 2 || a.domain[0] >= a.domain[1]))) errors.push(`${c.id}: invalid axis`);
      if(a.scale==='log' && a.domain.some(n=>n<=0)) errors.push(`${c.id}: log domain must be positive`);
      if(a.ticks.some(t=>!Number.isFinite(t.value))) errors.push(`${c.id}: invalid ticks`);
    });
    c.series.forEach(s => { id(s.id); s.values.forEach(v => { id(v.id); if(v.value!==null&&!Number.isFinite(v.value)) errors.push(`${v.id}: invalid value`); if (!d.regions.some(r=>r.id===v.regionId)) errors.push(`${v.id}: missing region`); if (!Number.isInteger(v.precision)||v.precision<0||v.precision>10) errors.push(`${v.id}: invalid precision`); }); });
  });
  d.questions.forEach(q => { id(q.id); if(reviewed(q.review)) errors.push(...validateQuestion(d,q)); });
  d.audio.forEach(a => { id(a.id); if (!safePath(a.path) || !/^[a-f0-9]{64}$/.test(a.sha256) || !/^[a-f0-9]{64}$/.test(a.textHash) || !Number.isFinite(a.durationMs)||a.durationMs<=0) errors.push(`${a.id}: invalid audio`); });
  if(points>100000) errors.push('Geometry exceeds point limit');
  return errors;
}
export function publicationIssues(d: Diagram): string[] {
  const issues = validateDiagram(d);
  d.regions.forEach(r => { if(!reviewed(r.geometryReview)||!reviewed(r.meaningReview)) issues.push(`${r.id}: geometry and meaning need review`); });
  d.relations.forEach(r => { if(!reviewed(r.review)) issues.push(`${r.id}: relation needs review`); });
  d.charts.forEach(c => { if(!reviewed(c.review)) issues.push(`${c.id}: chart needs review`); });
  d.questions.forEach(q => { if(!reviewed(q.review)) issues.push(`${q.id}: question needs review`); issues.push(...validateQuestion(d,q)); });
  return Array.from(new Set(issues));
}
export function offlineReadiness(d: Diagram, availablePaths: string[]): Readiness {
  const missing: string[] = [];
  if(!availablePaths.includes(d.source.path)) missing.push(d.source.path);
  const required = d.regions.map(r=>({id:r.id,kind:'label'})).concat(d.relations.map(r=>({id:r.id,kind:'label'}))).concat(d.questions.map(q=>({id:q.id,kind:'question'})));
  required.push({id:d.packageId,kind:'overview'});
  d.regions.filter(r=>r.description.trim()).forEach(r=>required.push({id:r.id,kind:'description'}));
  required.forEach(t => { const a=d.audio.find(a=>a.targetId===t.id&&a.kind===t.kind&&a.language===d.language); if(!a) missing.push(`audio:${t.id}:${t.kind}`); else if(!availablePaths.includes(a.path)) missing.push(a.path); });
  d.audio.forEach(a=>{if(!availablePaths.includes(a.path)&&!missing.includes(a.path))missing.push(a.path);});
  return { ready: missing.length===0, missing };
}
