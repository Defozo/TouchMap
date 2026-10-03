import { describe, it, expect, beforeAll, afterAll } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import { nativeContext } from '../testrunner/NativeContext';
import { packPortable, ArchiveFile } from '../../../main/ets/platform/PackageExporter';
import { inspectZip, encode, digest, uid } from '../../../main/ets/platform/Repository';
import { extractEntry } from '../../../main/ets/platform/ArchiveWorker';

export default function packageExporterSuite(): void {
  describe('TouchMapPackageExporter', () => {
    let cache: string;
    beforeAll(async () => {
      const context = await nativeContext();
      cache = `${context.cacheDir}/exporter-test-${uid()}`;
      fs.mkdirSync(cache, true);
    });
    afterAll(() => { if (cache && fs.accessSync(cache)) { fs.rmdirSync(cache); } });

    it('native_compression_roundtrips_root_paths_crc_and_repetitive_content', 0, async () => {
      const patterned = new Uint8Array(128 * 1024);
      for (let i = 0; i < patterned.length; i++) { patterned[i] = i % 251; }
      const files: ArchiveFile[] = [
        {name:'manifest.json',bytes:encode('{"format":"touchmap"}')},
        {name:'diagram.json',bytes:encode('{"title":"Michał"}')},
        {name:'audio/powtórzenie.wav',bytes:new Uint8Array(2 * 1024 * 1024)},
        {name:'source/pattern.bin',bytes:patterned}
      ];
      const bytes = await packPortable(files, cache);
      const entries = inspectZip(bytes);
      expect(entries.length).assertEqual(files.length);
      expect(bytes.length < 1024 * 1024).assertTrue();
      for (let i = 0; i < files.length; i++) {
        const entry = entries[i];
        expect(entry.path).assertEqual(files[i].name);
        const restored = await extractEntry(bytes.slice(entry.offset, entry.offset + entry.compressed), entry.method, entry.expanded, entry.crc);
        expect(await digest(restored)).assertEqual(await digest(files[i].bytes));
      }
      expect(fs.listFileSync(cache).length).assertEqual(0);
    });

    it('native_export_handles_more_than_50MiB_expanded_with_portable_ratio', 0, async () => {
      // Best compression exceeds the 200:1 import policy for this repeating
      // alphabet. Huffman-only would exceed 50 MiB; fast DEFLATE fits both limits.
      const phaseAt = Date.now();
      console.info(`TOUCHMAP_EXPORT_TEST_PHASE fixture_begin ms=${Date.now()-phaseAt}`);
      const content = new Uint8Array(18 * 1024 * 1024);
      // Preserve i & 255 exactly without an 18-million-iteration UI-thread loop.
      const block = new Uint8Array(1024 * 1024);
      for (let i = 0; i < 256; i++) { block[i] = i; }
      for (let filled = 256; filled < block.length; filled *= 2) { block.set(block.subarray(0, filled), filled); }
      for (let offset = 0; offset < content.length; offset += block.length) {
        content.set(block, offset);
        await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
      }
      console.info(`TOUCHMAP_EXPORT_TEST_PHASE fixture_end ms=${Date.now()-phaseAt}`);
      expect(await digest(content)).assertEqual('0b90571decc49a1bd765fcb126a0f2d945c20cf82b3bab6ec796e697bf269dbe');
      const files: ArchiveFile[] = [
        {name:'manifest.json',bytes:encode('{}')}, {name:'diagram.json',bytes:encode('{}')},
        {name:'audio/a.wav',bytes:content}, {name:'audio/b.wav',bytes:content}, {name:'audio/c.wav',bytes:content}
      ];
      console.info(`TOUCHMAP_EXPORT_TEST_PHASE pack_begin ms=${Date.now()-phaseAt}`);
      const bytes = await packPortable(files, cache);
      console.info(`TOUCHMAP_EXPORT_TEST_PHASE pack_end ms=${Date.now()-phaseAt}`);
      const entries = inspectZip(bytes);
      expect(entries.reduce((total, entry) => total + entry.expanded, 0) > 50 * 1024 * 1024).assertTrue();
      expect(bytes.length < 50 * 1024 * 1024).assertTrue();
      expect(entries.length).assertEqual(5);
      expect(fs.listFileSync(cache).length).assertEqual(0);
    });

    it('native_export_rejects_unsafe_duplicate_and_noncanonical_required_paths', 0, async () => {
      const badPaths = ['../escape', 'audio/CON.wav', 'audio/../escape', 'MANIFEST.JSON'];
      for (const path of badPaths) {
        let rejected = false;
        try {
          await packPortable([{name:path,bytes:encode('{}')},{name:'diagram.json',bytes:encode('{}')}], cache);
        } catch (error) { rejected = true; }
        expect(rejected).assertTrue();
      }
      let duplicateRejected = false;
      try {
        await packPortable([{name:'manifest.json',bytes:encode('{}')},{name:'diagram.json',bytes:encode('{}')},
          {name:'audio/a.wav',bytes:new Uint8Array(1)},{name:'audio/A.wav',bytes:new Uint8Array(1)}], cache);
      } catch (error) { duplicateRejected = true; }
      expect(duplicateRejected).assertTrue();
      expect(fs.listFileSync(cache).length).assertEqual(0);
    });
  });
}
