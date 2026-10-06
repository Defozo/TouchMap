# TouchMap

**Team: DEFOZO SOFTWARE HOUSE**  
**Sole team member: Michał Kiełtyka**

An arrow on a worksheet can explain a whole process. TouchMap makes that connection something a learner can explore: touch an object, hear its label, then follow the relationship to the next object.

Teachers turn diagrams into portable lessons with reviewed labels, relationships and questions. Learners choose touch, a list or single-button scanning, practise at their own pace and pick up an unfinished answer after a restart. Prepared lessons work offline without an account.

The lesson preserves how objects connect: learners can follow an arrow to its destination, explore overlapping layers, return to a bookmark and answer questions about the same material. Teachers control the source, meaning and accepted answers before publication. This connects lesson preparation with independent practice in one native application.

[Watch the narrated demo and download TouchMap](https://github.com/Defozo/TouchMap/releases/tag/v1.0.1), or follow the [guided native demo](docs/DEMO_ACCESS.md). The release includes the signed application, an English presentation and an editable PPTX with speaker notes. TouchMap runs as a native ArkTS/ArkUI application on OpenHarmony, with API 20 as its declared minimum. The Python preparation service and CLI support optional authoring workflows.

## Start the native application

Windows requires WSL2 Ubuntu; Linux can invoke the corresponding shell scripts directly. The tested toolchain uses the official Eclipse Oniro CLI, OpenHarmony API 20 SDK and an Oniro API 23 emulator. See [platform setup and signing](docs/platform.md) for prerequisites and the exact underlying commands.

```powershell
./scripts/setup-platform.ps1
./scripts/build.ps1 -Product openharmonyApi20
./scripts/start-emulator.ps1
./scripts/configure-emulator-audio.ps1 -Target 127.0.0.1:55555 -Action apply
./scripts/doctor.ps1
./scripts/install.ps1 -Target 127.0.0.1:55555
```

The installable artifact is `dist/touchmap-signed.hap`, with checksums and packaged API metadata beside the evidence. The pinned QEMU image also needs the checked audio-configuration correction described in [platform setup](docs/platform.md); the application itself retains ordinary permissions. The build creates development signing material in a private build directory. No provider key, account or backend is needed to use bundled lessons. A successful API 23 run does not establish API 20 runtime compatibility.

The emulator wrapper runs headless. Connect a local VNC viewer to `127.0.0.1:5900` (display `:0`) for the interactive screen; QEMU uses the host sound service for audio. The [release walkthrough](docs/DEMO_ACCESS.md) explains how to install the downloaded HAP without building it.

## Try the complete learning flow

1. Open **The water cycle** from the library. Inspect its source and author declaration, then accept the material locally.
2. Complete the three-shape tutorial and choose touch, list or single-button scanning. Preferences include label dwell, volume, vibration, contrast and text size.
3. Explore **Evaporation**, open **Connections**, and follow **Vapour cools into droplets** to **Condensation**. Overlapping objects remain available through the layer chooser.
4. Open the first lesson question. Select **Condensation** and press **Submit selected answer**. Exploration and selecting an option do not submit an answer.
5. Begin another answer, leave or terminate the application, then reopen it. **Resume** restores the last explored object, submitted answer and unfinished selection. **Repeat context** describes the committed state.
6. Export the teaching package and import it into a second installation. History and local acceptance are deliberately absent from teaching packages. History export is a separate action.

The other examples are an unfamiliar branching **Lumina workshop** and a **rainfall chart** whose June value is explicitly unknown. Unknown values remain explicit throughout the lesson, so learners can distinguish a missing measurement from zero.

## Prepare and review a material

Use **Import** to choose SVG, PNG/JPEG or an existing package. A raster source can be authored manually without a cloud call. The editor provides source overlays and coordinate forms, region and relationship edits, evidence, separate geometry/meaning review, chart values, question authoring, undo/redo and autosaved drafts. Editing creates a new content revision and invalidates affected reviews, questions and audio.

Review stays attached to the material it describes. A question opens only when it has been reviewed and its facts match the lesson revision. Teachers can correct a diagram and see which related content needs another review before learners use it. Portable teaching packages keep reusable content separate from personal learning history.

SVG conversion is available through the local CLI or a configured preparation service. Raster analysis is optional and requires explicit consent for the selected image. Generated content is a draft. Review arrow direction, labels, units, unknowns and question answers against the source before publishing. The **Ready offline** state additionally requires matching local assets and recordings. It is distinct from publication and from local acceptance of an imported author declaration.

```powershell
cd backend
uv sync --frozen
uv run touchmap --help
uv run touchmap serve --host 127.0.0.1 --port 8080
```

Read [backend operation](docs/backend.md) for actual CLI subcommands, configuration, pairing and provider smoke checks. A service bound to the computer's loopback is not automatically reachable from a phone. Remote operation requires HTTPS and a short-lived paired session. The app accepts HTTP only for its own loopback, including a deliberately configured HDC development tunnel.

Credentials are injected into the backend with `psst`, never written into the application or repository. Use named secrets only. The reference provider configuration is Gemini `gemini-3.8-flash` and ElevenLabs `eleven_flash_v2_5`; there is no automatic provider substitution. A missing credential leaves manual and offline workflows available and reports that the requested cloud feature is unavailable.

## Verify

```powershell
npm ci
npm test
npm run typecheck
cd backend
uv sync --frozen
uv run pytest
```

Run `scripts/verify-release.ps1` for package integrity, schemas, native metadata and recorded technical verification. Host JavaScript tests exercise the same pure modules imported by the native app. Native checks run on the API 23 emulator; the [test report](docs/TEST_REPORT.md) records their results, supported environment and use limits. [Release packaging](docs/RELEASE.md) links the committed sources, signed HAP, reviewed English demo, examples and checksums into one traceable bundle.

## Deployment and maintenance

Prepared lessons need no hosted service or recurring inference. An optional preparation backend can be operated by a school or content author with their own provider accounts. See [deployment, maintenance and product value](docs/OPERATIONS.md) for installation records, package backups, updates, credentials, health checks and cost controls.

## Repository map

- `app/`: native UI, OpenHarmony adapters and shared domain modules.
- `backend/`: safe converter, package library, CLI, authenticated API and provider adapters.
- `contracts/`: wire specification, JSON Schemas and interoperability fixtures.
- `samples/`: three teaching packages and a tutorial, with source, semantics, audio and provenance.
- `tests/evaluation/`: twenty owned process diagrams and five numeric charts, annotated truth, held-out splits and evaluation tools.
- `scripts/`: setup, build, install, doctor, sample generation and release validation.
- `docs/`: platform, accessibility, privacy, measurements, study protocol and demo script.

[Architecture](ARCHITECTURE.md), [AI development workflow](AI_WORKFLOW.md), [AI integration](AI_INTEGRATION.md), [third-party notices](THIRD_PARTY.md), and [sample provenance](samples/LICENSE.md) describe implementation and evidence boundaries.
