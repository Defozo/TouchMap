import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SystemPicker } from './SystemPicker';
import { image } from '@kit.ImageKit';
import { relationalStore, preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Diagram, Manifest, Progress, Action, Asset } from '../domain/types';
import { initialProgress, applyAction } from '../domain/engine';
import { validateDiagram, validateManifest, offlineReadiness, publicationIssues, safePath as portablePath } from '../domain/validate';
import { assertBoundedJson } from '../domain/jsonSafety';
import { packPortable, ArchiveFile } from './PackageExporter';
import { extractEntry } from './ArchiveWorker';
import { wavDuration, assertSafeSvg, assertPassiveSvg } from '../domain/media';

export interface Material {
  key: string;
  diagram: Diagram;
  manifest: Manifest;
  directory: string;
  accepted: boolean;
  draft: boolean;
  ready: boolean;
}
export interface Profile {
  dwell: number;
  volume: number;
  vibration: boolean;
  contrast: boolean;
  textScale: number;
  scanMs: number;
  readerSpeech: boolean;
  tutorial: boolean;
  service: string;
}
export function defaultProfile(): Profile {
  return { dwell: 250, volume: 0.8, vibration: true, contrast: true, textScale: 1,
    scanMs: 1800, readerSpeech: true, tutorial: false, service: '' };
}
export function uid(): string { return `${Date.now()}-${Math.floor(Math.random() * 1000000000)}`; }
export function encode(text: string): Uint8Array { return new util.TextEncoder().encodeInto(text); }
export function decode(bytes: Uint8Array): string { return util.TextDecoder.create('utf-8', { fatal: true }).decodeWithStream(bytes); }
export async function digest(bytes: Uint8Array): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  await md.update({ data: bytes });
  const result = await md.digest();
  return Array.from(result.data).map((b: number) => b.toString(16).padStart(2, '0')).join('');
}
export function readBytes(path: string, limit: number = 50 * 1024 * 1024): Uint8Array {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size = fs.statSync(file.fd).size;
    if (size > limit) { throw new Error('File exceeds the supported size limit.'); }
    const bytes = new ArrayBuffer(size);
    let offset = 0;
    while (offset < size) {
      const part = new ArrayBuffer(size - offset);
      const got = fs.readSync(file.fd, part, { offset: offset });
      if (got === 0) { throw new Error('File access expired or the file is truncated.'); }
      new Uint8Array(bytes).set(new Uint8Array(part, 0, got), offset);
      offset += got;
    }
    return new Uint8Array(bytes);
  } finally { fs.closeSync(file); }
}
export function writeBytes(path: string, bytes: Uint8Array): void {
  const parent = path.substring(0, path.lastIndexOf('/'));
  if (!fs.accessSync(parent)) { fs.mkdirSync(parent, true); }
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { if (fs.writeSync(file.fd, bytes.slice().buffer) !== bytes.byteLength) { throw new Error('Storage could not complete the write.'); } fs.fsyncSync(file.fd); } finally { fs.closeSync(file); }
}
export function safePath(path: string): boolean {
  return portablePath(path) && path.normalize('NFC') === path && !path.split('/').some((part: string) => /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(part));
}
interface ZipEntry { path: string; compressed: number; expanded: number; offset: number; method: number; crc: number; }
// Inspect every central and local header before the platform decompressor sees an archive.
export function inspectZip(bytes: Uint8Array): ZipEntry[] {
  if (bytes.byteLength > 50 * 1024 * 1024 || bytes.length < 22) { throw new Error('Invalid package size.'); }
  const view = new DataView(bytes.buffer);
  let end = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (view.getUint32(i, true) === 0x06054b50 && i + 22 + view.getUint16(i + 20, true) === bytes.length) { end = i; break; }
  }
  if (end < 0 || view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0) { throw new Error('Multipart or malformed ZIP is unsupported.'); }
  const count = view.getUint16(end + 10, true);
  let cursor = view.getUint32(end + 16, true);
  const directorySize = view.getUint32(end + 12, true);
  if (count < 2 || count > 1000 || cursor + directorySize !== end) { throw new Error('ZIP entry limit or directory is invalid.'); }
  const entries: ZipEntry[] = [];
  const names: string[] = [];
  let total = 0;
  for (let i = 0; i < count; i++) {
    if (cursor + 46 > end || view.getUint32(cursor, true) !== 0x02014b50) { throw new Error('Invalid ZIP entry.'); }
    const flags = view.getUint16(cursor + 8, true);
    const method = view.getUint16(cursor + 10, true);
    const compressed = view.getUint32(cursor + 20, true);
    const expanded = view.getUint32(cursor + 24, true);
    const nameSize = view.getUint16(cursor + 28, true);
    const extra = view.getUint16(cursor + 30, true);
    const comment = view.getUint16(cursor + 32, true);
    const offset = view.getUint32(cursor + 42, true);
    const attrs = view.getUint32(cursor + 38, true);
    if (cursor + 46 + nameSize + extra + comment > end) { throw new Error('Truncated ZIP directory.'); }
    const path = decode(bytes.slice(cursor + 46, cursor + 46 + nameSize));
    const normalized = path;
    const fileType = attrs >>> 16 & 0xF000;
    if (!safePath(normalized) || names.includes(normalized.toLowerCase()) || (fileType !== 0 && fileType !== 0x8000) ||
      (flags & 1) !== 0 || (method !== 0 && method !== 8) || expanded === 0xFFFFFFFF || offset === 0xFFFFFFFF) {
      throw new Error('Unsafe paths, links, duplicate names or unsupported ZIP entries.');
    }
    names.push(normalized.toLowerCase());
    total += expanded;
    if (total > 200 * 1024 * 1024 || expanded > 50 * 1024 * 1024 || expanded > Math.max(1024 * 1024, compressed * 200)) { throw new Error('Package expansion limit exceeded.'); }
    if (offset + 30 > end || view.getUint32(offset, true) !== 0x04034b50 || view.getUint16(offset + 8, true) !== method) { throw new Error('ZIP local entry mismatch.'); }
    const localName = view.getUint16(offset + 26, true);
    const localExtra = view.getUint16(offset + 28, true);
    if (decode(bytes.slice(offset + 30, offset + 30 + localName)) !== path || offset + 30 + localName + localExtra + compressed > view.getUint32(end + 16, true)) { throw new Error('ZIP local path or bounds mismatch.'); }
    if (view.getUint16(offset + 6, true) !== flags) { throw new Error('ZIP flag mismatch.'); }
    const dataOffset = offset + 30 + localName + localExtra;
    if (entries.some((entry: ZipEntry) => dataOffset < entry.offset + entry.compressed && dataOffset + compressed > entry.offset)) { throw new Error('Overlapping ZIP entries.'); }
    entries.push({ path: path, compressed: compressed, expanded: expanded, offset: dataOffset, method: method, crc: view.getUint32(cursor + 16, true) });
    cursor += 46 + nameSize + extra + comment;
  }
  if (cursor !== end || !names.includes('manifest.json') || !names.includes('diagram.json')) { throw new Error('The package lacks its manifest or diagram.'); }
  return entries;
}
const initializedStores: Map<string, Promise<void>> = new Map<string, Promise<void>>();

