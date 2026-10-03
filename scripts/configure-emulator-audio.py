"""Correct the pinned Oniro v6.1 image's ALSA card mapping on a test emulator.

The image declares Generic_1/card2 while its QEMU ES1370 device is AudioPCI/card0.
The vendor mapping correction persists in that emulator image. The control node
group correction lasts until reboot, so rerun apply after boot. Restore returns
the verified original configuration and group. TouchMap permissions/HAPs are
unchanged. Apply/restore restart only the native audio services, not the app.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONFIG = '/vendor/etc/hdfconfig/alsa_adapter.json'
OVERRIDE = '/data/local/tmp/touchmap-emulator-alsa.json'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('action', choices=['apply', 'restore', 'inspect'])
    args = parser.parse_args()
    hdc = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home() / 'command-line-tools'))) / 'sdk/default/openharmony/toolchains/hdc'
    def run(*command):
        result = subprocess.run([str(hdc), '-t', args.device, *command], capture_output=True, text=True, timeout=15, check=True)
        return result.stdout.strip()
    cards = run('shell', 'cat', '/proc/asound/cards')
    original = json.loads(run('shell', 'cat', CONFIG))
    if args.action == 'inspect':
        print(json.dumps({'device': args.device, 'cards': cards, 'configuration': original}, indent=2)); return
    expected = {'adapters': [{'name': 'primary', 'cardId': 2, 'cardName': 'Generic_1'}]}
    corrected = {'adapters': [{'name': 'primary', 'cardId': 0, 'cardName': 'AudioPCI'}]}
    if '0 [AudioPCI' not in cards or 'ENS1370' not in cards:
        raise SystemExit('This correction is only for the verified QEMU ES1370 card0 target.')
    if original not in [expected, corrected]:
        raise SystemExit('Unexpected existing audio mapping; refusing to replace it.')
    desired = expected if args.action == 'restore' else corrected
    local = ROOT / '.local/emulator-alsa-configuration.json'
    local.parent.mkdir(exist_ok=True)
    local.write_text(json.dumps(desired, indent=2) + '\n')
    if original == expected:
        (ROOT / 'docs/evidence/emulator-audio-original.json').write_text(json.dumps(original, indent=2) + '\n')
    if original != desired:
        print(run('file', 'send', str(local), OVERRIDE))
        # HDI runs inside a chipset mount namespace. A bind mount visible only
        # to HDC does not reach it, so replace the shared vendor inode content.
        print(run('shell', 'mount', '-o', 'remount,rw', '/vendor'))
        try:
            print(run('shell', 'cp', OVERRIDE, CONFIG))
        finally:
            print(run('shell', 'mount', '-o', 'remount,ro', '/vendor'))
    applied = json.loads(run('shell', 'cat', CONFIG))
    if applied != desired:
        raise SystemExit('The ALSA mapping did not apply.')
    # The image assigns controlC0 to midi_server. The audio_host service belongs
    # to audio but not midi_server, so ALSA enumeration fails with no soundcards.
    group = 'midi_server' if args.action == 'restore' else 'audio'
    print(run('shell', 'chgrp', group, '/dev/snd/controlC0'))
    print(run('shell', 'service_control', 'stop', 'audio_server'))
    print(run('shell', 'service_control', 'start', 'audio_server'))
    result = {'device': args.device, 'action': args.action, 'cards': cards, 'mapping': applied,
              'controlNode': run('shell', 'ls', '-l', '/dev/snd/controlC0'),
              'scope': 'Development emulator image configuration; no application privilege changes; audio services restarted, app not stopped.',
              'restore': f'python3 scripts/configure-emulator-audio.py --device {args.device} restore'}
    (ROOT / f'docs/evidence/emulator-audio-{args.device.rsplit(":", 1)[-1]}.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
