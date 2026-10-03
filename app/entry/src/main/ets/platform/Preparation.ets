import { tr } from '../domain/i18n';
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { Diagram, Audio } from '../domain/types';
import { validateDiagram } from '../domain/validate';
import { digest, encode, uid } from './Repository';

export interface DraftReport { unsupported: string[]; unresolved: string[]; }
export interface PreparedDraft { diagram: Diagram; report: DraftReport; sourceBase64?: string; previewBase64?: string; }
export interface DraftEnvelope { requestId: string; contractVersion: number; sourceHash: string; draftRevision: number; provider: string; model: string; result: PreparedDraft; }
export interface AudioLabel { targetId: string; kind: string; text: string; textHash: string; }
export interface PreparedAudio extends Audio { dataBase64: string; }
export interface AudioResult { audio: PreparedAudio[]; }
export interface AudioEnvelope { requestId: string; contractVersion: number; sourceHash: string; draftRevision: number; provider: string; model: string; result: AudioResult; }
interface PairResult { token: string; expiresAt: number; }
interface PairRequest { code: string; }
interface AudioRequest { requestId: string; sourceHash: string; draftRevision: number; language: string; consent: boolean; labels: AudioLabel[]; }
export interface SanitizedImage { bytes: Uint8Array; width: number; height: number; }
export interface Crop { x: number; y: number; width: number; height: number; }
interface Field { name: string; value: string; }
let sessionToken: string = '';
let sessionBase: string = '';

