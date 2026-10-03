import { audio } from '@kit.AudioKit';
import { vibrator } from '@kit.SensorServiceKit';
import { accessibility } from '@kit.AccessibilityKit';
import { Material, Profile, digest, readBytes } from './Repository';
import { parsePcmWav, PcmWav } from '../domain/media';

interface CachedRecording { key: string; bytes: Uint8Array; pcm: PcmWav; }

export class Feedback {
  private renderer: audio.AudioRenderer | undefined = undefined;
  private rendererFormat: string = '';
  private rendererBufferSize: number = 0;
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
  status: string = 'Audio ready';
  onStatus: (message: string) => void = () => {};
  onPlaybackStarted: (onsetMs: number) => void = () => {};
  onPlaybackFailure: (message: string) => void = () => {};
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
    this.renderer = renderer; this.rendererFormat = format; this.rendererBufferSize = await renderer.getBufferSize();
    renderer.on('audioInterrupt', (event: audio.InterruptEvent) => { console.info(`TOUCHMAP_AUDIO_INTERRUPT type=${event.eventType} hint=${event.hintType} force=${event.forceType}`); if (this.renderer === renderer && event.eventType === audio.InterruptType.INTERRUPT_TYPE_BEGIN) { this.stop(); } });
    renderer.on('outputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo) => { console.info(`TOUCHMAP_AUDIO_DEVICE_CHANGE reason=${info.changeReason}`); if (this.renderer === renderer) { this.stop(); } });
    return renderer;
  }
  stop(): void {
    this.generation++;
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    this.playing = false; this.paused = false;
    const wake = this.resumeWaiter; this.resumeWaiter = undefined; if (wake) { wake(); }
    const writing = this.pendingWrite, draining = this.pendingDrain;
    this.serialize(async () => {
      const renderer = this.renderer; if (!renderer) { return; }
      try {
        if (draining && renderer.state === audio.AudioState.STATE_RUNNING) { await renderer.stop(); }
        else if (renderer.state === audio.AudioState.STATE_RUNNING) { await renderer.pause(); }
        if (renderer.state !== audio.AudioState.STATE_PREPARED) { await renderer.flush(); }
        if (writing) { await this.settleWrite(writing); }
        if (renderer.state !== audio.AudioState.STATE_PREPARED) { await renderer.flush(); }
      } catch (error) { if (this.renderer === renderer) { this.renderer = undefined; } await renderer.release().catch(() => {}); }
    }).catch(() => {});
    try { vibrator.stopVibration().catch(() => {}); } catch (error) {}
  }
  release(): void {
    this.stop(); this.cache = [];
    this.serialize(async () => { const renderer = this.renderer; this.renderer = undefined; this.rendererFormat = ''; this.rendererBufferSize = 0; if (renderer) { await renderer.release().catch(() => {}); } }).catch(() => {});
  }
  private settleWrite(writing: Promise<number>): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const deadline = setTimeout(() => { reject(new Error('Cancelled audio write did not settle.')); }, 1000);
      writing.then(() => { clearTimeout(deadline); resolve(); }).catch(() => { clearTimeout(deadline); resolve(); });
    });
  }
  async pauseRecording(): Promise<void> {
    const renderer = this.renderer; const token = this.generation;
    if (!renderer || !this.playing || this.paused) { this.onStatus('No recording is currently playing.'); return; }
    try { this.paused = true; await this.serialize(async () => { if (token === this.generation) { await renderer.pause(); } }); if (token === this.generation) { this.onStatus('Recording paused. Resume keeps your place.'); } }
    catch (error) { if (token === this.generation) { this.paused = false; const wake = this.resumeWaiter; this.resumeWaiter = undefined; if (wake) { wake(); } this.onStatus('Recording could not be paused.'); } }
  }
  async resumeRecording(): Promise<void> {
    const renderer = this.renderer; const token = this.generation;
    if (!renderer || !this.paused) { this.onStatus('No paused recording. Choose Replay or an overview.'); return; }
    try {
      await this.serialize(async () => { if (token === this.generation) { await renderer.start(); } }); if (token !== this.generation) { return; }
      this.paused = false; const wake = this.resumeWaiter; this.resumeWaiter = undefined; if (wake) { wake(); }
      this.onStatus('Recording resumed at the saved position.');
    } catch (error) { if (token === this.generation) { this.onStatus('Recording could not be resumed. Replay when ready.'); } }
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
      this.play(material, target, kind, profile, token).catch((error: Error) => { if (token === this.generation) { this.status = error.message || 'Native audio playback failed.'; console.error(`TOUCHMAP_AUDIO_FAILURE ${this.status}`); this.onPlaybackFailure(this.status); this.onStatus(this.status); this.stop(); } });
    }, explicit ? 0 : profile.dwell);
    this.last = key; this.lastTime = Date.now();
  }
  private async play(material: Material, target: string, kind: string, profile: Profile, token: number): Promise<void> {
    const decisionAt = Date.now();
    const asset = material.diagram.audio.find((item) => item.targetId === target && item.kind === kind);
    if (!asset) { this.onStatus('Recording unavailable. The full text remains available.'); return; }
    const key = `${material.directory}:${asset.path}:${asset.sha256}`;
    let recording = this.cache.find((item: CachedRecording) => item.key === key);
    if (!recording) {
      const bytes = readBytes(`${material.directory}/${asset.path}`, 10 * 1024 * 1024);
      if (await digest(bytes) !== asset.sha256) { throw new Error('Audio integrity check failed.'); }
      if (token !== this.generation) { return; }
      recording = { key: key, bytes: bytes, pcm: parsePcmWav(bytes) };
      this.cache.push(recording);
      while (this.cache.length > 32 || this.cache.reduce((total: number, item: CachedRecording) => total + item.bytes.length, 0) > 16 * 1024 * 1024) { this.cache.shift(); }
    } else { this.cache = this.cache.filter((item: CachedRecording) => item.key !== key); this.cache.push(recording); }
    const bytes = recording.bytes, pcm = recording.pcm;
    await this.serialize(async () => {
      if (token !== this.generation) { return; }
      const renderer = await this.prepareRenderer(pcm.sampleRate, pcm.channels, pcm.bitsPerSample);
      if (token !== this.generation) { return; }
      await renderer.setVolume(profile.volume);
      if (token !== this.generation) { return; }
      await renderer.start();
    });
    if (token !== this.generation) { return; }
    const renderer = this.renderer; if (!renderer) { throw new Error('Audio renderer is unavailable.'); }
    this.playing = true; this.paused = false;
    const chunkSize = Math.max(pcm.blockAlign, Math.floor(this.rendererBufferSize / pcm.blockAlign) * pcm.blockAlign);
    let offset = pcm.dataOffset, onsetLogged = false, emptyWrites = 0;
    const end = pcm.dataOffset + pcm.dataLength;
    while (offset < end && token === this.generation) {
      if (this.paused) { await new Promise<void>((resolve) => { this.resumeWaiter = resolve; }); if (token !== this.generation) { return; } }
      const chunk = bytes.slice(offset, Math.min(end, offset + chunkSize));
      const pending = renderer.write(chunk.buffer); this.pendingWrite = pending;
      let written = 0;
      try { written = await pending; } finally { if (this.pendingWrite === pending) { this.pendingWrite = undefined; } }
      if (token !== this.generation) { return; }
      if (written > 0) {
        offset += written; emptyWrites = 0;
        if (!onsetLogged) { onsetLogged = true; const onset = Date.now() - decisionAt; console.info(`TOUCHMAP_AUDIO_ONSET ms=${onset} target=${target} kind=${kind} adapter=AudioRendererPCM`); this.onPlaybackStarted(onset); this.onStatus('Playing local PCM recording'); }
      } else {
        emptyWrites++; if (emptyWrites > 10 && !this.paused) { throw new Error('Audio renderer did not accept PCM samples.'); }
        await new Promise<void>((resolve) => { setTimeout(resolve, 10); });
      }
    }
    if (token !== this.generation) { return; }
    if (this.paused) { await new Promise<void>((resolve) => { this.resumeWaiter = resolve; }); }
    if (token !== this.generation) { return; }
    const draining = renderer.drain(); this.pendingDrain = draining;
    try { await draining; } finally { if (this.pendingDrain === draining) { this.pendingDrain = undefined; } }
    if (token === this.generation) { this.onStatus('Recording finished'); this.stop(); }
  }

}

export const feedback = new Feedback();
