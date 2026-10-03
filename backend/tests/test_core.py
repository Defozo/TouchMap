import io
import json
from pathlib import Path
import zipfile
import pytest
from PIL import Image
from pydantic import ValidationError
from shapely.geometry import Polygon as Shape
from touchmap.models import Diagram,Review
from touchmap.svg import convert_svg,transform,apply
from touchmap.packages import validate_package,build_package,sha256,read_json,revise,content_report
from touchmap.images import normalize_image
from touchmap.errors import TouchMapError

SVG=b'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect id="box" x="10" y="20" width="30" height="40" aria-label="Box"/></svg>'

@pytest.fixture
def diagram():return Diagram.model_validate(convert_svg(SVG)["diagram"])

def test_transform_order():
    assert apply(transform("translate(10,20) scale(2)"),(3,4))==(16,28)
    assert apply(transform("rotate(90 10 10)"),(20,10))==pytest.approx((10,20))

@pytest.mark.parametrize("aspect,first,last",[("xMidYMid meet",(0,60),(640,380)),("none",(0,0),(640,440)),("xMinYMin slice",(0,0),(880,440))])
def test_viewbox_maps_geometry_into_rendered_source_pixels(aspect,first,last):
    result=convert_svg(f'<svg width="640" height="440" viewBox="100 100 200 100" preserveAspectRatio="{aspect}"><rect x="100" y="100" width="200" height="100"/></svg>'.encode())
    region=result["diagram"]["regions"][0]
    points=region["polygons"][0]["outer"]
    assert (min(p["x"] for p in points),min(p["y"] for p in points))==pytest.approx(first)
    assert (max(p["x"] for p in points),max(p["y"] for p in points))==pytest.approx(last)
    assert result["diagram"]["source"]["viewBox"]==[100,100,200,100]

@pytest.mark.parametrize("rule,reverse,area",[("evenodd",False,6400),("nonzero",False,10000),("nonzero",True,6400)])
def test_holes_fill_rules(rule,reverse,area):
    inner="M20 20 V80 H80 V20Z" if reverse else "M20 20 H80 V80 H20Z"
    svg=f'<svg width="100" height="100"><path fill-rule="{rule}" d="M0 0 H100 V100 H0Z {inner}"/></svg>'.encode()
    result=convert_svg(svg)
    polygons=result["diagram"]["regions"][0]["polygons"]
    assert sum(Shape([(p["x"],p["y"]) for p in x["outer"]],[[(p["x"],p["y"]) for p in h] for h in x["holes"]]).area for x in polygons)==pytest.approx(area)

def test_curve_transform_and_inherited_styles():
    result=convert_svg(b'<svg width="200" height="200"><g transform="translate(5 10) scale(2)" fill="none" stroke="black" stroke-width="2"><path d="M0 0 C0 50 50 50 50 0"/></g></svg>')
    r=result["diagram"]["regions"][0]
    assert len(r["line"])>10 and r["line"][0]=={"x":5,"y":10} and r["line"][-1]=={"x":105,"y":10}
    assert r["lineWidth"]==4

@pytest.mark.parametrize("body",[b'<!DOCTYPE svg [<!ENTITY a SYSTEM "file:///etc/passwd">]><svg/>',b'<svg><script>alert(1)</script></svg>',b'<svg><image href="https://evil.test/pixel"/></svg>',b'<svg onload="alert(1)"/>',b'<svg><path fill="url(https://evil.test/x)"/></svg>'])
def test_reject_hostile_svg(body):
    with pytest.raises(TouchMapError):convert_svg(body)

def test_unsupported_not_silent():
    result=convert_svg(b'<svg width="100" height="100"><style>.a{fill:red}</style><rect class="a" width="20" height="20"/></svg>')
    assert any("style" in x for x in result["report"]["unsupported"])
    assert any("class" in x for x in result["report"]["unsupported"])

def test_nonuniform_stroke_and_invisible_lines():
    result=convert_svg(b'<svg width="200" height="200"><g transform="scale(3 1)"><line x1="10" y1="10" x2="20" y2="10" stroke="black" stroke-width="4"/></g><line x1="0" y1="0" x2="100" y2="100"/></svg>')
    assert len(result["diagram"]["regions"])==1
    region=result["diagram"]["regions"][0]
    assert region["polygons"] and not region["line"]
    xs=[p["x"] for p in region["polygons"][0]["outer"]]
    assert min(xs)==30 and max(xs)==60

