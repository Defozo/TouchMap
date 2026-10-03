"""Bind the manually driven native offline flow to its retained evidence."""
from datetime import datetime, timezone
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/evidence'

def contains(filename, expected):
    data = json.loads((EVIDENCE / filename).read_text())
    assert expected in json.dumps(data), f'{filename} does not prove {expected}'
    return filename

checks = {
    'acceptedMaterial': contains('final-offline-accepted.json', 'Water cycle offline check'),
    'listSelection': contains('final-offline-evaporation.json', 'Evaporation'),
    'directedConnection': contains('final-offline-connection.json', 'Vapour cools into droplets'),
    'explicitSubmission': contains('final-offline-submitted.json', 'Correct'),
    'savedContextAfterForceStop': contains('final-offline-resume.json', 'Your selection is saved but not submitted'),
    'unfinishedSelectionRestored': contains('final-offline-resumed-selection.json', 'Selected: Collection'),
    'ordinaryTouchFirstRegion': contains('final-offline-touch-evaporation.json', 'Evaporation'),
    'ordinaryTouchSecondRegion': contains('final-offline-touch-precipitation.json', 'Precipitation'),
    'systemPickerExport': contains('final-offline-export.json', 'Teaching package exported'),
    'independentPackageValidation': contains('offline-export-verification.json', 'passed'),
}
network = json.loads((EVIDENCE / 'offline-on.json').read_text())
assert '-A TM_OFFLINE -j DROP' in network['ipv4'] and '-A TM_OFFLINE -j DROP' in network['ipv6']
audio = json.loads((ROOT / 'dist/demo-touch-raw.sync.json').read_text())
report = {
    'recordedAt': datetime.now(timezone.utc).isoformat(), 'status': 'passed',
    'device': '127.0.0.1:55555',
    'productionHapSha256': '2616f496c2c67ef58a688e494fc8eb8be2090199bc19fdecff63efff84484c54',
    'appSourceSha256': 'a5467e3eafae0f2638f3e16465e0397d31f92bc3e98e63b830f7637b3c1cbefe',
    'network': {'enabledEvidence': 'offline-on.json', 'restoredEvidence': 'offline-off.json', 'scope': network['scope']},
    'checks': checks,
    'touchMethod': 'Actual uitest longClick at visually inspected region centers on native Canvas. Native selected labels changed from Condensation to Evaporation, then Precipitation. This is ordinary touch, not genuine screen-reader hover.',
    'audioCapture': audio,
    'limitations': ['No physical speaker or headphone measurement.', 'No genuine screen reader available on this emulator.', 'Later source changes require their separately documented final-build verification.']
}
(EVIDENCE / 'final-offline-flow.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'status': report['status'], 'checks': len(checks)}))
