"""Validate release bytes and report declared evidence gates without inventing them."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
from touchmap.packages import validate_package
from app_source_fingerprint import fingerprint_app
from presentation_artifacts import MANIFEST, reviewed_presentation


def verify_presentation(root, commit, gates):
    committed = subprocess.run(['git', 'show', f'{commit}:{MANIFEST}'], cwd=root, capture_output=True)
    metadata, _ = reviewed_presentation(root, {MANIFEST: committed.stdout} if committed.returncode == 0 else {})
    if metadata is None and 'finalEnglishPresentation' in gates:
        raise ValueError('Declared presentation gate requires a committed reviewed presentation manifest')
    return metadata

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-all-gates', action='store_true')
    args = parser.parse_args()
    required = ['README.md', 'ARCHITECTURE.md', 'AI_WORKFLOW.md', 'AI_INTEGRATION.md',
                'THIRD_PARTY.md', 'LICENSE', 'TEAM.json', 'SUBMISSION.md', 'toolchain.lock.json',
                'docs/TEST_REPORT.md', 'docs/PRIVACY.md', 'docs/ACCESSIBILITY.md',
                'docs/platform.md', 'docs/backend.md', 'contracts/CONTRACT.md',
                'contracts/diagram.schema.json', 'contracts/manifest.schema.json',
                'app/oh-package-lock.json5', 'backend/uv.lock', 'package-lock.json']
    failures = [f'Missing {p}' for p in required if not (ROOT / p).is_file()]
    team = json.loads((ROOT / 'TEAM.json').read_text(encoding='utf-8'))
    for name in ['README.md', 'SUBMISSION.md', 'LICENSE']:
        content = (ROOT / name).read_text(encoding='utf-8')
        if team['team_name'] not in content or any(member not in content for member in team['members']):
            failures.append(f'Team attribution differs in {name}')
    samples = []
    for path in sorted((ROOT / 'samples').glob('*.touchmap')):
        try:
            manifest, diagram, report, assets = validate_package(path.read_bytes())
            samples.append({'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'report': report})
            if not report['publishable'] or not report['readyOffline']:
                failures.append(f'{path.name} is not reviewed and ready offline')
        except Exception as error:
            failures.append(f'{path.name}: {error}')
    hap = ROOT / 'dist/touchmap-signed.hap'
    hap_info = None
    if not hap.exists():
        failures.append('Missing signed HAP')
    else:
        with zipfile.ZipFile(hap) as archive:
            metadata = json.loads(archive.read('module.json'))
        native = metadata['app']
        hap_info = {'sha256': hashlib.sha256(hap.read_bytes()).hexdigest(), 'bytes': hap.stat().st_size,
                    'bundleName': native['bundleName'], 'minimumApi': native['minAPIVersion'], 'targetApi': native['targetAPIVersion']}
        if native['bundleName'] != 'org.touchmap.app' or int(native['minAPIVersion']) != 20:
            failures.append('Unexpected HAP identity or minimum API')
        saved = ROOT / 'docs/evidence/hap-metadata.json'
        native_evidence = json.loads(saved.read_text()) if saved.exists() else {}
        if native_evidence.get('sha256') != hap_info['sha256']:
            failures.append('HAP does not match verification evidence')
        current_inputs = fingerprint_app(ROOT / 'app')
        if native_evidence.get('appSourceSha256') != current_inputs['appSourceSha256']:
            failures.append('HAP build inputs do not match the current app source fingerprint')
        hap_info['appSourceSha256'] = native_evidence.get('appSourceSha256')
        hap_info['buildInputGitHead'] = native_evidence.get('sourceFingerprint', {}).get('gitHeadAtBuild')
    gates_path = ROOT / 'docs/evidence/release-gates.json'
    gates = json.loads(gates_path.read_text(encoding='utf-8')) if gates_path.exists() else {'evidenceManifest': {'status': 'pending'}}
    outstanding = [key for key, value in gates.items() if value.get('status') != 'passed']
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    presentation = None
    try:
        presentation = verify_presentation(ROOT, commit, gates)
    except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        failures.append(f'Presentation: {error}')
    result = {'team': team, 'sourceCommit': commit, 'presentation': presentation,
              'hap': hap_info, 'samples': samples, 'artifactFailures': failures, 'gates': gates,
              'outstandingGates': outstanding, 'competitionSubmitted': False}
    (ROOT / 'dist').mkdir(exist_ok=True)
    (ROOT / 'dist/release-verification.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps({'artifactFailures': failures, 'outstandingGates': outstanding, 'sampleCount': len(samples)}, indent=2))
    raise SystemExit(1 if failures or (args.require_all_gates and outstanding) else 0)

if __name__ == '__main__':
    main()
