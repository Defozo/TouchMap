# AI-assisted development workflow

Submission team: **DEFOZO SOFTWARE HOUSE**. Sole human team member: **Michał Kiełtyka**. Coding agents are tools and are not listed as team members. These details were explicitly supplied by the user in `TEAM.json`.

## Inputs and selection

The user requested implementation of the complete selected `official-2026-10-03/PLAN.md`, explicitly excluding the historical root plan as authority. The official technical brief, partner rules, task metadata, selected TouchMap proposal and inherited OneStep, AccessRelay and ThreadBack principles were reviewed. The pre-existing files document proposal selection; they do not establish implementation, inference or testing. The selection metadata records `gpt-6-astra`, reasoning effort `ultra`, service tier `default`, for that planning pipeline.

Main implementation instruction, translated: implement the complete selected plan, read all official task materials and service documentation, work in this project, run the solution, verify key flows and fix defects; do not reduce scope based on time, team size or the event format. Additional instruction: secrets are in `psst`; avoid em dashes in messaging.

## Tools and delegation actually used

Codex, described by the runtime as a GPT-6-based coding agent, coordinated three concurrent coding agents. The precise selected model variant was not exposed as a repository-verifiable value. Delegation covered: native ArkTS UI and adapters; Python preparation service/CLI/providers; and OpenHarmony toolchain, signing and emulator. The primary agent implemented contracts, shared domain modules, examples, host tests, evaluation assets, integration review and documentation.

Tools used include PowerShell and WSL shell execution, `rg`, `apply_patch`, Git, npm/TypeScript/tsx, Python/uv/pytest, official web documentation lookup, the Eclipse Oniro App Builder, OHPM, hvigor, HDC and the emulator. Credentials were injected selectively by `psst`. No secret values were printed or committed. The `walkthrough-artifacts` instruction guided collection of genuine runtime screenshots/recordings; its cloud-only recording tools were unavailable, so device tooling supplies local evidence. Sites/canvas instructions were inspected for applicability and not used to replace the native deliverable.

## Major delegated prompts

- Build the full Python service and CLI against the shared wire contract, with SVG/ZIP safety, review states, bounded provider requests, authentication, idempotency, cancellation and actual provider smoke tests.
- Build native Library, Import, Editor, Explorer, Lesson, Resume and Settings, using public API20 capabilities, local recordings, RDB transactions, accessibility hover and equivalent controls.
- Install a compatible official OpenHarmony SDK and emulator, compile and sign an actual normal-privilege HAP, install it, preserve API/runtime metadata and investigate screen-reader support independently.
- Preserve complete scope. Do not claim a runtime test from source code or a successful build. Coordinate interfaces and report concrete failures.

## Review and debugging

Generated code was reviewed across agent boundaries. Specific review findings included source/audio hash agreement, recording text staleness, collision of imported content revisions, draft-file cleanup, metadata-stripped image identity, and differences between native and Python validation. Host tests check geometry boundaries/holes/overlaps, inverse transforms, exact answer sets, missing facts, stale progress, duplicate submissions, review invalidation, undo/redo and late AI results.

Toolchain discovery initially found no DevEco/SDK/HDC installation. An official scriptable Oniro route in WSL supplied API20 SDK, offline development signing and an API23 emulator. The initial signed Hello World established platform setup only; it is not product completion evidence. Exact compiler/runtime errors and fixes are reflected in evidence and commits rather than retrospectively presented as first-attempt success.

Original owned SVGs and teaching text were authored for this project. ElevenLabs generated 48 local WAV recordings, including seven tutorial clips, after account/voice capability inspection. Image analysis uses synthetic nonsensitive sources. Provider generation is distinct from code-generation assistance. The evaluation corpus reserves five of twenty diagrams as held out and must not be presented as representative-user validation.

Actual device inspection caught frozen dynamic builder labels, an invisible modal system picker, duplicate-directory import failures and missing SVG text/arrowheads. Reactive components and the system picker's full-page contract fixed the first issues. Source PNG previews preserve text and markers alongside the original SVG; a second renderer font failure on Linux was caught by pixel tests and fixed with a bundled licensed font. Font substitution remains explicit and subject to author review. Importing a complete package then exposed a real foreground lifecycle timeout from decompression on the UI thread. Bounded extraction was moved into a native taskpool worker; the failing device trace is retained with subsequent retest evidence.

The native test runner initially returned process exit code zero despite ten setup errors. Verification checks the actual Hypium totals. Test context acquisition was repaired using a real EntryAbility lifecycle monitor; the suite subsequently passed all ten tests. Native forced-restart and audio measurements use that same real application context and remain distinct from host state serialization tests.

## Limits and reproducibility

See `docs/TEST_REPORT.md` for measured outcomes and unfulfilled gates. Automated unit tests cannot prove usability for blind/low-vision learners or physical haptic perception. No user study result, percentage improvement, provider privacy guarantee or screen-reader success is fabricated. Product inference data handling and consent are documented separately in `AI_INTEGRATION.md`.

Public source and evidence must exclude private signing keys, access tokens, local state, provider headers, account identifiers unrelated to reproduction and confidential source images. The original service-catalog pointer is planning context only; clean builds use the repository and developers' own optional credentials.
