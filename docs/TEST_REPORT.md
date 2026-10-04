# Verification results and supported environment

TouchMap's current application is the native OpenHarmony release distributed as `touchmap-signed.hap` in [v1.0.1](https://github.com/Defozo/TouchMap/releases/tag/v1.0.1). Its SHA-256 is `e0a62c9bf865ef6333c708cfd4f51957c5f14447d368694df96a5b87e194a367`. The application source fingerprint is `c4f22e847a194700ceafc0645596d4470269193f4636657c7ffbbff9f26248ee`, from application checkpoint `17b51cb44b3a0272477cc70eb4f74cfbb77786b7`. Documentation updates do not change these binary identities.

## Reproducible checks

| Check | Recorded result | Scope and evidence |
| --- | --- | --- |
| Python backend | 93 passed | [Clean backend run](evidence/pitch-clean-pytest.txt), covering conversion, validation, jobs, packages and release structure. Controlled provider doubles do not reproduce a real provider outage. |
| Shared TypeScript modules | 51 passed; typecheck passed | [Clean host run](evidence/pitch-clean-npm.txt). These are the pure modules imported by the native app. |
| Release native integration | 18 passed, no failures or errors | [Artifact identity](evidence/native-test-artifact.json) and [native results](evidence/native-test-results.txt). |
| Release native audio controls | Five checks passed | [Control results](evidence/native-audio-controls.json): cancellation before dwell, latest-target replacement, pause/resume, replacement during a pending write and completion of a short PCM tail. |
| Independent local reproduction | Backend 93, host 51, typecheck, build/signature, native 18 and audio 5 passed | A fresh local clone produced independently signed HAP `b523156d...` with the same app-source fingerprint. [Reproduction record](evidence/pitch-clean-reproduction.json). Existing second-emulator data was retained. |
| Current installed UI | Four checks passed | [UI verification](evidence/pitch-final-ui/verification.json): library, saved correct answer after restart, unfinished selection and explicit submission control. |
| Offline authoring CLI | Conversion, revision, review, recording import, packing and independent unpacking passed | [CLI results](backend-checks.json) and [example package](evidence/backend-cli/new-material.touchmap). No cloud call is needed. |

Run `npm ci`, `npm test` and `npm run typecheck` at the repository root. In `backend`, run `uv sync --frozen` and `uv run pytest`. Native build and test commands are documented in [platform setup](platform.md).

## Persistence, transfer and input coverage

Earlier native runs separately exercised package import/export, scanning, ordinary-permission shared-file opening and offline lesson restoration. The [offline flow record](evidence/final-offline-flow.json) identifies the tested binaries and network isolation. The [100 forced-restart record](evidence/native-recovery.json) covers durable acknowledgements; it is distinct from the [three mid-transaction interruption checks](evidence/native-transaction-interruption.json). These historical runs retain their own artifact identities and are not presented as fresh executions on a later binary.

The [native input observations](evidence/native-ui-observations.json) cover labelled coordinate editing, Undo/Redo, navigation and text at 200%. [Accessibility behavior](ACCESSIBILITY.md) describes both the implemented alternatives and the runtime verification boundary.

## Performance measurements

On candidate HAP `d1ad20df...`, a complete 100-event run measured scheduler-to-first-accepted-PCM-write median 4 ms, p95 49 ms and maximum 148 ms. Including the configured 250 ms dwell, the p95 was 318 ms. The run used an isolated clocked audio sink; normal renderer initialization and physical acoustic output are outside the interval. [Measurements and artifact](evidence/pitch-audio100/summary.json). An earlier attempt stalled after five observations; the successful retry contains its own 100 observations and does not merge the incomplete samples. [Incomplete attempt](evidence/pitch-audio100-incomplete/artifact.json).

Historical HAP `1209c871...` recorded context-restoration p95 130 ms and maximum 453 ms across 100 acknowledged observations. The boundary is Library open through restored state and ArkUI `willDraw`, not physical display scanout or cold launch. The sample consists of 92 acknowledged observations and eight more after a UiTest RPC stall. [Restoration summary](evidence/native-restore-benchmark.json).

The shared WSLg audio route showed intermittent stalls. The isolated clocked route completed the recorded native controls. It captures emulator PCM without live speaker output. Use [emulator audio setup](EMULATOR_AUDIO.md) to choose and verify the intended route before demonstrating the application.

## Optional provider evaluation

The first-attempt synthetic corpus contains 20 process diagrams and five charts. Process diagrams scored 20/20 on the constrained scorer. Charts produced five schema-valid responses, all 16 source values and both unknowns correctly, but only 2/5 strict representation matches and 0/2 held-out matches. These are small authored corpora, not estimates of classroom accuracy. [AI integration](../AI_INTEGRATION.md) preserves the evaluation definitions and error analysis. Generated drafts require teacher review.

## Compatibility and use limits

- The tested runtime is Oniro/OpenHarmony API 23. API 20 is the declared minimum and build target; API 20 runtime execution has not been established.
- The pinned emulator does not provide a genuine spoken screen reader for a complete learner walkthrough. Accessibility event and labelled-control checks do not establish spoken-reader compatibility.
- Physical vibration, physical headphone removal and simultaneous reader/application audio remain unverified on real hardware.
- No representative blind/low-vision learner or teacher study has been completed. Learning benefit and reduced authoring effort have not been measured against the comparison conditions in the [evaluation protocol](STUDY_PROTOCOL.md).
- Provider readiness checks verify configuration. They do not establish inference success, remote phone reachability or exactly-once billing.

These limits apply when planning deployment or user evaluation. Package checksums, source fingerprints and retained test records allow each technical result to be traced to its actual inputs.
