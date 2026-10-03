import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { wavDuration } from '../app/entry/src/main/ets/domain/media';
test('portable PCM recording validation shares malformed-header cases with backend',()=>{
  const source=readFileSync('samples/lumina-process/audio/seed-label.wav');
  assert.equal(wavDuration(source),697);
  const fixtures=JSON.parse(readFileSync('contracts/fixtures/audio-mutations.json','utf8')) as {name:string;offset:number;bytes:number[]}[];
  for(const fixture of fixtures){const bytes=new Uint8Array(source);bytes.set(fixture.bytes,fixture.offset);assert.throws(()=>wavDuration(bytes),Error,fixture.name);}
  assert.throws(()=>wavDuration(source.subarray(0,source.length-1)));
  assert.throws(()=>wavDuration(Buffer.concat([source,Buffer.from([0])])));
});
