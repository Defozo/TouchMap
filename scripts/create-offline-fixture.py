"""Create a fresh-import identity for the unchanged owned water-cycle lesson.

Only package identity/title and the overview target change. Teaching content,
source, recordings and review declarations remain those of the released sample.
This is an explicitly labelled test fixture, not a new author review.
"""
from pathlib import Path
import json
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'backend'))
from touchmap.packages import validate_package, build_package, sha256
from touchmap.models import Diagram

manifest, diagram, _, assets = validate_package((ROOT/'samples/water-cycle.touchmap').read_bytes())
old_id = diagram.packageId
modified = diagram.model_dump()
modified['packageId'] = 'water-cycle-offline-verification'
modified['title'] = 'Water cycle offline check'
for recording in modified['audio']:
    if recording['targetId'] == old_id:
        recording['targetId'] = modified['packageId']
diagram = Diagram.model_validate(modified)
output = ROOT/'docs/evidence/offline-input.touchmap'
data = build_package(diagram, {path:content for path,content in assets.items() if path not in ['manifest.json','diagram.json']},
                     manifest.author.name, manifest.author.declaration, manifest.license, output)
_, _, report, _ = validate_package(data)
(ROOT/'docs/evidence/offline-input.json').write_text(json.dumps({
    'source': 'samples/water-cycle.touchmap', 'packageId': diagram.packageId, 'sha256': sha256(data),
    'changes': ['New test package identity', 'Test material title', 'Overview target bound to test identity'],
    'unchanged': ['geometry', 'source pixels', 'relationships', 'questions', 'audio bytes', 'source review declarations'],
    'validation': report
}, indent=2)+'\n')
print(json.dumps({'output': str(output.relative_to(ROOT)), 'readyOffline': report['readyOffline']}))
