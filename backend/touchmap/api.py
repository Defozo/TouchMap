from __future__ import annotations
import asyncio
import base64
from contextlib import asynccontextmanager
import ipaddress
import logging
import re
import time
import uuid
from fastapi import FastAPI, Request, UploadFile, File, Form, Depends
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import Field, ValidationError, model_validator
from .errors import TouchMapError
from .images import normalize_image
from .models import Model, Id, Text, Hash
from .packages import sha256, json_bytes, validate_package
from .providers import Providers
from .settings import Settings
from .store import Store
from .svg import convert_svg

logger=logging.getLogger("touchmap")

class PairRequest(Model):
    code: str = Field(min_length=6,max_length=128)
class LabelRequest(Model):
    targetId: Id
    kind: str = Field(pattern="^(label|description|question|overview)$")
    text: str = Field(min_length=1,max_length=4000)
    textHash: Hash
    @model_validator(mode="after")
    def valid_hash(self):
        if sha256(self.text.encode())!=self.textHash:raise ValueError("Text hash mismatch")
        return self
class SpeechRequest(Model):
    requestId: Id
    sourceHash: Hash
    draftRevision: int = Field(ge=1)
    language: str = Field(pattern=r"^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$",max_length=35)
    consent: bool
    labels: list[LabelRequest] = Field(min_length=1,max_length=100)
    @model_validator(mode="after")
    def total(self):
        if sum(len(l.text) for l in self.labels)>20000:raise ValueError("Split batches at 20000 characters")
        if len({(l.targetId,l.kind) for l in self.labels})!=len(self.labels):raise ValueError("Duplicate label target and kind")
        return self

class BodyLimit:
    def __init__(self,app):self.app=app
    async def __call__(self,scope,receive,send):
        if scope["type"]!="http":return await self.app(scope,receive,send)
        limit=51*1024*1024 if scope.get("path")=="/v1/packages/validate" else 11*1024*1024
        count=0
        async def limited_receive():
            nonlocal count
            event=await receive();count+=len(event.get("body",b""))
            if count>limit:raise TouchMapError("upload_limit","Request exceeds upload limit",413)
            return event
        length=dict(scope.get("headers",[])).get(b"content-length")
        if length and (not length.isdigit() or int(length)>limit):
            return await JSONResponse({"error":{"code":"upload_limit","message":"Request exceeds upload limit"},"requestId":""},status_code=413)(scope,receive,send)
        await self.app(scope,limited_receive,send)

