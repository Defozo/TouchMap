import { Audio, Axis, Chart, ChartValue, Diagram, Evidence, Manifest, Point, Polygon, Question, Region, Relation, Review, Series, Source } from './types';

// A TypeScript annotation does not make JSON.parse or an HTTP response trusted.
function keys(value: Object, allowed: string[]): boolean { return value !== null && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).every(k => allowed.includes(k)); }
function text(value: string): boolean { return typeof value === 'string' && value.length <= 10000; }
function identifier(value: string): boolean { return typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/.test(value); }
function hash(value: string): boolean { return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value); }
function integer(value: number, min: number = 0): boolean { return Number.isSafeInteger(value) && value >= min; }
function language(value: string): boolean { return typeof value === 'string' && value.length <= 35 && /^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$/.test(value); }
function strings(value: string[], maximum: number): boolean { return Array.isArray(value) && value.length <= maximum && value.every(text); }
function point(p: Point): boolean { return keys(p, ['x','y']) && Number.isFinite(p.x) && Number.isFinite(p.y) && Math.abs(p.x) <= 1000000 && Math.abs(p.y) <= 1000000; }
function points(p: Point[]): boolean { return Array.isArray(p) && p.length <= 100000 && p.every(point); }
function evidence(e: Evidence[]): boolean { return Array.isArray(e) && e.length <= 1000 && e.every(x => keys(x, ['sourceId','reference','origin']) && identifier(x.sourceId) && text(x.reference) && ['source-derived','human-authored','AI-proposed'].includes(x.origin)); }
export function reviewShape(r: Review): boolean { return keys(r, ['status','revision','reviewer','issues']) && ['draft','needs_review','reviewed'].includes(r.status) && integer(r.revision, 1) && text(r.reviewer) && strings(r.issues, 1000) && (r.status !== 'reviewed' || (r.reviewer.trim().length > 0 && r.issues.length === 0)); }
export function portablePath(path: string): boolean { return typeof path === 'string' && path.length > 0 && path.length <= 256 && path === path.normalize('NFC') && !path.startsWith('/') && !/[\\:\x00-\x1f]/.test(path) && path.split('/').every(p => p !== '' && p !== '.' && p !== '..' && !/[. ]$/.test(p) && !/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(p)); }
function source(s: Source): boolean { return keys(s, ['id','sha256','width','height','path','attribution','license','viewBox','previewPath','previewSha256']) && identifier(s.id) && hash(s.sha256) && portablePath(s.path) && text(s.attribution) && text(s.license) && [s.width,s.height].every(n => Number.isFinite(n) && n > 0 && n <= 100000) && Array.isArray(s.viewBox) && s.viewBox.length === 4 && s.viewBox.every(Number.isFinite) && s.viewBox[2] > 0 && s.viewBox[3] > 0 && ((s.previewPath===undefined||s.previewPath==='')&&(s.previewSha256===undefined||s.previewSha256==='') || portablePath(s.previewPath!)&&hash(s.previewSha256!)&&s.previewPath!==s.path); }
function polygon(p: Polygon): boolean { return keys(p, ['outer','holes']) && points(p.outer) && p.outer.length >= 3 && Array.isArray(p.holes) && p.holes.length <= 1000 && p.holes.every(h => points(h) && h.length >= 3); }
function region(r: Region): boolean { return keys(r, ['id','label','description','polygons','line','lineWidth','zIndex','readingOrder','evidence','geometryReview','meaningReview']) && identifier(r.id) && text(r.label) && text(r.description) && Array.isArray(r.polygons) && r.polygons.length <= 10000 && r.polygons.every(polygon) && points(r.line) && Number.isFinite(r.lineWidth) && r.lineWidth >= 0 && r.lineWidth <= 100000 && Number.isSafeInteger(r.zIndex) && integer(r.readingOrder) && evidence(r.evidence) && reviewShape(r.geometryReview) && reviewShape(r.meaningReview); }
function relation(r: Relation): boolean { return keys(r, ['id','fromId','toId','label','type','direction','path','evidence','review']) && identifier(r.id) && identifier(r.fromId) && identifier(r.toId) && text(r.label) && typeof r.type === 'string' && r.type.length <= 128 && ['forward','both','unknown'].includes(r.direction) && (r.path === null || (points(r.path) && r.path.length >= 2)) && evidence(r.evidence) && reviewShape(r.review); }
function axis(a: Axis): boolean { return keys(a, ['label','unit','scale','domain','ticks']) && text(a.label) && text(a.unit) && ['linear','log','category'].includes(a.scale) && Array.isArray(a.domain) && a.domain.length <= 1000 && a.domain.every(Number.isFinite) && Array.isArray(a.ticks) && a.ticks.length <= 1000 && a.ticks.every(t => keys(t, ['value','label']) && Number.isFinite(t.value) && text(t.label)); }
function chartValue(v: ChartValue): boolean { return keys(v, ['id','regionId','x','value','precision','evidence']) && identifier(v.id) && identifier(v.regionId) && text(v.x) && (v.value === null || Number.isFinite(v.value)) && integer(v.precision) && v.precision <= 10 && evidence(v.evidence); }
function series(s: Series): boolean { return keys(s, ['id','label','values']) && identifier(s.id) && text(s.label) && Array.isArray(s.values) && s.values.length <= 10000 && s.values.every(chartValue); }
function chart(c: Chart): boolean { return keys(c, ['id','title','kind','xAxis','yAxis','series','evidence','review']) && identifier(c.id) && text(c.title) && ['bar','line'].includes(c.kind) && axis(c.xAxis) && axis(c.yAxis) && Array.isArray(c.series) && c.series.length <= 1000 && c.series.every(series) && evidence(c.evidence) && reviewShape(c.review); }
export function questionShape(q: Question): boolean { return keys(q, ['id','prompt','type','factIds','options','acceptedAnswers','hint','explanation','requiredRevision','review']) && identifier(q.id) && text(q.prompt) && ['adjacency','direction','sequence','comparison','value'].includes(q.type) && strings(q.factIds, 1000) && q.factIds.length > 0 && q.factIds.every(identifier) && Array.isArray(q.options) && q.options.length >= 2 && q.options.length <= 100 && q.options.every(o => keys(o, ['id','label']) && identifier(o.id) && text(o.label)) && strings(q.acceptedAnswers, 100) && q.acceptedAnswers.length > 0 && q.acceptedAnswers.every(identifier) && text(q.hint) && text(q.explanation) && integer(q.requiredRevision, 1) && reviewShape(q.review); }
function audio(a: Audio): boolean { return keys(a, ['id','targetId','kind','path','textHash','language','provider','voice','sha256','durationMs']) && identifier(a.id) && identifier(a.targetId) && ['label','description','question','overview'].includes(a.kind) && portablePath(a.path) && hash(a.textHash) && language(a.language) && text(a.provider) && text(a.voice) && hash(a.sha256) && integer(a.durationMs, 1) && a.durationMs <= 3600000; }
export function diagramShape(d: Diagram): boolean { return keys(d, ['schemaVersion','packageId','revision','title','language','source','regions','relations','charts','questions','audio','description']) && d.schemaVersion === 1 && identifier(d.packageId) && integer(d.revision, 1) && text(d.title) && language(d.language) && text(d.description) && source(d.source) && Array.isArray(d.regions) && d.regions.length <= 500 && d.regions.every(region) && Array.isArray(d.relations) && d.relations.length <= 2000 && d.relations.every(relation) && Array.isArray(d.charts) && d.charts.length <= 100 && d.charts.every(chart) && Array.isArray(d.questions) && d.questions.length <= 1000 && d.questions.every(questionShape) && Array.isArray(d.audio) && d.audio.length <= 2000 && d.audio.every(audio); }
export function manifestShape(m: Manifest): boolean {
  return keys(m,['schemaVersion','packageId','revision','title','language','author','license','assets'])&&m.schemaVersion===1&&identifier(m.packageId)&&integer(m.revision,1)&&text(m.title)&&language(m.language)&&keys(m.author,['name','declaration'])&&text(m.author.name)&&text(m.author.declaration)&&text(m.license)&&Array.isArray(m.assets)&&m.assets.length<=999&&m.assets.every(a=>keys(a,['path','sha256','bytes','mediaType'])&&portablePath(a.path)&&hash(a.sha256)&&integer(a.bytes)&&a.bytes<=50*1024*1024&&typeof a.mediaType==='string'&&a.mediaType.length<=128);
}

