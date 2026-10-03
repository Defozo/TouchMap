"""Bind measured audio implementation to current source across LF normalization."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    stage = args.stage.resolve()
    paths = ['entry/src/main/ets/platform/Feedback.ets']
    seen = set()
    records = []
    while paths:
        relative = paths.pop()
        if relative in seen:
            continue
        seen.add(relative)
        measured = (stage/relative).read_bytes()
        current = (ROOT/'app'/relative).read_bytes()
        normalized_measured = measured.replace(b'\r\n', b'\n')
        normalized_current = current.replace(b'\r\n', b'\n')
        records.append({'path':relative,'measuredRawSha256':sha(measured),'currentRawSha256':sha(current),
                        'normalizedMeasuredSha256':sha(normalized_measured),'normalizedCurrentSha256':sha(normalized_current),
                        'equalAfterCrLfToLf':normalized_measured == normalized_current})
        for imported in re.findall(r"from\s+['\"]([.][^'\"]+)['\"]", measured.decode()):
            base = (stage/relative).parent/imported
            found = next((Path(str(base)+suffix) for suffix in ['', '.ets','.ts'] if Path(str(base)+suffix).is_file()),None)
            if found is None:
                raise RuntimeError('Unresolved measured dependency: '+imported)
            resolved = found.resolve().relative_to(stage).as_posix()
            if not resolved.startswith('entry/src/main/ets/'):
                raise RuntimeError('Dependency left the expected application source tree.')
            paths.append(resolved)
    artifact = json.loads((ROOT/'docs/evidence/native-audio-test-artifact.json').read_text())
    measured_inputs = json.loads((stage/'stage-input-fingerprint.json').read_text())
    if measured_inputs['appSourceSha256'] != artifact['sourceFingerprint']['appSourceSha256']:
        raise RuntimeError('Requested stage is not the app source bound to the audio measurement.')
    report = {'status':'passed' if all(item['equalAfterCrLfToLf'] for item in records) else 'failed',
              'scope':'Exact Feedback source and recursively resolved relative source dependencies. Only CRLF to LF is normalized; no whitespace, token or behavior differences are ignored. SDK dependencies are pinned separately in toolchain lock.',
              'measuredHapSha256':artifact['productionHapSha256'],
              'measuredAppSourceSha256':measured_inputs['appSourceSha256'],
              'currentGitHead':subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip(),
              'files':sorted(records,key=lambda item:item['path'])}
    (ROOT/'docs/evidence/audio-source-equivalence.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'status':report['status'],'files':len(records)}))
    if report['status'] != 'passed':
        raise SystemExit('Audio implementation or dependency changed beyond line endings.')


if __name__ == '__main__':
    main()
