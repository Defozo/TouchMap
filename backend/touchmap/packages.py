from __future__ import annotations
import hashlib
import io
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
import stat
import tempfile
import unicodedata
import zipfile
import wave
import math
import struct
import zlib
from pydantic import ValidationError
from .errors import TouchMapError
from .models import Diagram, Manifest, Review
from .audio import wav_duration

MAX_COMPRESSED = 50 * 1024 * 1024
MAX_EXPANDED = 200 * 1024 * 1024
MAX_JSON = 16 * 1024 * 1024

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def safe_path(name: str) -> str:
    if not name or len(name) > 256 or name != unicodedata.normalize("NFC", name) or "\\" in name or ":" in name or "\x00" in name:
        raise TouchMapError("unsafe_path", "Package contains a non-portable path")
    p = PurePosixPath(name)
    if p.is_absolute() or any(x in ("", ".", "..") for x in name.split("/")):
        raise TouchMapError("unsafe_path", "Absolute or traversing path rejected")
    for part in p.parts:
        if part.endswith((" ", ".")) or part.split(".")[0].upper() in {"CON","PRN","AUX","NUL",*[f"COM{i}" for i in range(1,10)],*[f"LPT{i}" for i in range(1,10)]} or any(ord(c) < 32 for c in part):
            raise TouchMapError("unsafe_path", "Unsupported platform filename")
    return name

def json_bytes(value) -> bytes:
    if hasattr(value,"model_dump"):
        value = value.model_dump()
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")

