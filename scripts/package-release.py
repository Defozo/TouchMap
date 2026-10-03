"""Create a reproducible local review bundle from a frozen Git commit and verified artifacts.

No publication, repository mutation or competition submission is performed.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
_FINGERPRINT_SPEC = importlib.util.spec_from_file_location('release_app_fingerprint', ROOT/'scripts/app_source_fingerprint.py')
_FINGERPRINT = importlib.util.module_from_spec(_FINGERPRINT_SPEC)
_FINGERPRINT_SPEC.loader.exec_module(_FINGERPRINT)
REQUIRED = [
    'README.md', 'ARCHITECTURE.md', 'AI_WORKFLOW.md', 'AI_INTEGRATION.md',
    'THIRD_PARTY.md', 'LICENSE', 'TEAM.json', 'SUBMISSION.md', 'toolchain.lock.json',
    'docs/TEST_REPORT.md', 'docs/PRIVACY.md', 'docs/ACCESSIBILITY.md',
    'docs/platform.md', 'docs/backend.md', 'contracts/CONTRACT.md',
    'contracts/diagram.schema.json', 'contracts/manifest.schema.json',
    'app/oh-package-lock.json5', 'backend/uv.lock', 'package-lock.json',
    'samples/LICENSE.md', 'samples/water-cycle.touchmap', 'samples/lumina-process.touchmap',
    'samples/rainfall-chart.touchmap', 'samples/tutorial.touchmap',
    'docs/evidence/demo-manifest.json', 'docs/demo-storyboard.json',
]
TOP_DOCS = ['README.md', 'ARCHITECTURE.md', 'AI_WORKFLOW.md', 'AI_INTEGRATION.md',
            'THIRD_PARTY.md', 'LICENSE', 'TEAM.json', 'SUBMISSION.md', 'toolchain.lock.json']


def canonical_json(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode('utf-8')


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def committed_app_fingerprint(files: dict[str, bytes]) -> str:
    """The same path/content algorithm as the build, over committed archive bytes."""
    aggregate = hashlib.sha256()
    for full_name, data in sorted(files.items()):
        if not full_name.startswith('app/'):
            continue
        path = PurePosixPath(full_name[4:])
        if any(part in _FINGERPRINT.GENERATED_DIRECTORIES for part in path.parts) or path.name in _FINGERPRINT.GENERATED_FILES:
            continue
        if path.suffix.lower() in _FINGERPRINT.PRIVATE_SIGNING_SUFFIXES and (len(path.parts) == 1 or path.parts[0] == 'signing'):
            continue
        aggregate.update(path.as_posix().encode('utf-8') + b'\0' + sha256(data).encode('ascii') + b'\n')
    return aggregate.hexdigest()


def git(root: Path, *arguments: str) -> bytes:
    return subprocess.check_output(['git', *arguments], cwd=root, stderr=subprocess.PIPE)


def source_files(root: Path, commit: str) -> dict[str, bytes]:
    files = {}
    raw = git(root, 'archive', '--format=tar', commit)
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        for member in archive:
            if member.isdir():
                continue
            path = PurePosixPath(member.name)
            if not member.isfile() or path.is_absolute() or '..' in path.parts or '\\' in member.name:
                raise ValueError(f'Nonportable source archive entry: {member.name}')
            if path.name.startswith('.env') and path.name != '.env.example' or path.suffix.lower() in {'.p12', '.p7b', '.jks', '.keystore', '.key', '.pem'} or any(part in {'.psst', '.state', '.git'} for part in path.parts):
                raise ValueError(f'Private configuration is tracked in the selected commit: {member.name}')
            files[member.name] = archive.extractfile(member).read()
    return files


def deterministic_zip(files: dict[str, bytes]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            # Shell entrypoints retain executability in the nested source bundle.
            info.external_attr = (0o100755 if name.endswith('.sh') else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return output.getvalue()


def inspect_demo(path: Path) -> dict:
    executable = shutil.which('ffprobe')
    if not executable:
        raise ValueError('ffprobe is required to verify the demonstration media; install FFmpeg')
    result = subprocess.run([executable, '-v', 'error', '-show_entries',
                             'format=duration:stream=codec_type,codec_name,width,height',
                             '-of', 'json', str(path)], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise ValueError('Demonstration is not readable media')
    metadata = json.loads(result.stdout)
    if not any(stream.get('codec_type') == 'video' for stream in metadata.get('streams', [])) or float(metadata.get('format', {}).get('duration', 0)) <= 0:
        raise ValueError('Demonstration must contain a nonempty video stream')
    return metadata


def prepare(root: Path, commit: str, hap: Path, demo: Path, verification: Path,
            require_all_gates: bool = False) -> tuple[dict, dict[str, bytes]]:
    failures = []
    try:
        resolved = git(root, 'rev-parse', '--verify', f'{commit}^{{commit}}').decode().strip()
        if git(root, 'rev-parse', 'HEAD').decode().strip() != resolved:
            failures.append('HEAD must equal the selected release commit')
        if git(root, 'status', '--porcelain', '--untracked-files=no').strip():
            failures.append('Tracked source files differ from the selected commit; freeze them first')
        files = source_files(root, resolved)
    except (ValueError, subprocess.CalledProcessError) as error:
        return {'status': 'failed', 'failures': [str(error)], 'competitionSubmitted': False}, {}
    failures.extend(f'Missing committed file: {path}' for path in REQUIRED if path not in files)
    for label, path in [('signed HAP', hap), ('English demonstration video', demo), ('release verification', verification)]:
        if not path.is_file() or path.stat().st_size == 0:
            failures.append(f'Missing or empty {label}: {path.name}')
    if failures:
        return {'status': 'failed', 'sourceCommit': resolved, 'failures': failures, 'competitionSubmitted': False}, {}

    try:
        team = json.loads(files['TEAM.json'])
        if not team.get('team_name') or not team.get('members') or team.get('human_member_count') != len(team['members']):
            raise ValueError('Committed TEAM.json is incomplete or internally inconsistent')
        for name in ['README.md', 'SUBMISSION.md', 'LICENSE']:
            text = files[name].decode('utf-8')
            if team['team_name'] not in text or any(member not in text for member in team['members']):
                raise ValueError(f'Team attribution differs in committed {name}')
        report = json.loads(verification.read_bytes())
        hap_bytes = hap.read_bytes()
        if report.get('sourceCommit') != resolved:
            raise ValueError('Release verification is for a different source commit')
        if report.get('artifactFailures'):
            raise ValueError('Release verification records artifact failures')
        if report.get('team') != team:
            raise ValueError('Release verification team differs from the committed TEAM.json')
        if report.get('hap', {}).get('sha256') != sha256(hap_bytes):
            raise ValueError('Signed HAP hash differs from release verification')
        app_fingerprint = committed_app_fingerprint(files)
        if report.get('hap', {}).get('appSourceSha256') != app_fingerprint:
            raise ValueError('Signed HAP build inputs differ from the committed app source fingerprint')
        checked_samples = {sample['file']: sample['sha256'] for sample in report.get('samples', [])}
        for name, data in files.items():
            if name.startswith('samples/') and name.endswith('.touchmap') and checked_samples.get(PurePosixPath(name).name) != sha256(data):
                raise ValueError(f'Committed sample differs from release verification: {name}')
        with zipfile.ZipFile(io.BytesIO(hap_bytes)) as archive:
            metadata = json.loads(archive.read('module.json'))['app']
        if metadata.get('bundleName') != 'org.touchmap.app' or metadata.get('minAPIVersion') != 20:
            raise ValueError('Unexpected native HAP identity or minimum API')
        outstanding = report.get('outstandingGates')
        if not isinstance(outstanding, list) or not isinstance(report.get('gates'), dict):
            raise ValueError('Release verification must declare gates and outstandingGates')
        computed = sorted(key for key, value in report['gates'].items() if value.get('status') != 'passed')
        if sorted(outstanding) != computed:
            raise ValueError('Release verification gate summary is inconsistent')
        if require_all_gates and outstanding:
            raise ValueError('Required release gates are outstanding: ' + ', '.join(outstanding))
        demo_metadata = inspect_demo(demo)
        # Use the verified bytes once. They are hashed and archived together.
        demo_bytes = demo.read_bytes()
        demo_review = json.loads(files['docs/evidence/demo-manifest.json'])
        if demo_review.get('reviewed') is not True:
            raise ValueError('Demonstration has no completed committed review')
        if demo_review.get('videoSha256') != sha256(demo_bytes):
            raise ValueError('Demonstration hash differs from the reviewed committed manifest')
        if demo_review.get('storyboardSha256') != sha256(files['docs/demo-storyboard.json']):
            raise ValueError('Committed storyboard differs from the reviewed demonstration')
        if abs(float(demo_review.get('durationSeconds', 0)) - float(demo_metadata['format']['duration'])) > 0.1:
            raise ValueError('Demonstration duration differs from the reviewed committed manifest')
        bundle = {'source.zip': deterministic_zip(files), 'touchmap-signed.hap': hap_bytes,
                  'demo/touchmap-demo.mp4': demo_bytes, 'release-verification.json': canonical_json(report)}
        for name, data in files.items():
            if (name in TOP_DOCS or name.startswith(('docs/', 'licenses/', 'assets/brand/', 'contracts/'))
                    or name == 'backend/touchmap/assets/DejaVu-LICENSE.txt'
                    or name.startswith('samples/') and (name.endswith('.touchmap') or name == 'samples/LICENSE.md')):
                bundle[name] = data
        environment = {'sourceCommit': resolved, 'sourceTree': git(root, 'rev-parse', f'{resolved}^{{tree}}').decode().strip(),
                       'sourceCommitEpoch': int(git(root, 'show', '-s', '--format=%ct', resolved)),
                       'appSourceSha256': app_fingerprint, 'appSourceFingerprintAlgorithm': _FINGERPRINT.ALGORITHM,
                       'buildInputGitHead': report['hap'].get('buildInputGitHead'),
                       'toolchain': json.loads(files['toolchain.lock.json']),
                       'packagingRuntime': {'python': '.'.join(map(str, sys.version_info[:3])), 'zlib': zlib.ZLIB_RUNTIME_VERSION},
                       'archivePolicy': 'Sorted UTF-8 paths, fixed ZIP timestamp 1980-01-01, DEFLATE level 9',
                       'sourcePolicy': 'Every source byte comes from git archive of sourceCommit; local untracked files are excluded'}
        bundle['environment-manifest.json'] = canonical_json(environment)
        manifest = {'formatVersion': 1, 'project': 'TouchMap', 'challenge': "IMAGINE WHAT'S NEXT",
                    'sourceCommit': resolved, 'team': team, 'demo': demo_metadata,
                    'publicRepositoryUrl': report.get('publicRepositoryUrl'),
                    'publicReleaseUrl': report.get('publicReleaseUrl'),
                    'officialSubmission': report.get('officialSubmission'),
                    'outstandingGates': outstanding, 'allGatesPassed': not outstanding,
                    'competitionSubmitted': False,
                    'artifacts': [{'path': name, 'bytes': len(data), 'sha256': sha256(data)} for name, data in sorted(bundle.items())]}
        bundle['release-manifest.json'] = canonical_json(manifest)
        bundle['SHA256SUMS'] = ''.join(f'{sha256(data)}  {name}\n' for name, data in sorted(bundle.items())).encode()
        return {'status': 'ready', 'sourceCommit': resolved, 'failures': [], 'outstandingGates': outstanding,
                'files': len(bundle), 'competitionSubmitted': False}, bundle
    except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile, subprocess.TimeoutExpired) as error:
        return {'status': 'failed', 'sourceCommit': resolved, 'failures': [str(error)], 'competitionSubmitted': False}, {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commit', required=True, help='Frozen source commit; must match HEAD and release-verification.json')
    parser.add_argument('--hap', type=Path, default=ROOT/'dist/touchmap-signed.hap')
    parser.add_argument('--demo', type=Path, default=ROOT/'dist/touchmap-demo.mp4')
    parser.add_argument('--verification', type=Path, default=ROOT/'dist/release-verification.json')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--check-only', action='store_true', help='Print all preflight failures without creating an archive')
    parser.add_argument('--require-all-gates', action='store_true', help='Disallow a review bundle with explicitly outstanding release gates')
    args = parser.parse_args()
    report, files = prepare(ROOT, args.commit, args.hap, args.demo, args.verification, args.require_all_gates)
    if report['failures']:
        print(json.dumps(report, indent=2, ensure_ascii=False)); return 1
    if not args.check_only:
        output = args.output or ROOT/f'dist/touchmap-release-{report["sourceCommit"][:12]}.zip'
        archive = deterministic_zip(files)
        if output.exists() and output.read_bytes() != archive:
            report['status'] = 'failed'; report['failures'] = ['Output already exists with different bytes; choose a new --output path']
            print(json.dumps(report, indent=2, ensure_ascii=False)); return 1
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            if not output.exists():
                staging = output.with_suffix(output.suffix+'.partial')
                with staging.open('xb') as handle:
                    handle.write(archive); handle.flush(); os.fsync(handle.fileno())
                staging.replace(output)
            output.with_suffix(output.suffix+'.sha256').write_text(f'{sha256(archive)}  {output.name}\n', encoding='utf-8')
        except OSError as error:
            report['status'] = 'failed'; report['failures'] = [f'Cannot write release archive: {error}']
            print(json.dumps(report, indent=2, ensure_ascii=False)); return 1
        report.update({'archive': output.name, 'sha256': sha256(archive), 'bytes': len(archive)})
    print(json.dumps(report, indent=2, ensure_ascii=False)); return 0


if __name__ == '__main__':
    raise SystemExit(main())
