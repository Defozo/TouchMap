# TouchMap verification report

Prepared on 3 October 2026 for DEFOZO SOFTWARE HOUSE. Sole human team member: Michał Kiełtyka.

This report separates completed execution from implementation and pending release gates. It is an evidence snapshot of the working tree; the final release commit, HAP checksum and refreshed native results must be attached after the final build. The authoritative scope is `official-2026-10-03/PLAN.md`. A missing result below remains required work or an explicit research/hardware gap, not a reduction of that scope.

## Measured results

| Check | Observed result | Evidence and limits |
| --- | --- | --- |
| Backend automated suite | 69 passed in the last saved run | [JUnit report](evidence/backend-pytest.xml). Python 3.12.12 under Ubuntu/WSL. API failure cases use controlled provider doubles; they are not real outages at Google or ElevenLabs. Includes portable PCM WAV, preview/source integrity, raster dimension parity, shared CSS SVG preview, compressed ZIP roundtrips above 50 MiB expanded and release packaging preflight/determinism in an isolated synthetic Git repository. |
| Pure native domain modules on host | 42 checks passed in the combined saved run | [Host results](evidence/domain-tests.txt), including domain, bounded JSON/manifest, polygon, safe SVG profiles and PCM audio parity tests. These execute the TypeScript modules used by ArkTS, under Node 24.13.0. They do not substitute for emulator integration. |
| TypeScript checking | Passed with current JSON, manifest, PCM and passive SVG guards | [Saved typecheck](evidence/typecheck.txt), `npm run typecheck`. |
| Fresh offline SVG authoring | Passed conversion, edit into revision 2, separate geometry/meaning review, licensed recording import, packaging and independent unpacking | [Executed CLI report](backend-checks.json), [retained package](evidence/backend-cli/new-material.touchmap), [unpacked diagram](evidence/backend-cli/second-installation/diagram.json). No cloud calls in this flow. Native domain validation also accepted this exact CLI artifact, including its PNG preview. |
| Backend crash recovery | 100 actual subprocess exits passed | [CLI/recovery report](backend-checks.json). Fifty acknowledged results remained committed; fifty interrupted running jobs became `outcome_unknown`. These are preparation-job storage checks, not native learner checkpoint tests. |
| Native learner crash recovery | 100 forced restarts verified | [Native recovery report](evidence/native-recovery.json) contains 101 committed records including final verification. It covers save, unfinished selection, submission/idempotent replay and ZIP import after a durable acknowledgement. It does not inject failure in the middle of a transaction. |
| Native build and signature | A real signed HAP was built and its signature verified | [Build log](evidence/native-build.log), [signature log](evidence/signature-verification.log), [HAP metadata](evidence/hap-metadata.json). Metadata records bundle `org.touchmap.app`, minimum API 20 and target API 20. Rebuild/checksum refresh is required after current edits. |
| Primary emulator install/launch | Passed for a signed TouchMap HAP | [Primary installation](evidence/native-install-primary.log) records installation and successful ability launch. This is the application, not only the earlier empty platform baseline. |
| Second clean emulator install/launch | Passed for a signed TouchMap HAP | [Before installation](evidence/second-clean-target-before.txt) has no TouchMap bundle; [second installation](evidence/native-install-second.log) records successful installation and launch. Both emulators use the same pinned runtime family. |
| Native Hypium suite | 10/10 passed after repairing the test harness | [Native result log](evidence/native-test-results.txt) reports 10 tests, 0 failures, 0 errors and 10 passes. Coverage includes platform SHA256, actual bundled content, geometry, transactional checkpoint reload, duplicate/stale submission handling, review invalidation, paths, native Settings controls, reactive tutorial and deletion. This rerun supersedes an earlier failed `beforeAll` attempt; a process exit code alone was not accepted as proof. |
| Live Gemini smoke | Passed one actual image/schema request | [Smoke report](gemini-smoke.json): `gemini-3.8-flash`, two regions, one relation, 5,687 ms. Input was an owned synthetic Seed → Plant image. Health checks are not counted as inference. |
| Live image evaluation | 20/20 schema successes; 20/20 drafts met the script's constrained usable-draft rule | [Complete evaluation](evidence/ai-evaluation/summary.json). Exact-label recall and direction accuracy averaged 1.0 on these owned small process fixtures. Five were held out, including one clear held-out fixture. This is not a claim of general diagram accuracy or teacher-reviewed usability. |
| Sample content integrity | Process, unfamiliar process, numerical chart and tutorial packages pass backend package validation | [Generation record](sample-generation.json), checked-in `samples/*.touchmap`, and `test_released_samples`. Required/audio counts are respectively 15/15, 17/17, 9/9 and 7/7. Latest regeneration reused existing recordings; it did not make new TTS calls. |
| SVG source preview | Text, marker and CSS pixels verified in generated PNG; source and preview hashes verified | `test_svg_preview_preserves_text_and_arrow_marker`, `test_css_svg_preview_uses_shared_native_retention_fixture`, paired preview contract and bundle assets. Shared CSS source passes the native pure module's wider passive SVG profile only when callers provide a verified PNG preview. Rendering uses pinned resvg and bundled DejaVu Sans. Font substitution is explicit and requires author review. |
| Python distribution packaging | Wheel and source distribution built; font and licence verified in wheel | `uv build`; wheel entries include `touchmap/assets/DejaVuSans.ttf` and `touchmap/assets/DejaVu-LICENSE.txt`. This is separate from Docker execution. |
| Optional Docker runtime | Not executed | The inspected WSL environment has no running Docker daemon/socket. Dockerfile and instructions are supplied; no container execution or hosted deployment is claimed. |

