import { abilityDelegatorRegistry } from '@kit.TestKit';
import { nativeContext } from './NativeContext';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Repository, Material, defaultProfile, encode, writeBytes, digest } from '../../../main/ets/platform/Repository';
import { Feedback } from '../../../main/ets/platform/Feedback';

interface AudioControlCheck { name: string; passed: boolean; detail: string; }
interface AudioControlObservation { elapsedMs: number; kind: string; value: string; }
interface AudioControlReport { status: string; checks: AudioControlCheck[]; error: string; scope: string; observations: AudioControlObservation[]; }
function delay(milliseconds: number): Promise<void> { return new Promise<void>((resolve) => { setTimeout(resolve, milliseconds); }); }
async function until(predicate: () => boolean, milliseconds: number): Promise<void> {
  const deadline = Date.now() + milliseconds;
  while (!predicate()) { if (Date.now() > deadline) { throw new Error('Native audio control timed out.'); } await delay(20); }
}
function tailFixture(): Uint8Array {
  // One 20 ms PCM buffer plus two complete 16-bit frames exercises the native <=4-byte tail.
  const bytes = new Uint8Array(44 + 964); const header = new DataView(bytes.buffer);
  bytes.set([82,73,70,70],0); header.setUint32(4,bytes.length-8,true); bytes.set([87,65,86,69,102,109,116,32],8);
  header.setUint32(16,16,true); header.setUint16(20,1,true); header.setUint16(22,1,true);
  header.setUint32(24,24000,true); header.setUint32(28,48000,true); header.setUint16(32,2,true); header.setUint16(34,16,true);
  bytes.set([100,97,116,97],36); header.setUint32(40,964,true); return bytes;
}

