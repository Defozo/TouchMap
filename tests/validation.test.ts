import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Diagram, Polygon } from '../app/entry/src/main/ets/domain/types';
import { offlineReadiness, publicationIssues, safePath, validateDiagram, validateQuestion } from '../app/entry/src/main/ets/domain/validate';
function sample(name='water-cycle'):Diagram {return JSON.parse(readFileSync(`samples/${name}/diagram.json`,'utf8'));}
test('malformed nested wire objects are rejected without exceptions',()=>{
  const mutations=[(d:any)=>d.source=null,(d:any)=>d.regions[0].polygons=null,(d:any)=>d.regions[0].evidence=[null],(d:any)=>d.regions[0].geometryReview.issues={},(d:any)=>d.regions[0].line=[null],(d:any)=>d.regions[0].label=7,(d:any)=>d.regions[0].polygons[0].holes=[{}],(d:any)=>d.questions[0].options=[null,null],(d:any)=>d.audio[0].targetId={},(d:any)=>d.language='english', (d:any)=>d.regions[0].geometryReview.verified=true];
  for(const change of mutations){const d=sample();change(d);assert.ok(validateDiagram(d).length);assert.ok(publicationIssues(d).length);assert.equal(offlineReadiness(d,[]).ready,false);}
  for(const d of [null,[],{},17,'diagram'])assert.ok(validateDiagram(d as Diagram).length);
});
test('current revision and provenance are publication gates even when audio exists',()=>{
  const d=sample();d.regions[0].meaningReview.revision=2;assert.ok(publicationIssues(d).length);d.regions[0].meaningReview.revision=1;
  d.source.license='Unspecified';assert.ok(publicationIssues(d).some(x=>x.includes('license')));d.source.license='CC0';
  d.regions[0].evidence=[];assert.ok(publicationIssues(d).some(x=>x.includes('evidence')));assert.equal(offlineReadiness(d,[d.source.path,...d.audio.map(a=>a.path)]).ready,false);
  const q=sample();q.questions[0].review.revision=2;assert.ok(validateQuestion(q,q.questions[0]).some(x=>x.includes('stale')));
});
test('native validator rejects wrong audio kinds, duplicate targets and chart evidence',()=>{
  const d=sample();d.audio[0].targetId=d.questions[0].id;d.audio[0].kind='description';assert.ok(validateDiagram(d).some(x=>x.includes('audio target')));
  const duplicate=sample();duplicate.audio.push({...duplicate.audio[0],id:'duplicate-audio'});assert.ok(validateDiagram(duplicate).some(x=>x.includes('duplicate audio target')));
  const c=sample('rainfall-chart');c.charts[0].series[0].values[0].evidence[0].sourceId='absent';assert.ok(validateDiagram(c).some(x=>x.includes('evidence')));
  const reserved=sample();reserved.regions[0].id=reserved.packageId;assert.ok(validateDiagram(reserved).some(x=>x.includes('duplicate ID')));
});
test('native and preparation validators use shared polygon acceptance fixtures',()=>{
  const cases=JSON.parse(readFileSync('contracts/fixtures/polygons.json','utf8')) as {name:string;valid:boolean;polygon:Polygon}[];
  for(const c of cases){const d=sample();d.regions[0].polygons=[c.polygon];const topology=validateDiagram(d).filter(x=>x.includes('polygon'));assert.equal(topology.length===0,c.valid,c.name);}
});
test('portable names exclude reserved Windows devices and non-NFC aliases',()=>{for(const name of ['CON','audio/aux.wav','a/COM1.txt','Lpt9','e\u0301.wav'])assert.equal(safePath(name),false,name);assert.equal(safePath('audio/COM10.wav'),true);});
test('the actual offline CLI artifact passes native publication and preview readiness',()=>{
  const directory='docs/evidence/backend-cli/second-installation/';
  const d=JSON.parse(readFileSync(directory+'diagram.json','utf8')) as Diagram;
  const manifest=JSON.parse(readFileSync(directory+'manifest.json','utf8')) as {assets:{path:string}[]};
  assert.deepEqual(validateDiagram(d),[]);assert.deepEqual(publicationIssues(d),[]);
  assert.ok(d.source.previewPath);assert.equal(offlineReadiness(d,manifest.assets.map(a=>a.path)).ready,true);
  assert.equal(offlineReadiness(d,manifest.assets.filter(a=>a.path!==d.source.previewPath).map(a=>a.path)).ready,false);
});
