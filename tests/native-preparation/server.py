"""Loopback-only delayed transport fixture; never contacts an inference provider.

Run with the backend virtualenv. A selected emulator reaches 127.0.0.1:8089
through an explicit HDC reverse port mapping. Control endpoints release a held
response even after cancellation, reproducing an uncooperative remote worker.
"""
from __future__ import annotations
import argparse
import asyncio
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from touchmap.svg import convert_svg
import uvicorn

app = FastAPI(docs_url=None, redoc_url=None)
release = asyncio.Event()
records: list[dict] = []
fixture_diagram = json.loads((ROOT / "docs/evidence/native-ai-draft.json").read_text())


@app.get("/test/status")
async def status():
    return {"received": len(records), "completed": sum(r["completed"] for r in records),
            "cancelled": sum(r["cancelled"] for r in records), "records": records,
            "scope": "Controlled loopback transport fixture; no provider requests."}


@app.post("/test/reset")
async def reset():
    if any(not r["completed"] for r in records):
        raise HTTPException(409, "Release the pending fixture response first")
    records.clear()
    release.clear()
    return {"reset": True}


@app.post("/test/release")
async def unblock():
    release.set()
    return {"released": True}


@app.post("/v1/sessions/pair")
async def pair():
    return {"token": "controlled-local-test-fixture", "expiresAt": 4102444800}


@app.delete("/v1/jobs/{request_id}")
async def cancel(request_id: str):
    for record in records:
        if record["requestId"] == request_id:
            record["cancelled"] = True
    # Deliberately keep computing until /test/release. Cancellation cannot make
    # a remote provider promise that its in-flight work has ceased.
    return {"state": "cancelled"}


@app.post("/v1/import/svg")
@app.post("/v1/analyze/image")
async def draft(file: UploadFile = File(), requestId: str = Form(),
                draftRevision: int = Form(), sourceHash: str = Form(),
                language: str = Form("en"), consent: str = Form("false")):
    data = await file.read(10 * 1024 * 1024 + 1)
    if len(data) > 10 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != sourceHash:
        raise HTTPException(400, "Fixture upload integrity or size mismatch")
    if (file.filename or "").endswith(".svg"):
        result = convert_svg(data, revision=draftRevision, language=language)
    else:
        if sourceHash != fixture_diagram["source"]["sha256"]:
            raise HTTPException(400, "Raster fixture accepts only the owned native diagram-01 source")
        diagram = json.loads(json.dumps(fixture_diagram))
        diagram["revision"] = draftRevision
        for region in diagram["regions"]:
            region["geometryReview"]["revision"] = draftRevision
            region["meaningReview"]["revision"] = draftRevision
        for relation in diagram["relations"]:
            relation["review"]["revision"] = draftRevision
        result = {"diagram": diagram, "report": {"unsupported": [], "unresolved": []}}
    result["diagram"]["regions"][0]["label"] = "DELAYED FIXTURE PROPOSAL"
    record = {"requestId": requestId, "draftRevision": draftRevision, "sourceHash": sourceHash,
              "receivedAt": datetime.now(timezone.utc).isoformat(),
              "completed": False, "cancelled": False, "completionReason": "pending"}
    records.append(record)
    try:
        await asyncio.wait_for(release.wait(), timeout=300)
    except TimeoutError:
        record["completed"] = True
        record["completionReason"] = "hold_timeout"
        record["completedAt"] = datetime.now(timezone.utc).isoformat()
        raise HTTPException(504, "Controlled fixture was not released")
    record["completed"] = True
    record["completionReason"] = "response_released"
    record["completedAt"] = datetime.now(timezone.utc).isoformat()
    return {"requestId": requestId, "contractVersion": 1, "sourceHash": sourceHash,
            "draftRevision": draftRevision, "provider": "controlled-local-fixture", "model": "no-inference",
            "result": result}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8089)
    args = parser.parse_args()
    uvicorn.run(app, host="127.0.0.1", port=args.port, access_log=False)
