"""Release preflight and determinism tests using an isolated synthetic Git repository."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import zipfile
import pytest

SPEC=importlib.util.spec_from_file_location('pack_release',Path(__file__).parents[2]/'scripts/package-release.py')
release=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(release)


@pytest.fixture
def candidate(tmp_path,monkeypatch):
    root=tmp_path/'synthetic';root.mkdir()
    def git(*args):return subprocess.check_output(['git',*args],cwd=root,stderr=subprocess.DEVNULL).decode().strip()
    git('init');git('config','user.name','Packaging fixture');git('config','user.email','fixture@example.invalid')
    for name in release.REQUIRED:
        path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('Fixture Team\nFixture Member\n')
    team={'team_name':'Fixture Team','members':['Fixture Member'],'human_member_count':1}
    (root/'TEAM.json').write_text(json.dumps(team));(root/'toolchain.lock.json').write_text('{"fixture":true}')
    demo_bytes=b'synthetic media; never a release artifact'
    (root/'docs/demo-storyboard.json').write_text('{"scenes":[{"duration":1}]}')
    (root/'docs/evidence/demo-manifest.json').write_text(json.dumps({'reviewed':True,
        'videoSha256':release.sha256(demo_bytes),'durationSeconds':1,
        'storyboardSha256':release.sha256((root/'docs/demo-storyboard.json').read_bytes())}))
    (root/'.gitignore').write_text('dist/\n')
    git('add','.');git('commit','-m','Isolated fixture');commit=git('rev-parse','HEAD')
    dist=root/'dist';dist.mkdir();hap=dist/'test.hap';demo=dist/'test.mp4';verification=dist/'verification.json'
    with zipfile.ZipFile(hap,'w') as archive:archive.writestr('module.json',json.dumps({'app':{'bundleName':'org.touchmap.app','minAPIVersion':20}}))
    demo.write_bytes(demo_bytes)
    monkeypatch.setattr(release,'inspect_demo',lambda path:{'format':{'duration':'1'},'streams':[{'codec_type':'video'}]})
    report={'sourceCommit':commit,'team':team,'artifactFailures':[],'hap':{'sha256':release.sha256(hap.read_bytes()),
            'appSourceSha256':release.committed_app_fingerprint(release.source_files(root,commit)),'buildInputGitHead':commit},
            'samples':[{'file':path.name,'sha256':release.sha256(path.read_bytes())} for path in (root/'samples').glob('*.touchmap')],
            'outstandingGates':['fixtureOnly'],'gates':{'fixtureOnly':{'status':'pending'}}}
    verification.write_text(json.dumps(report))
    return root,commit,hap,demo,verification


def test_release_bundle_uses_committed_bytes_and_is_deterministic(candidate):
    root,commit,hap,demo,verification=candidate
    (root/'untracked-personal.txt').write_text('must not ship')
    report,files=release.prepare(*candidate)
    assert report['status']=='ready' and report['competitionSubmitted'] is False
    assert release.deterministic_zip(files)==release.deterministic_zip(release.prepare(*candidate)[1])
    with zipfile.ZipFile(io.BytesIO(files['source.zip'])) as archive:
        assert 'untracked-personal.txt' not in archive.namelist()
        assert archive.read('TEAM.json')==(root/'TEAM.json').read_bytes()
    for row in files['SHA256SUMS'].decode().splitlines():
        digest,path=row.split('  ',1);assert release.sha256(files[path])==digest
    assert json.loads(files['environment-manifest.json'])['sourceCommit']==commit


def test_release_rejects_dirty_missing_and_unpassed_inputs(candidate):
    root,commit,hap,demo,verification=candidate
    assert release.prepare(*candidate,require_all_gates=True)[0]['status']=='failed'
    demo.unlink()
    report,files=release.prepare(*candidate)
    assert any('demonstration' in failure for failure in report['failures']) and files=={}
    (root/'README.md').write_text('changed')
    assert any('Tracked' in failure for failure in release.prepare(*candidate)[0]['failures'])


def test_release_rejects_mismatched_artifact_or_commit(candidate):
    root,commit,hap,demo,verification=candidate
    hap.write_bytes(hap.read_bytes()+b'changed')
    assert 'HAP hash' in release.prepare(*candidate)[0]['failures'][0]
    report=json.loads(verification.read_text());report['sourceCommit']='0'*40;verification.write_text(json.dumps(report))
    assert 'different source commit' in release.prepare(*candidate)[0]['failures'][0]


def test_release_binds_app_bytes_across_documentation_only_commits(candidate):
    root,build_commit,hap,demo,verification=candidate
    app_digest=release._FINGERPRINT.fingerprint_app(root/'app')['appSourceSha256']
    report=json.loads(verification.read_text())
    assert app_digest==report['hap']['appSourceSha256']
    (root/'README.md').write_text('Fixture Team\nFixture Member\nFinal evidence documentation\n')
    release.git(root,'add','README.md');release.git(root,'commit','-m','Documentation after build')
    release_commit=release.git(root,'rev-parse','HEAD').decode().strip()
    report['sourceCommit']=release_commit;verification.write_text(json.dumps(report))
    result,files=release.prepare(root,release_commit,hap,demo,verification)
    assert result['status']=='ready'
    assert json.loads(files['environment-manifest.json'])['buildInputGitHead']==build_commit
    (root/'app/oh-package-lock.json5').write_text('different application bytes')
    release.git(root,'add','app');release.git(root,'commit','-m','App changed after build')
    report['sourceCommit']=release.git(root,'rev-parse','HEAD').decode().strip();verification.write_text(json.dumps(report))
    result,_=release.prepare(root,report['sourceCommit'],hap,demo,verification)
    assert result['status']=='failed' and 'build inputs' in result['failures'][0]


@pytest.mark.parametrize('change,expected',[
    ('video','Demonstration hash'),('review','completed committed review'),
    ('storyboard','Committed storyboard'),('duration','Demonstration duration')])
def test_release_requires_review_of_exact_demo(candidate,change,expected):
    root,commit,hap,demo,verification=candidate
    manifest_path=root/'docs/evidence/demo-manifest.json'
    manifest=json.loads(manifest_path.read_text())
    if change=='video':demo.write_bytes(b'different demo cut')
    elif change=='review':manifest['reviewed']=False
    elif change=='duration':manifest['durationSeconds']=180
    else:(root/'docs/demo-storyboard.json').write_text('{"scenes":[{"duration":180}]}')
    manifest_path.write_text(json.dumps(manifest))
    release.git(root,'add','docs')
    if change!='video':release.git(root,'commit','-m','Changed demo review fixture')
    commit=release.git(root,'rev-parse','HEAD').decode().strip()
    verification_report=json.loads(verification.read_text());verification_report['sourceCommit']=commit
    verification.write_text(json.dumps(verification_report))
    result,files=release.prepare(root,commit,hap,demo,verification)
    assert result['status']=='failed' and files=={}
    assert expected in result['failures'][0]
