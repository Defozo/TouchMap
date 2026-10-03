"""Inspect and drive the actual native UI through official Oniro/HDC tooling.

This is a development test utility, not an application feature. Click selectors
are resolved from a fresh real accessibility tree, never guessed coordinates.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time
import os

def main():
    p=argparse.ArgumentParser();p.add_argument('--device',default='127.0.0.1:55555');p.add_argument('action',choices=['dump','click','fill','scroll','text','tap','swipe','screenshot','back','restart']);p.add_argument('value',nargs='?',default='');p.add_argument('--text');p.add_argument('--index',type=int,default=0);p.add_argument('--x',type=int);p.add_argument('--y',type=int);p.add_argument('--x2',type=int);p.add_argument('--y2',type=int);p.add_argument('--output');args=p.parse_args()
    cli=Path(os.getenv('TOUCHMAP_TOOLS_DIR',str(Path.home()/'touchmap-toolchain')))/'node_modules/.bin/oniro-app'
    def run(*cmd):
        result=subprocess.run([str(cli),*cmd,'--device',args.device],capture_output=True,text=True,check=True)
        return result.stdout
    def dump():
        data=json.loads(run('dump','layout'));nodes=[]
        def walk(n):
            if n.get('text') or n.get('type') in ['TextInput','TextArea','Canvas','Checkbox','CheckboxGroup','Toggle']:
                nodes.append({k:n[k] for k in ['type','text','c','b','click'] if k in n})
            for c in n.get('children',[]):walk(c)
        walk(data['tree']);return data,nodes
    if args.action=='fill':
        data,nodes=dump();labels=[n for n in nodes if n.get('text')==args.value and n['c'][1]>0]
        if not labels:raise SystemExit('Visible field label not found: '+args.value)
        label=labels[args.index];fields=[n for n in nodes if n['type'] in ['TextInput','TextArea'] and n['c'][1]>label['c'][1]]
        if not fields:raise SystemExit('Visible field below label not found: '+args.value)
        field=min(fields,key=lambda n:n['c'][1]);run('input','--type','click','--x',str(round(field['c'][0]*data['display']['width'])),'--y',str(round(field['c'][1]*data['display']['height'])))
        hdc=Path.home()/'command-line-tools/sdk/default/openharmony/toolchains/hdc'
        subprocess.run([str(hdc),'-t',args.device,'shell','uitest','uiInput','keyEvent','2072','2017'],check=True,capture_output=True)
        run('input','--type','inputText','--text',args.text or '')
        run('input','--type','keyEvent','--key','Back')
    elif args.action=='click':
        data,nodes=dump();matches=[n for n in nodes if n.get('text')==args.value and n.get('click')]
        if not matches: matches=[n for n in nodes if n.get('text')==args.value]
        if len(matches)<=args.index:raise SystemExit('Visible button not found: '+args.value+'\n'+json.dumps(nodes))
        n=matches[args.index];run('input','--type','click','--x',str(round(n['c'][0]*data['display']['width'])),'--y',str(round(n['c'][1]*data['display']['height'])))
    elif args.action=='tap':run('input','--type','click','--x',str(args.x),'--y',str(args.y))
    elif args.action=='swipe':run('input','--type','swipe','--x',str(args.x),'--y',str(args.y),'--x2',str(args.x2),'--y2',str(args.y2),'--speed',args.value or '300')
    elif args.action=='scroll':
        if args.value=='down':run('input','--type','swipe','--x','330','--y','625','--x2','330','--y2','245','--speed','850')
        else:run('input','--type','swipe','--x','330','--y','245','--x2','330','--y2','625','--speed','850')
    elif args.action=='text':run('input','--type','inputText','--text',args.value)
    elif args.action=='back':run('input','--type','keyEvent','--key','Back')
    elif args.action=='restart':
        hdc=Path.home()/'command-line-tools/sdk/default/openharmony/toolchains/hdc'
        subprocess.run([str(hdc),'-t',args.device,'shell','aa','force-stop','org.touchmap.app'],check=True,capture_output=True)
        subprocess.run([str(hdc),'-t',args.device,'shell','aa','start','-b','org.touchmap.app','-a','EntryAbility'],check=True,capture_output=True);time.sleep(1)
    elif args.action=='screenshot':print(run('screenshot','-o',args.output));return
    if args.action!='dump':time.sleep(.25)
    data,nodes=dump()
    if args.output:Path(args.output).write_text(json.dumps(data,indent=2),encoding='utf-8')
    print(json.dumps(nodes,ensure_ascii=False))

if __name__=='__main__':main()