export async function runAudioControls(mode: string = 'all'): Promise<void> {
  const context = await nativeContext(); const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const playback = new Feedback();
  const observedAt = Date.now(); const observations: AudioControlObservation[] = [];
  const observe = (kind: string, value: string): void => { observations.push({elapsedMs:Date.now()-observedAt,kind:kind,value:value}); };
  const phase = (name: string): void => { observe('phase',name); writeBytes(`${context.filesDir}/audio-controls-progress.json`, encode(JSON.stringify({phase:name,utc:Date.now(),observations:observations}))); console.info(`TOUCHMAP_AUDIO_CONTROL_PHASE ${name}`); };
  phase('initialize');
  const report: AudioControlReport = { status:'running',checks:[],error:'',scope:'Actual native Feedback scheduling, PCM target callbacks, AudioRenderer pause/resume and natural completion. These checks do not measure physical speaker acoustics.',observations:observations };
  try {
    const repository = new Repository(context); await repository.initialize(); await playback.initialize();
    const material = (await repository.list()).find((item: Material) => item.diagram.packageId === 'water-cycle' && !item.draft && item.ready)!;
    if (!material || material.diagram.regions.length < 2) { throw new Error('Water-cycle control fixture is missing.'); }
    const profile = defaultProfile(); profile.vibration = false; profile.readerSpeech = false; profile.dwell = 250;
    const first = material.diagram.regions[0].id, second = material.diagram.regions[1].id;
    const started: string[] = []; const statuses: string[] = []; const failures: string[] = [];
    playback.onPlaybackStarted = (_onset: number, target: string) => { started.push(target); observe('started',target); };
    playback.onStatus = (message: string) => { statuses.push(message); observe('status',message); };
    playback.onPlaybackFailure = (message: string) => { failures.push(message); observe('failure',message); };
    if (mode !== 'tail') {
    phase('stop_before_dwell');
    playback.speak(material, first, 'label', profile, false); playback.stop(); await delay(600);
    report.checks.push({name:'stop_before_dwell',passed:started.length === 0 && failures.length === 0,detail:`Observed ${started.length} native onset callbacks after cancellation.`});

    phase('rapid_replacement');
    playback.speak(material, first, 'label', profile, false); playback.speak(material, second, 'label', profile, false);
    await until(() => started.length > 0 || failures.length > 0, 5000);
    report.checks.push({name:'rapid_replacement_only_latest_target',passed:started.length === 1 && started[0] === second && failures.length === 0,detail:`Native PCM targets: ${started.join(',')}`});
    playback.stop(); await delay(100);

    started.length = 0; statuses.length = 0;
    const recording = material.diagram.audio.find((item) => item.targetId === first && item.kind === 'description') || material.diagram.audio.find((item) => item.targetId === first && item.kind === 'label')!;
    playback.speak(material, first, recording.kind, profile, true);
    await until(() => started.length > 0 || failures.length > 0, 5000);
    phase('pause_call'); await playback.pauseRecording(); phase('pause_complete'); await delay(300);
    const pausedWithoutFinish = statuses.includes('Recording paused. Resume keeps your place.') && !statuses.includes('Recording finished');
    phase('resume_call'); await playback.resumeRecording(); phase('resume_complete');
    await until(() => statuses.includes('Recording finished') || failures.length > 0, recording.durationMs + 5000);
    report.checks.push({name:'pause_resume_finishes_same_recording',passed:pausedWithoutFinish && statuses.includes('Recording resumed at the saved position.') && statuses.includes('Recording finished') && started.length === 1 && failures.length === 0,detail:statuses.join(' | ')});

    phase('replace_pending_batched_write');
    started.length = 0; statuses.length = 0; failures.length = 0;
    let firstWriteBytes = 0, replacedWriteBytes = 0;
    playback.onPlaybackTrace = (trace) => { if (trace.target === first) { firstWriteBytes = trace.firstWriteBytes; } };
    playback.onWritePending = (target: string, byteCount: number) => {
      if (target === first && firstWriteBytes > 0 && byteCount > firstWriteBytes && replacedWriteBytes === 0) {
        replacedWriteBytes = byteCount; observe('replaceNativeWritePending',String(byteCount));
        playback.speak(material,second,'label',profile,true);
      }
    };
    playback.speak(material,first,recording.kind,profile,true);
    await until(() => statuses.includes('Recording finished') || failures.length > 0,5000);
    playback.onWritePending = () => {}; playback.onPlaybackTrace = () => {};
    report.checks.push({name:'replace_pending_batched_write_finishes_latest_only',passed:replacedWriteBytes > firstWriteBytes && firstWriteBytes > 0 && started.length === 2 && started[0] === first && started[1] === second && statuses.filter((value:string) => value === 'Recording finished').length === 1 && failures.length === 0,detail:`Replaced actual pending ${replacedWriteBytes}-byte native write after ${firstWriteBytes}-byte onset; targets: ${started.join(',')}; ${statuses.join(' | ')}`});
    }
    phase('four_byte_tail');
    started.length = 0; statuses.length = 0; failures.length = 0;
    const tail = tailFixture(); const testMaterial = JSON.parse(JSON.stringify(material)) as Material;
    testMaterial.directory = context.cacheDir; testMaterial.key = `${material.key}-pcm-tail-test`;
    const asset = testMaterial.diagram.audio.find((item) => item.targetId === first && item.kind === 'label')!;
    asset.path = 'pcm-tail-control.wav'; asset.sha256 = await digest(tail); asset.durationMs = 21;
    writeBytes(`${testMaterial.directory}/${asset.path}`,tail);
    try {
      playback.speak(testMaterial,first,'label',profile,true);
      await until(() => statuses.includes('Recording finished') || failures.length > 0,5000);
      report.checks.push({name:'four_byte_final_pcm_tail_finishes',passed:statuses.includes('Recording finished') && started.length === 1 && failures.length === 0,detail:`964 PCM bytes: ${statuses.join(' | ')}; failures: ${failures.join(' | ')}`});
    } finally { playback.stop(); fs.unlinkSync(`${testMaterial.directory}/${asset.path}`); }
    phase('checks_complete');
    report.status = report.checks.every((check: AudioControlCheck) => check.passed) ? 'passed' : 'failed';
  } catch (error) { report.status = 'failed'; report.error = `${(error as Error).message}\n${(error as Error).stack || ''}`; }
  finally { playback.release(); }
  writeBytes(`${context.filesDir}/audio-controls.json`, encode(JSON.stringify(report)));
  console.info(`TOUCHMAP_AUDIO_CONTROLS ${JSON.stringify(report)}`);
  await delegator.finishTest(`Native audio controls ${report.status}`, report.status === 'passed' ? 0 : -1);
}