interface Edge { a: Point; b: Point; ring: number; index: number; size: number; minX: number; maxX: number; minY: number; maxY: number }
function same(a: Point, b: Point): boolean { return a.x === b.x && a.y === b.y; }
function cross(a: Point, b: Point, c: Point): number { return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x); }
function onSegment(p: Point, a: Point, b: Point): boolean { return cross(a,b,p) === 0 && p.x >= Math.min(a.x,b.x) && p.x <= Math.max(a.x,b.x) && p.y >= Math.min(a.y,b.y) && p.y <= Math.max(a.y,b.y); }
function intersects(a: Edge, b: Edge): boolean {
  if(a.maxX<b.minX||b.maxX<a.minX||a.maxY<b.minY||b.maxY<a.minY) return false;
  const c1=cross(a.a,a.b,b.a),c2=cross(a.a,a.b,b.b),c3=cross(b.a,b.b,a.a),c4=cross(b.a,b.b,a.b);
  return ((c1>0&&c2<0||c1<0&&c2>0)&&(c3>0&&c4<0||c3<0&&c4>0)) || onSegment(b.a,a.a,a.b)||onSegment(b.b,a.a,a.b)||onSegment(a.a,b.a,b.b)||onSegment(a.b,b.a,b.b);
}
function inside(p: Point, ring: Point[]): boolean { let found=false;for(let i=0,j=ring.length-1;i<ring.length;j=i++){const a=ring[j],b=ring[i];if(onSegment(p,a,b))return false;if((a.y>p.y)!==(b.y>p.y)&&p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x)found=!found;}return found; }
// Bounding-box sweep and a work ceiling avoid quadratic import stalls. Holes
// must be strictly inside, without touching any other ring (also enforced in Python).
export function validPolygon(p: Polygon): boolean {
  const rings=[p.outer,...p.holes].map(r=>same(r[0],r[r.length-1])?r.slice(0,-1):r),edges:Edge[]=[];
  for(let n=0;n<rings.length;n++) {
    const ring=rings[n];let area=0;
    if(ring.length<3||new Set(ring.map(v=>`${v.x},${v.y}`)).size!==ring.length)return false;
    for(let i=0;i<ring.length;i++){const a=ring[i],b=ring[(i+1)%ring.length];area+=a.x*b.y-b.x*a.y;edges.push({a,b,ring:n,index:i,size:ring.length,minX:Math.min(a.x,b.x),maxX:Math.max(a.x,b.x),minY:Math.min(a.y,b.y),maxY:Math.max(a.y,b.y)});}
    if(area===0)return false;
  }
  edges.sort((a,b)=>a.minX-b.minX);let active:Edge[]=[];let work=0;
  for(const e of edges){active=active.filter(a=>a.maxX>=e.minX);for(const a of active){if(++work>2000000)return false;const adjacent=a.ring===e.ring&&(Math.abs(a.index-e.index)===1||Math.abs(a.index-e.index)===a.size-1);if(adjacent){const common=same(a.a,e.a)||same(a.a,e.b)?a.a:a.b,otherA=same(a.a,common)?a.b:a.a,otherB=same(e.a,common)?e.b:e.a;if(onSegment(otherA,common,otherB)||onSegment(otherB,common,otherA))return false;}else if(intersects(a,e))return false;}active.push(e);}
  for(let i=1;i<rings.length;i++){if(!inside(rings[i][0],rings[0]))return false;for(let j=1;j<i;j++)if(inside(rings[i][0],rings[j])||inside(rings[j][0],rings[i]))return false;}
  return true;
}
