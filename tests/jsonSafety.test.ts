import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { assertBoundedJson } from '../app/entry/src/main/ets/domain/jsonSafety';
import { validateManifest } from '../app/entry/src/main/ets/domain/validate';
import { Manifest } from '../app/entry/src/main/ets/domain/types';
function manifest():Manifest{return JSON.parse(readFileSync('samples/water-cycle/manifest.json','utf8'));}
test('bounded JSON accepts actual package documents and escaped strings',()=>{
  for(const name of ['water-cycle','lumina-process','rainfall-chart','tutorial'])for(const file of ['manifest.json','diagram.json'])assert.doesNotThrow(()=>assertBoundedJson(readFileSync(`samples/${name}/${file}`,'utf8')));
  for(const value of ['null','false','1.2e-5','[0,-1,true,false,null,"a\\n\\u017c"]','{"one":{"a":1},"two":{"a":2}}'])assert.doesNotThrow(()=>assertBoundedJson(value));
});
test('bounded JSON rejects duplicate decoded names, excessive depth and malformed tokens',()=>{
  for(const value of ['{"a":1,"a":2}','{"a":1,"\\u0061":2}','{"a":{"b":1,"b":2}}','['.repeat(34)+'0'+']'.repeat(34),'[NaN]','1e400','01','1.','1e','+1','[true,]','{"a":1,}','"unterminated','"\\x"','"\\u123"','null trailing','{"a":true "b":false}',''])assert.throws(()=>assertBoundedJson(value),Error,value);
});
test('manifest rejects malformed authors/assets before native adoption',()=>{
  assert.deepEqual(validateManifest(manifest()),[]);
  const mutations=[(m:any)=>delete m.author,(m:any)=>m.author=null,(m:any)=>m.author.name=7,(m:any)=>m.assets=null,(m:any)=>m.assets=[null],(m:any)=>m.assets[0].bytes='100',(m:any)=>m.assets[0].bytes=-1,(m:any)=>m.assets[0].sha256='wrong',(m:any)=>m.assets[0].mediaType={},(m:any)=>m.verified=true];
  for(const mutation of mutations){const m=manifest();mutation(m);assert.ok(validateManifest(m).length);}
  for(const bad of [null,[],{},7])assert.ok(validateManifest(bad as Manifest).length);
});
test('manifest rejects case collisions, self references and unbounded assets',()=>{
  const m=manifest();m.assets.push({...m.assets[0],path:m.assets[0].path.toUpperCase()});assert.ok(validateManifest(m).length);
  const reserved=manifest();reserved.assets[0].path='manifest.json';assert.ok(validateManifest(reserved).length);
  const giant=manifest();giant.assets[0].bytes=50*1024*1024+1;assert.ok(validateManifest(giant).length);
});
