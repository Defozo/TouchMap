"""Read back native private storage after the recorded real WAV-picker flow."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
HDC = str(Path.home() / 'command-line-tools/sdk/default/openharmony/toolchains/hdc')
DEVICE = '127.0.0.1:55555'
def shell(*args):
    return subprocess.check_output([HDC, '-t', DEVICE, 'shell', *args], text=True)
paths = shell('find', '/data/app/el2/100/base/org.touchmap.app/haps/entry/files/materials', '-name', 'diagram.json').splitlines()
found = []
for path in paths:
    diagram = json.loads(shell('cat', path.strip()))
    if diagram['packageId'] != 'material-1791046235553-247866615':
        continue
    for recording in diagram['audio']:
        if recording['provider'] == 'recording' and recording['voice'].startswith('Licensed TouchMap ElevenLabs Bella'):
            destination = ROOT / '.local/native-imported-audio.wav'
            subprocess.run([HDC, '-t', DEVICE, 'file', 'recv', str(Path(path).parent / recording['path']), str(destination)], check=True, capture_output=True)
            content = destination.read_bytes()
            assert hashlib.sha256(content).hexdigest() == recording['sha256']
            assert content == (ROOT / '.local/import-input-1.wav').read_bytes()
            assert recording['durationMs'] == 1115
            found.append({'packageId': diagram['packageId'], 'revision': diagram['revision'], 'recording': recording, 'bytes': len(content)})
assert len(found) == 1, f'Expected exactly one adopted recording, found {len(found)}'
report = {'status': 'passed', 'device': DEVICE,
          'productionHapSha256': '2616f496c2c67ef58a688e494fc8eb8be2090199bc19fdecff63efff84484c54',
          'method': 'Actual native Speech target selection, rights entry, SystemPicker WAV selection, save and playback, followed by independent private-file readback.',
          'recordings': found, 'allImportedBytesMatchLicensedSource': True,
          'nativePlayback': json.loads((ROOT / 'docs/evidence/native-manual-audio-playback.json').read_text()),
          'scope': 'Developer verification on the actual emulator. No new TTS request; recording was retained from the previously licensed native authoring package.'}
(ROOT / 'docs/evidence/native-manual-audio-import.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'status': 'passed', 'recordings': len(found)}))
