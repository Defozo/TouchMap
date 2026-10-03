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


def presentation_pptx(with_notes=True):
    """Minimal one-slide OOXML package with real slide and notes relationships."""
    p=release._PRESENTATION.PRESENTATION_NS;a=release._PRESENTATION.DRAWING_NS
    r=release._PRESENTATION.OFFICE_REL_NS;rels=release._PRESENTATION.REL_NS
    parts={
        '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
        '_rels/.rels':f'<Relationships xmlns="{rels}"/>',
        'ppt/presentation.xml':f'<p:presentation xmlns:p="{p}" xmlns:r="{r}"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst></p:presentation>',
        'ppt/_rels/presentation.xml.rels':f'<Relationships xmlns="{rels}"><Relationship Id="rId1" Type="{r}/slide" Target="slides/slide1.xml"/></Relationships>',
        'ppt/slides/slide1.xml':f'<p:sld xmlns:p="{p}"/>',
        'ppt/slides/_rels/slide1.xml.rels':f'<Relationships xmlns="{rels}"><Relationship Id="rId1" Type="{r}/notesSlide" Target="../notesSlides/notesSlide1.xml"/></Relationships>',
        'ppt/notesSlides/notesSlide1.xml':f'<p:notes xmlns:p="{p}" xmlns:a="{a}"><p:cSld><p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>{"Explain this fixture slide." if with_notes else ""}</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:notes>'}
    return release.deterministic_zip({name:value.encode() for name,value in parts.items()})


@pytest.fixture
def presentation_candidate(candidate,monkeypatch):
    root,commit,hap,demo,verification=candidate
    pdf=root/'dist/deck.pdf';pdf.write_bytes(b'%PDF-1.7\nsynthetic page metadata fixture')
    pptx=root/'dist/deck.pptx';pptx.write_bytes(presentation_pptx())
    manifest={'reviewed':True,'language':'en','slideCount':1,
        'pdf':{'path':'dist/deck.pdf','sha256':release.sha256(pdf.read_bytes())},
        'pptx':{'path':'dist/deck.pptx','sha256':release.sha256(pptx.read_bytes())}}
    (root/release._PRESENTATION.MANIFEST).write_text(json.dumps(manifest))
    release.git(root,'add','docs');release.git(root,'commit','-m','Reviewed presentation fixture')
    commit=release.git(root,'rev-parse','HEAD').decode().strip()
    monkeypatch.setattr(release._PRESENTATION,'inspect_pdf',lambda path:1)
    report=json.loads(verification.read_text());report['sourceCommit']=commit
    report['presentation']=release._PRESENTATION.reviewed_presentation(root,release.source_files(root,commit))[0]
    report['gates']['finalEnglishPresentation']={'status':'passed'}
    verification.write_text(json.dumps(report))
    return root,commit,hap,demo,verification


def test_release_includes_exact_reviewed_pdf_editable_slides_and_notes(presentation_candidate):
    root,commit,hap,demo,verification=presentation_candidate
    result,files=release.prepare(*presentation_candidate)
    assert result['status']=='ready'
    details=json.loads(files['release-manifest.json'])['presentation']
    assert details['pdf']['pages']==details['pptx']['slides']==details['pptx']['notes']==1
    assert files['presentation/deck.pdf']==(root/'dist/deck.pdf').read_bytes()
    assert files['presentation/deck.pptx']==(root/'dist/deck.pptx').read_bytes()
    assert details['manifestSha256']==release.sha256(release.source_files(root,commit)[release._PRESENTATION.MANIFEST])
    for row in files['SHA256SUMS'].decode().splitlines():
        digest,path=row.split('  ',1);assert release.sha256(files[path])==digest


@pytest.mark.parametrize('change,expected',[
    ('pdf_hash','PDF hash'),('pptx_hash','PPTX hash'),('missing','Missing or empty'),
    ('review','completed committed review'),('language','English with 1 to 10'),
    ('pages','PDF page count'),('slides','PPTX slide count'),('notes','nonempty speaker notes'),
    ('escape','safe dist-relative'),('size','10 MB upload limit'),
    ('verification','differs from release verification')])
