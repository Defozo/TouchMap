# Controlled delayed native preparation

This fixture sends no provider requests. It deliberately holds a source-derived
response until released, including after the client cancels. It binds only host
loopback and is a test server, not a deployed preparation service.

From the repository root on the Linux/WSL build host:

```sh
backend/.venv/bin/python tests/native-preparation/server.py --port 8089
```

Use another terminal with the documented HDC binary and selected development
emulator. Keep the regular preparation service's port mapping intact:

```sh
hdc -t 127.0.0.1:55555 rport tcp:8089 tcp:8089
hdc -t 127.0.0.1:55555 shell aa test -b org.touchmap.app -m entry_test \
  -s unittest OpenHarmonyTestRunner -s preparationChecks true -w 60000
hdc -t 127.0.0.1:55555 file recv \
  /data/app/el2/100/base/org.touchmap.app/haps/entry/files/preparation-checks.json \
  docs/evidence/native-preparation-checks.json
```

Install the current signed production and test HAPs first, and ensure a previous
network-block test has been restored. `PreparationRunner.ets` uses actual native
HTTP, hashing, the product revision guard and repository persistence. It saves an
edit while the response is pending, releases the old response and checks both
in-memory and durable state. It then cancels another request, commits a later
edit and releases the remote response anyway. A delivered cancelled result or an
overwritten edit fails the test. The owned test material is isolated and removed
after the test; existing published samples are preserved.

For a separate full Editor UI check, configure `http://127.0.0.1:8089` and pair
with synthetic text. The fixture accepts the original owned native diagram-01
raster, or a supported SVG. Start preparation, wait for `/test/status` to show a
received request, cancel or leave the editor, save a later edit and POST
`/test/release`. Read back the real native material and confirm its newer content
and review state. The marker `DELAYED FIXTURE PROPOSAL` must not overwrite it.
Use POST `/test/reset` between runs only after the previous response completed.
This manual UI result is separate from the native runner and must be recorded
only after actual execution.

Stop the fixture and remove only its `tcp:8089 tcp:8089` reverse mapping after
verification. Record both installed HAP checksums with the resulting evidence.
