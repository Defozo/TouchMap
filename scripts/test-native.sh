#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd)
target=${1:?HDC target required}
build_dir=$(cat "$repository/.native-build-path")
test -d "$build_dir" || { echo 'Build the native app first.' >&2; exit 2; }
command_tools=${ONIRO_CMD_TOOLS_PATH:-"$HOME/command-line-tools"}
hdc="$command_tools/sdk/default/openharmony/toolchains/hdc"
cd "$build_dir"
# hvigor 5.18.5 registers ohosTest under the default product. Both product
# profiles declare the same OpenHarmony API 20 SDK and normal app signature.
"$command_tools/bin/hvigorw" assembleHap --mode module -p product=default -p module=entry@ohosTest -p isOhosTest=true -p buildMode=test --no-daemon > "$repository/docs/evidence/native-test-build.log" 2>&1
hap=$(find entry/build -path '*/ohosTest/*' -name '*-signed.hap' -type f -print -quit)
test -n "$hap" || { echo 'No signed native test HAP produced.' >&2; exit 3; }
cp "$hap" "$repository/dist/touchmap-tests-signed.hap"
"$hdc" -t "$target" install "$hap"
# Official arkXtest test-mode setting, on the explicitly selected development
# target. Start the daemon after compilation because it times out without a client.
"$hdc" -t "$target" shell param set persist.ace.testmode.enabled 1
"$hdc" -t "$target" shell aa force-stop org.touchmap.app
"$hdc" -t "$target" shell uitest start-daemon default
"$hdc" -t "$target" shell aa test -b org.touchmap.app -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 30000 -w 120000 | tee "$repository/docs/evidence/native-test-results.txt"
python3 - "$repository/docs/evidence/native-test-results.txt" "$repository" "$build_dir" "$target" <<'PY'
import hashlib,json,re,sys
from datetime import datetime,timezone
from pathlib import Path
text=Path(sys.argv[1]).read_text()
match=re.search(r'Tests run: (\d+), Failure: (\d+), Error: (\d+), Pass: (\d+)',text)
passed=bool(match and int(match[1])>0 and not int(match[2]) and not int(match[3]) and match[1]==match[4])
repository,stage=Path(sys.argv[2]),Path(sys.argv[3])
result={'recordedAt':datetime.now(timezone.utc).isoformat(),'device':sys.argv[4],
        'status':'passed' if passed else 'failed',
        'productionHapSha256':hashlib.sha256((repository/'dist/touchmap-signed.hap').read_bytes()).hexdigest(),
        'testHapSha256':hashlib.sha256((repository/'dist/touchmap-tests-signed.hap').read_bytes()).hexdigest()}
if match:
    result['tests']={'run':int(match[1]),'failed':int(match[2]),'errors':int(match[3]),'passed':int(match[4])}
fingerprint=stage/'stage-input-fingerprint.json'
if fingerprint.exists():
    result['sourceFingerprint']={key:value for key,value in json.loads(fingerprint.read_text()).items() if key!='files'}
(repository/'docs/evidence/native-test-artifact.json').write_text(json.dumps(result,indent=2)+'\n')
if not passed:
    raise SystemExit('Native Hypium tests did not all pass. Inspect native-test-results.txt.')
print(f'Native Hypium: {match[4]}/{match[1]} passed.')
PY
