# Preparation service and offline CLI

TouchMap is developed by DEFOZO SOFTWARE HOUSE. Its sole human team member is Michał Kiełtyka. The preparation service converts sources and prepares audio. Learner activity, profiles, answers and checkpoints remain on the device.

## Reproduce the backend

Install Python 3.12 and uv. From `backend`, run:

```sh
uv sync --frozen
uv run pytest -q
uv run python tests/run_cli_checks.py
uv run touchmap serve --host 127.0.0.1 --port 8080
```

The lockfile pins dependency versions. This checkout was executed using Python 3.12 in Ubuntu under WSL, with its own environment outside the Windows checkout. On Windows, the helper uses the same code:

```powershell
./scripts/start-backend.ps1 -Wsl
```

`scripts/backend-wsl.sh` keeps the Linux virtual environment at `~/.cache/touchmap-backend-venv`. Do not share one virtual environment between Windows and Linux. Native Windows startup is also supported by the helper without `-Wsl`; the release execution evidence identifies the environment actually tested.

`GET /health/live` reports a running process. `GET /health/ready` reports configured adapters and limits. Neither performs inference or proves a provider accepts a request. Actual synthetic-image inference evidence is in `gemini-smoke.json`; the larger constrained corpus is under `evidence/ai-evaluation`.

## Offline author workflow

The CLI works without network access for SVG conversion, manual image preparation, editing, review, recording import and package exchange. Commands print JSON and exit nonzero on failure. An edit requires a different output diagram path, retains the original revision and invalidates review and audio conservatively.

```sh
uv run touchmap convert-svg ../docs/evidence/backend-cli/fresh.svg work/draft1 --title Seed
uv run touchmap edit work/draft1/diagram.json patch.json work/draft2/diagram.json
uv run touchmap review work/draft2/diagram.json --reviewer "Actual reviewer name and source-access declaration" --ids seed --aspect geometry
uv run touchmap review work/draft2/diagram.json --reviewer "Actual reviewer name and source-access declaration" --ids seed --aspect meaning
uv run touchmap import-audio work/draft2/diagram.json ../samples/lumina-process/audio/seed-label.wav --target seed --kind label --provenance "Owned TouchMap Seed recording, licensed ElevenLabs account"
```

`patch.json` is a JSON object of changed top-level fields. To supply source attribution and licence, include the complete existing `source` object with those fields corrected. Preserve its hash, path, dimensions and viewBox. Set `description` to the text used by the overview recording. Inspect the draft's `packageId`, then import its overview recording with `--target PACKAGE_ID --kind overview`. There is no automatic claim that a recording matches its text: the author must listen and review pronunciation.

```sh
uv run touchmap pack work/draft2/diagram.json work/seed.touchmap --author "DEFOZO SOFTWARE HOUSE / Michał Kiełtyka" --declaration "Geometry, meaning and speech reviewed against the owned source" --license CC0-1.0
uv run touchmap validate work/seed.touchmap
uv run touchmap unpack work/seed.touchmap work/second-installation
```

Normal `pack` requires publication review. `--allow-draft` explicitly exports incomplete material with its review state retained. `publishable` and `readyOffline` are separate: readiness also requires matching text/language hashes and all required playable audio assets. Import preserves the author's declaration and returns `requiresLocalAcceptance: true`; hashes are integrity checks, not identity or truth certification.

For image-only offline authoring use `touchmap new-image INPUT OUTPUT --title TITLE`. It normalizes image orientation and strips metadata, then creates an empty manual draft. Portable release recordings use PCM WAV: mono or stereo, 8-192 kHz, 8/16/24/32-bit samples, at most 10 MiB each. Backend and native import enforce the same container, frame and duration checks. Other licensed recordings can be converted locally before importing with `ffmpeg -i INPUT -acodec pcm_s16le -ar 24000 -ac 1 OUTPUT.wav`. This offline conversion makes no provider request. A successful local conversion does not establish the author's reuse licence; the author still supplies provenance and listens to the recording.