export class Repository {
  context: common.UIAbilityContext;
  db: relationalStore.RdbStore | undefined = undefined;
  prefs: preferences.Preferences | undefined = undefined;
  profile: Profile = defaultProfile();
  private writing: Promise<void> = Promise.resolve();
  constructor(context: common.UIAbilityContext) { this.context = context; }
  private async lockMutation(): Promise<() => void> {
    const previous = this.writing;
    let release: () => void = () => {};
    this.writing = new Promise<void>((resolve) => { release = resolve; });
    await previous;
    return release;
  }
  async initialize(): Promise<void> {
    this.db = await relationalStore.getRdbStore(this.context, { name: 'touchmap.db', securityLevel: relationalStore.SecurityLevel.S1 });
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS materials (id TEXT PRIMARY KEY, body TEXT NOT NULL)');
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS progress (id TEXT PRIMARY KEY, revision INTEGER NOT NULL, body TEXT NOT NULL)');
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, material TEXT NOT NULL, body TEXT NOT NULL)');
    this.prefs = await preferences.getPreferences(this.context, { name: 'touchmap-profile' });
    this.profile = JSON.parse(await this.prefs.get('profile', JSON.stringify(defaultProfile())) as string) as Profile;
    const key = this.context.filesDir;
    const existing = initializedStores.get(key);
    if (existing) { await existing; return; }
    const initializing = this.initializeFiles();
    initializedStores.set(key, initializing);
    try { await initializing; } catch (error) { initializedStores.delete(key); throw new Error((error as Error).message); }
  }
  private async initializeFiles(): Promise<void> {
    for (const name of fs.listFileSync(this.context.cacheDir)) {
      if (/^portable-export-[0-9]+-[0-9]+$/.test(name)) {
        const path = `${this.context.cacheDir}/${name}`;
        if (fs.statSync(path).isDirectory()) { fs.rmdirSync(path); }
      }
    }
    const staging = `${this.context.filesDir}/staging`;
    if (fs.accessSync(staging)) { fs.rmdirSync(staging); }
    fs.mkdirSync(staging, true);
    if (!(await this.prefs!.get('seeded', false) as boolean)) {
      for (const sample of ['water-cycle', 'lumina-process', 'rainfall-chart', 'tutorial']) { await this.seed(sample); }
      await this.prefs!.put('seeded', true); await this.prefs!.flush();
    }
    const active = (await this.list()).map((m: Material) => m.directory);
    const materialRoot = `${this.context.filesDir}/materials`;
    if (fs.accessSync(materialRoot)) {
      for (const name of fs.listFileSync(materialRoot)) {
        const path = `${materialRoot}/${name}`;
        if (!active.includes(path) && fs.statSync(path).isDirectory()) { fs.rmdirSync(path); }
      }
    }
  }
  async saveProfile(profile: Profile): Promise<void> {
    await this.prefs!.put('profile', JSON.stringify(profile)); await this.prefs!.flush(); this.profile = profile;
  }
  private async seed(id: string): Promise<void> {
    const root = `${this.context.filesDir}/materials/${id}-bundled`;
    if (!fs.accessSync(root)) { fs.mkdirSync(root, true); }
    const manifestData = await this.context.resourceManager.getRawFileContent(`samples/${id}/manifest.json`);
    const manifest = JSON.parse(decode(manifestData)) as Manifest;
    writeBytes(`${root}/manifest.json`, manifestData);
    for (const asset of manifest.assets) { writeBytes(`${root}/${asset.path}`, await this.context.resourceManager.getRawFileContent(`samples/${id}/${asset.path}`)); }
    await this.adopt(root, false);
  }
  async list(): Promise<Material[]> {
    const result = await this.db!.querySql('SELECT body FROM materials ORDER BY id');
    const items: Material[] = [];
    try { while (result.goToNextRow()) { items.push(JSON.parse(result.getString(0)) as Material); } } finally { result.close(); }
    return items;
  }
  async saveMaterial(material: Material): Promise<void> {
    const release = await this.lockMutation();
    try {
    const row = await this.db!.querySql('SELECT body FROM materials WHERE id=?', [material.key]);
    try {
      if (row.goToFirstRow()) {
        const old = JSON.parse(row.getString(0)) as Material;
        if (!old.draft && JSON.stringify(old.diagram) !== JSON.stringify(material.diagram)) { throw new Error('Published revisions are immutable. Save a new revision.'); }
      }
    } finally { row.close(); }
    await this.db!.executeSql('INSERT OR REPLACE INTO materials(id,body) VALUES(?,?)', [material.key, JSON.stringify(material)]);
    } finally { release(); }
  }
  async accept(material: Material): Promise<Material> {
    const accepted: Material = JSON.parse(JSON.stringify(material)) as Material; accepted.accepted = true;
    await this.saveMaterial(accepted); return accepted;
  }
  async adopt(directory: string, draft: boolean): Promise<Material> {
    const manifestText = decode(readBytes(`${directory}/manifest.json`, 2 * 1024 * 1024));
    const diagramText = decode(readBytes(`${directory}/diagram.json`, 16 * 1024 * 1024));
    assertBoundedJson(manifestText); assertBoundedJson(diagramText);
    const manifest = JSON.parse(manifestText) as Manifest;
    const manifestErrors = validateManifest(manifest);
    if (manifestErrors.length > 0) { throw new Error(manifestErrors.slice(0, 4).join('\n')); }
    const diagram = JSON.parse(diagramText) as Diagram;
    const errors = validateDiagram(diagram);
    if (errors.length > 0) { throw new Error(errors.slice(0, 4).join('\n')); }
    if (manifest.schemaVersion !== 1 || manifest.packageId !== diagram.packageId || manifest.revision !== diagram.revision || manifest.title !== diagram.title || manifest.language !== diagram.language || manifest.assets.length > 999) { throw new Error('Manifest and content revision do not match.'); }
    const available: string[] = [];
    for (const asset of manifest.assets) {
      if (!safePath(asset.path) || available.map((p: string) => p.toLowerCase()).includes(asset.path.toLowerCase())) { throw new Error('Invalid manifest asset path.'); }
      const bytes = readBytes(`${directory}/${asset.path}`);
      if (bytes.length !== asset.bytes || await digest(bytes) !== asset.sha256) { throw new Error(`Integrity check failed: ${asset.path}`); }
      available.push(asset.path);
    }
    if (!available.includes('diagram.json') || !available.includes(diagram.source.path)) { throw new Error('Source and diagram must be covered by integrity hashes.'); }
    const expected = ['diagram.json', diagram.source.path, ...diagram.audio.map((a) => a.path)];
    if (diagram.source.previewPath) { expected.push(diagram.source.previewPath); }
    if (available.some((path: string) => !expected.includes(path)) || expected.some((path: string) => !available.includes(path))) { throw new Error('A teaching package may contain only declared source, diagram and audio.'); }
    const sourceBytes = readBytes(`${directory}/${diagram.source.path}`, 10 * 1024 * 1024);
    if (await digest(sourceBytes) !== diagram.source.sha256) { throw new Error('Source hash differs from the diagram.'); }
    if (diagram.source.previewPath) {
      const preview = readBytes(`${directory}/${diagram.source.previewPath}`);
      const header = new DataView(preview.buffer);
      if (await digest(preview) !== diagram.source.previewSha256 || preview.length < 24 ||
        header.getUint32(0) !== 0x89504e47 || header.getUint32(4) !== 0x0d0a1a0a ||
        header.getUint32(16) !== Math.ceil(diagram.source.width) || header.getUint32(20) !== Math.ceil(diagram.source.height)) {
        throw new Error('Source preview must be an intact PNG matching source dimensions.');
      }
      await this.validateRaster(preview, diagram.source.width, diagram.source.height);
    }
    if (diagram.source.path.toLowerCase().endsWith('.svg')) {
      if (diagram.source.previewPath) { assertPassiveSvg(decode(sourceBytes)); }
      else { assertSafeSvg(decode(sourceBytes)); }
    } else {
      if (!Number.isInteger(diagram.source.width) || !Number.isInteger(diagram.source.height)) { throw new Error('Raster source dimensions must be exact pixel counts.'); }
      await this.validateRaster(sourceBytes, diagram.source.width, diagram.source.height);
    }
    for (const audio of diagram.audio) {
      const asset = manifest.assets.find((a: Asset) => a.path === audio.path);
      if (!asset || asset.sha256 !== audio.sha256) { throw new Error('Audio integrity metadata differs from its manifest.'); }
      let text = '';
      const region = diagram.regions.find((r) => r.id === audio.targetId);
      const relation = diagram.relations.find((r) => r.id === audio.targetId);
      const question = diagram.questions.find((q) => q.id === audio.targetId);
      if (audio.kind === 'overview' && audio.targetId === diagram.packageId) { text = diagram.description || diagram.title; }
      else if (region && audio.kind === 'label') { text = region.label; }
      else if (region && audio.kind === 'description') { text = region.description; }
      else if (relation && audio.kind === 'label') { text = relation.label; }
      else if (question && audio.kind === 'question') { text = question.prompt; }
      if (!text || await digest(encode(text)) !== audio.textHash || audio.language !== diagram.language) { throw new Error('Recording does not match the current text or language.'); }
      if (!audio.path.toLowerCase().endsWith('.wav') || Math.abs(wavDuration(readBytes(`${directory}/${audio.path}`, 10 * 1024 * 1024)) - audio.durationMs) > 50) { throw new Error('Recording format or duration does not match its metadata.'); }
    }
    const existing = (await this.list()).find((m: Material) => m.key === `${diagram.packageId}@${diagram.revision}`);
    if (existing) {
      if (JSON.stringify(existing.diagram) !== JSON.stringify(diagram)) { throw new Error('A different material already uses this package revision. Ask the author to export a new revision.'); }
      if (existing.directory !== directory && directory.startsWith(`${this.context.filesDir}/materials/`)) { fs.rmdirSync(directory); }
      return existing;
    }
    const material: Material = { key: `${diagram.packageId}@${diagram.revision}`, diagram: diagram, manifest: manifest,
      directory: directory, accepted: false, draft: draft || publicationIssues(diagram).length > 0, ready: publicationIssues(diagram).length === 0 && offlineReadiness(diagram, available).ready };
    await this.saveMaterial(material); return material;
  }
  private async validateRaster(bytes: Uint8Array, width: number, height: number): Promise<void> {
    if (bytes.length > 10 * 1024 * 1024) { throw new Error('Source image exceeds 10 MiB.'); }
    const source = image.createImageSource(bytes.slice().buffer);
    try {
      const info = await source.getImageInfo();
      if (info.size.width !== Math.ceil(width) || info.size.height !== Math.ceil(height) || info.size.width * info.size.height > 20000000) {
        throw new Error('Decoded source dimensions differ from the declared geometry or exceed 20 megapixels.');
      }
      const pixels = await source.createPixelMap();
      await pixels.release();
    } finally { await source.release(); }
  }
  async pick(): Promise<string> {
    return new SystemPicker(this.context).select();
  }
  async importPackage(uri: string): Promise<Material> {
    // Let the picker-result and foreground lifecycle callbacks finish first.
    await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
    const bytes = readBytes(uri);
    const entries = inspectZip(bytes);
    const manifestEntry = entries.find((entry: ZipEntry) => entry.path === 'manifest.json')!;
    if (manifestEntry.expanded > 2 * 1024 * 1024) { throw new Error('Package manifest exceeds 2 MiB.'); }
    const manifestBytes = await extractEntry(bytes.slice(manifestEntry.offset, manifestEntry.offset + manifestEntry.compressed), manifestEntry.method, manifestEntry.expanded, manifestEntry.crc);
    const manifestText = decode(manifestBytes); assertBoundedJson(manifestText);
    const manifest = JSON.parse(manifestText) as Manifest;
    const errors = validateManifest(manifest); if (errors.length) { throw new Error(errors[0]); }
    const expected = ['manifest.json', ...manifest.assets.map((asset: Asset) => asset.path)];
    if (entries.length !== expected.length || entries.some((entry: ZipEntry) => !expected.includes(entry.path))) { throw new Error('Teaching packages cannot contain undeclared files or private learning history.'); }
    const id = uid(); const stage = `${this.context.filesDir}/staging/${id}`;
    fs.mkdirSync(stage, true);
    try {
      for (const entry of entries) {
        const compressed = bytes.slice(entry.offset, entry.offset + entry.compressed);
        const expanded = entry.path === 'manifest.json' ? manifestBytes : await extractEntry(compressed, entry.method, entry.expanded, entry.crc);
        writeBytes(`${stage}/${entry.path}`, expanded);
      }
      const target = `${this.context.filesDir}/materials/${id}`;
      if (!fs.accessSync(`${this.context.filesDir}/materials`)) { fs.mkdirSync(`${this.context.filesDir}/materials`, true); }
      fs.renameSync(stage, target);
      try { return await this.adopt(target, false); } catch (error) { fs.rmdirSync(target); throw new Error((error as Error).message); }
    } finally { if (fs.accessSync(stage)) { fs.rmdirSync(stage); } }
  }
  async saveDraft(diagram: Diagram, previous: Material): Promise<Material> {
    const all = await this.list();
    const collision = all.find((m: Material) => m.key === `${diagram.packageId}@${diagram.revision}`);
    if (collision && (!collision.draft || collision.key !== previous.key) && JSON.stringify(collision.diagram) !== JSON.stringify(diagram)) {
      diagram = JSON.parse(JSON.stringify(diagram)) as Diagram;
      diagram.revision = Math.max(...all.filter((m: Material) => m.diagram.packageId === diagram.packageId).map((m: Material) => m.diagram.revision)) + 1;
      diagram.regions.forEach((r) => { r.geometryReview.revision = diagram.revision; r.meaningReview.revision = diagram.revision; });
      diagram.relations.forEach((r) => { r.review.revision = diagram.revision; });
      diagram.charts.forEach((c) => { c.review.revision = diagram.revision; });
      diagram.questions.forEach((q) => { q.requiredRevision = diagram.revision; q.review.revision = diagram.revision; });
    }
    const directory = `${this.context.filesDir}/materials/draft-${uid()}`; fs.mkdirSync(directory, true);
    const sourceBytes = readBytes(`${previous.directory}/${previous.diagram.source.path}`);
    writeBytes(`${directory}/${diagram.source.path}`, sourceBytes);
    const assets: Asset[] = [];
    if (diagram.source.previewPath) {
      const preview = readBytes(`${previous.directory}/${diagram.source.previewPath}`);
      if (await digest(preview) !== diagram.source.previewSha256) { throw new Error('Source preview integrity failed.'); }
      writeBytes(`${directory}/${diagram.source.previewPath}`, preview);
      assets.push({ path: diagram.source.previewPath, bytes: preview.length, sha256: diagram.source.previewSha256!, mediaType: 'image/png' });
    }
    for (const audio of diagram.audio) {
      const bytes = readBytes(`${previous.directory}/${audio.path}`); writeBytes(`${directory}/${audio.path}`, bytes);
      const hash = await digest(bytes);
      const existingAsset = assets.find((asset: Asset) => asset.path === audio.path);
      if (existingAsset && (existingAsset.sha256 !== hash || existingAsset.mediaType !== 'audio/wav')) { throw new Error('Conflicting asset paths in the draft.'); }
      if (!existingAsset) { assets.push({ path: audio.path, bytes: bytes.length, sha256: hash, mediaType: 'audio/wav' }); }
    }
    const diagramBytes = encode(JSON.stringify(diagram)); writeBytes(`${directory}/diagram.json`, diagramBytes);
    assets.push({ path: 'diagram.json', bytes: diagramBytes.length, sha256: await digest(diagramBytes), mediaType: 'application/json' });
    assets.push({ path: diagram.source.path, bytes: sourceBytes.length, sha256: await digest(sourceBytes), mediaType: previous.manifest.assets.find((a: Asset) => a.path === previous.diagram.source.path)?.mediaType || 'image/png' });
    const manifest: Manifest = { schemaVersion: 1, packageId: diagram.packageId, revision: diagram.revision, title: diagram.title, language: diagram.language,
      author: previous.manifest.author, license: previous.manifest.license, assets: assets };
    writeBytes(`${directory}/manifest.json`, encode(JSON.stringify(manifest)));
    const material: Material = { key: `${diagram.packageId}@${diagram.revision}`, diagram: diagram, manifest: manifest, directory: directory, accepted: false, draft: true, ready: offlineReadiness(diagram, assets.map((a: Asset) => a.path)).ready };
    await this.saveMaterial(material);
    if (previous.draft && previous.key === material.key && previous.directory !== directory && previous.directory.startsWith(`${this.context.filesDir}/materials/`) && fs.accessSync(previous.directory)) { fs.rmdirSync(previous.directory); }
    return material;
  }
  async createSource(diagram: Diagram, bytes: Uint8Array, preview?: Uint8Array): Promise<Material> {
    const directory = `${this.context.filesDir}/materials/source-${uid()}`; fs.mkdirSync(directory, true);
    writeBytes(`${directory}/${diagram.source.path}`, bytes);
    if (diagram.source.previewPath) {
      if (!preview || await digest(preview) !== diagram.source.previewSha256) { throw new Error('An intact source preview is required.'); }
      writeBytes(`${directory}/${diagram.source.previewPath}`, preview);
    }
    const manifest: Manifest = { schemaVersion: 1, packageId: diagram.packageId, revision: diagram.revision, title: diagram.title, language: diagram.language,
      author: { name: '', declaration: 'Unreviewed source imported by the local author.' }, license: diagram.source.license, assets: [] };
    const seed: Material = { key: '', diagram: diagram, manifest: manifest, directory: directory, accepted: false, draft: true, ready: false };
    return this.saveDraft(diagram, seed);
  }
  async progress(material: Material): Promise<Progress> {
    const row = await this.db!.querySql('SELECT body FROM progress WHERE id=?', [material.key]);
    try { return row.goToFirstRow() ? JSON.parse(row.getString(0)) as Progress : initialProgress(material.diagram); } finally { row.close(); }
  }
  async dispatch(material: Material, action: Action): Promise<Progress> {
    const release = await this.lockMutation();
    try {
      this.db!.beginTransaction();
      try {
        const present = await this.db!.querySql('SELECT id FROM materials WHERE id=?', [material.key]);
        try { if (!present.goToFirstRow()) { throw new Error('This material was deleted. Return to the library.'); } } finally { present.close(); }
        const current = await this.progress(material);
        const result = applyAction(material.diagram, current, action);
        if (!result.duplicate) {
          await this.db!.executeSql('INSERT INTO events(id,material,body) VALUES(?,?,?)', [action.eventId, material.key, JSON.stringify(action)]);
          await this.db!.executeSql('INSERT OR REPLACE INTO progress(id,revision,body) VALUES(?,?,?)', [material.key, result.state.stateRevision, JSON.stringify(result.state)]);
        }
        this.db!.commit(); return result.state;
      } catch (error) { this.db!.rollBack(); throw new Error((error as Error).message); }
    } finally { release(); }
  }
  async deleteMaterial(material: Material): Promise<void> {
    const release = await this.lockMutation();
    try {
    this.db!.beginTransaction();
    try {
      await this.db!.executeSql('DELETE FROM events WHERE material=?', [material.key]);
      await this.db!.executeSql('DELETE FROM progress WHERE id=?', [material.key]);
      await this.db!.executeSql('DELETE FROM materials WHERE id=?', [material.key]);
      this.db!.commit();
    } catch (error) { this.db!.rollBack(); throw new Error((error as Error).message); }
    if (material.directory.startsWith(`${this.context.filesDir}/materials/`) && fs.accessSync(material.directory)) { fs.rmdirSync(material.directory); }
    } finally { release(); }
  }
  async clearHistory(material: Material): Promise<void> {
    const release = await this.lockMutation();
    try {
    this.db!.beginTransaction();
    try {
      await this.db!.executeSql('DELETE FROM events WHERE material=?', [material.key]);
      await this.db!.executeSql('DELETE FROM progress WHERE id=?', [material.key]); this.db!.commit();
    } catch (error) { this.db!.rollBack(); throw new Error((error as Error).message); }
    } finally { release(); }
  }
  async saveAs(bytes: Uint8Array, name: string): Promise<boolean> {
    const destination = await new SystemPicker(this.context).save(name);
    if (!destination) { return false; }
    const file = fs.openSync(destination, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { if (fs.writeSync(file.fd, bytes.slice().buffer) !== bytes.byteLength) { throw new Error('The export could not be written completely.'); } fs.fsyncSync(file.fd); } finally { fs.closeSync(file); }
    return true;
  }
  async exportPackage(material: Material): Promise<boolean> {
    const errors = validateManifest(material.manifest);
    if (errors.length) { throw new Error(errors[0]); }
    const files: ArchiveFile[] = [{ name: 'manifest.json', bytes: encode(JSON.stringify(material.manifest)) }];
    for (const asset of material.manifest.assets) {
      const bytes = readBytes(`${material.directory}/${asset.path}`);
      if (await digest(bytes) !== asset.sha256) { throw new Error('Cannot export changed or corrupt assets.'); }
      files.push({ name: asset.path, bytes: bytes });
    }
    return this.saveAs(await packPortable(files, this.context.cacheDir), `${material.diagram.packageId}.touchmap`);
  }
  async exportHistory(material: Material): Promise<boolean> {
    const progress = await this.progress(material);
    return this.saveAs(encode(JSON.stringify(progress, null, 2)), `${material.diagram.packageId}-private-history.json`);
  }
}