def create_app(settings:Settings|None=None,providers=None):
    cfg=settings or Settings();cfg.validate();store=Store(cfg);provider=providers or Providers(cfg)
    @asynccontextmanager
    async def lifespan(app):
        store.cleanup(startup=True)
        yield
    app=FastAPI(title="TouchMap preparation API",version="1.0.0",lifespan=lifespan)
    app.add_middleware(BodyLimit)
    app.state.settings=cfg;app.state.store=store;app.state.providers=provider

    @app.exception_handler(TouchMapError)
    async def known_error(request,exc):
        return JSONResponse({"error":{"code":exc.code,"message":exc.message},"requestId":getattr(request.state,"request_id","")},status_code=exc.status)
    @app.exception_handler(RequestValidationError)
    async def input_error(request,exc):
        return JSONResponse({"error":{"code":"invalid_input","message":"Request fields do not satisfy the published schema"},"requestId":getattr(request.state,"request_id","")},status_code=422)
    @app.exception_handler(ValidationError)
    async def schema_error(request,exc):
        return JSONResponse({"error":{"code":"schema_invalid","message":"Input does not satisfy diagram schema"},"requestId":getattr(request.state,"request_id","")},status_code=422)
    @app.middleware("http")
    async def transport(request,call_next):
        started=time.monotonic();request.state.request_id=""
        host=request.client.host if request.client else ""
        try:
            local=ipaddress.ip_address(host).is_loopback
        except ValueError:local=host=="testclient"
        if not cfg.remote and not local:
            return JSONResponse({"error":{"code":"loopback_only","message":"Remote access requires HTTPS and pairing configuration"},"requestId":""},status_code=403)
        if cfg.remote and request.url.scheme!="https":
            return JSONResponse({"error":{"code":"https_required","message":"HTTPS is required"},"requestId":""},status_code=403)
        try:
            response=await call_next(request)
        except TouchMapError as exc:return await known_error(request,exc)
        except Exception:
            logger.error("request_failed request_id=%s code=internal_error",request.state.request_id)
            return JSONResponse({"error":{"code":"internal_error","message":"Request failed; saved work was not changed"},"requestId":request.state.request_id},status_code=500)
        logger.info("request_id=%s status=%s duration_ms=%d",request.state.request_id,response.status_code,(time.monotonic()-started)*1000)
        response.headers["Cache-Control"]="no-store"
        response.headers["X-Content-Type-Options"]="nosniff"
        return response

    async def session(request:Request):
        token=request.headers.get("authorization","")
        if not token and not cfg.remote:
            value="local"
        else:
            if not token.startswith("Bearer "):raise TouchMapError("authentication_required","Pair with this preparation service",401)
            value=store.authenticate(token[7:])
        store.throttle("session:"+value)
        return value

    def fields(request,request_id,revision,language):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}",request_id) or revision<1 or not re.fullmatch(r"[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*",language):
            raise TouchMapError("invalid_input","Invalid request ID, revision or language",422)
        request.state.request_id=request_id

    async def read_upload(file,limit):
        try:data=await file.read(limit+1)
        finally:await file.close()
        if len(data)>limit:raise TouchMapError("upload_limit","Upload exceeds endpoint limit",413)
        return data

    async def run_job(request_id,session_id,fingerprint,source_hash,revision,provider_name,model,operation,analysis=False,reserve=0):
        cached=store.begin(request_id,session_id,fingerprint,analysis,reserve)
        if cached is not None:return cached
        try:
            result=await asyncio.wait_for(operation(),45)
            envelope={"requestId":request_id,"contractVersion":1,"sourceHash":source_hash,"draftRevision":revision,"provider":provider_name,"model":model,"result":result}
            if len(json_bytes(envelope))>50*1024*1024:raise TouchMapError("result_limit","Generated result exceeds output limit",413)
            store.finish(request_id,envelope)
            return envelope
        except asyncio.TimeoutError:
            store.fail(request_id,"outcome_unknown")
            raise TouchMapError("outcome_unknown","Request deadline exceeded; provider outcome is unknown. Retry explicitly with a new request ID.",504) from None
        except asyncio.CancelledError:
            store.job(request_id,session_id,cancel=True)
            raise
        except TouchMapError as e:
            store.fail(request_id,e.code);raise
        except Exception:
            store.fail(request_id,"failed");raise

    @app.get("/health/live")
    async def live():return {"status":"live","contractVersion":1}
    @app.get("/health/ready")
    async def ready():
        return {"status":"ready","contractVersion":1,"svg":True,"aiConfigured":bool(cfg.ai_enabled and cfg.google_key),"ttsConfigured":bool(cfg.tts_enabled and cfg.eleven_key and cfg.voice),"remote":cfg.remote,"providerInferenceVerified":False,"models":{"image":cfg.gemini_model,"speech":cfg.tts_model},"limits":{"imageBytes":10485760,"imagePixels":20000000,"packageBytes":52428800,"expandedBytes":209715200,"regions":500,"relations":2000,"geometryPoints":100000}}
    @app.post("/v1/sessions/pair")
    async def pair(body:PairRequest,request:Request):
        store.throttle("pair:"+(request.client.host if request.client else ""),5)
        return store.pair(body.code)
    @app.delete("/v1/sessions/current")
    async def revoke(session_id=Depends(session)):
        with store.connection() as db:
            db.execute("DELETE FROM sessions WHERE hash=?",(session_id,))
            db.execute("UPDATE jobs SET state='cancelled',result=NULL WHERE session=?",(session_id,))
        return {"revoked":True}
    @app.get("/v1/jobs/{request_id}")
    async def get_job(request_id:str,session_id=Depends(session)):return store.job(request_id,session_id)
    @app.delete("/v1/jobs/{request_id}")
    async def cancel_job(request_id:str,session_id=Depends(session)):return store.job(request_id,session_id,True)

    @app.post("/v1/import/svg")
    async def import_svg(request:Request,file:UploadFile=File(),draftRevision:int=Form(),language:str=Form(),requestId:str=Form(),session_id=Depends(session)):
        fields(request,requestId,draftRevision,language);data=await read_upload(file,10*1024*1024);digest=sha256(data)
        async def operation():return await asyncio.to_thread(convert_svg,data,draftRevision,language)
        return await run_job(requestId,session_id,sha256(json_bytes(["svg",digest,draftRevision,language])),digest,draftRevision,"local","svg-profile-v1",operation)

    @app.post("/v1/analyze/image")
    async def analyze(request:Request,file:UploadFile=File(),draftRevision:int=Form(),language:str=Form(),requestId:str=Form(),sourceHash:str=Form(),consent:bool=Form(),session_id=Depends(session)):
        fields(request,requestId,draftRevision,language)
        if not consent:raise TouchMapError("consent_required","Explicit image upload consent is required",403)
        data=await read_upload(file,10*1024*1024);digest=sha256(data)
        if sourceHash!=digest:raise TouchMapError("source_hash","Uploaded bytes do not match sourceHash",409)
        clean,w,h=normalize_image(data)
        if len(clean)>10*1024*1024:raise TouchMapError("normalized_image_limit","Normalized PNG exceeds 10 MiB; crop or simplify the image",413)
        async def operation():return await provider.analyze(clean,w,h,draftRevision,language)
        return await run_job(requestId,session_id,sha256(json_bytes(["image",digest,draftRevision,language])),digest,draftRevision,"Google",cfg.gemini_model,operation,True,.20)

    @app.post("/v1/audio/labels")
    async def speech(body:SpeechRequest,request:Request,session_id=Depends(session)):
        fields(request,body.requestId,body.draftRevision,body.language)
        if not body.consent:raise TouchMapError("consent_required","Separate speech upload consent is required",403)
        async def operation():
            result=[]
            for item in body.labels:
                key=sha256(json_bytes([item.textHash,body.language,cfg.voice,cfg.tts_model]))
                cached=store.audio(key)
                if cached is None:
                    data,duration=await provider.speech(item.text,body.language)
                    cached={"dataBase64":base64.b64encode(data).decode(),"sha256":sha256(data),"durationMs":duration}
                    store.audio(key,cached)
                result.append({"id":"audio-"+item.targetId+"-"+item.kind,"targetId":item.targetId,"kind":item.kind,"path":"audio/"+key+".wav","textHash":item.textHash,"language":body.language,"provider":"ElevenLabs","voice":cfg.voice,**cached})
            return {"audio":result}
        reserve=max(.01,sum(len(l.text) for l in body.labels)*.0002)
        return await run_job(body.requestId,session_id,sha256(json_bytes(body)),body.sourceHash,body.draftRevision,"ElevenLabs",cfg.tts_model,operation,reserve=reserve)

    @app.post("/v1/packages/validate")
    async def validate(request:Request,file:UploadFile=File(),requestId:str=Form(),session_id=Depends(session)):
        fields(request,requestId,1,"en");data=await read_upload(file,50*1024*1024)
        manifest,diagram,report,_=await asyncio.to_thread(validate_package,data)
        return {"requestId":requestId,"contractVersion":1,"sourceHash":diagram.source.sha256,"draftRevision":diagram.revision,"provider":"local","model":"package-v1","result":report}
    return app

app=create_app()
