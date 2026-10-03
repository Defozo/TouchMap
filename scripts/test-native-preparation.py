"""Run delayed/cancelled native HTTP preparation against the controlled local fixture."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home()/'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'

    def command(*words, timeout=15):
        return subprocess.check_output([str(hdc),'-t',args.device,*words],text=True,stderr=subprocess.STDOUT,timeout=timeout)

    report = {'status':'running','device':args.device,'startedUtc':datetime.now(timezone.utc).isoformat(),
              'productionHapSha256':hashlib.sha256((ROOT/'dist/touchmap-signed.hap').read_bytes()).hexdigest(),
              'testHapSha256':hashlib.sha256((ROOT/'dist/touchmap-tests-signed.hap').read_bytes()).hexdigest(),
              'fixture':'tests/native-preparation/server.py on host127.0.0.1:8089; no provider calls'}
    try:
        command('rport','tcp:8089','tcp:8089')
        command('shell','aa','force-stop','org.touchmap.app')
        command('shell','rm','-f','/data/app/el2/100/base/org.touchmap.app/haps/entry/files/preparation-checks.json')
        log = command('shell','aa','test','-b','org.touchmap.app','-m','entry_test','-s','unittest','OpenHarmonyTestRunner',
                      '-s','preparationChecks','true','-w','60000',timeout=70)
        (ROOT/'docs/evidence/native-preparation-results.txt').write_text(log)
        raw = command('shell','cat','/data/app/el2/100/base/org.touchmap.app/haps/entry/files/preparation-checks.json')
        native = json.loads(raw)
        report['nativeReport'] = native
        report['status'] = native['status']
        if native['status'] != 'passed':
            raise RuntimeError('Native delayed/cancelled preparation checks failed.')
    except Exception as error:
        report['status'] = 'failed'; report['error'] = str(error); raise
    finally:
        report['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        (ROOT/'docs/evidence/native-preparation-checks.json').write_text(json.dumps(report,indent=2)+'\n')
        command('shell','aa','force-stop','org.touchmap.app')
        print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