## Platform and artifact identity

The public application product is `openharmonyApi20`. The pinned SDK is OpenHarmony 6.0.0.47 Beta1; compile, target and minimum compatibility are API 20. The actual emulator runtime is Oniro v6.1 / OpenHarmony 6.1.0.31, API 23, x86_64 QEMU with KVM and a 360 × 720 display. See [toolchain lock](../toolchain.lock.json) and [platform instructions](platform.md).

Successful execution on API 23 does not establish API 20 runtime compatibility. No physical phone execution is recorded. The HAP metadata and signature files describe their corresponding build, so they must be regenerated together for a release rather than combined with later unbuilt source changes.

`platform-baseline.mp4` is an earlier empty-template platform smoke recording. It is not the required final product demonstration. The final approximately three-minute English demonstration, source/release links and commit-bound checksum manifest remain separate deliverables.

## Native complete-flow checklist

The following checks need a current recorded result on the final HAP. Installation, a screenshot, a host unit test or a backend roundtrip alone does not satisfy a complete flow.

| Required flow | Current evidence status |
| --- | --- |
| Import bundled material, inspect author declaration, explicitly accept, complete tutorial | Native application runs; final complete-flow result pending. Tutorial reactive-state screenshot is supporting evidence only. |
| Explore regions using touch, accessible list, large buttons and on-screen scanning; stop/exit | Implemented; final current-HAP execution result pending. Genuine reader-enabled hover is separately unverified. |
| Choose incoming/outgoing relation, follow known path, announce unknown-path limitation | Domain transitions tested on host; native end-to-end result pending. |
| Select and explicitly submit an answer; preserve unfinished selection separately | Host state machine and native transaction/idempotency/reload tests passed. Recorded full learner UI sequence remains pending. |
| Kill the native learner process before/after acknowledgement, restart and resume | The latest [native recovery run](evidence/native-recovery.json) passed 100 actual forced restart boundaries after fsynced post-commit acknowledgements, including incomplete selection, submit/idempotent replay and package import. It supersedes an earlier failure at import cycle 11; concurrent repository initialization was repaired with process-wide coordination. Mid-transaction native fault injection remains separate and unverified. |
| Block WAN and use reviewed local packages, including audio | Architecture has no exploration-path service call; recorded native network-isolation proof pending. |
| Import a new SVG/image, edit geometry and facts, undo/redo, review and publish | CLI completed its offline author flow; full native editor/picker workflow pending current-HAP evidence. |
| Perform real native cloud analysis with consent, revise source-linked drafts and reject a late result | Provider inference verified independently and version-binding tested; native authoring roundtrip pending. |
| Prepare/import speech, verify readiness, export, then import into a clean installation | Offline CLI roundtrip passed. A native exported package exists, but completed final-revision native transfer must be independently verified. |
| Delete material with its private assets/history; separately export learning history | Native deletion test passed for assets, progress and events. Separate history export needs its recorded complete-flow result. |
| Handle cold/shared-open file and existing-ability file entry | Platform adapter exists; both complete paths need recorded verification. |
| Survive storage/write failure without false success; clean abandoned import staging | Transaction/staging implementation exists; native failure-injection evidence pending. |

## Accessibility and hardware limits

[Runtime investigation](evidence/screen-reader-investigation.json) found no genuine spoken screen reader on the pinned emulator. The installed development accessibility-hover probe is not a reader and cannot establish a successful blind-user flow. The remaining reader gate includes import, acceptance, tutorial, exploration, list navigation, answer selection/submission, pause, exit and resumption, with English announcements, stable focus, audio coordination and 200% text.

