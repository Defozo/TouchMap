"""Deterministically bind native HAP evidence to the exact copied app inputs."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ALGORITHM = 'sha256-path-nul-content-sha256-newline-v1'
GENERATED_DIRECTORIES = {'build', '.hvigor', 'oh_modules', '.git', '.oniro'}
GENERATED_FILES = {'local.properties', 'stage-input-fingerprint.json', 'sign.log',
                   'verified-certificate.cer', 'verified-profile.p7b'}
PRIVATE_SIGNING_SUFFIXES = {'.p12', '.pfx', '.jks', '.keystore', '.p7b', '.csr', '.key'}

def fingerprint_app(directory: Path) -> dict:
    directory = directory.resolve(strict=True)
    files = []
    aggregate = hashlib.sha256()
    for path in sorted(directory.rglob('*'), key=lambda value: value.relative_to(directory).as_posix()):
        relative = path.relative_to(directory)
        if any(part in GENERATED_DIRECTORIES for part in relative.parts):
            continue
        if path.name in GENERATED_FILES:
            continue
        if path.suffix.lower() in PRIVATE_SIGNING_SUFFIXES and (len(relative.parts) == 1 or relative.parts[0] == 'signing'):
            continue
        if path.is_symlink():
            raise ValueError(f'App source fingerprint refuses symlink: {relative}')
        if not path.is_file():
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        name = relative.as_posix()
        aggregate.update(name.encode('utf-8') + b'\0' + digest.encode('ascii') + b'\n')
        files.append({'path': name, 'bytes': path.stat().st_size, 'sha256': digest})
    return {'algorithm': ALGORITHM, 'appSourceSha256': aggregate.hexdigest(),
            'appSourceFileCount': len(files), 'appSourceBytes': sum(item['bytes'] for item in files),
            'files': files}

def main():
    if len(sys.argv) not in [2, 4]:
        raise SystemExit('Usage: app_source_fingerprint.py APP_DIR [REPOSITORY OUTPUT_JSON]')
    result = fingerprint_app(Path(sys.argv[1]))
    if len(sys.argv) == 4:
        repository = Path(sys.argv[2])
        result['gitHeadAtBuild'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip()
        result['workingTreeDirty'] = bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=repository, text=True).strip())
        result['snapshot'] = 'Exact copied app files before generated local SDK configuration and signing injection. Git HEAD is recorded separately and may predate uncommitted inputs.'
        Path(sys.argv[3]).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in result.items() if key != 'files'}, indent=2))

if __name__ == '__main__':
    main()
