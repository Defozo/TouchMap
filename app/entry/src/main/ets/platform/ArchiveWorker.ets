import { taskpool } from '@kit.ArkTS';
import { inflateRaw, crc32 } from '../domain/zip';

@Concurrent
function decodeEntry(input: Uint8Array, method: number, expectedSize: number, expectedCrc: number): Uint8Array {
  const output = method === 0 ? input : inflateRaw(input, expectedSize);
  if (output.length !== expectedSize || crc32(output) !== expectedCrc) { throw new Error('Extracted package size or checksum mismatch.'); }
  return output;
}

// The caller passes an isolated slice. Transferring it cannot detach the archive.
export async function extractEntry(input: Uint8Array, method: number, size: number, crc: number): Promise<Uint8Array> {
  return await taskpool.execute(decodeEntry, input, method, size, crc) as Uint8Array;
}
