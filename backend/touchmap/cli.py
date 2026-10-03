from __future__ import annotations
import argparse
import asyncio
import base64
import io
import json
import sys
import time
import uuid
from pathlib import Path
import wave
from pydantic import ValidationError
from PIL import Image, ImageDraw
from .errors import TouchMapError
from .images import normalize_image
from .models import Diagram, Manifest, Source, Audio, Review
from .packages import json_bytes, read_json, sha256, write_atomic, validate_package, build_package, content_report, text_for, revise, safe_path
from .providers import Providers
from .settings import Settings
from .store import Store
from .svg import convert_svg
from .audio import wav_duration

def load_diagram(path):return Diagram.model_validate(read_json(Path(path).read_bytes()))
def save_diagram(path,diagram):write_atomic(Path(path),json_bytes(diagram))

def main():
    parser=argparse.ArgumentParser(prog="touchmap",description="Offline TouchMap authoring and optional preparation service")
    commands=parser.add_subparsers(dest="command",required=True)
    svg=commands.add_parser("convert-svg",help="Extract supported SVG geometry to an editable draft directory")
    svg.add_argument("input",type=Path);svg.add_argument("output",type=Path);svg.add_argument("--language",default="en");svg.add_argument("--title",default="Imported diagram")
    manual=commands.add_parser("new-image",help="Create an offline manual image authoring draft")
    manual.add_argument("input",type=Path);manual.add_argument("output",type=Path);manual.add_argument("--title",required=True);manual.add_argument("--language",default="en")
    validate=commands.add_parser("validate");validate.add_argument("input",type=Path)
    edit=commands.add_parser("edit",help="Apply a JSON top-level patch, creating a new revision and invalidating review/audio")
    edit.add_argument("diagram",type=Path);edit.add_argument("patch",type=Path);edit.add_argument("output",type=Path)
    review=commands.add_parser("review",help="Explicit author declaration of a completed source review")
    review.add_argument("diagram",type=Path);review.add_argument("--reviewer",required=True);review.add_argument("--ids",nargs="+",required=True);review.add_argument("--aspect",choices=["geometry","meaning","fact"],required=True)
    audio=commands.add_parser("import-audio");audio.add_argument("diagram",type=Path);audio.add_argument("file",type=Path);audio.add_argument("--target",required=True);audio.add_argument("--kind",choices=["label","description","question","overview"],required=True);audio.add_argument("--provenance",required=True)
    pack=commands.add_parser("pack");pack.add_argument("diagram",type=Path);pack.add_argument("output",type=Path);pack.add_argument("--author",required=True);pack.add_argument("--declaration",required=True);pack.add_argument("--license",required=True);pack.add_argument("--allow-draft",action="store_true")
    extract=commands.add_parser("unpack");extract.add_argument("input",type=Path);extract.add_argument("output",type=Path)
    pair=commands.add_parser("pair-code",help="Issue a five-minute one-use code using the service state directory")
    serve=commands.add_parser("serve");serve.add_argument("--host",default="127.0.0.1");serve.add_argument("--port",type=int,default=8787);serve.add_argument("--certfile");serve.add_argument("--keyfile")
    schemas=commands.add_parser("schemas");schemas.add_argument("output",type=Path)
    smoke=commands.add_parser("provider-smoke",help="Live synthetic image test, no private input")
    smoke.add_argument("--output",type=Path,required=True);smoke.add_argument("--image",type=Path)
    args=parser.parse_args()
    try:
        result=run(args)
        if result is not None:print(json.dumps(result,ensure_ascii=False,indent=2))
    except (TouchMapError,ValidationError,OSError,ValueError) as e:
        code=e.code if isinstance(e,TouchMapError) else "invalid_input"
        # Validation locations are useful without echoing potentially private input values.
        message=e.message if isinstance(e,TouchMapError) else "Validation or filesystem operation failed"
        print(json.dumps({"error":{"code":code,"message":message}}),file=sys.stderr);sys.exit(1)

