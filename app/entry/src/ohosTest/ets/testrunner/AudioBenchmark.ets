import { abilityDelegatorRegistry } from '@kit.TestKit';
import { nativeContext } from './NativeContext';
import { Repository, Material, defaultProfile, encode, writeBytes } from '../../../main/ets/platform/Repository';
import { Feedback, AudioOnsetTrace } from '../../../main/ets/platform/Feedback';
interface AudioMeasure { index: number; material: string; target: string; onsetMs: number; scheduledLabelToPlayingMs: number; error: string; trace?: AudioOnsetTrace; }
interface AudioReport { status: string; requested: number; succeeded: number; failed: number; dwellMs: number; onsetP95Ms: number; scheduledLabelToPlayingP95Ms: number; onsetTargetMs: number; targetMet: boolean; scope: string; measurements: AudioMeasure[]; }
interface AudioProgress { phase: string; index: number; requested: number; timestamp: number; error: string; measurements: AudioMeasure[]; }

export async function runAudioBenchmark(count: number): Promise<void> {
  try { await measureAudio(count); }
  catch (error) {
    const message = `${(error as Error).message}\n${(error as Error).stack || ''}`;
    console.error(`TOUCHMAP_AUDIO_BENCHMARK_FAILED ${message}`);
    try { const context = await nativeContext(); const failure: AudioProgress = { phase:'failed',index:-1,requested:count,timestamp:Date.now(),error:message,measurements:[] }; writeBytes(`${context.filesDir}/audio-benchmark-failure.json`, encode(JSON.stringify(failure))); } catch (storageError) { console.error('Cannot persist audio benchmark failure'); }
    await abilityDelegatorRegistry.getAbilityDelegator().finishTest(`Audio benchmark failed: ${message}`, -1);
  }
}

async function measureAudio(count: number): Promise<void> {
  const context = await nativeContext(); const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const repository = new Repository(context); await repository.initialize();
  const progress: AudioProgress = {phase:'initialize-audio',index:0,requested:count,timestamp:Date.now(),error:'',measurements:[]};
  writeBytes(`${context.filesDir}/audio-benchmark-progress.json`, encode(JSON.stringify(progress)));
  const playback = new Feedback(); await playback.initialize();
  const profile = defaultProfile(); profile.readerSpeech = false; profile.vibration = false;
  const materials = (await repository.list()).filter((material: Material) => !material.draft && material.ready && ['water-cycle','lumina-process','rainfall-chart'].includes(material.diagram.packageId) && material.diagram.regions.some((region) => material.diagram.audio.some((asset) => asset.targetId === region.id && asset.kind === 'label')));
  const measurements: AudioMeasure[] = [];
  if (!Number.isInteger(count) || count < 1 || count > 1000 || !materials.length) { await delegator.finishTest('Invalid audio benchmark count or missing sample materials', -1); return; }
  let consecutiveFailures = 0;
  for (let index = 0; index < count; index++) {
    const material = materials[index % materials.length]; const regions = material.diagram.regions.filter((region) => material.diagram.audio.some((asset) => asset.targetId === region.id && asset.kind === 'label'));
    const region = regions[Math.floor(index / materials.length) % regions.length];
    const measured: AudioMeasure = {index:index,material:material.key,target:region.id,onsetMs:-1,scheduledLabelToPlayingMs:-1,error:''};
    progress.phase = 'scheduled'; progress.index = index; progress.timestamp = Date.now(); progress.measurements = measurements;
    writeBytes(`${context.filesDir}/audio-benchmark-progress.json`, encode(JSON.stringify(progress)));
    console.info(`TOUCHMAP_AUDIO_BENCHMARK_PROGRESS phase=scheduled index=${index}`);
    const begin = Date.now();
    await new Promise<void>((resolve) => {
      let done = false;
      const timeout = setTimeout(() => { if (!done) { done = true; measured.error = 'No accepted native PCM write within 5 seconds'; resolve(); } }, 5000);
      playback.onPlaybackTrace = (trace: AudioOnsetTrace) => { measured.trace = trace; };
      playback.onPlaybackStarted = (onset: number) => {
        if (!done) { done = true; clearTimeout(timeout); measured.onsetMs = onset; measured.scheduledLabelToPlayingMs = Date.now() - begin; resolve(); }
      };
      playback.onPlaybackFailure = (message: string) => { if (!done) { done = true; clearTimeout(timeout); measured.error = message; resolve(); } };
      playback.onStatus = (message: string) => {
        if (!done && (message.includes('unavailable') || message.includes('could not') || message.includes('failed') || message.includes('interrupted'))) { done = true; clearTimeout(timeout); measured.error = message; resolve(); }
      };
      playback.speak(material, region.id, 'label', profile, false);
    });
    measurements.push(measured);
    progress.phase = 'observed'; progress.timestamp = Date.now(); progress.measurements = measurements;
    writeBytes(`${context.filesDir}/audio-benchmark-progress.json`, encode(JSON.stringify(progress)));
    console.info(`TOUCHMAP_AUDIO_BENCHMARK_PROGRESS phase=observed index=${index} onsetMs=${measured.onsetMs} error=${measured.error}`);
    playback.stop();
    consecutiveFailures = measured.error ? consecutiveFailures + 1 : 0;
    await new Promise<void>((resolve) => { setTimeout(resolve, 40); });
    if (consecutiveFailures >= 3) { break; }
  }
  const success = measurements.filter((item: AudioMeasure) => !item.error);
  const onsets = success.map((item: AudioMeasure) => item.onsetMs).sort((a: number, b: number) => a - b);
  const totals = success.map((item: AudioMeasure) => item.scheduledLabelToPlayingMs).sort((a: number, b: number) => a - b);
  const p95 = Math.max(0, Math.ceil(onsets.length * 0.95) - 1);
  const report: AudioReport = {status:success.length === count ? 'complete' : 'incomplete',requested:count,succeeded:success.length,failed:measurements.length - success.length,dwellMs:profile.dwell,onsetP95Ms:onsets.length ? onsets[p95] : -1,scheduledLabelToPlayingP95Ms:totals.length ? totals[p95] : -1,onsetTargetMs:150,targetMet:success.length === count && onsets[p95] < 150,scope:'Actual AudioRenderer first accepted PCM writes for local recordings on this runtime. Onset starts at playback scheduler decision. The renderer is prewarmed during normal Feedback initialization and reused. First use verifies file integrity; later uses may use the bounded immutable PCM cache. Initialization time is excluded. Total starts at Feedback.speak and includes configured dwell; this is not a measured physical finger or speaker acoustic latency.',measurements:measurements};
  writeBytes(`${context.filesDir}/audio-benchmark.json`, encode(JSON.stringify(report)));
  console.info(`TOUCHMAP_AUDIO_BENCHMARK ${JSON.stringify(report)}`);
  playback.release();
  await delegator.finishTest(`Audio benchmark ${success.length}/${count}, p95 ${report.onsetP95Ms} ms`, success.length === count ? 0 : -1);
}