def read_json(data: bytes):
    if len(data) > MAX_JSON:
        raise TouchMapError("json_limit", "JSON exceeds the bounded document size", 413)
    def pairs(items):
        out = {}
        for key, value in items:
            if key in out:
                raise ValueError("Duplicate JSON property")
            out[key] = value
        return out
    try:
        value = json.loads(data, object_pairs_hook=pairs, parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Non-finite number")))
        pending = [(value,0)]
        while pending:
            node, depth = pending.pop()
            if depth > 32:
                raise ValueError("JSON depth exceeds 32")
            if isinstance(node,float) and not math.isfinite(node):
                raise ValueError("Non-finite JSON number")
            if isinstance(node,dict):
                pending.extend((v,depth+1) for v in node.values())
            elif isinstance(node,list):
                pending.extend((v,depth+1) for v in node)
        return value
    except (ValueError, RecursionError, UnicodeError) as e:
        raise TouchMapError("invalid_json", str(e)) from None

def text_for(diagram: Diagram, target: str, kind: str) -> str | None:
    if target == diagram.packageId and kind == "overview":
        return diagram.description or diagram.title
    for r in diagram.regions:
        if r.id == target:
            return r.label if kind == "label" else r.description if kind == "description" else None
    for r in diagram.relations:
        if r.id == target and kind == "label":
            return r.label
    for q in diagram.questions:
        if q.id == target and kind == "question":
            return q.prompt
    return None

def content_report(diagram: Diagram) -> dict:
    issues = []
    reviews = {}
    for r in diagram.regions:
        reviews[r.id] = [r.geometryReview, r.meaningReview]
    for r in [*diagram.relations, *diagram.charts, *diagram.questions]:
        reviews[r.id] = [r.review]
    for fact_id, rs in reviews.items():
        if any(r.status != "reviewed" or r.revision != diagram.revision or r.issues for r in rs):
            issues.append(f"{fact_id}: review required for revision {diagram.revision}")
    values = {v.id:v for c in diagram.charts for s in c.series for v in s.values}
    relations = {r.id:r for r in diagram.relations}
    facts={r.id for r in [*diagram.regions,*diagram.relations,*diagram.charts]}|set(values)
    for fact in [*diagram.regions,*diagram.relations,*diagram.charts,*values.values()]:
        if not fact.evidence or any(not e.reference.strip() for e in fact.evidence):
            issues.append(f"{fact.id}: source-linked evidence needs review")
    if not diagram.title.strip():issues.append("Material title is required")
    for r in diagram.regions:
        if not r.label.strip():issues.append(f"{r.id}: region label is required")
    for r in diagram.relations:
        if not r.label.strip() or not r.type.strip():issues.append(f"{r.id}: relationship meaning is required")
    for q in diagram.questions:
        if not q.prompt.strip() or not q.explanation.strip() or any(not o.label.strip() for o in q.options):
            issues.append(f"{q.id}: question prompt, explanation and option labels are required")
        if not set(q.factIds).issubset(facts):
            issues.append(f"{q.id}: missing fact reference")
        if q.requiredRevision != diagram.revision:
            issues.append(f"{q.id}: question requires a different content revision")
        for fact in q.factIds:
            if fact in reviews and any(r.status!="reviewed" or r.revision!=diagram.revision for r in reviews[fact]):
                issues.append(f"{q.id}: referenced fact requires review")
            if fact in values:
                owner=next(c for c in diagram.charts if any(v.id==fact for s in c.series for v in s.values))
                if owner.review.status!="reviewed" or owner.review.revision!=diagram.revision:issues.append(f"{q.id}: referenced chart requires review")
            if q.type in ("direction", "sequence") and fact in relations and relations[fact].direction == "unknown":
                issues.append(f"{q.id}: an unknown direction cannot support this question")
            if q.type in ("value", "comparison") and fact in values and values[fact].value is None:
                issues.append(f"{q.id}: an unknown value cannot support this question")
    if not diagram.regions:
        issues.append("A learning material needs at least one region")
    if not diagram.source.attribution.strip() or diagram.source.attribution.startswith("Author must") or not diagram.source.license.strip() or diagram.source.license=="Unspecified":
        issues.append("Source attribution and license require an author declaration")
    required = {(r.id,"label") for r in diagram.regions} | {(r.id,"description") for r in diagram.regions if r.description} | {(r.id,"label") for r in diagram.relations} | {(q.id,"question") for q in diagram.questions} | {(diagram.packageId,"overview")}
    valid_audio = set()
    audio_issues = []
    for audio in diagram.audio:
        text = text_for(diagram,audio.targetId,audio.kind)
        if text is None or sha256(text.encode()) != audio.textHash or audio.language != diagram.language:
            audio_issues.append(f"{audio.id}: audio is stale or has the wrong language")
        else:
            valid_audio.add((audio.targetId,audio.kind))
    audio_issues.extend(f"{target}/{kind}: audio missing" for target,kind in sorted(required-valid_audio))
    return {"publishable": not issues, "readyOffline": not issues and not audio_issues, "issues":issues, "audioIssues":audio_issues}

def validate_package(data: bytes) -> tuple[Manifest, Diagram, dict, dict[str,bytes]]:
    if len(data) > MAX_COMPRESSED:
        raise TouchMapError("package_limit", "Package exceeds 50 MiB compressed",413)
    assets = {}
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            infos = z.infolist()
            if len(infos)>1000 or sum(i.file_size for i in infos)>MAX_EXPANDED:
                raise TouchMapError("package_limit", "Package exceeds entry or expanded size limits",413)
            seen = set()
            for i in infos:
                if i.file_size > 50 * 1024 * 1024:
                    raise TouchMapError("package_limit", "Individual package asset exceeds 50 MiB",413)
                safe_path(i.filename)
                name = i.filename.casefold()
                mode = (i.external_attr>>16)&0xFFFF
                if name in seen or i.is_dir() or stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0,stat.S_IFREG)) or i.flag_bits&1:
                    raise TouchMapError("unsafe_archive", "Duplicate, link, directory, special or encrypted archive entry")
                seen.add(name)
                if i.compress_type not in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED) or (i.file_size>1024*1024 and i.file_size/max(1,i.compress_size)>200):
                    raise TouchMapError("archive_bomb", "Unsupported compression or suspicious expansion ratio")
                with z.open(i) as f:
                    payload=f.read(min(i.file_size+1,MAX_EXPANDED+1))
                if len(payload)!=i.file_size:
                    raise TouchMapError("archive_size", "Archive size mismatch")
                assets[i.filename]=payload
    except (zipfile.BadZipFile,RuntimeError,NotImplementedError,OSError) as e:
        raise TouchMapError("invalid_zip", "Malformed or unreadable package") from None
    if not {"manifest.json","diagram.json"}.issubset(assets):
        raise TouchMapError("missing_document", "Package requires manifest.json and diagram.json")
    try:
        manifest=Manifest.model_validate(read_json(assets["manifest.json"]))
        diagram=Diagram.model_validate(read_json(assets["diagram.json"]))
    except ValidationError as e:
        raise TouchMapError("schema_invalid", "Package does not satisfy schema: " + "; ".join(".".join(map(str,x["loc"]))+": "+x["msg"] for x in e.errors(include_input=False)[:6])) from None
    if any(getattr(manifest,k)!=getattr(diagram,k) for k in ("packageId","revision","title","language")):
        raise TouchMapError("manifest_mismatch", "Manifest and diagram identity differ")
    expected={safe_path(a.path):a for a in manifest.assets}
    if len(expected)!=len(manifest.assets) or set(expected)!=(set(assets)-{"manifest.json"}):
        raise TouchMapError("asset_manifest", "Manifest must list every asset exactly once")
    for name, a in expected.items():
        if len(assets[name])!=a.bytes or sha256(assets[name])!=a.sha256:
            raise TouchMapError("integrity", f"Asset integrity failure: {name}")
    if diagram.source.path not in assets or sha256(assets[diagram.source.path])!=diagram.source.sha256:
        raise TouchMapError("source_integrity", "Source asset hash mismatch")
    if diagram.source.previewPath:
        preview_path=safe_path(diagram.source.previewPath)
        if preview_path not in assets or sha256(assets[preview_path])!=diagram.source.previewSha256:
            raise TouchMapError("preview_integrity","Source preview is missing or its hash differs")
        if not assets[preview_path].startswith(b"\x89PNG\r\n\x1a\n"):
            raise TouchMapError("preview_format","Source preview must be a PNG image")
        from .images import normalize_image
        if len(assets[preview_path])>10*1024*1024:raise TouchMapError("preview_limit","Source preview exceeds 10 MiB",413)
        _,width,height=normalize_image(assets[preview_path])
        if width!=math.ceil(diagram.source.width) or height!=math.ceil(diagram.source.height):
            raise TouchMapError("preview_dimensions","Source preview dimensions differ from source coordinates")
    for a in diagram.audio:
        if a.path not in assets or sha256(assets[a.path])!=a.sha256:
            raise TouchMapError("audio_integrity", "Audio asset missing or hash mismatch")
        if not a.path.lower().endswith(".wav"):
            raise TouchMapError("audio_format","Portable packages require PCM WAV recordings; convert other formats before importing")
        duration=wav_duration(assets[a.path])
        if abs(duration-a.durationMs)>50:raise TouchMapError("audio_invalid","Audio duration differs from its metadata by more than 50 ms")
    allowed={"diagram.json",diagram.source.path,*[a.path for a in diagram.audio]}
    if diagram.source.previewPath:allowed.add(diagram.source.previewPath)
    if set(expected)!=allowed:
        raise TouchMapError("unexpected_asset", "Teaching package may contain only declared source, diagram and audio; history is excluded")
    source_data=assets[diagram.source.path]
    if len(source_data)>10*1024*1024:raise TouchMapError("source_limit","Source exceeds 10 MiB",413)
    if diagram.source.path.lower().endswith(".svg"):
        from .svg import inspect_svg
        inspect_svg(source_data)
    else:
        from .images import normalize_image
        _,width,height=normalize_image(source_data)
        if width!=diagram.source.width or height!=diagram.source.height:
            raise TouchMapError("source_dimensions","Decoded source dimensions differ from its declared coordinate system")
    return manifest,diagram,{"valid":True,**content_report(diagram),"authorDeclaration":manifest.author.model_dump(),"requiresLocalAcceptance":True},assets

