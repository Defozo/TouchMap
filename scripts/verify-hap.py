"""Inspect the actual packaged module metadata, not only source build settings."""
import hashlib
import json
import sys
from pathlib import Path
from zipfile import ZipFile

hap = Path(sys.argv[1])
with ZipFile(hap) as archive:
    metadata = json.loads(archive.read("module.json"))
app = metadata["app"]
assert app["bundleName"] == "org.touchmap.app", app
assert int(app["minAPIVersion"]) == 20, app
assert int(app["targetAPIVersion"]) >= 20, app
result = {
    "sha256": hashlib.sha256(hap.read_bytes()).hexdigest(),
    "bytes": hap.stat().st_size,
    "bundleName": app["bundleName"],
    "minAPIVersion": app["minAPIVersion"],
    "targetAPIVersion": app["targetAPIVersion"],
    "apiReleaseType": app.get("apiReleaseType"),
    "module": metadata["module"]["name"],
    "signatureVerification": "hap-sign-tool verify-app must pass before this script runs; installation recorded separately",
}
Path(sys.argv[2]).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, indent=2))