`tests/run_cli_checks.py` executes a fresh SVG through conversion, a new revision, two separate reviews, recording imports, packaging and independent unpacking. It preserves inspectable inputs and outputs under `docs/evidence/backend-cli` and writes `docs/backend-checks.json`. The same script runs 100 actual forcibly exited worker processes against the backend job store. That is backend durability evidence, not a native learner-process recovery result.

## Optional cloud configuration

Cloud adapters are disabled by default. Provider keys must be injected by psst into the backend process, never placed in the HAP or checked into source. The supplied `.env.example` documents nonsecret settings only; the application does not automatically load dotenv files.

```powershell
./scripts/start-backend.ps1 -Cloud -Wsl
```

The helper injects `GOOGLE_AI_STUDIO_API_KEY` and `ELEVENLABS_API_KEY` through psst. WSLENV passes inherited values into WSL without placing their values in command arguments or files. The approved model IDs are `gemini-3.8-flash` and `eleven_flash_v2_5`. The configured voice is `hpp4J3VqNfWAUOO0d1Us`. The source image requires explicit upload consent; sending text for speech requires separate consent. A configured service is not evidence that the user consented to a particular request.

Operator controls are `TOUCHMAP_CLOUD_AI_ENABLED`, `TOUCHMAP_CLOUD_TTS_ENABLED`, `TOUCHMAP_ANALYSES_PER_SESSION` (20), `TOUCHMAP_GENERATION_CEILING` (100), and `TOUCHMAP_SPEND_CEILING_USD` (10). The spend ceiling uses conservative local reservations rather than provider billing reconciliation; it persists in the state database. It does not guarantee an exact invoice total. See `AI_INTEGRATION.md` for provider data handling and evaluation limits.

## API and job outcomes

The complete OpenAPI and JSON Schemas are in `contracts`; regenerate them with `uv run touchmap schemas ../contracts`. Multipart file endpoints receive the file as bytes, not a remote URL or server path.

| Operation | Required request fields |
| --- | --- |
| `POST /v1/import/svg` | `file`, `draftRevision`, `language`, `requestId` |
| `POST /v1/analyze/image` | Those fields plus exact uploaded `sourceHash` and `consent` |
| `POST /v1/audio/labels` | JSON `requestId`, `sourceHash`, `draftRevision`, `language`, `consent`, and `labels` with `targetId`, `kind`, `text`, `textHash` |
| `POST /v1/packages/validate` | `file`, `requestId` |
| `GET /v1/jobs/{requestId}` | Same authenticated session as the original request |
| `DELETE /v1/jobs/{requestId}` | Cancel and discard any late result |

Responses identify the request, source hash, draft revision, contract version, provider and model. Reusing a request ID with different input or session returns an idempotency conflict. Completed identical requests can be replayed within the bounded retry window. Unknown provider outcomes after timeout or process death remain `outcome_unknown` and require an explicit new request ID. The service does not promise exactly-once external billing.

Provider timeouts are 30 seconds within a 45-second total job deadline. The adapters retry at most once for eligible transient failures. Invalid input, authentication failures, refusal and cancellation are not converted into successful drafts. A cancelled or stale result cannot overwrite an edited native draft.

## Local and remote deployment

Loopback development accepts local requests without pairing and rejects non-loopback clients. The native emulator needs a supported host/port forwarding arrangement to reach that listener. Do not expose the unauthenticated loopback mode by a generic public tunnel.

Remote mode requires `TOUCHMAP_REMOTE=true`, a psst-injected `TOUCHMAP_SESSION_SIGNING_KEY` of at least 32 characters, and a TLS certificate/private key. Start with `touchmap serve --host 0.0.0.0 --port 8787 --certfile /tls/cert.pem --keyfile /tls/key.pem`. TLS is served directly; forwarded headers are not trusted. Use a certificate trusted by the client runtime.

