import asyncio
import io
import json
import time
from pathlib import Path
import httpx
from fastapi.testclient import TestClient
from PIL import Image
import pytest
from touchmap.api import create_app
from touchmap.settings import Settings
from touchmap.store import Store
from touchmap.errors import TouchMapError
from touchmap.providers import Draft,DraftRegion,DraftRelation,draft_to_diagram,bounded_call
from touchmap.models import Source
from touchmap.packages import sha256,json_bytes
from test_core import SVG

@pytest.fixture
def client(tmp_path):
    with TestClient(create_app(Settings(state_dir=tmp_path))) as client:yield client

def test_health_no_inference_and_svg_idempotency(client):
    assert client.get("/health/ready").json()["providerInferenceVerified"] is False
    fields={"requestId":"idempotency-1","draftRevision":"1","language":"en"}
    first=client.post("/v1/import/svg",data=fields,files={"file":("source.svg",SVG,"image/svg+xml")})
    assert first.status_code==200,first.text
    second=client.post("/v1/import/svg",data=fields,files={"file":("source.svg",SVG,"image/svg+xml")})
    assert first.json()==second.json()
    changed=client.post("/v1/import/svg",data={**fields,"draftRevision":"2"},files={"file":("source.svg",SVG,"image/svg+xml")})
    assert changed.status_code==409 and changed.json()["error"]["code"]=="idempotency_conflict"
    assert client.delete("/v1/jobs/idempotency-1").json()["state"]=="cancelled"
    assert client.get("/v1/jobs/idempotency-1").json()["result"] is None

def test_consent_and_hash(client):
    payload={"requestId":"image-1","draftRevision":"1","language":"en","consent":"false","sourceHash":"0"*64}
    assert client.post("/v1/analyze/image",data=payload,files={"file":("image.png",b"fake","image/png")}).status_code==403
    payload["consent"]="true"
    response=client.post("/v1/analyze/image",data=payload,files={"file":("image.png",b"fake","image/png")})
    assert response.json()["error"]["code"]=="source_hash"

def test_invalid_fields_do_not_echo_sensitive_content(client):
    response=client.post("/v1/audio/labels",json={"secretText":"private label"})
    assert response.status_code==422 and "private label" not in response.text
    response=client.post("/v1/audio/labels",json={"requestId":"a","sourceHash":"0"*64,"draftRevision":1,"language":"en","consent":True,"labels":[{"targetId":"r","kind":"label","text":"private label","textHash":"0"*64}]})
    assert response.status_code==422 and "private label" not in response.text

def test_upload_header_limit(client):
    response=client.post("/v1/import/svg",content=b"",headers={"content-length":str(100*1024*1024)})
    assert response.status_code==413

def test_pairing_expiry_rate_and_https(tmp_path):
    cfg=Settings(state_dir=tmp_path,remote=True,signing_key="x"*32)
    app=create_app(cfg);code=app.state.store.pairing_code()
    with TestClient(app,base_url="https://service.test") as client:
        pair=client.post("/v1/sessions/pair",json={"code":code})
        assert pair.status_code==200
        assert client.post("/v1/sessions/pair",json={"code":code}).status_code==401
        assert client.get("/v1/jobs/nothing").status_code==401
        token=pair.json()["token"]
        assert client.get("/v1/jobs/nothing",headers={"authorization":"Bearer "+token}).status_code==404
        assert client.delete("/v1/sessions/current",headers={"authorization":"Bearer "+token}).status_code==200
        assert client.get("/v1/jobs/nothing",headers={"authorization":"Bearer "+token}).status_code==401
    with TestClient(app,base_url="http://service.test") as client:assert client.get("/health/live").status_code==403

def test_store_restart_unknown_cancel_and_budget(tmp_path):
    cfg=Settings(state_dir=tmp_path,spend_ceiling_usd=.3)
    store=Store(cfg);assert store.begin("job","session","fingerprint",analysis=True,reserve=.2) is None
    store.cleanup(startup=True)
    assert store.job("job","session")["state"]=="outcome_unknown"
    with pytest.raises(TouchMapError,match="unknown"):store.begin("job","session","fingerprint",analysis=True,reserve=.2)
    with pytest.raises(TouchMapError,match="allowance"):store.begin("job2","session","fingerprint2",analysis=True,reserve=.2)
    store.begin("job3","session","fingerprint3")
    store.job("job3","session",True)
    with pytest.raises(TouchMapError,match="Late result"):store.finish("job3",{"success":True})