def run(args):
    if args.command=="convert-svg":
        data=args.input.read_bytes();result=convert_svg(data,language=args.language,title=args.title)
        args.output.mkdir(parents=True,exist_ok=True)
        write_atomic(args.output/"source/source.svg",data);write_atomic(args.output/"diagram.json",json_bytes(result["diagram"]));write_atomic(args.output/"conversion-report.json",json_bytes(result["report"]))
        write_atomic(args.output/result["diagram"]["source"]["previewPath"],base64.b64decode(result["previewBase64"],validate=True))
        return {"draft":str(args.output/"diagram.json"),"report":result["report"]}
    if args.command=="new-image":
        data,w,h=normalize_image(args.input.read_bytes())
        diagram=Diagram(packageId="material-"+uuid.uuid4().hex[:12],revision=1,title=args.title,language=args.language,source=Source(id="source",sha256=sha256(data),width=w,height=h,path="source/source.png",attribution="Author must supply attribution",license="Unspecified",viewBox=[0,0,w,h]),regions=[])
        write_atomic(args.output/diagram.source.path,data);save_diagram(args.output/"diagram.json",diagram)
        return {"draft":str(args.output/"diagram.json"),"cloudUsed":False}
    if args.command=="validate":
        if args.input.suffix==".touchmap":return validate_package(args.input.read_bytes())[2]
        diagram=load_diagram(args.input);return {"valid":True,**content_report(diagram)}
    if args.command=="edit":
        if args.output.resolve()==args.diagram.resolve():raise TouchMapError("immutable_revision","Write an edited revision to a new diagram path")
        original=load_diagram(args.diagram)
        diagram=revise(original,read_json(args.patch.read_bytes()))
        if args.output.parent.resolve()!=args.diagram.parent.resolve():
            write_atomic(args.output.parent/safe_path(diagram.source.path),(args.diagram.parent/safe_path(original.source.path)).read_bytes())
            if original.source.previewPath and diagram.source.previewPath:
                write_atomic(args.output.parent/safe_path(diagram.source.previewPath),(args.diagram.parent/safe_path(original.source.previewPath)).read_bytes())
        save_diagram(args.output,diagram)
        return {"revision":diagram.revision,**content_report(diagram)}
    if args.command=="review":
        diagram=load_diagram(args.diagram)
        if not args.reviewer.strip():raise ValueError("Reviewer required")
        pending=set(args.ids)
        for item in [*diagram.regions,*diagram.relations,*diagram.charts,*diagram.questions]:
            if item.id not in pending:continue
            review=Review(status="reviewed",revision=diagram.revision,reviewer=args.reviewer,issues=[])
            if args.aspect=="geometry" and hasattr(item,"geometryReview"):item.geometryReview=review
            elif args.aspect=="meaning" and hasattr(item,"meaningReview"):item.meaningReview=review
            elif args.aspect=="fact" and hasattr(item,"review"):item.review=review
            else:raise TouchMapError("review_aspect","Selected element does not support that review aspect")
            pending.remove(item.id)
        if pending:raise TouchMapError("review_id","One or more selected IDs do not exist")
        diagram=Diagram.model_validate(diagram.model_dump());save_diagram(args.diagram,diagram)
        return content_report(diagram)
    if args.command=="import-audio":
        diagram=load_diagram(args.diagram);text=text_for(diagram,args.target,args.kind)
        if not text:raise TouchMapError("audio_target","Target has no matching text")
        data=args.file.read_bytes()
        if len(data)>10*1024*1024:raise TouchMapError("audio_limit","Recording exceeds 10 MiB")
        if args.file.suffix.lower()!=".wav":
            raise TouchMapError("audio_format","Convert the licensed recording first: ffmpeg -i INPUT -acodec pcm_s16le -ar 24000 -ac 1 OUTPUT.wav ; then import OUTPUT.wav")
        duration=wav_duration(data)
        path="audio/"+sha256(data)+args.file.suffix.lower()
        asset=Audio(id="audio-"+args.target+"-"+args.kind,targetId=args.target,kind=args.kind,path=path,textHash=sha256(text.encode()),language=diagram.language,provider="Imported licensed recording",voice=args.provenance,sha256=sha256(data),durationMs=duration)
        diagram.audio=[a for a in diagram.audio if (a.targetId,a.kind)!=(args.target,args.kind)]+[asset]
        write_atomic(args.diagram.parent/path,data);save_diagram(args.diagram,diagram)
        return content_report(diagram)
    if args.command=="pack":
        diagram=load_diagram(args.diagram);report=content_report(diagram)
        if not args.allow_draft and not report["publishable"]:raise TouchMapError("review_required","Complete source review and resolve questions before publication")
        paths={diagram.source.path,*[a.path for a in diagram.audio]}
        if diagram.source.previewPath:paths.add(diagram.source.previewPath)
        assets={p:(args.diagram.parent/safe_path(p)).read_bytes() for p in paths}
        data=build_package(diagram,assets,args.author,args.declaration,args.license,args.output)
        return {"path":str(args.output),"sha256":sha256(data),**report}
    if args.command=="unpack":
        manifest,diagram,report,assets=validate_package(args.input.read_bytes())
        if args.output.exists() and any(args.output.iterdir()):raise TouchMapError("output_not_empty","Choose a new or empty directory")
        for p,data in assets.items():write_atomic(args.output/safe_path(p),data)
        return report
    if args.command=="pair-code":
        cfg=Settings();cfg.validate();return {"code":Store(cfg).pairing_code(),"expiresInSeconds":300,"uses":1}
    if args.command=="serve":
        cfg=Settings();cfg.validate()
        if args.host not in ("127.0.0.1","localhost","::1") and (not cfg.remote or not args.certfile or not args.keyfile):raise TouchMapError("remote_configuration","External binding requires remote mode, session signing secret, certificate and private key")
        import uvicorn
        uvicorn.run("touchmap.api:app",host=args.host,port=args.port,ssl_certfile=args.certfile,ssl_keyfile=args.keyfile,proxy_headers=False,access_log=False)
        return None
    if args.command=="schemas":
        from .api import create_app,SpeechRequest
        from .providers import Draft
        args.output.mkdir(parents=True,exist_ok=True)
        for name,model in [("diagram",Diagram),("manifest",Manifest),("audio-request",SpeechRequest),("ai-draft",Draft)]:write_atomic(args.output/(name+".schema.json"),json_bytes(model.model_json_schema()))
        write_atomic(args.output/"openapi.json",json_bytes(create_app().openapi()))
        return {"schemas":str(args.output)}
    if args.command=="provider-smoke":return asyncio.run(provider_smoke(args))