Run `touchmap pair-code` with the same state directory and signing key. It emits a one-use code valid for five minutes. `POST /v1/sessions/pair` exchanges that code for a one-hour bearer session; `DELETE /v1/sessions/current` revokes it and cancels its stored jobs. Pairing codes and bearer values are credentials; share them only with the intended local author and exclude them from evidence artifacts.

Build the optional container from `backend`:

```sh
docker build -t touchmap-preparation .
# Linux host networking retains the default loopback-only listener.
docker run --rm --network host -v touchmap-state:/state touchmap-preparation uv run --frozen touchmap serve --host 127.0.0.1 --port 8080
```

The image runs as an unprivileged user and contains only the pinned service code and dependencies. The default command binds loopback inside its container; publishing a port alone does not make it reachable. A remote container must explicitly use the TLS command above, receive the psst-injected environment, mount `/tls` read-only and publish port 8787. Do not bake secrets or certificates into the image. No public hosted deployment is implied by the Dockerfile or these instructions.

## Validation and retention

Source images are bounded at 10 MiB and 20 megapixels. Packages are bounded at 50 MiB compressed, 200 MiB expanded and 1,000 entries. The ZIP writer adjusts DEFLATE compression for repetitive recordings so its output satisfies the same 200:1 expansion policy as imported packages. Graph limits are 500 regions, 2,000 relations and 100,000 total geometry points. Numeric coordinates are finite and bounded at absolute value 1,000,000. The native topology sweep additionally rejects more than two million overlapping edge comparisons rather than hanging on adversarial geometry.

The SVG profile reports unsupported features and rejects active/external content. ZIP validation rejects traversal, Unicode path aliases, reserved Windows device filenames, case collisions, links, special entries, encrypted entries and suspicious expansion. Every declared source/audio byte hash is checked before package adoption. WAV headers, frame counts and duration are checked; native code independently validates the package. Extra package assets, including learner history, are rejected.

New SVG conversions also render a PNG preview with pinned `resvg_py==0.5.0` and the bundled licensed DejaVu Sans font. The source carries paired `previewPath` and `previewSha256` fields; packages retain the original SVG and the exact rendered PNG. Native playback draws that PNG because the tested native SVG decoder drops text and marker arrows. Text and arrow pixels are checked in the backend regression test. Font-family substitution is disclosed in the conversion report and the author must review layout and meaning before publishing. The preview hash protects bytes and does not establish semantic agreement with the source. [Renderer API documentation](https://resvg-py.readthedocs.io/en/latest/api.html) describes explicit font loading; the bundled font notice is in `backend/touchmap/assets/DejaVu-LICENSE.txt`.

Polygon rings must be simple, nonzero and distinct. Holes lie strictly inside their outer ring and cannot touch or intersect any ring. Shared fixtures in `contracts/fixtures/polygons.json` execute against both implementations. Publication requires source attribution/licence, source-linked evidence and current geometry/meaning/fact reviews. Exact numerical or directional questions cannot use unknown answers as established facts.

Raw uploads have no separate persistent file. Successful job results are stored in SQLite for a ten-minute retry window, and include derived source material: the rendered PNG preview for SVG conversion, or the normalized PNG for image analysis, together with proposed labels and geometry. The SVG result stores its original byte hash; the client already holds the original source bytes. Prepared audio also has a ten-minute retry cache. Cancelling a job or revoking its session clears its result; independently cached speech expires under the same short cache policy. Request tombstones remain for one day to prevent accidental replay after expiry. Cleanup runs at startup, before a new job and before a job-status lookup; expired cache rows can remain on disk while the service is idle. SQLite itself may retain deleted pages; this policy is logical retention, not a claim of secure physical erasure. Provider-side retention is governed separately by the provider account terms. Logs contain request IDs, status and duration rather than uploaded images, labels or bearer headers.
