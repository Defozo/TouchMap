"""Observe ordinary fresh-process Library launch; disclose host polling overhead."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--count', type=int, default=5)
    args = parser.parse_args()
    if not 1 <= args.count <= 20:
        parser.error('Use 1 to 20 cold process launches.')
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home()/'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
    cli = Path(os.getenv('TOUCHMAP_TOOLS_DIR', str(Path.home()/'touchmap-toolchain'))) / 'node_modules/.bin/oniro-app'

    def device(*words):
        return subprocess.check_output([str(hdc), '-t', args.device, *words],text=True,stderr=subprocess.STDOUT,timeout=20)

    def visible_library(tree):
        labels = set()
        def visit(node):
            center = node.get('c', [0,0])
            if 0 < center[0] < 1 and 0 < center[1] < 1:
                labels.add(node.get('text',''))
            for child in node.get('children',[]):
                visit(child)
        visit(tree)
        return 'Library' in labels and 'A world you can explore.' in labels

    report = {'status':'running','device':args.device,'startedUtc':datetime.now(timezone.utc).isoformat(),
              'installedHap':json.loads((ROOT/f'docs/evidence/installation-{args.device.replace(":","_")}.json').read_text()),
              'requested':args.count,
              'scope':'Ordinary aa start launches after force-stop of an already provisioned installation. Times include HDC transport, host process startup and UI-tree polling. They are upper-bound observations, not intrinsic startup latency, first-install seeding or a performance-threshold claim.',
              'runs':[]}
    try:
        for index in range(args.count):
            device('shell','aa','force-stop','org.touchmap.app')
            before = device('shell','pidof','org.touchmap.app').strip()
            if before:
                raise RuntimeError('The previous app process did not stop: '+before)
            started = time.perf_counter()
            launch = device('shell','aa','start','-b','org.touchmap.app','-a','EntryAbility')
            launch_ms = round((time.perf_counter()-started)*1000,2)
            polls = []
            while time.perf_counter()-started < 45:
                poll_at = time.perf_counter()
                raw = subprocess.check_output([str(cli),'dump','layout','--device',args.device],text=True,stderr=subprocess.PIPE,timeout=20)
                layout = json.loads(raw)
                polls.append(round((time.perf_counter()-poll_at)*1000,2))
                if visible_library(layout['tree']):
                    visible_ms = round((time.perf_counter()-started)*1000,2)
                    break
            else:
                raise TimeoutError('Library was not observed after ordinary launch.')
            pid = device('shell','pidof','org.touchmap.app').strip()
            report['runs'].append({'index':index,'pid':pid,'aaStartReturnMs':launch_ms,'libraryObservedMs':visible_ms,
                                   'pollDurationsMs':polls,'launchResult':launch.strip()})
            (ROOT/f'docs/evidence/native-cold-library-{index+1}.json').write_text(json.dumps(layout,indent=2)+'\n')
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'; report['error'] = str(error); raise
    finally:
        report['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        (ROOT/'docs/evidence/native-cold-start.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
