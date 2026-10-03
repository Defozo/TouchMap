import { tr } from '../domain/i18n';
import { audio } from '@kit.AudioKit';
import { vibrator } from '@kit.SensorServiceKit';
import { accessibility } from '@kit.AccessibilityKit';
import { Material, Profile, digest, readBytes } from './Repository';
import { parsePcmWav, PcmWav } from '../domain/media';

interface CachedRecording { key: string; bytes: Uint8Array; pcm: PcmWav; }
export interface AudioOnsetTrace {
  target: string; cacheHit: boolean; integrityMs: number; controlWaitMs: number;
  prepareMs: number; volumeMs: number; startMs: number; firstWriteDispatchMs: number;
  firstWriteResolveMs: number; rendererState: number; bufferBytes: number; bufferDurationMs: number;
  firstWriteBytes: number; firstWriteDurationMs: number; writeAttemptsBeforeOnset: number;
}

export class Feedback {
  private renderer: audio.AudioRenderer | undefined = undefined;
  private rendererFormat: string = '';
  private rendererBufferSize: number = 0;
  private rendererVolume: number = -1;
  private idleTimer: number = -1;
  private control: Promise<void> = Promise.resolve();
  private pendingWrite: Promise<number> | undefined = undefined;
  private pendingDrain: Promise<void> | undefined = undefined;
  private cache: CachedRecording[] = [];
  private playing: boolean = false;
  private paused: boolean = false;
  private resumeWaiter: (() => void) | undefined = undefined;
  private timer: number = -1;
  private generation: number = 0;
  private last: string = '';
  private lastTime: number = 0;
  reader: boolean = false;
  vibrationAvailable: boolean = false;
  status: string = tr('tm_b2701d74e733');
  onStatus: (message: string) => void = () => {};
  onPlaybackStarted: (onsetMs: number, targetId: string) => void = () => {};
  onPlaybackFailure: (message: string) => void = () => {};
  onPlaybackTrace: (trace: AudioOnsetTrace) => void = () => {};
  onWritePending: (targetId: string, byteCount: number) => void = () => {};
  async initialize(): Promise<void> {
    try { this.reader = accessibility.isScreenReaderOpenSync(); } catch (error) { this.reader = false; }
    accessibility.on('screenReaderStateChange', (enabled: boolean) => { this.reader = enabled; this.stop(); });
    try { this.vibrationAvailable = await vibrator.isSupportEffect('haptic.clock.timer'); } catch (error) { this.vibrationAvailable = false; }
    try {
      await this.serialize(async () => {
        const renderer = await this.prepareRenderer(24000, 1, 16);
        await renderer.start(); await renderer.pause(); await renderer.flush();
      });
    } catch (error) { console.warn('TOUCHMAP_AUDIO_PREWARM_UNAVAILABLE'); this.release(); }
  }
  private serialize(work: () => Promise<void>): Promise<void> {
    const next = this.control.then(work); this.control = next.catch(() => {}); return next;
  }
  private async prepareRenderer(rate: number, channels: number, bits: number): Promise<audio.AudioRenderer> {
    const format = `${rate}:${channels}:${bits}`;
    if (this.renderer && this.rendererFormat === format) { return this.renderer; }
    if (this.renderer) { const old = this.renderer; this.renderer = undefined; await old.release(); }
    const sampleFormat = bits === 8 ? audio.AudioSampleFormat.SAMPLE_FORMAT_U8 : bits === 16 ? audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE : bits === 24 ? audio.AudioSampleFormat.SAMPLE_FORMAT_S24LE : audio.AudioSampleFormat.SAMPLE_FORMAT_S32LE;
    const options: audio.AudioRendererOptions = {
      streamInfo: { samplingRate: rate as audio.AudioSamplingRate, channels: channels as audio.AudioChannel, sampleFormat: sampleFormat, encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
      rendererInfo: { usage: audio.StreamUsage.STREAM_USAGE_MUSIC, rendererFlags: 0 }
    };
    const renderer = await audio.createAudioRenderer(options);
    this.renderer = renderer; this.rendererFormat = format; this.rendererVolume = -1; this.rendererBufferSize = await renderer.getBufferSize();
    renderer.on('audioInterrupt', (event: audio.InterruptEvent) => { console.info(`TOUCHMAP_AUDIO_INTERRUPT type=${event.eventType} hint=${event.hintType} force=${event.forceType}`); if (this.renderer === renderer && event.eventType === audio.InterruptType.INTERRUPT_TYPE_BEGIN) { this.release(); } });
    renderer.on('outputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo) => { console.info(`TOUCHMAP_AUDIO_DEVICE_CHANGE reason=${info.changeReason}`); if (this.renderer === renderer) { this.release(); } });
    return renderer;
  }
  stop(): void {
    this.generation++;
    if (this.idleTimer >= 0) { clearTimeout(this.idleTimer); this.idleTimer = -1; }
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    this.playing = false; this.paused = false;
    const wake = this.resumeWaiter; this.resumeWaiter = undefined; if (wake) { wake(); }
    const writing = this.pendingWrite, draining = this.pendingDrain;
    this.serialize(async () => {
      const renderer = this.renderer; if (!renderer) { return; }
      try {
        if (draining && renderer.state === audio.AudioState.STATE_RUNNING) { await renderer.stop(); }
        if (renderer.state !== audio.AudioState.STATE_PREPARED) { await renderer.flush(); }
        if (writing) { await this.settleWrite(writing); }
        if (renderer.state !== audio.AudioState.STATE_PREPARED) { await renderer.flush(); }
      } catch (error) { if (this.renderer === renderer) { this.renderer = undefined; } await renderer.release().catch(() => {}); }
    }).catch(() => {});
    const generation = this.generation;
    this.idleTimer = setTimeout(() => { if (generation === this.generation && !this.playing) { this.release(); } }, 2000);
    try { vibrator.stopVibration().catch(() => {}); } catch (error) {}
  }
  release(): void {
    this.stop(); this.cache = [];
    if (this.idleTimer >= 0) { clearTimeout(this.idleTimer); this.idleTimer = -1; }
    this.serialize(async () => { const renderer = this.renderer; this.renderer = undefined; this.rendererFormat = ''; this.rendererBufferSize = 0; if (renderer) { await renderer.release().catch(() => {}); } }).catch(() => {});
  }
  private settleWrite(writing: Promise<number>): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const deadline = setTimeout(() => { reject(new Error(tr('tm_7fa4317a4313'))); }, 1000);
      writing.then(() => { clearTimeout(deadline); resolve(); }).catch(() => { clearTimeout(deadline); resolve(); });
    });
  }
  async pauseRecording(): Promise<void> {
    const renderer = this.renderer; const token = this.generation;
    if (!renderer || !this.playing || this.paused) { this.onStatus(tr('tm_1c4331f4276e')); return; }
    try {
      this.paused = true;
      const writing = this.pendingWrite;
      await this.serialize(async () => {
        if (token !== this.generation) { return; }
        // The legacy native write bridge can remain active until its buffer is
        // accepted. Keep the renderer running while that bounded write settles.
        if (writing) { await this.settleWrite(writing); }
        if (token === this.generation) { await renderer.pause(); }
      });
      if (token === this.generation) { this.onStatus(tr('tm_cf90ba16af2d')); }
    }
    catch (error) { if (token === this.generation) { this.paused = false; const wake = this.resumeWaiter; this.resumeWaiter = undefined; if (wake) { wake(); } this.onStatus(tr('tm_65eda82062f1')); } }
  }
  async resumeRecording(): Promise<void> {
    const renderer = this.renderer; const token = this.generation;
    if (!renderer || !this.paused) { this.onStatus(tr('tm_0da021897d32')); return; }
    try {
      await this.serialize(async () => { if (token === this.generation) { await renderer.start(); } }); if (token !== this.generation) { return; }
      this.paused = false; const wake = this.resumeWaiter; this.resumeWaiter = undefined; if (wake) { wake(); }
      this.onStatus(tr('tm_664ba280bbe5'));
    } catch (error) { if (token === this.generation) { this.onStatus(tr('tm_2e93372b7567')); } }
  }
  cue(profile: Profile): void {
    if (!profile.vibration || !this.vibrationAvailable) { return; }
    vibrator.startVibration({ type: 'preset', effectId: 'haptic.clock.timer', count: 1 }, { usage: 'touch' }).catch(() => { this.vibrationAvailable = false; });
  }
  announce(message: string): void {
    if (!this.reader) { return; }
    const event: accessibility.EventInfo = { type: 'announceForAccessibility', bundleName: 'org.touchmap.app', triggerAction: 'common', textAnnouncedForAccessibility: message };
    accessibility.sendAccessibilityEvent(event).catch(() => { this.onStatus(message); });
  }
  speak(material: Material, target: string, kind: string, profile: Profile, explicit: boolean = false): void {
    if (!explicit && this.reader && profile.readerSpeech) {
      this.stop();
      const region = material.diagram.regions.find((r) => r.id === target);
      const relation = material.diagram.relations.find((r) => r.id === target);
      const text = region ? kind === 'description' ? region.description : region.label : relation ? relation.label : material.diagram.title;
      this.timer = setTimeout(() => { this.announce(text); }, profile.dwell); return;
    }
    const key = `${material.key}:${target}:${kind}`;
    if (!explicit && key === this.last && Date.now() - this.lastTime < 500) { return; }
    this.stop();
    const token = this.generation;
    this.timer = setTimeout(() => {
      this.play(material, target, kind, profile, token).catch((error: Error) => { if (token === this.generation) { this.status = error.message || tr('tm_f846ef468846'); console.error(`TOUCHMAP_AUDIO_FAILURE ${this.status}`); this.onPlaybackFailure(this.status); this.onStatus(this.status); this.stop(); } });
    }, explicit ? 0 : profile.dwell);
    this.last = key; this.lastTime = Date.now();
  }
  private async play(material: Material, target: string, kind: string, profile: Profile, token: number): Promise<void> {
    const decisionAt = Date.now();
    const asset = material.diagram.audio.find((item) => item.targetId === target && item.kind === kind);
    if (!asset) { this.onStatus(tr('tm_ff0bfbb8caef')); return; }
    const key = `${material.directory}:${asset.path}:${asset.sha256}`;
    let recording = this.cache.find((item: CachedRecording) => item.key === key);
    const trace: AudioOnsetTrace = { target:target,cacheHit:recording !== undefined,integrityMs:0,controlWaitMs:0,prepareMs:0,volumeMs:0,startMs:0,firstWriteDispatchMs:0,firstWriteResolveMs:0,rendererState:-1,bufferBytes:0,bufferDurationMs:0,firstWriteBytes:0,firstWriteDurationMs:0,writeAttemptsBeforeOnset:0 };
    if (!recording) {
      const bytes = readBytes(`${material.directory}/${asset.path}`, 10 * 1024 * 1024);
      if (await digest(bytes) !== asset.sha256) { throw new Error(tr('tm_9fa75bcd2677')); }
      if (token !== this.generation) { return; }
      recording = { key: key, bytes: bytes, pcm: parsePcmWav(bytes) };
      this.cache.push(recording);
      while (this.cache.length > 32 || this.cache.reduce((total: number, item: CachedRecording) => total + item.bytes.length, 0) > 16 * 1024 * 1024) { this.cache.shift(); }
    } else { this.cache = this.cache.filter((item: CachedRecording) => item.key !== key); this.cache.push(recording); }
    const bytes = recording.bytes, pcm = recording.pcm;
    trace.integrityMs = Date.now() - decisionAt;
    const controlQueuedAt = Date.now();
    await this.serialize(async () => {
      trace.controlWaitMs = Date.now() - controlQueuedAt;
      if (token !== this.generation) { return; }
      const prepareAt = Date.now();
      const renderer = await this.prepareRenderer(pcm.sampleRate, pcm.channels, pcm.bitsPerSample);
      trace.prepareMs = Date.now() - prepareAt;
      if (token !== this.generation) { return; }
      const volumeAt = Date.now();
      if (this.rendererVolume !== profile.volume) { await renderer.setVolume(profile.volume); this.rendererVolume = profile.volume; }
      trace.volumeMs = Date.now() - volumeAt; trace.rendererState = renderer.state;
      if (token !== this.generation) { return; }
      const startAt = Date.now();
      if (renderer.state !== audio.AudioState.STATE_RUNNING) { await renderer.start(); }
      trace.startMs = Date.now() - startAt;
    });
    if (token !== this.generation) { return; }
    const renderer = this.renderer; if (!renderer) { throw new Error(tr('tm_abdc1154056b')); }
    this.playing = true; this.paused = false;
    const chunkSize = Math.max(pcm.blockAlign, Math.floor(this.rendererBufferSize / pcm.blockAlign) * pcm.blockAlign);
    trace.bufferBytes = chunkSize; trace.bufferDurationMs = chunkSize * 1000 / (pcm.sampleRate * pcm.blockAlign);
    let offset = pcm.dataOffset, onsetLogged = false, emptyWrites = 0;
    const end = pcm.dataOffset + pcm.dataLength;
    while (offset < end && token === this.generation) {
      if (this.paused) { await new Promise<void>((resolve) => { this.resumeWaiter = resolve; }); if (token !== this.generation) { return; } }
      // Keep the first native buffer small for onset. Batch following buffers so
      // scheduling one promise per 20 ms cannot starve playback on a busy host.
      const writeSize = onsetLogged ? chunkSize * 8 : chunkSize;
      const sourceChunk = bytes.slice(offset, Math.min(end, offset + writeSize));
      // OpenHarmony's legacy write bridge ignores a remaining buffer of <=4 bytes.
      // Pad only the transport buffer with complete silent frames, never the verified WAV.
      let chunk = sourceChunk;
      if (sourceChunk.length <= 4) {
        chunk = new Uint8Array(Math.ceil(5 / pcm.blockAlign) * pcm.blockAlign);
        if (pcm.bitsPerSample === 8) { chunk.fill(128); }
        chunk.set(sourceChunk);
      }
      const writeAt = Date.now();
      if (!onsetLogged) { if (trace.writeAttemptsBeforeOnset === 0) { trace.firstWriteDispatchMs = writeAt - decisionAt; trace.firstWriteBytes = chunk.length; trace.firstWriteDurationMs = chunk.length * 1000 / (pcm.sampleRate * pcm.blockAlign); } trace.writeAttemptsBeforeOnset++; }
      const pending = renderer.write(chunk.buffer); this.pendingWrite = pending;
      this.onWritePending(target, chunk.length);
      let written = 0;
      try { written = await pending; } finally { if (this.pendingWrite === pending) { this.pendingWrite = undefined; } }
      if (token !== this.generation) { return; }
      if (written > 0) {
        offset += Math.min(written, sourceChunk.length); emptyWrites = 0;
        if (!onsetLogged) { onsetLogged = true; const onset = Date.now() - decisionAt; trace.firstWriteResolveMs = onset - trace.firstWriteDispatchMs; this.onPlaybackTrace(trace); console.info(`TOUCHMAP_AUDIO_ONSET ms=${onset} target=${target} kind=${kind} adapter=AudioRendererPCM`); this.onPlaybackStarted(onset, target); this.onStatus(tr('tm_8049e42f47a6')); }
      } else {
        emptyWrites++; if (emptyWrites > 10 && !this.paused) { throw new Error(tr('tm_b3de49f9fd14')); }
        await new Promise<void>((resolve) => { setTimeout(resolve, 10); });
      }
    }
    if (token !== this.generation) { return; }
    if (this.paused) { await new Promise<void>((resolve) => { this.resumeWaiter = resolve; }); }
    if (token !== this.generation) { return; }
    const draining = renderer.drain(); this.pendingDrain = draining;
    try { await draining; } finally { if (this.pendingDrain === draining) { this.pendingDrain = undefined; } }
    if (token === this.generation) { this.onStatus(tr('tm_35880193055a')); this.stop(); }
  }

}

export const feedback = new Feedback();
