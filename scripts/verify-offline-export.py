"""Independently compare the package exported by the real offline native UI."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from touchmap.packages import validate_package

original = ROOT / 'docs/evidence/offline-input.touchmap'
exported = ROOT / 'docs/evidence/offline-export.touchmap'
_, before, _, before_assets = validate_package(original.read_bytes())
_, after, validation, after_assets = validate_package(exported.read_bytes())
assert before.model_dump() == after.model_dump(), 'Teaching content changed in export'
assert before_assets == after_assets, 'Package assets or manifest changed in export'
assert validation['readyOffline'] and validation['publishable']
report = {
    'verifiedAt': datetime.now(timezone.utc).isoformat(),
    'status': 'passed',
    'inputSha256': hashlib.sha256(original.read_bytes()).hexdigest(),
    'exportSha256': hashlib.sha256(exported.read_bytes()).hexdigest(),
    'archiveBytesIdentical': original.read_bytes() == exported.read_bytes(),
    'allArchiveEntriesIdentical': True,
    'entries': sorted(after_assets),
    'validation': validation,
    'privacy': 'The exported archive contains only the original teaching package entries, no local answers, progress, profile or history.',
    'method': 'System picker export from native app with emulator IPv4/IPv6 outbound blocked. Independent backend validation and byte comparison of every unpacked entry.'
}
(ROOT / 'docs/evidence/offline-export-verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'status': report['status'], 'archiveBytesIdentical': report['archiveBytesIdentical'], 'entries': len(after_assets)}))
