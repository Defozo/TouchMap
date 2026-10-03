"""Expose an existing licensed recording for a real native system-picker test."""
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
with zipfile.ZipFile(ROOT / 'docs/evidence/native-authored.touchmap') as archive:
    diagram = json.loads(archive.read('diagram.json'))
    region = next(r for r in diagram['regions'] if r['label'] == 'Input 1')
    recording = next(a for a in diagram['audio'] if a['targetId'] == region['id'] and a['kind'] == 'label')
    output = ROOT / '.local/import-input-1.wav'
    output.write_bytes(archive.read(recording['path']))
    (ROOT / 'docs/evidence/native-audio-picker-fixture.json').write_text(json.dumps({
        'source': 'docs/evidence/native-authored.touchmap', 'label': 'Input 1',
        'recording': recording, 'purpose': 'Actual native picker import of the same licensed label, not new synthesis.'
    }, indent=2) + '\n')
    print(json.dumps({'filename': output.name, 'recording': recording}))