def test_package_roundtrip_and_declared_trust(diagram):
    from touchmap.svg import render_preview
    data=build_package(diagram,{diagram.source.path:SVG,diagram.source.previewPath:render_preview(SVG)},"Author","Source review declaration","CC0")
    manifest,d,report,assets=validate_package(data)
    assert d==diagram and report["requiresLocalAcceptance"] and not report["readyOffline"]
    assert report["authorDeclaration"]["name"]=="Author"

def test_css_svg_preview_uses_shared_native_retention_fixture():
    import base64
    source=(Path(__file__).parents[2]/"contracts/fixtures/passive-svg.svg").read_bytes()
    result=convert_svg(source)
    assert result["diagram"]["source"]["sha256"]==sha256(source)
    assert any("style" in item for item in result["report"]["unsupported"])
    preview=base64.b64decode(result["previewBase64"])
    with Image.open(io.BytesIO(preview)) as rendered:
        assert rendered.size==(101,101)
        assert rendered.convert("RGB").getpixel((50,30))==(18,52,171)
    diagram=Diagram.model_validate(result["diagram"])
    package=build_package(diagram,{diagram.source.path:source,diagram.source.previewPath:preview},"Author","CSS source and preview reviewed","CC0")
    assert validate_package(package)[3][diagram.source.path]==source

@pytest.mark.parametrize("name",["../escape","/absolute","C:/root","x\\y","source/../bad","CON","a.","a//b"])
def test_zip_paths(name):
    out=io.BytesIO()
    with zipfile.ZipFile(out,"w") as z:z.writestr(name,b"x")
    with pytest.raises(TouchMapError):validate_package(out.getvalue())

def test_duplicate_case_archive():
    out=io.BytesIO()
    with zipfile.ZipFile(out,"w") as z:z.writestr("Source/a",b"a");z.writestr("source/A",b"b")
    with pytest.raises(TouchMapError,match="Duplicate"):validate_package(out.getvalue())

def test_invalid_graph(diagram):
    d=diagram.model_dump();d["relations"]=[{"id":"r","fromId":"box","toId":"missing","label":"r","direction":"forward","type":"flow","path":None,"evidence":[],"review":{"revision":1}}]
    with pytest.raises(ValidationError):Diagram.model_validate(d)

@pytest.mark.parametrize("data",[b'{"x":1,"x":2}',b'{"x":NaN}',b'{"x":1e400}',b'['*40+b'0'+b']'*40])
def test_json_safety(data):
    with pytest.raises(TouchMapError):read_json(data)

def test_revision_invalidates_without_mutation(diagram):
    diagram.regions[0].geometryReview=Review(status="reviewed",revision=1,reviewer="Teacher")
    new=revise(diagram,{"title":"Changed"})
    assert diagram.revision==1 and diagram.regions[0].geometryReview.status=="reviewed"
    assert new.revision==2 and new.regions[0].geometryReview.status=="draft" and new.audio==[]

def test_image_normalization_strips_metadata():
    im=Image.new("RGB",(10,20),"white");buf=io.BytesIO();im.save(buf,format="JPEG",exif=b'Exif\x00\x00')
    data,w,h=normalize_image(buf.getvalue())
    assert (w,h)==(10,20) and not Image.open(io.BytesIO(data)).info

def test_svg_preview_preserves_text_and_arrow_marker():
    import base64
    data=b'''<svg xmlns="http://www.w3.org/2000/svg" width="240" height="100"><defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="5" refY="5" orient="auto"><path d="M0 0 L10 5 L0 10 Z" fill="black"/></marker></defs><text x="10" y="35" font-family="sans-serif" font-size="24">TouchMap</text><line x1="10" y1="70" x2="200" y2="70" stroke="black" stroke-width="2" marker-end="url(#arrow)"/></svg>'''
    result=convert_svg(data);preview=base64.b64decode(result["previewBase64"])
    assert sha256(preview)==result["diagram"]["source"]["previewSha256"]
    with Image.open(io.BytesIO(preview)) as image:
        assert image.size==(240,100)
        alpha=image.convert("RGBA").getchannel("A")
        assert sum(1 for value in alpha.crop((10,10,160,38)).tobytes() if value>128)>200
        assert sum(1 for value in alpha.crop((192,62,208,68)).tobytes() if value>128)>15

def test_preview_integrity_and_required_pair(diagram):
    from touchmap.svg import render_preview
    preview=render_preview(SVG)
    with pytest.raises(TouchMapError,match="preview"):
        build_package(diagram,{diagram.source.path:SVG,diagram.source.previewPath:preview+b"changed"},"Author","Reviewed","CC0")
    wrong=diagram.model_dump();wrong["source"]["previewSha256"]=""
    with pytest.raises(ValidationError):Diagram.model_validate(wrong)