def write_atomic(path: Path, data: bytes):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd, staging=tempfile.mkstemp(prefix=".touchmap-",suffix=".staging",dir=path.parent)
    try:
        with os.fdopen(fd,"wb") as f:
            f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(staging,path)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)

def portable_archive(files: dict[str,bytes]) -> bytes:
    """Build root-relative UTF-8 ZIP entries within the importer's ratio policy.

    Normal DEFLATE can over-compress silence and simple patterns beyond 200:1.
    Fast DEFLATE and then Huffman-only preserve such valid recordings without
    weakening the untrusted archive import limits.
    """
    if not 2 <= len(files) <= 1000 or sum(map(len,files.values())) > MAX_EXPANDED:
        raise TouchMapError("package_limit", "Package exceeds entry or expanded size limits",413)
    seen=set(); output=bytearray(); central=[]
    for path,data in files.items():
        safe_path(path)
        if path.casefold() in seen or len(data)>50*1024*1024:
            raise TouchMapError("package_limit", "Duplicate path or individual asset exceeds 50 MiB",413)
        seen.add(path.casefold());name=path.encode("utf-8")
        for level,strategy in ((9,zlib.Z_DEFAULT_STRATEGY),(1,zlib.Z_DEFAULT_STRATEGY),(6,zlib.Z_HUFFMAN_ONLY)):
            compressor=zlib.compressobj(level,zlib.DEFLATED,-15,strategy=strategy)
            packed=compressor.compress(data)+compressor.flush()
            if len(data)<=max(1024*1024,len(packed)*200):break
        else:raise TouchMapError("archive_bomb","Cannot satisfy portable compression policy")
        crc=zlib.crc32(data);offset=len(output)
        output.extend(struct.pack("<IHHHHHIIIHH",0x04034b50,20,0x800,8,0,33,crc,len(packed),len(data),len(name),0))
        output.extend(name);output.extend(packed)
        central.append(struct.pack("<IHHHHHHIIIHHHHHII",0x02014b50,20,20,0x800,8,0,33,crc,len(packed),len(data),len(name),0,0,0,0,0,offset)+name)
        if len(output)+sum(map(len,central))+22>MAX_COMPRESSED:
            raise TouchMapError("package_limit","Package exceeds 50 MiB compressed; split the material",413)
    if not {"manifest.json","diagram.json"}.issubset(files):
        raise TouchMapError("missing_document","Package requires manifest.json and diagram.json")
    offset=len(output);directory=b"".join(central);output.extend(directory)
    output.extend(struct.pack("<IHHHHIIH",0x06054b50,0,0,len(files),len(files),len(directory),offset,0))
    return bytes(output)