def test_release_rejects_unreviewed_or_unusable_presentation(presentation_candidate,monkeypatch,change,expected):
    root,commit,hap,demo,verification=presentation_candidate
    path=root/release._PRESENTATION.MANIFEST;manifest=json.loads(path.read_text())
    if change=='pdf_hash':(root/'dist/deck.pdf').write_bytes(b'%PDF-different')
    elif change=='pptx_hash':(root/'dist/deck.pptx').write_bytes(presentation_pptx(False))
    elif change=='missing':(root/'dist/deck.pdf').unlink()
    elif change=='review':manifest['reviewed']=False
    elif change=='language':manifest['language']='pl'
    elif change=='pages':monkeypatch.setattr(release._PRESENTATION,'inspect_pdf',lambda path:2)
    elif change=='slides':
        manifest['slideCount']=2;monkeypatch.setattr(release._PRESENTATION,'inspect_pdf',lambda path:2)
    elif change=='notes':
        value=presentation_pptx(False);(root/'dist/deck.pptx').write_bytes(value)
        manifest['pptx']['sha256']=release.sha256(value)
    elif change=='escape':manifest['pdf']['path']='dist/../deck.pdf'
    elif change=='size':
        with (root/'dist/deck.pdf').open('r+b') as handle:handle.truncate(10_000_001)
    else:
        report=json.loads(verification.read_text());report['presentation']['pdf']['bytes']+=1
        verification.write_text(json.dumps(report))
    original=path.read_text();path.write_text(json.dumps(manifest))
    if path.read_text()!=original:
        release.git(root,'add','docs');release.git(root,'commit','-m','Invalid presentation fixture')
        commit=release.git(root,'rev-parse','HEAD').decode().strip()
        report=json.loads(verification.read_text());report['sourceCommit']=commit
        verification.write_text(json.dumps(report))
    result,files=release.prepare(root,commit,hap,demo,verification)
    assert result['status']=='failed' and files=={}
    assert expected in result['failures'][0]


@pytest.mark.parametrize('uncommitted',[False,True])
def test_declared_presentation_cannot_be_silently_omitted(candidate,uncommitted):
    root,commit,hap,demo,verification=candidate
    report=json.loads(verification.read_text());report['gates']['finalEnglishPresentation']={'status':'passed'}
    verification.write_text(json.dumps(report))
    if uncommitted:(root/release._PRESENTATION.MANIFEST).write_text('{}')
    result,files=release.prepare(*candidate)
    assert result['status']=='failed' and files=={}
    assert ('not committed' if uncommitted else 'requires a committed') in result['failures'][0]


def test_pdf_page_verification_explains_missing_dependency(tmp_path,monkeypatch):
    monkeypatch.setattr(release._PRESENTATION.shutil,'which',lambda name:None)
    with pytest.raises(ValueError,match='install Poppler'):
        release._PRESENTATION.inspect_pdf(tmp_path/'deck.pdf')


@pytest.mark.parametrize('target,valid',[
    ('/ppt/slides/slide1.xml',True),
    ('../../../slide1.xml',False),
    ('//example.invalid/slide1.xml',False)])
def test_presentation_resolves_package_root_and_rejects_external_escape(target,valid):
    with zipfile.ZipFile(io.BytesIO(presentation_pptx())) as archive:
        parts={name:archive.read(name) for name in archive.namelist()}
    name='ppt/_rels/presentation.xml.rels'
    parts[name]=parts[name].replace(b'Target="slides/slide1.xml"',f'Target="{target}"'.encode())
    name='ppt/slides/_rels/slide1.xml.rels'
    parts[name]=parts[name].replace(b'Target="../notesSlides/notesSlide1.xml"',b'Target="/ppt/notesSlides/notesSlide1.xml"')
    data=release.deterministic_zip(parts)
    if valid:assert release._PRESENTATION.inspect_pptx(data)==(1,1)
    else:
        with pytest.raises(ValueError,match='escapes|internal'):
            release._PRESENTATION.inspect_pptx(data)