def test_escaped_external_svg_styles_are_rejected():
    for data in [br'<svg width="100" height="100"><rect style="fill:u\72l(file:///x)"/></svg>',br'<svg width="100" height="100"><style>@im\70ort "file:///x";</style></svg>']:
        with pytest.raises(TouchMapError):convert_svg(data)

def test_quoted_local_svg_marker_is_supported():
    source=b'''<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><defs><marker id="arrow" markerWidth="3" markerHeight="3"><path d="M0 0L3 1.5L0 3Z"/></marker></defs><line x1="10" y1="50" x2="80" y2="50" stroke="black" marker-end="url('#arrow')"/></svg>'''
    assert convert_svg(source)["diagram"]["regions"]

def test_portable_pcm_audio_contract_parity():
    from touchmap.audio import wav_duration
    root=Path(__file__).parents[2]
    data=(root/"samples/lumina-process/audio/seed-label.wav").read_bytes()
    assert wav_duration(data)==697
    for case in read_json((root/"contracts/fixtures/audio-mutations.json").read_bytes()):
        changed=bytearray(data);changed[case["offset"]:case["offset"]+len(case["bytes"])]=bytes(case["bytes"])
        with pytest.raises(TouchMapError):wav_duration(changed)
    for changed in (data[:-1],data+b"\0"):
        with pytest.raises(TouchMapError):wav_duration(changed)

def test_raster_source_dimensions_are_verified(diagram):
    image=Image.new("RGB",(10,20),"white");output=io.BytesIO();image.save(output,format="PNG");data=output.getvalue()
    source={**diagram.source.model_dump(),"path":"source/source.png","sha256":sha256(data),"previewPath":"","previewSha256":""}
    changed=Diagram.model_validate({**diagram.model_dump(),"source":source})
    with pytest.raises(TouchMapError,match="dimensions"):
        build_package(changed,{changed.source.path:data},"Author","Reviewed","CC0")

def test_portable_audio_duration_tolerance():
    root=Path(__file__).parents[2]
    _,original,_,assets=validate_package((root/"samples/lumina-process.touchmap").read_bytes())
    original.audio[0].durationMs+=51
    with pytest.raises(TouchMapError,match="50 ms"):
        build_package(original,{p:b for p,b in assets.items() if p not in ("manifest.json","diagram.json")},"Author","Reviewed","CC0")

def test_released_samples():
    samples=Path(__file__).parents[2]/"samples"
    for path in samples.glob("*.touchmap"):
        assert validate_package(path.read_bytes())[2]["readyOffline"],path.name

def test_polygon_contract_parity():
    from touchmap.models import Polygon
    fixtures=read_json((Path(__file__).parents[2]/"contracts/fixtures/polygons.json").read_bytes())
    for case in fixtures:
        if case["valid"]:Polygon.model_validate(case["polygon"])
        else:
            with pytest.raises(ValidationError):Polygon.model_validate(case["polygon"])

def test_untrusted_json_requires_actual_numeric_types(diagram):
    d=diagram.model_dump();d["revision"]="1"
    with pytest.raises(ValidationError):Diagram.model_validate(d)
    d=diagram.model_dump();d["regions"][0]["polygons"][0]["outer"][0]["x"]=1000001
    with pytest.raises(ValidationError):Diagram.model_validate(d)

def test_publication_requires_current_review_and_source_evidence(diagram):
    diagram.source.attribution="Owned synthetic fixture";diagram.source.license="CC0"
    diagram.regions[0].geometryReview=Review(status="reviewed",revision=1,reviewer="Teacher")
    diagram.regions[0].meaningReview=Review(status="reviewed",revision=1,reviewer="Teacher")
    assert content_report(diagram)["publishable"]
    diagram.regions[0].meaningReview.revision=2
    assert not content_report(diagram)["publishable"]
    diagram.regions[0].meaningReview.revision=1;diagram.regions[0].evidence=[]
    assert any("evidence" in i for i in content_report(diagram)["issues"])

def test_audio_target_kind_and_duplicates():
    d=read_json((Path(__file__).parents[2]/"samples/water-cycle/diagram.json").read_bytes())
    d["audio"][0]["kind"]="question";d["audio"][0]["targetId"]=d["regions"][0]["id"]
    with pytest.raises(ValidationError):Diagram.model_validate(d)
    d=read_json((Path(__file__).parents[2]/"samples/water-cycle/diagram.json").read_bytes())
    d["audio"].append({**d["audio"][0],"id":"duplicate-audio"})
    with pytest.raises(ValidationError):Diagram.model_validate(d)