def test_ai_coordinate_order_and_draft_review():
    source=Source(id="source",sha256="0"*64,width=800,height=400,path="source/a.png",attribution="",license="",viewBox=[0,0,800,400])
    draft=Draft(title="Example",description="",regions=[DraftRegion(id="a",label="A",description="",box_2d=[100,200,400,600],sourceText="A")],relations=[],charts=[],unresolved=[],unsupported=[])
    diagram=draft_to_diagram(draft,source,7,"en")
    assert diagram.regions[0].polygons[0].outer[0].model_dump()=={"x":160,"y":40}
    assert diagram.regions[0].geometryReview.status=="draft"
    assert diagram.regions[0].geometryReview.revision==7

@pytest.mark.asyncio
@pytest.mark.parametrize("status,expected,retries",[(401,"provider_auth",1),(403,"provider_auth",1),(400,"provider_request",1),(429,"provider_rate_limit",2),(500,"provider_unavailable",2)])
async def test_provider_failure_codes(status,expected,retries):
    calls=0
    async def operation(timeout):
        nonlocal calls
        calls+=1
        response=httpx.Response(status,request=httpx.Request("POST","https://provider.test"),headers={"Retry-After":"0"})
        response.raise_for_status()
    with pytest.raises(TouchMapError) as error:await bounded_call(operation)
    assert error.value.code==expected and calls==retries

@pytest.mark.asyncio
async def test_provider_timeout_never_retries():
    calls=0
    async def operation(timeout):
        nonlocal calls
        calls+=1;raise asyncio.TimeoutError()
    with pytest.raises(TouchMapError) as error:await bounded_call(operation)
    assert error.value.code=="outcome_unknown" and calls==1

def test_tts_idempotency_and_text_hash_cache(tmp_path):
    class Fake:
        calls=0
        async def speech(self,text,language):self.calls+=1;return b"audio",100
    fake=Fake();app=create_app(Settings(state_dir=tmp_path),fake)
    with TestClient(app) as client:
        payload={"requestId":"tts1","sourceHash":"0"*64,"draftRevision":1,"language":"en","consent":True,"labels":[{"targetId":"a","kind":"label","text":"A","textHash":sha256(b"A")}]}
        first=client.post("/v1/audio/labels",json=payload)
        assert first.status_code==200,first.text
        assert client.post("/v1/audio/labels",json=payload).json()==first.json()
        payload["requestId"]="tts2";payload["draftRevision"]=2
        assert client.post("/v1/audio/labels",json=payload).status_code==200
        assert fake.calls==1

def test_expired_result_is_removed_before_job_poll(tmp_path):
    store=Store(Settings(state_dir=tmp_path));store.begin("expired","session","fingerprint");store.finish("expired",{"private":"result"})
    with store.connection() as db:db.execute("UPDATE jobs SET expires=? WHERE id='expired'",(time.time()-1,))
    result=store.job("expired","session")
    assert result["state"]=="expired" and result["result"] is None


def test_tts_identical_relation_text_shares_bytes_but_preserves_each_target(tmp_path):
    import io
    import wave
    audio = io.BytesIO()
    with wave.open(audio, 'wb') as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000)
        wav.writeframes(b'\0' * 4800)
    class Provider:
        calls = 0
        async def speech(self, text, language):
            self.calls += 1
            return audio.getvalue(), 100
    provider = Provider()
    with TestClient(create_app(Settings(state_dir=tmp_path), provider)) as client:
        response = client.post('/v1/audio/labels', json={
            'requestId': 'same-relation-text', 'sourceHash': '0' * 64,
            'draftRevision': 6, 'language': 'en', 'consent': True,
            'labels': [{'targetId': target, 'kind': 'label', 'text': 'points to',
                        'textHash': sha256(b'points to')} for target in ['input-to-gate', 'gate-to-output']]})
    assert response.status_code == 200, response.text
    recordings = response.json()['result']['audio']
    assert [item['targetId'] for item in recordings] == ['input-to-gate', 'gate-to-output']
    assert len({item['id'] for item in recordings}) == 2
    assert recordings[0]['path'] == recordings[1]['path']
    assert recordings[0]['dataBase64'] == recordings[1]['dataBase64']
    assert all(item['sha256'] == sha256(audio.getvalue()) for item in recordings)
    assert provider.calls == 1