export class Preparation {
  base: string = '';
  private connection: http.HttpRequest | undefined = undefined;
  private cancelled: boolean = false;
  requestId: string = '';
  private endpoint(path: string): string {
    const base = this.base.trim().replace(/\/$/, '');
    if (!/^https:\/\/[a-zA-Z0-9.-]+(?::[0-9]+)?(?:\/[a-zA-Z0-9_/-]*)?$/.test(base) && !/^http:\/\/(127\.0\.0\.1|localhost)(:[0-9]+)?$/.test(base)) { throw new Error(tr('tm_a6f6605e8249')); }
    return base + path;
  }
  private async request(path: string, body: string | ArrayBuffer, contentType: string): Promise<string> {
    const connection = http.createHttp(); this.connection = connection;
    try {
      const response = await connection.request(this.endpoint(path), { method: http.RequestMethod.POST,
        header: { 'Content-Type': contentType, 'Authorization': sessionBase === this.base && sessionToken ? `Bearer ${sessionToken}` : '' }, extraData: body,
        connectTimeout: 10000, readTimeout: 45000, expectDataType: http.HttpDataType.STRING });
      if (this.cancelled) { throw new Error(tr('tm_96344a5615b4')); }
      if (response.responseCode !== 200) {
        const labels: Map<number, string> = new Map([[401, tr('tm_3858c76eb824')], [429, tr('tm_5f94c1859c63')], [413, tr('tm_e19af17e3aa2')], [503, tr('tm_554c4ef57e45')], [504, tr('tm_5d6d3d5bfe86')]]);
        throw new Error(labels.get(response.responseCode) || tr('tm_11f6576e2eab', [String(response.responseCode)]));
      }
      if (typeof response.result !== 'string' || response.result.length > 30 * 1024 * 1024) { throw new Error(tr('tm_bfdf95cf54c6')); }
      return response.result;
    } finally { connection.destroy(); if (this.connection === connection) { this.connection = undefined; } }
  }
  async pair(code: string): Promise<void> {
    this.cancelled = false;
    const body: PairRequest = { code: code };
    const result = JSON.parse(await this.request('/v1/sessions/pair', JSON.stringify(body), 'application/json')) as PairResult;
    if (!result.token || result.token.length > 8192) { throw new Error(tr('tm_c0dbdcdbfb30')); }
    sessionToken = result.token; sessionBase = this.base;
  }
  cancel(): void {
    this.cancelled = true;
    const pending = this.connection; this.connection = undefined;
    if (!pending) { return; }
    try { pending.destroy(); } catch (error) {}
    if (this.requestId) {
      const connection = http.createHttp();
      connection.request(this.endpoint(`/v1/jobs/${this.requestId}`), { method: http.RequestMethod.DELETE, header: { 'Authorization': sessionBase === this.base ? `Bearer ${sessionToken}` : '' }, connectTimeout: 5000, readTimeout: 5000 })
        .then(() => { connection.destroy(); }).catch(() => { connection.destroy(); });
    }
  }
  async draft(bytes: Uint8Array, diagram: Diagram, svg: boolean, consent: boolean): Promise<DraftEnvelope> {
    if (!svg && !consent) { throw new Error(tr('tm_3c4a2af806af')); }
    if (bytes.length > 10 * 1024 * 1024) { throw new Error(tr('tm_1e2bc7a7e13e')); }
    this.cancelled = false; this.requestId = uid();
    const hash = await digest(bytes);
    if (this.cancelled) { throw new Error(tr('tm_1611043bad34')); }
    const boundary = `TouchMap${uid()}`;
    const fields: Field[] = [{ name: 'draftRevision', value: String(diagram.revision) }, { name: 'language', value: diagram.language },
      { name: 'requestId', value: this.requestId }, { name: 'sourceHash', value: hash }, { name: 'consent', value: String(consent) }];
    let prefix = '';
    fields.forEach((field: Field) => { prefix += `--${boundary}\r\nContent-Disposition: form-data; name="${field.name}"\r\n\r\n${field.value}\r\n`; });
    prefix += `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="source.${svg ? 'svg' : 'png'}"\r\nContent-Type: ${svg ? 'image/svg+xml' : 'image/png'}\r\n\r\n`;
    const pre = encode(prefix); const post = encode(`\r\n--${boundary}--\r\n`);
    const data = new Uint8Array(pre.length + bytes.length + post.length); data.set(pre); data.set(bytes, pre.length); data.set(post, pre.length + bytes.length);
    const response = JSON.parse(await this.request(svg ? '/v1/import/svg' : '/v1/analyze/image', data.buffer, `multipart/form-data; boundary=${boundary}`)) as DraftEnvelope;
    if (response.requestId !== this.requestId || response.contractVersion !== 1 || response.sourceHash !== hash || response.draftRevision !== diagram.revision) { throw new Error(tr('tm_1638c2874499')); }
    if (!response.result || !response.result.report || !Array.isArray(response.result.report.unsupported) || !Array.isArray(response.result.report.unresolved) ||
      response.result.report.unsupported.some((item: string) => typeof item !== 'string') || response.result.report.unresolved.some((item: string) => typeof item !== 'string') ||
      typeof response.provider !== 'string' || typeof response.model !== 'string') { throw new Error(tr('tm_894e8f35e387')); }
    const errors = validateDiagram(response.result.diagram);
    if (errors.length > 0) { throw new Error(tr('tm_1f30e3eba81e', [String(errors[0])])); }
    return response;
  }
  async speech(diagram: Diagram, labels: AudioLabel[], consent: boolean): Promise<AudioEnvelope> {
    if (!consent) { throw new Error(tr('tm_07c3f5bc0fb3')); }
    this.cancelled = false; this.requestId = uid();
    const request: AudioRequest = { requestId: this.requestId, sourceHash: diagram.source.sha256, draftRevision: diagram.revision, language: diagram.language, consent: true, labels: labels };
    const response = JSON.parse(await this.request('/v1/audio/labels', JSON.stringify(request), 'application/json')) as AudioEnvelope;
    if (response.requestId !== this.requestId || response.contractVersion !== 1 || response.sourceHash !== diagram.source.sha256 || response.draftRevision !== diagram.revision) { throw new Error(tr('tm_89bca1b82d36')); }
    return response;
  }
}
export async function sanitizeImage(bytes: Uint8Array, crop?: Crop): Promise<SanitizedImage> {
  const source = image.createImageSource(bytes.buffer);
  const info = await source.getImageInfo();
  if (info.size.width * info.size.height > 20000000) { source.release(); throw new Error(tr('tm_f370838b58f2')); }
  const pixels = await source.createPixelMap({ editable: true });
  try {
    if (crop) {
      if (![crop.x, crop.y, crop.width, crop.height].every(Number.isFinite) || crop.width < 1 || crop.height < 1 || crop.x < 0 || crop.y < 0 || crop.x + crop.width > info.size.width || crop.y + crop.height > info.size.height) { throw new Error(tr('tm_29bb6bff4c36')); }
      await pixels.crop({ x: crop.x, y: crop.y, size: { width: crop.width, height: crop.height } });
    }
    const packer = image.createImagePacker();
    try {
      const packed = await packer.packing(pixels, { format: 'image/png', quality: 100 });
      if (packed.byteLength > 10 * 1024 * 1024) { throw new Error(tr('tm_b9d324ad619b')); }
      return { bytes: new Uint8Array(packed), width: crop ? crop.width : info.size.width, height: crop ? crop.height : info.size.height };
    } finally { packer.release(); }
  } finally { pixels.release(); source.release(); }
}
export function base64Bytes(text: string): Uint8Array { return new util.Base64Helper().decodeSync(text); }

export async function verifySourcePreview(bytes: Uint8Array, width: number, height: number): Promise<void> {
  const source = image.createImageSource(bytes.buffer);
  try {
    const info = await source.getImageInfo();
    if (info.size.width !== Math.ceil(width) || info.size.height !== Math.ceil(height) || info.size.width * info.size.height > 20000000) { throw new Error(tr('tm_2838a0c29f22')); }
    const pixels = await source.createPixelMap(); pixels.release();
  } finally { source.release(); }
}
