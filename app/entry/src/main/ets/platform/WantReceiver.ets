import { Want } from '@kit.AbilityKit';

/** URI grants remain the caller's responsibility; import validates the file contents. */
export function openedFileUri(want: Want): string {
  if (want.uri) { return compatibleFileUri(want.uri) ? want.uri : ''; }
  const streams = want.parameters?.['ability.params.stream'] as string[] | undefined;
  if (!Array.isArray(streams) || streams.length !== 1 || typeof streams[0] !== 'string') { return ''; }
  return compatibleFileUri(streams[0]) ? streams[0] : '';
}

function compatibleFileUri(uri: string): boolean {
  return uri.length > 7 && uri.length <= 4096 && uri.startsWith('file://') && !/[\u0000-\u001f\u007f]/.test(uri);
}
