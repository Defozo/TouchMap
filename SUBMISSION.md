# TouchMap

**Challenge:** IMAGINE WHAT'S NEXT, HackYeah 2026  
**Team:** DEFOZO SOFTWARE HOUSE  
**Team member:** Michał Kiełtyka  
**Human team size:** 1  
**Primary area:** Human-Centric Technology, accessibility and education  
**Supporting area:** Intelligent Experiences, optional reviewed AI authoring

TouchMap is a native OpenHarmony application for exploring educational diagrams through touch, recorded speech, optional vibration and equivalent accessible controls. A teacher reviews the source geometry, relationships and numerical facts, adds deterministic lesson questions and exports a portable package. A learner accepts the author's declaration, explores independently, explicitly submits answers and resumes unfinished work offline without an account.

The implementation combines a native ArkTS/ArkUI application with an optional Python preparation service and local SVG CLI. It preserves unknown chart values, distinguishes review from offline audio readiness and learner acceptance, and protects immutable content revisions and transactional progress. Gemini proposes reviewable image drafts; ElevenLabs can prepare local recordings. Neither provider is needed for prepared lessons or for deterministic answer checking.

Included examples cover a water cycle, an unfamiliar branching process, a chart with an unknown value, and a three-shape tutorial. Source geometry, semantics and question answers are authored explicitly; packages include local recordings and provenance. The owned provider evaluation contains 20 process diagrams and five charts, with five and two held-out images respectively. All process drafts met their constrained scorer. The charts preserved all 16 source values, including two explicit unknowns, but only two of five matched the strict representation score, including neither held-out chart. The [source audit](docs/evidence/ai-chart-evaluation/INTERPRETATION.md) retains all three differences; these small synthetic corpora do not establish general accuracy or human usability.

The [recorded native authoring verification](docs/evidence/native-authoring-flow.json) completed real image analysis, source correction and review, a deterministic question, separately consented speech generation, local playback, publication and portable export. Its declaration names the developer verification tool, not the human team member. The exported package was independently validated and [imported on a second offline emulator with all asset hashes matching](docs/evidence/second-import-integrity.json). Repeated speech text correctly shares cached bytes after a native duplicate-path bug was fixed.

The native product declares minimum and target API20 and is tested on the recorded API23 Oniro/OpenHarmony emulator. Build, signature, installation, provider tests, actual UI flows and outstanding accessibility/hardware/research gates are identified separately in [the test report](docs/TEST_REPORT.md). A 100-play software benchmark measured p95 25 ms from scheduler decision to first accepted PCM write with a prewarmed renderer; the interval including intentional dwell had p95 303 ms. These are not physical touch-to-sound timings. An emulator vibration event is not physical-hardware evidence. A genuine screen-reader walkthrough and representative-user study remain unverified. No representative-user benefit percentage is claimed.

## Submission contents

- `dist/touchmap-signed.hap` and SHA-256 checksums.
- Source repository and lockfiles, `README.md`, `ARCHITECTURE.md`, reproducible setup/build/install scripts.
- `AI_WORKFLOW.md`, `AI_INTEGRATION.md`, `THIRD_PARTY.md`, software and sample licences.
- `TEAM.json` with user-confirmed team data.
- `samples/*.touchmap`, original sources, reviewed semantics and local recordings.
- `docs/TEST_REPORT.md`, machine-readable runtime/provider evidence and the short English demonstration recording, whose completion and review state are bound in the release evidence.

The [official submission requirements and supporting public sources](docs/SUBMISSION_REQUIREMENTS.md) record the verified deadlines and distinguish them from fields only visible after HackTribe sign-in. The user confirmed that TouchMap already exists in HackTribe. Final material submission has not been confirmed. Repository publication, official upload fields and submission status are recorded in the release manifest. This document is prepared submission copy, not proof that the competition submission has been sent.
