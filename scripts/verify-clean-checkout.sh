#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd)
revision=${1:-HEAD}
checkout=$(mktemp -d "${TMPDIR:-/tmp}/touchmap-checkout-XXXXXXXX")
git clone --no-local --quiet "$repository" "$checkout"
git -C "$checkout" checkout --quiet "$revision"
commit=$(git -C "$checkout" rev-parse HEAD)
mkdir -p "$checkout/docs/evidence"
cd "$checkout"
npm ci > docs/evidence/clean-npm.txt 2>&1
npm test >> docs/evidence/clean-npm.txt 2>&1
npm run typecheck >> docs/evidence/clean-npm.txt 2>&1
uv_executable=${TOUCHMAP_UV:-"$HOME/.local/bin/uv"}
test -x "$uv_executable" || uv_executable=uv
(cd backend && "$uv_executable" run --frozen pytest) > docs/evidence/clean-pytest.txt 2>&1
bash scripts/platform.sh build "$checkout" openharmonyApi20 debug > docs/evidence/clean-build-invocation.txt 2>&1
python3 - "$repository" "$checkout" "$commit" <<'PY'
import hashlib,json,sys
from datetime import datetime,timezone
from pathlib import Path
repository,checkout,commit=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
hap=checkout/'dist/touchmap-signed.hap'
native_metadata=json.loads((checkout/'docs/evidence/hap-metadata.json').read_text())
result={'checkedAt':datetime.now(timezone.utc).isoformat(),'commit':commit,
        'method':'Fresh local git clone --no-local; dependencies installed from lockfiles; no credentials copied',
        'checks':{'npmCi':True,'domainTests':True,'typescript':True,'pytest':True,
                  'nativeCleanBuild':True,'signatureVerification':True},
        'signedHapSha256':hashlib.sha256(hap.read_bytes()).hexdigest(),
        'signedHapBytes':hap.stat().st_size,
        'signingNote':'Independent development signing can change the HAP hash. This verifies source reproduction, not byte-identical signatures.',
        'installation':'Separate runtime evidence is required; this script does not modify a device.'}
if 'appSourceSha256' in native_metadata:
    result['appSourceSha256']=native_metadata['appSourceSha256']
    result['sourceFingerprint']=native_metadata['sourceFingerprint']
evidence=repository/'docs/evidence'
for name in ['clean-npm.txt','clean-pytest.txt','clean-build-invocation.txt']:
    (evidence/name).write_bytes((checkout/'docs/evidence'/name).read_bytes())
staged=checkout/'docs/evidence/stage-input-fingerprint.json'
if staged.exists():
    (evidence/'clean-stage-input-fingerprint.json').write_bytes(staged.read_bytes())
(evidence/'clean-checkout.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
PY
printf 'Clean checkout retained at: %s\n' "$checkout"
