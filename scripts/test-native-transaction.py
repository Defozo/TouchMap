"""Kill the actual native test process after real uncommitted RDB writes."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
REMOTE = '/data/app/el2/100/base/org.touchmap.app/haps/entry/files/'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home()/'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
    def command(*words, timeout=15):
        return subprocess.check_output([str(hdc), '-t', args.device, *words], text=True, stderr=subprocess.STDOUT, timeout=timeout)
    def read(name):
        try:
            return json.loads(command('shell', 'cat', REMOTE+name))
        except (subprocess.SubprocessError, json.JSONDecodeError):
            return None
    def launch(phase):
        return subprocess.Popen([str(hdc), '-t', args.device, 'shell', 'aa', 'test', '-b', 'org.touchmap.app', '-m', 'entry_test',
                                 '-s', 'unittest', 'OpenHarmonyTestRunner', '-s', 'transactionFailure', phase, '-w', '90000'],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    report = {'startedUtc': datetime.now(timezone.utc).isoformat(), 'device': args.device, 'status': 'running', 'runs': [],
              'productionHapSha256': hashlib.sha256((ROOT/'dist/touchmap-signed.hap').read_bytes()).hexdigest(),
              'testHapSha256': hashlib.sha256((ROOT/'dist/touchmap-tests-signed.hap').read_bytes()).hexdigest(),
              'scope': 'Three actual process deaths after native SQL writes and before commit. Tests use isolated synthetic material in the production RDB tables. Not an injected production-dispatch callback.'}
    process = None
    try:
        for mode in ['event-only', 'progress-written', 'delete-partial']:
            command('shell', 'aa', 'force-stop', 'org.touchmap.app')
            for name in ['transaction-ready.json', 'transaction-report.json']:
                command('shell', 'rm', '-f', REMOTE+name)
            process = launch('prepare-'+mode)
            deadline = time.monotonic()+45
            while time.monotonic() < deadline:
                marker = read('transaction-ready.json')
                if marker and marker.get('status') == 'uncommitted-writes-complete' and marker.get('mode') == mode:
                    break
                if process.poll() is not None:
                    raise RuntimeError('Native pre-commit runner exited without its barrier.')
                time.sleep(.2)
            else:
                raise TimeoutError('Native pre-commit barrier not reached.')
            command('shell', 'aa', 'force-stop', 'org.touchmap.app')
            process.communicate(timeout=10)
            process = launch('verify-'+mode)
            log, _ = process.communicate(timeout=60)
            (ROOT/f'docs/evidence/native-transaction-{mode}.txt').write_text(log)
            result = read('transaction-report.json')
            if not result or result.get('status') != 'passed':
                raise RuntimeError('Native rollback verification failed: '+json.dumps(result))
            report['runs'].append({'preCommitMarker': marker, 'verification': result})
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'; report['error'] = str(error)
        raise
    finally:
        if process and process.poll() is None:
            command('shell', 'aa', 'force-stop', 'org.touchmap.app')
            process.terminate()
        report['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        (ROOT/'docs/evidence/native-transaction-interruption.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'status': report['status'], 'processDeaths': len(report['runs'])}))

if __name__ == '__main__':
    main()
