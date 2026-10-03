"""Build a separate ordinary-permission app to verify real cross-app URI grants."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    args = parser.parse_args()
    package = args.package.resolve(strict=True)
    tools = Path(os.getenv('TOUCHMAP_TOOLS_DIR', str(Path.home() / 'touchmap-toolchain')))
    sdk = Path(os.getenv('ONIRO_SDK_ROOT_DIR', str(Path.home() / 'setup-ohos-sdk')))
    command_tools = Path(os.getenv('ONIRO_CMD_TOOLS_PATH', str(Path.home() / 'command-line-tools')))
    build_root = Path.home() / '.cache/touchmap-build'
    build_root.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='share-sender-', dir=build_root))
    def put(relative, value):
        path = stage / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, indent=2) + '\n')
    for relative in ['build-profile.json5','hvigorfile.ts','hvigor/hvigor-config.json5',
                     'oh-package.json5','oh-package-lock.json5','entry/hvigorfile.ts',
                     'entry/oh-package.json5','entry/build-profile.json5','entry/obfuscation-rules.txt']:
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'app' / relative, target)
    put('AppScope/app.json5', {'app':{'bundleName':'org.touchmap.testshare','vendor':'TouchMap tests',
        'versionCode':1000000,'versionName':'1.0.0','icon':'$media:icon','label':'$string:app_name'}})
    put('AppScope/resources/base/element/string.json', {'string':[{'name':'app_name','value':'TouchMap share test'}]})
    for base in ['AppScope','entry/src/main']:
        icon = stage / base / 'resources/base/media/icon.png'
        icon.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'app/AppScope/resources/base/media/foreground.png', icon)
    put('entry/src/main/module.json5', {'module':{'name':'entry','type':'entry','description':'TouchMap URI grant test sender',
        'mainElement':'EntryAbility','deviceTypes':['default','tablet'],'deliveryWithInstall':True,'installationFree':False,
        'pages':'$profile:main_pages','abilities':[{'name':'EntryAbility','srcEntry':'./ets/entryability/EntryAbility.ets',
        'icon':'$media:icon','label':'$string:app_name','startWindowIcon':'$media:icon','startWindowBackground':'$color:background',
        'exported':True,'skills':[{'entities':['entity.system.home'],'actions':['ohos.want.action.home']}]}]}})
    put('entry/src/main/resources/base/element/color.json', {'color':[{'name':'background','value':'#F0F5F8'}]})
    put('entry/src/main/resources/base/profile/main_pages.json', {'src':['pages/Index']})
    for name, directory in [('EntryAbility.ets','entryability'),('Index.ets','pages')]:
        target = stage / 'entry/src/main/ets' / directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'tests/native-share-sender' / name, target)
    raw = stage / 'entry/src/main/resources/rawfile/payload.touchmap'
    raw.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(package, raw)
    (stage / 'local.properties').write_text(f'sdk.dir={sdk}/linux\n')
    environment = dict(os.environ, ONIRO_SDK_ROOT_DIR=str(sdk), ONIRO_CMD_TOOLS_PATH=str(command_tools))
    environment['PATH'] = f'{command_tools}/bin:{command_tools}/tool/ohpm/bin:' + environment['PATH']
    cli = tools / 'node_modules/.bin/oniro-app'
    subprocess.run([str(cli),'sign',str(stage),'--bootstrap'], env=environment, check=True)
    subprocess.run([str(cli),'build',str(stage),'--product','openharmonyApi20','--mode','debug','--json'], env=environment, check=True)
    hap = next((stage / 'entry/build').rglob('*-signed.hap'))
    subprocess.run(['java','-jar',str(sdk / 'linux/20/toolchains/lib/hap-sign-tool.jar'),'verify-app',
                    '-inFile',str(hap),'-outCertChain',str(stage / 'verified-certificate.cer'),
                    '-outProfile',str(stage / 'verified-profile.p7b')], check=True)
    with ZipFile(hap) as archive:
        metadata = json.loads(archive.read('module.json'))
    assert metadata['app']['bundleName'] == 'org.touchmap.testshare'
    assert not metadata['module'].get('requestPermissions')
    output = ROOT / 'dist/touchmap-share-sender-signed.hap'
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(hap, output)
    result = {'bundleName':'org.touchmap.testshare','permissions':[],
              'hapSha256':hashlib.sha256(output.read_bytes()).hexdigest(),
              'packageSha256':hashlib.sha256(package.read_bytes()).hexdigest(),
              'packageBytes':package.stat().st_size,'signatureVerified':True,
              'sourceFiles':{name:hashlib.sha256((ROOT / 'tests/native-share-sender' / name).read_bytes()).hexdigest()
                             for name in ['EntryAbility.ets','Index.ets']},
              'scope':'Separate ordinary-permission helper. Runtime receipt/import must be verified separately.'}
    (ROOT / 'docs/evidence/native-share-helper-build.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

if __name__ == '__main__':
    main()
