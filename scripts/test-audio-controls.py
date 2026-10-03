"""Run actual native cancellation, latest-only playback and pause/resume checks."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--mode', choices=['all', 'tail'], default='all')
    args = parser.parse_args()
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home() / 'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
    remote = '/data/app/el2/100/base/org.touchmap.app/haps/entry/files/audio-controls.json'
    output = ROOT / 'docs/evidence/native-audio-controls.json'
    artifact = {'device':args.device,'mode':args.mode,'startedUtc':datetime.now(timezone.utc).isoformat(),
                'productionHapSha256':hashlib.sha256((ROOT/'dist/touchmap-signed.hap').read_bytes()).hexdigest(),
                'testHapSha256':hashlib.sha256((ROOT/'dist/touchmap-tests-signed.hap').read_bytes()).hexdigest(),
                'sourceFingerprint':json.loads((ROOT/'docs/evidence/hap-metadata.json').read_text())['sourceFingerprint']}
    def run(*command, timeout=15):
        return subprocess.run([str(hdc), '-t', args.device, *command], capture_output=True, text=True, timeout=timeout, check=True).stdout
    output.write_text(json.dumps({'status':'running','device':args.device})+'\n')
    try:
        run('shell', 'aa', 'force-stop', 'org.touchmap.app')
        run('shell', 'rm', '-f', remote)
        run('shell', 'uitest', 'start-daemon', 'default')
        text = run('shell', 'aa', 'test', '-b', 'org.touchmap.app', '-m', 'entry_test',
                   '-s', 'unittest', 'OpenHarmonyTestRunner', '-s', 'audioControls', args.mode, '-w', '90000', timeout=90)
        (ROOT / 'docs/evidence/native-audio-controls-results.txt').write_text(text)
        run('file', 'recv', remote, str(output))
        report = json.loads(output.read_text())
        print(json.dumps(report, indent=2))
        expected = {'four_byte_final_pcm_tail_finishes'}
        if args.mode == 'all':
            expected.update({'stop_before_dwell', 'rapid_replacement_only_latest_target',
                             'pause_resume_finishes_same_recording',
                             'replace_pending_batched_write_finishes_latest_only'})
        checks = report.get('checks', [])
        if (report.get('status') != 'passed' or len(checks) != len(expected)
                or {item.get('name') for item in checks} != expected
                or not all(item['passed'] for item in checks)):
            raise RuntimeError('Native audio controls did not all pass.')
    except Exception as error:
        report = json.loads(output.read_text())
        if report.get('status') == 'running':
            output.write_text(json.dumps({'status':'failed','device':args.device,'error':str(error)},indent=2)+'\n')
        raise
    finally:
        artifact['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        artifact['status'] = json.loads(output.read_text()).get('status','failed')
        (ROOT/'docs/evidence/native-audio-controls-artifact.json').write_text(json.dumps(artifact,indent=2)+'\n')
        run('shell', 'aa', 'force-stop', 'org.touchmap.app')

if __name__ == '__main__':
    main()
