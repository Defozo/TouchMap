"""Inject ENOSPC only into the selected test app's empty staging directory."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
APP_FILES = '/data/app/el2/100/base/org.touchmap.app/haps/entry/files'
STAGING = APP_FILES + '/staging'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home() / 'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
    output = ROOT / 'docs/evidence/native-failure-checks.json'
    evidence = {'startedUtc': datetime.now(timezone.utc).isoformat(), 'device': args.device,
                'mountTarget': STAGING, 'filesystem': 'tmpfs', 'sizeBytes': 65536,
                'scope': 'Host fault injection confined to an empty app staging directory. Existing materials, database and progress remain on their original filesystem.'}
    evidence['productionHapSha256'] = hashlib.sha256((ROOT/'dist/touchmap-signed.hap').read_bytes()).hexdigest()
    evidence['testHapSha256'] = hashlib.sha256((ROOT/'dist/touchmap-tests-signed.hap').read_bytes()).hexdigest()
    evidence['artifactBinding'] = 'Requires matching production and test HAPs installed before this script; the script itself does not install them.'

    def command(*words, timeout=15):
        return subprocess.run([str(hdc), '-t', args.device, *words], capture_output=True, text=True, timeout=timeout, check=True).stdout

    def read_json(name):
        try:
            return json.loads(command('shell', 'cat', APP_FILES + '/' + name))
        except (json.JSONDecodeError, subprocess.CalledProcessError):
            return None

    mounted = False
    process = None
    namespace = []
    mount_path = STAGING
    try:
        command('shell', 'aa', 'force-stop', 'org.touchmap.app')
        for name in ['failure-injection-ready.json', 'failure-checks.json', 'failure-injection-go']:
            command('shell', 'rm', '-f', APP_FILES + '/' + name)
        command('shell', 'uitest', 'start-daemon', 'default')
        process = subprocess.Popen([str(hdc), '-t', args.device, 'shell', 'aa', 'test', '-b', 'org.touchmap.app',
                                    '-m', 'entry_test', '-s', 'unittest', 'OpenHarmonyTestRunner',
                                    '-s', 'failureChecks', '1', '-w', '120000'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            ready = read_json('failure-injection-ready.json')
            if ready and ready.get('status') == 'ready':
                break
            if process.poll() is not None:
                raise RuntimeError('Native runner ended before the mount handshake.')
            time.sleep(.2)
        else:
            raise TimeoutError('Native runner did not become ready for fault injection.')
        if ready.get('staging') != '/data/storage/el2/base/haps/entry/files/staging':
            raise RuntimeError('Unexpected app staging path: ' + repr(ready))
        if command('shell', 'ls', '-A', STAGING).strip():
            raise RuntimeError('Refusing to cover a nonempty staging directory.')
        mounts = command('shell', 'cat', '/proc/mounts')
        if any(line.split()[1] == STAGING for line in mounts.splitlines()):
            raise RuntimeError('Staging already has a mount; refusing to replace it.')
        ownership = command('shell', 'stat', '-c', '%u:%g', STAGING).strip()
        owner, group = ownership.split(':')
        if not owner.isdigit() or not group.isdigit():
            raise RuntimeError('Invalid staging ownership.')
        options = f'size=65536,mode=0770,uid={owner},gid={group}'
        pid = command('shell', 'pidof', 'org.touchmap.app').strip()
        if not pid.isdigit():
            raise RuntimeError('Expected one target app process for mount namespace injection.')
        namespace = ['nsenter', '-t', pid, '-m', '--']
        mount_path = f'/proc/{pid}/root/data/storage/el2/base/haps/entry/files/staging'
        if command('shell', *namespace, 'ls', '-A', mount_path).strip():
            raise RuntimeError('App namespace staging directory is not empty.')
        evidence['appPid'] = int(pid)
        evidence['mountNamespace'] = 'Selected app process only; host namespace mounts do not propagate into the sandbox.'
        result = command('shell', *namespace, 'mount', '-t', 'tmpfs', '-o', options, 'touchmap-test-enospc', mount_path)
        mounts = command('shell', *namespace, 'cat', '/proc/mounts')
        mount = [line for line in mounts.splitlines() if line.split()[0] == 'touchmap-test-enospc']
        if not mount or 'tmpfs' not in mount[0]:
            raise RuntimeError('Scoped tmpfs mount was not applied: ' + result)
        mounted = True
        evidence['mountedEntry'] = mount[0]
        command('shell', 'touch', APP_FILES + '/failure-injection-go')
        log, _ = process.communicate(timeout=65)
        (ROOT / 'docs/evidence/native-failure-results.txt').write_text(log)
        report = read_json('failure-checks.json')
        if not report:
            raise RuntimeError('Native failure report missing.')
        evidence['nativeReport'] = report
        if report.get('status') != 'passed':
            raise RuntimeError('Native failure checks did not all pass.')
        evidence['status'] = 'passed'
    except Exception as error:
        evidence['status'] = 'failed'
        evidence['error'] = str(error)
        raise
    finally:
        if mounted:
            command('shell', *namespace, 'umount', mount_path)
            evidence['mountRemoved'] = not any(line.split()[0] == 'touchmap-test-enospc' for line in command('shell', *namespace, 'cat', '/proc/mounts').splitlines())
            if not evidence['mountRemoved']:
                evidence['status'] = 'failed'
                evidence['error'] = 'Scoped fault injection mount could not be removed.'
        else:
            evidence['mountRemoved'] = True
        if process and process.poll() is None:
            command('shell', 'aa', 'force-stop', 'org.touchmap.app')
            process.terminate()
        command('shell', 'rm', '-f', APP_FILES + '/failure-injection-go')
        command('shell', 'aa', 'force-stop', 'org.touchmap.app')
        evidence['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        output.write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
