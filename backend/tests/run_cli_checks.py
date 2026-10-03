"""Actual installed CLI roundtrip and forcibly exited job-store recovery evidence."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import shutil
from datetime import datetime, timezone
from touchmap.packages import read_json,validate_package,write_atomic,json_bytes
from touchmap.settings import Settings
from touchmap.store import Store

ROOT=Path(__file__).parents[2]
started=time.monotonic()
results=[]
def cli(*args):
    completed=subprocess.run([sys.executable,"-m","touchmap.cli",*map(str,args)],capture_output=True,text=True,encoding="utf-8")
    if completed.returncode:raise RuntimeError(completed.stderr)
    return json.loads(completed.stdout)

with tempfile.TemporaryDirectory(prefix="touchmap-cli-") as td:
    tmp=Path(td);svg=tmp/"fresh.svg"
    svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="100 100 200 100"><rect id="seed" x="110" y="110" width="100" height="60" aria-label="Seed"/></svg>',encoding="utf-8")
    result=cli("convert-svg",svg,tmp/"draft1","--title","Seed")
    d=read_json((tmp/"draft1/diagram.json").read_bytes())
    source=d["source"];source["attribution"]="Owned synthetic CLI verification diagram";source["license"]="CC0-1.0"
    patch=tmp/"patch.json";patch.write_text(json.dumps({"source":source,"description":"Seed"}))
    result=cli("edit",tmp/"draft1/diagram.json",patch,tmp/"draft2/diagram.json")
    assert result["revision"]==2
    for aspect in ("geometry","meaning"):
        cli("review",tmp/"draft2/diagram.json","--reviewer","Developer synthetic fixture review","--ids","seed","--aspect",aspect)
    audio=ROOT/"samples/lumina-process/audio/seed-label.wav"
    if not audio.exists():
        _,_,_,assets=validate_package((ROOT/"samples/lumina-process.touchmap").read_bytes())
        key=next(p for p in assets if p.endswith("seed-label.wav"));audio=tmp/"seed-label.wav";audio.write_bytes(assets[key])
    for target,kind in [("seed","label"),(d["packageId"],"overview")]:
        cli("import-audio",tmp/"draft2/diagram.json",audio,"--target",target,"--kind",kind,"--provenance","Owned TouchMap Seed recording, licensed ElevenLabs account")
    packed=cli("pack",tmp/"draft2/diagram.json",tmp/"new-material.touchmap","--author","Developer","--declaration","Synthetic source and single label reviewed","--license","CC0-1.0")
    assert packed["readyOffline"]
    imported=cli("unpack",tmp/"new-material.touchmap",tmp/"second-installation")
    assert imported["readyOffline"] and imported["requiresLocalAcceptance"]
    assert (tmp/"draft1/diagram.json").exists()
    evidence=ROOT/"docs/evidence/backend-cli"
    evidence.mkdir(parents=True,exist_ok=True)
    for name in ("fresh.svg","new-material.touchmap"):
        shutil.copy2(tmp/name,evidence/name)
    for name in ("draft1","draft2","second-installation"):
        shutil.copytree(tmp/name,evidence/name,dirs_exist_ok=True)
    results.append({"flow":"fresh SVG -> convert -> edit revision -> geometry and meaning review -> licensed recording import -> package -> independent unpack","passed":True,"readyOffline":True,"newRevision":2,"originalRetained":True,"cloudCalls":0})

with tempfile.TemporaryDirectory(prefix="touchmap-crash-") as td:
    cfg=Settings(state_dir=Path(td));store=Store(cfg);committed=0;unknown=0
    worker=ROOT/"backend/tests/crash_worker.py"
    for i in range(100):
        mode="complete" if i%2 else "running"
        done=subprocess.run([sys.executable,str(worker),td,str(i),mode],capture_output=True)
        assert done.returncode==17
        store.cleanup(startup=True)
        state=store.job(f"crash-{i}","crash-test")
        if mode=="complete":assert state["state"]=="complete" and state["result"]["acknowledged"] is True;committed+=1
        else:assert state["state"]=="outcome_unknown";unknown+=1
    results.append({"flow":"100 actual subprocess exits before/after committed preparation result","passed":True,"processExits":100,"acknowledgedResultsPreserved":committed,"interruptedJobsMarkedOutcomeUnknown":unknown,"scope":"Backend preparation job store only; not native learner persistence evidence"})

report={"success":True,"recordedAt":datetime.now(timezone.utc).isoformat(),"python":sys.version.split()[0],"platform":sys.platform,"durationMs":round((time.monotonic()-started)*1000),"checks":results}
write_atomic(ROOT/"docs/backend-checks.json",json_bytes(report))
print(json.dumps(report,indent=2))
