# TouchMap

**Challenge:** IMAGINE WHAT'S NEXT, HackYeah 2026  
**Team:** DEFOZO SOFTWARE HOUSE  
**Team member:** Michał Kiełtyka  
**Human team size:** 1  
**Primary area:** Human-Centric Technology, accessibility and education  
**Supporting area:** Intelligent Experiences, optional reviewed AI authoring

TouchMap is a native OpenHarmony application for exploring educational diagrams through touch, recorded speech, optional vibration and equivalent accessible controls. A teacher reviews the source geometry, relationships and numerical facts, adds deterministic lesson questions and exports a portable package. A learner accepts the author's declaration, explores independently, explicitly submits answers and resumes unfinished work offline without an account.

The implementation combines a native ArkTS/ArkUI application with an optional Python preparation service and local SVG CLI. It preserves unknown chart values, distinguishes review from offline audio readiness and learner acceptance, and protects immutable content revisions and transactional progress. Gemini proposes reviewable image drafts; ElevenLabs can prepare local recordings. Neither provider is needed for prepared lessons or for deterministic answer checking.

Included examples cover a water cycle, an unfamiliar branching process, a chart with an unknown value, and a three-shape tutorial. Source geometry, semantics and question answers are authored explicitly; packages include local recordings and provenance. An annotated 20-image owned corpus supports provider evaluation, with a held-out subset and all failed/rejected cases included in reporting.

The native product declares minimum and target API20 and is tested on the recorded API23 Oniro/OpenHarmony emulator. Build, signature, installation, provider tests, actual UI flows and outstanding accessibility/hardware/research gates are identified separately in the test report. An emulator vibration event is not physical-hardware evidence. A probe is not a genuine screen reader. No representative-user benefit percentage is claimed without a study.

## Submission contents

- `dist/touchmap-signed.hap` and SHA-256 checksums.
- Source repository and lockfiles, `README.md`, `ARCHITECTURE.md`, reproducible setup/build/install scripts.
- `AI_WORKFLOW.md`, `AI_INTEGRATION.md`, `THIRD_PARTY.md`, software and sample licences.
- `TEAM.json` with user-confirmed team data.
- `samples/*.touchmap`, original sources, reviewed semantics and local recordings.
- `docs/TEST_REPORT.md`, machine-readable runtime/provider evidence and the short English demonstration recording when completed.

Repository publication, official upload fields and submission status are recorded in the release manifest. This document is prepared submission copy, not proof that the competition submission has been sent.
