"""Measure real Library open intent to end of rendered restoration frame."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
APP_FILES = '/data/app/el2/100/base/org.touchmap.app/haps/entry/files'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--count', type=int, default=100)
    args = parser.parse_args()
    if not 1 <= args.count <= 1000:
        parser.error('Count must be between1 and1000.')
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home() / 'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
    output = ROOT / 'docs/evidence/native-restore-benchmark.json'

    def command(*words, timeout=15):
        return subprocess.run([str(hdc), '-t', args.device, *words], capture_output=True, text=True, timeout=timeout, check=True).stdout

    artifact = {'device': args.device, 'startedUtc': datetime.now(timezone.utc).isoformat(),
                'productionHapSha256': hashlib.sha256((ROOT/'dist/touchmap-signed.hap').read_bytes()).hexdigest(),
                'testHapSha256': hashlib.sha256((ROOT/'dist/touchmap-tests-signed.hap').read_bytes()).hexdigest()}
    metadata = json.loads((ROOT/'docs/evidence/hap-metadata.json').read_text())
    artifact['sourceFingerprint'] = metadata['sourceFingerprint']
    output.write_text(json.dumps({'status':'running','device':args.device,'requested':args.count})+'\n')
    try:
        command('shell', 'aa', 'force-stop', 'org.touchmap.app')
        command('shell', 'rm', '-f', APP_FILES+'/restore-benchmark.json', APP_FILES+'/restore-benchmark-progress.json')
        command('shell', 'uitest', 'start-daemon', 'default')
        log = command('shell', 'aa', 'test', '-b', 'org.touchmap.app', '-m', 'entry_test', '-s', 'unittest',
                      'OpenHarmonyTestRunner', '-s', 'restoreBenchmark', str(args.count), '-w', '1200000', timeout=args.count*30+60)
        (ROOT/'docs/evidence/native-restore-results.txt').write_text(log)
        command('file', 'recv', APP_FILES+'/restore-benchmark.json', str(output))
        report = json.loads(output.read_text())
        artifact['status'] = report['status']
        print(json.dumps({key:value for key,value in report.items() if key!='samples'},indent=2))
        if report.get('status') != 'passed' or len(report.get('samples',[])) != args.count:
            raise RuntimeError('Native rendered restoration target was not met.')
    finally:
        artifact['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        (ROOT/'docs/evidence/native-restore-artifact.json').write_text(json.dumps(artifact,indent=2)+'\n')
        command('shell', 'aa', 'force-stop', 'org.touchmap.app')


if __name__ == '__main__':
    main()
