import { tr } from '../domain/i18n';
import { fileIo as fs } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { safePath } from '../domain/validate';
export interface ArchiveFile { name: string; bytes: Uint8Array; }
interface CompressedEntry { name: Uint8Array; data: Uint8Array; size: number; crc: number; method: number; offset: number; }
function write(path: string, bytes: Uint8Array): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { if (fs.writeSync(file.fd, bytes.slice().buffer) !== bytes.length) { throw new Error(tr('tm_a4ce824f7af5')); } fs.fsyncSync(file.fd); } finally { fs.closeSync(file); }
}
function read(path: string): Uint8Array {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size = fs.statSync(file.fd).size; if (size > 50 * 1024 * 1024) { throw new Error(tr('tm_27020c7859b2')); }
    const bytes = new Uint8Array(size); let offset = 0;
    while (offset < size) {
      const part = new ArrayBuffer(size - offset); const got = fs.readSync(file.fd, part, { offset: offset });
      if (got === 0) { throw new Error(tr('tm_1faa45aefed0')); }
      bytes.set(new Uint8Array(part, 0, got), offset); offset += got;
    }
    return bytes;
  } finally { fs.closeSync(file); }
}
function compressedEntry(archive: Uint8Array, name: Uint8Array, size: number): CompressedEntry {
  const view = new DataView(archive.buffer); let end = -1;
  for (let offset = archive.length - 22; offset >= Math.max(0, archive.length - 65557); offset--) { if (view.getUint32(offset, true) === 0x06054b50 && offset + 22 + view.getUint16(offset + 20, true) === archive.length) { end = offset; break; } }
  if (end < 0 || view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0 || view.getUint16(end + 8, true) !== 1 || view.getUint16(end + 10, true) !== 1) { throw new Error(tr('tm_75cbf3dc417f')); }
  const central = view.getUint32(end + 16, true);
  if (central + 46 > end || central + view.getUint32(end + 12, true) !== end || view.getUint32(central, true) !== 0x02014b50 || view.getUint32(central + 24, true) !== size) { throw new Error(tr('tm_df475fec3a0f')); }
  const method = view.getUint16(central + 10, true), compressed = view.getUint32(central + 20, true), local = view.getUint32(central + 42, true);
  const flags = view.getUint16(central + 8, true);
  if ((flags & 1) !== 0 || (method !== 0 && method !== 8) || local + 30 > central || view.getUint32(local, true) !== 0x04034b50 || view.getUint16(local + 8, true) !== method || view.getUint16(local + 6, true) !== flags) { throw new Error(tr('tm_c4bd04c5712c')); }
  const payload = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
  if (payload + compressed > central) { throw new Error(tr('tm_2a829bf60ab4')); }
  return {name:name,data:archive.slice(payload,payload+compressed),size:size,crc:view.getUint32(central+16,true),method:method,offset:0};
}
export async function packPortable(files: ArchiveFile[], cacheDir: string): Promise<Uint8Array> {
  if (files.length < 2 || files.length > 1000) { throw new Error(tr('tm_940938e8f655')); }
  const names: string[] = []; let expanded = 0;
  for (const file of files) {
    if (!safePath(file.name) || names.includes(file.name.toLowerCase()) || file.bytes.length > 50 * 1024 * 1024) { throw new Error(tr('tm_95cf48d80039')); }
    names.push(file.name.toLowerCase()); expanded += file.bytes.length;
  }
  if (expanded > 200 * 1024 * 1024 || !files.some((file: ArchiveFile) => file.name === 'manifest.json') || !files.some((file: ArchiveFile) => file.name === 'diagram.json')) { throw new Error(tr('tm_3223e544b119')); }
  const root = `${cacheDir}/portable-export-${Date.now()}-${Math.floor(Math.random()*1000000000)}`;
  fs.mkdirSync(root, true); const entries: CompressedEntry[] = []; const encoder = new util.TextEncoder(); let size = 22;
  try {
    for (const file of files) {
      write(`${root}/input.bin`, file.bytes);
      const archivePath = `${root}/compressed.zip`; if (fs.accessSync(archivePath)) { fs.unlinkSync(archivePath); }
      await zlib.compressFile(`${root}/input.bin`, archivePath, { level: zlib.CompressLevel.COMPRESS_LEVEL_BEST_COMPRESSION });
      let entry = compressedEntry(read(archivePath), encoder.encodeInto(file.name), file.bytes.length);
      // Match the importer's expansion policy even for highly repetitive valid data.
      if (entry.size > Math.max(1024*1024,entry.data.length*200)) {
        fs.unlinkSync(archivePath);
        // Fast compression retains back-references but usually has a lower ratio.
        // Trying it first avoids inflating patterned recordings with Huffman-only.
        await zlib.compressFile(`${root}/input.bin`, archivePath, { level: zlib.CompressLevel.COMPRESS_LEVEL_BEST_SPEED });
        entry = compressedEntry(read(archivePath), encoder.encodeInto(file.name), file.bytes.length);
      }
      if (entry.size > Math.max(1024*1024,entry.data.length*200)) {
        fs.unlinkSync(archivePath);
        await zlib.compressFile(`${root}/input.bin`, archivePath, { strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_HUFFMAN_ONLY });
        entry = compressedEntry(read(archivePath), encoder.encodeInto(file.name), file.bytes.length);
      }
      if (entry.size > Math.max(1024*1024,entry.data.length*200)) { throw new Error(tr('tm_a7b56ce78078')); }
      entries.push(entry); size += 76 + entry.name.length*2 + entry.data.length;
      if (size > 50*1024*1024) { throw new Error(tr('tm_7c6be2c28c6c')); }
    }
    const bytes = new Uint8Array(size); const view = new DataView(bytes.buffer); let cursor = 0;
    for (const entry of entries) {
      entry.offset=cursor; view.setUint32(cursor,0x04034b50,true); view.setUint16(cursor+4,20,true); view.setUint16(cursor+6,0x800,true); view.setUint16(cursor+8,entry.method,true);
      view.setUint32(cursor+14,entry.crc,true); view.setUint32(cursor+18,entry.data.length,true); view.setUint32(cursor+22,entry.size,true); view.setUint16(cursor+26,entry.name.length,true);
      bytes.set(entry.name,cursor+30); bytes.set(entry.data,cursor+30+entry.name.length); cursor+=30+entry.name.length+entry.data.length;
    }
    const central=cursor;
    for (const entry of entries) {
      view.setUint32(cursor,0x02014b50,true); view.setUint16(cursor+4,20,true); view.setUint16(cursor+6,20,true); view.setUint16(cursor+8,0x800,true); view.setUint16(cursor+10,entry.method,true);
      view.setUint32(cursor+16,entry.crc,true); view.setUint32(cursor+20,entry.data.length,true); view.setUint32(cursor+24,entry.size,true); view.setUint16(cursor+28,entry.name.length,true); view.setUint32(cursor+42,entry.offset,true);
      bytes.set(entry.name,cursor+46); cursor+=46+entry.name.length;
    }
    view.setUint32(cursor,0x06054b50,true); view.setUint16(cursor+8,entries.length,true); view.setUint16(cursor+10,entries.length,true); view.setUint32(cursor+12,cursor-central,true); view.setUint32(cursor+16,central,true);
    return bytes;
  } finally { if (fs.accessSync(root)) { fs.rmdirSync(root); } }
}
