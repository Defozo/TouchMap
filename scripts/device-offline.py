"""Reversible network isolation for the dedicated OpenHarmony test emulator.

Only the explicit TM_OFFLINE chain is changed. The HDC transport remains usable.
Run `off` after verification. This script never changes the host firewall.
"""
import argparse
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone

parser=argparse.ArgumentParser()
parser.add_argument('mode',choices=['on','off','status'])
parser.add_argument('--device',default='127.0.0.1:55555')
parser.add_argument('--hdc-device-port',type=int,default=55555)
args=parser.parse_args()
if not 1<=args.hdc_device_port<=65535:raise SystemExit('Invalid HDC port')
hdc=Path.home()/'command-line-tools/sdk/default/openharmony/toolchains/hdc'
chain='TM_OFFLINE'
def shell(*command):
    result=subprocess.run([str(hdc),'-t',args.device,'shell',*command],capture_output=True,text=True,timeout=15)
    return result.stdout+result.stderr
def checked(*command):
    output=shell(*command)
    if output.strip():raise RuntimeError(' '.join(command)+': '+output)
def remove(binary):
    rules=shell(binary,'-S')
    if '-A OUTPUT -j '+chain in rules:checked(binary,'-D','OUTPUT','-j',chain)
    if '-N '+chain in rules:
        checked(binary,'-F',chain)
        checked(binary,'-X',chain)
if args.mode=='on':
    for binary in ['iptables','ip6tables']:remove(binary)
    try:
        for binary in ['iptables','ip6tables']:
            checked(binary,'-N',chain)
            checked(binary,'-A',chain,'-p','tcp','--sport',str(args.hdc_device_port),'-j','RETURN')
            checked(binary,'-A',chain,'-j','DROP')
        # Verify the exception exists before enabling a rule which could block HDC.
        for binary in ['iptables','ip6tables']:
            rules=shell(binary,'-S',chain)
            if '--sport '+str(args.hdc_device_port) not in rules:raise RuntimeError('HDC exception not installed')
            checked(binary,'-I','OUTPUT','1','-j',chain)
    except Exception:
        for binary in ['iptables','ip6tables']:remove(binary)
        raise
elif args.mode=='off':
    for binary in ['iptables','ip6tables']:remove(binary)
report={'time':datetime.now(timezone.utc).isoformat(),'device':args.device,'operation':args.mode,
        'scope':'Dedicated emulator IPv4/IPv6 outbound blocked except HDC replies; includes application loopback and WAN.',
        'ipv4':shell('iptables','-S'),'ipv6':shell('ip6tables','-S')}
root=Path(__file__).resolve().parents[1]
(root/'docs/evidence'/f'offline-{args.mode}.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