def build_package(diagram: Diagram, assets: dict[str,bytes], author_name: str, declaration: str, license: str, output: Path | None=None) -> bytes:
    all_assets={**assets,"diagram.json":json_bytes(diagram)}
    manifest=Manifest(schemaVersion=1,packageId=diagram.packageId,revision=diagram.revision,title=diagram.title,language=diagram.language,author={"name":author_name,"declaration":declaration},license=license,assets=[{"path":safe_path(p),"sha256":sha256(b),"bytes":len(b),"mediaType":mimetypes.guess_type(p)[0] or "application/octet-stream"} for p,b in sorted(all_assets.items())])
    data=portable_archive({"manifest.json":json_bytes(manifest),**dict(sorted(all_assets.items()))})
    validate_package(data)
    if output:
        write_atomic(output,data)
    return data

def revise(diagram: Diagram, changes: dict) -> Diagram:
    """Conservative invalidation; prior immutable input remains unchanged."""
    data=diagram.model_dump()
    for forbidden in ("schemaVersion","packageId","revision","audio"):
        if forbidden in changes:
            raise TouchMapError("immutable_field",f"Cannot edit {forbidden} directly")
    data.update(changes)
    data["revision"]+=1
    data["audio"]=[]
    for r in data["regions"]:
        for key in ("geometryReview","meaningReview"):
            r[key]=Review(revision=data["revision"]).model_dump()
    for r in [*data["relations"],*data["charts"],*data["questions"]]:
        r["review"]=Review(revision=data["revision"]).model_dump()
    for q in data["questions"]:
        q["requiredRevision"]=data["revision"]
    return Diagram.model_validate(data)