No physical vibration perception, hardware switch compatibility, headphone-removal behavior or external audio-route behavior is claimed. The on-screen scanning mode is distinct from physical assistive-switch support. Authoring controls and settings need the same real-reader review as learner exploration. [Accessibility behavior](ACCESSIBILITY.md) records intended behavior and these limits.

## AI evaluation interpretation

All 20 requests are retained in the denominator, including potential rejection/error records. The observed zero failures is limited to generated three-object process layouts and their controlled clear, low-contrast, rotated-text, ambiguous-arrow and instruction-like-text variants. The scoring script compares explicit labels and relation directions; it does not measure full geometry quality, author correction effort, semantic completeness, real photographs, dense pages or chart-number extraction accuracy.

The held-out subset contains five related synthetic fixtures rather than a broad external benchmark. Unknown arrow directions are scored against explicit unknown expectations. Instruction-like source text is treated as diagram data; the model has no tool execution or browser access. No participant study or independent expert source review of the generated corpus is recorded.

Author preparation time, correction time, edit count, time to reviewed publication and actual provider invoice cost are `null` in the evaluation report because they were not measured. Raw provider usage is retained where supplied. The service's reservation ceiling is an operational limit, not an invoice measurement.

## Performance and usefulness

Host geometry tests execute 1,000 hit-test events over 500 synthetic regions and enforce a 16 ms p95 host threshold. Runs passed, but this is Node host evidence. The native recovery run separately measured 100 warm hit tests (p95 1 ms, maximum 2 ms) and committed checkpoint reads (p95 2 ms, maximum 13 ms), using `Date.now()` millisecond resolution on its selected emulator. These measurements exclude cold startup, rendering and human interaction. No successful native p95 input-to-feedback, audio startup, cancellation latency, peak memory, package adoption time or battery measurement is claimed in this snapshot. The saved audio benchmark is currently unsuccessful and must not be interpreted as playable audio proof.

No blind/low-vision participant outcomes, teacher efficiency improvement, clinical result or superiority over a linear description/list baseline are claimed. [Study protocol](STUDY_PROTOCOL.md) defines three conditions and the remaining work. Useful learning and reduced author effort remain hypotheses until measured with representative participants and comparable materials.

## Bugs found and corrected during verification

- Imported nested JSON previously relied on TypeScript annotations. Runtime shape guards now reject malformed structures, unknown fields and bounded-content violations.
- Review status previously allowed a review from another revision. Publication and lesson checks now bind review to the current content revision.
- Polygon self-intersections, outside/touching holes, missing chart evidence and invalid/duplicate audio targets now have shared native/backend validation and regression fixtures.
- Portable paths now reject reserved Windows device names and Unicode normalization aliases.
- Manifest shape checks prevent missing author or malformed asset metadata from reaching the library. Bounded JSON parsing rejects duplicate decoded property names and excessive nesting before `JSON.parse` silently changes input meaning.
- Backend audio acceptance now matches native PCM WAV checks and the 50 ms metadata tolerance. Other recording formats receive an explicit local conversion instruction. Source raster dimensions are checked against the declared coordinate system.
- Highly repetitive valid recordings could exceed the package importer's 200:1 expansion policy after normal ZIP compression. The exporter now tries fast and Huffman-only DEFLATE without weakening import limits. Backend tests cover a 54 MiB expanded archive and a complete package containing a minute of silent PCM; native exporter execution is tracked separately.
- Expired backend job results are cleared before polling, while interrupted unknown outcomes remain distinct from successful completion.
- Actual emulator SVG decoding dropped text and marker arrows. Original SVG plus a hashed PNG preview now preserves those visible source elements. A first renderer attempt also lost text because its default font family was unavailable; pixel assertions caught this and explicit bundled-font loading corrected it.
- The narrow native SVG renderer profile rejected safe CSS-bearing sources returned with an accurate PNG preview. A separate passive source-retention validator now checks XML, entities, active content and external resources while permitting source CSS that is represented by the verified preview. Shared backend/native fixtures also cover fractional source dimensions rounded up for preview pixels.
- Concurrent repository initialization removed active import staging during a recovery test. Shared initialization coordination corrected that race; the subsequent 100-boundary native restart run passed.
- The native Hypium process returned an apparently successful runner exit despite setup errors. The harness was repaired and the later run reported ten actual passes; the earlier exit code was not counted as success.

Final release verification must replace pending entries with linked results, preserve genuine limitations, and tie artifacts to the final source commit. It must not infer completion from this checklist or from planned scripts.
