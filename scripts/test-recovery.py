"""Force-stop 100 separate native processes and verify durable acknowledgements.

Run inside the documented Linux/WSL host after installing the native test HAP.
Only the TouchMap test runner and its generated fixtures are affected.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', default='127.0.0.1:55555')
    parser.add_argument('--boundaries', type=int, default=100)
    args = parser.parse_args()
    if not 1 <= args.boundaries <= 1000:
        raise SystemExit('Choose 1..1000 restart boundaries.')
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home() / 'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
    def shell(*command):
        return subprocess.run([str(hdc), '-t', args.device, 'shell', *command], capture_output=True, text=True, timeout=15).stdout
    base = '/data/app/el2/100/base/org.touchmap.app/haps/entry/files'
    output = ROOT / 'docs/evidence/native-recovery.json'
    records = []
    try:
        for cycle in range(args.boundaries + 1):
            shell('aa', 'force-stop', 'org.touchmap.app')
            started = time.monotonic()
            process = subprocess.Popen([str(hdc), '-t', args.device, 'shell', 'aa', 'test', '-b', 'org.touchmap.app', '-m', 'entry_test', '-s', 'unittest', 'OpenHarmonyTestRunner', '-s', 'recoveryCycle', str(cycle), '-w', '120000'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                marker = None
                while time.monotonic() - started < 45:
                    raw = shell('cat', base + '/recovery-observed.json')
                    try:
                        current = json.loads(raw)
                    except (ValueError, TypeError):
                        current = {}
                    if current.get('cycle') == cycle:
                        marker = current
                        break
                    time.sleep(.15)
                if not marker or marker.get('status') != 'committed':
                    raise RuntimeError(f'Cycle {cycle} did not acknowledge a durable commit: {marker}')
                if cycle and not marker.get('verifiedPrevious'):
                    raise RuntimeError(f'Cycle {cycle} did not verify its preceding forced restart')
                records.append({**marker, 'launchAndWorkMs': round((time.monotonic() - started) * 1000)})
                output.write_text(json.dumps({'status': 'running', 'device': args.device, 'records': records}, indent=2), encoding='utf-8')
                if cycle % 10 == 0:
                    print(f'Native recovery: {cycle}/{args.boundaries} verified restart boundaries', flush=True)
            finally:
                shell('aa', 'force-stop', 'org.touchmap.app')
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=3)
        metrics = json.loads(shell('cat', base + '/recovery-metrics.json'))
        result = {'status': 'passed', 'device': args.device, 'forcedRestartsVerified': args.boundaries,
                  'scope': 'Real process death after fsynced post-commit acknowledgements across save, unfinished answer, submit/idempotent replay and ZIP import; not mid-transaction fault injection.',
                  'nativeMetrics': metrics, 'records': records}
        output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({k:v for k,v in result.items() if k != 'records'}, indent=2))
    except Exception as error:
        output.write_text(json.dumps({'status': 'failed', 'error': str(error), 'device': args.device, 'records': records}, indent=2), encoding='utf-8')
        raise

if __name__ == '__main__':
    main()
