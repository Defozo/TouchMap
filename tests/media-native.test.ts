import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parsePcmWav } from '../app/entry/src/main/ets/domain/media';

test('all bundled recordings expose complete aligned PCM samples for native AudioRenderer', () => {
  let count=0, expected=0;
  for(const material of ['water-cycle','lumina-process','rainfall-chart','tutorial']) {
    expected += JSON.parse(readFileSync(join('samples',material,'diagram.json'),'utf8')).audio.length;
    const root=join('samples',material,'audio');
    for(const file of readdirSync(root).filter(name=>name.endsWith('.wav'))) {
      const bytes=readFileSync(join(root,file));const pcm=parsePcmWav(bytes);
      assert.ok(pcm.dataOffset>=44);assert.ok(pcm.dataLength>0);assert.equal(pcm.dataLength%pcm.blockAlign,0);
      assert.ok(pcm.dataOffset+pcm.dataLength<=bytes.length);assert.ok(pcm.durationMs>0);
      assert.equal(pcm.byteRate,pcm.sampleRate*pcm.blockAlign);assert.equal(pcm.blockAlign,pcm.channels*pcm.bitsPerSample/8);count++;
    }
  }
  assert.equal(count,expected);assert.ok(count>0);
});
test('native PCM parser rejects compressed WAV and truncated sample payloads before playback', () => {
  const sample=readFileSync('samples/water-cycle/audio/collection-label.wav');
  assert.throws(()=>parsePcmWav(sample.subarray(0,sample.length-1)));
  const compressed=Buffer.from(sample);let at=12;
  while(at+8<compressed.length) { const size=compressed.readUInt32LE(at+4); if(compressed.toString('ascii',at,at+4)==='fmt ') {compressed.writeUInt16LE(3,at+8);break;}at+=8+size+(size%2); }
  assert.throws(()=>parsePcmWav(compressed));
});