async def provider_smoke(args):
    cfg=Settings();cfg.ai_enabled=True;cfg.validate()
    if args.image:data,w,h=normalize_image(args.image.read_bytes())
    else:
        im=Image.new("RGB",(640,320),"white");draw=ImageDraw.Draw(im)
        draw.rectangle((40,100,220,230),outline="black",width=4);draw.text((90,150),"SEED",fill="black",font_size=28)
        draw.rectangle((420,100,600,230),outline="black",width=4);draw.text((450,150),"PLANT",fill="black",font_size=28)
        draw.line((230,165,405,165),fill="black",width=5);draw.polygon([(405,165),(383,154),(383,176)],fill="black")
        draw.text((265,125),"grows into",fill="black",font_size=20)
        stream=io.BytesIO();im.save(stream,format="PNG");data=stream.getvalue();w,h=im.size
    started=time.monotonic()
    report={"provider":"Google","model":cfg.gemini_model,"source":"owned synthetic SEED to PLANT diagram" if not args.image else "explicit operator supplied evaluation image","sourceHash":sha256(data),"inputBytes":len(data),"schemaVersion":1,"store":False}
    try:
        result=await Providers(cfg).analyze(data,w,h,1,"en")
        report.update({"success":True,"durationMs":round((time.monotonic()-started)*1000),"regions":len(result["diagram"]["regions"]),"relations":len(result["diagram"]["relations"]),"report":result["report"],"usage":result.get("usage")})
        write_atomic(args.output.with_suffix(".draft.json"),json_bytes(result["diagram"]))
    except TouchMapError as exc:
        report.update({"success":False,"durationMs":round((time.monotonic()-started)*1000),"error":{"code":exc.code,"message":exc.message}})
    write_atomic(args.output,json_bytes(report));return report

if __name__=="__main__":main()
