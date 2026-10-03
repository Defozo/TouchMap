#!/usr/bin/env bash
set -euo pipefail
repository=$(cd "$(dirname "$0")/.." && pwd)
target=${1:?HDC target required}
count=${2:-100}
[[ "$count" =~ ^[0-9]+$ ]] && (( count >= 1 && count <= 1000 )) || { echo 'Choose 1..1000 playback measurements.' >&2; exit 2; }
command_tools=${ONIRO_CMD_TOOLS_PATH:-"$HOME/command-line-tools"}
hdc="$command_tools/sdk/default/openharmony/toolchains/hdc"
mkdir -p "$repository/docs/evidence"
record_host() {
  python3 - "$repository/docs/evidence/native-audio-host.json" "$1" "$target" <<'PY'
import json,os,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
path=Path(sys.argv[1])
report=json.loads(path.read_text()) if sys.argv[2]!='before' and path.exists() else {'device':sys.argv[3],'scope':'Linux build host snapshots before and after the native audio run. Load averages are not per-emulator CPU measurements.'}
names=subprocess.check_output(['ps','-eo','comm='],text=True).splitlines()
report[sys.argv[2]]={'at':datetime.now(timezone.utc).isoformat(),'logicalCpuCount':os.cpu_count(),'loadAverage':list(os.getloadavg()),'buildProcesses':{name:names.count(name) for name in ['java','hvigorw','clang','ninja']}}
path.write_text(json.dumps(report,indent=2)+'\n')
PY
}
finish() {
  exit_code=$?
  if [[ -n "${vmstat_pid:-}" ]]; then
    kill "$vmstat_pid" 2>/dev/null || true
    wait "$vmstat_pid" 2>/dev/null || true
  fi
  record_host after
  "$hdc" -t "$target" shell aa force-stop org.touchmap.app >/dev/null 2>&1 || true
  python3 - "$repository/docs/evidence/native-audio-benchmark.json" "$exit_code" <<'PY'
import json,sys
from pathlib import Path
path=Path(sys.argv[1])
if path.exists():
    report=json.loads(path.read_text())
    if report.get('status')=='running':
        report.update(status='failed',error=f'Host runner exited {sys.argv[2]} before receiving a native final report.')
        path.write_text(json.dumps(report,indent=2)+'\n')
PY
}
trap finish EXIT
python3 - "$repository/docs/evidence/native-audio-benchmark.json" "$target" "$count" <<'PY'
import json,sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({'status':'running','device':sys.argv[2],'requested':int(sys.argv[3])})+'\n')
PY
"$hdc" -t "$target" shell aa force-stop org.touchmap.app
"$hdc" -t "$target" shell rm -f /data/app/el2/100/base/org.touchmap.app/haps/entry/files/audio-benchmark.json
"$hdc" -t "$target" shell uitest start-daemon default
record_host before
vmstat -t 1 > "$repository/docs/evidence/native-audio-host-vmstat.txt" &
vmstat_pid=$!
timeout "$((count * 6 + 30))s" "$hdc" -t "$target" shell aa test -b org.touchmap.app -m entry_test -s unittest OpenHarmonyTestRunner -s audioBench "$count" -w 120000 | tee "$repository/docs/evidence/native-audio-results.txt"
"$hdc" -t "$target" file recv /data/app/el2/100/base/org.touchmap.app/haps/entry/files/audio-benchmark.json "$repository/docs/evidence/native-audio-benchmark.json"
python3 - "$repository/docs/evidence/native-audio-benchmark.json" "$count" <<'PY'
import json,sys
from pathlib import Path
report=json.loads(Path(sys.argv[1]).read_text())
print(json.dumps({key:value for key,value in report.items() if key!='measurements'},indent=2))
if report['requested']!=int(sys.argv[2]) or report['status']!='complete' or report['succeeded']!=report['requested']:
    raise SystemExit('Native audio benchmark did not complete every playback.')
if not report['targetMet']:
    raise SystemExit('The measured native audio p95 exceeds the onset target. Inspect native-audio-benchmark.json.')
PY
