"""Install an independently built checkout and verify its native runtime flows."""
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
    parser.add_argument('--checkout', required=True, type=Path)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    evidence = ROOT / 'docs/evidence'
    source = checkout / 'docs/evidence'
    metadata = json.loads((source / 'hap-metadata.json').read_text())
    expected = json.loads((evidence / 'hap-metadata.json').read_text())
    if metadata['appSourceSha256'] != expected['appSourceSha256']:
        raise RuntimeError('Independent checkout does not match the release app source.')
    report = {'status': 'running', 'device': args.device,
              'startedUtc': datetime.now(timezone.utc).isoformat(),
              'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=checkout, text=True).strip(),
              'productionHapSha256': hashlib.sha256((checkout / 'dist/touchmap-signed.hap').read_bytes()).hexdigest(),
              'appSourceSha256': metadata['appSourceSha256'],
              'sourceFingerprint': metadata['sourceFingerprint'],
              'scope': 'Independent clean-checkout HAP installed over the existing second installation with data retained. Native Hypium, actual audio controls and ordinary Library launch are executed against these independently built bytes.'}
    def run(command, log):
        with (evidence / log).open('w') as output:
            subprocess.run(command, cwd=checkout, stdout=output, stderr=subprocess.STDOUT, timeout=600, check=True)
    try:
        run(['bash', str(checkout / 'scripts/platform.sh'), 'install', str(checkout), args.device], 'clean-install-results.txt')
        run(['bash', str(checkout / 'scripts/test-native.sh'), args.device], 'clean-native-invocation.txt')
        for name in ['native-test-results.txt', 'native-test-artifact.json', 'native-test-build.log']:
            (evidence / ('clean-' + name)).write_bytes((source / name).read_bytes())
        native = json.loads((source / 'native-test-artifact.json').read_text())
        report['nativeTests'] = native['tests']
        report['testHapSha256'] = native['testHapSha256']
        run(['python3', str(checkout / 'scripts/test-audio-controls.py'), '--device', args.device], 'clean-audio-controls-results.txt')
        controls = json.loads((source / 'native-audio-controls.json').read_text())
        (evidence / 'clean-audio-controls.json').write_text(json.dumps(controls, indent=2) + '\n')
        report['audioControls'] = {'status': controls['status'], 'checks': controls['checks']}
        hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home() / 'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
        subprocess.run([str(hdc), '-t', args.device, 'shell', 'aa', 'force-stop', 'org.touchmap.app'], capture_output=True, text=True, timeout=20, check=True)
        subprocess.run([str(hdc), '-t', args.device, 'shell', 'aa', 'start', '-b', 'org.touchmap.app', '-a', 'EntryAbility'], capture_output=True, text=True, timeout=20, check=True)
        cli = Path(os.getenv('TOUCHMAP_TOOLS_DIR', str(Path.home() / 'touchmap-toolchain'))) / 'node_modules/.bin/oniro-app'
        layout = json.loads(subprocess.check_output([str(cli), 'dump', 'layout', '--device', args.device], text=True, stderr=subprocess.PIPE, timeout=30))
        (evidence / 'clean-installed-library.json').write_text(json.dumps(layout, indent=2) + '\n')
        labels = set()
        def visit(node):
            center = node.get('c', [0, 0])
            if 0 < center[0] < 1 and 0 < center[1] < 1:
                labels.add(node.get('text', ''))
            for child in node.get('children', []):
                visit(child)
        visit(layout['tree'])
        if 'Library' not in labels or 'Explore diagrams by touch and sound.' not in labels:
            raise RuntimeError('The independent HAP did not show the ordinary Library.')
        report['ordinaryLibraryVisible'] = True
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        report['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        (evidence / 'clean-installation.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
