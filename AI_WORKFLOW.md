# AI-assisted development and content provenance

TouchMap was developed for HackYeah 2026 by **DEFOZO SOFTWARE HOUSE**, with **Michał Kiełtyka** as its sole human team member.

## Development

AI coding agents assisted with planning, ArkTS/ArkUI implementation, Python conversion and package handling, tests, documentation and release scripts. The repository contains the resulting source and regression tests. Generated code was checked through host tests, backend tests, native builds, emulator integration and source-bound artifact verification. [Test results](docs/TEST_REPORT.md) identify the executed checks and their limits.

The design separates the shared semantic model from native input, audio, storage and lifecycle adapters. Model suggestions were revised when verification exposed problems, including malformed package input, interrupted persistence, source rendering, audio completion and large native test fixtures. These engineering checks do not establish usability or learning outcomes for the intended population.

## Product inference

The learner's offline path makes no model call. Optional Gemini image analysis produces an editable draft for a teacher. Optional ElevenLabs speech generation produces recordings for local playback. Both require explicit consent; the teacher reviews source facts before publication. Learner answers are checked against the reviewed lesson data, not graded by a model. See [AI integration](AI_INTEGRATION.md) for provider models, evaluation results, consent, costs and retention.

## Demonstration and presentation

The English demonstration combines real native emulator recordings, sixteen narrated scenes and an original instrumental score. Narration uses the premade ElevenLabs Alice voice with `eleven_multilingual_v2`; it does not clone the team member's voice. The score was composed and synthesized locally with NumPy and SoundFile. The native Evaporation recording is retained in the film.

Gemini 3.8 Flash assisted with review of the rendered demonstration audio. Automated transcript, signal, decoding and image checks supplement that review. Automated perception is not a claim of human listening, physical acoustic performance or a participant study. [Audio provenance](docs/evidence/demo-pitch-audio-provenance.json), the [demo manifest](docs/evidence/demo-manifest.json) and the [presentation manifest](docs/evidence/presentation-manifest.json) identify the released media and its source material.

The editable presentation uses actual application screenshots, with their origins retained in [image provenance](docs/evidence/presentation-sources.json). AI assistance did not supply invented participants, testimonials, deployments or measured learning benefits.

## Reproduction and attribution

Dependency and toolchain locks are committed. [Platform setup](docs/platform.md), [backend operation](docs/backend.md) and [release packaging](docs/RELEASE.md) describe reproduction. Provider credentials and signing keys are supplied locally and are not distributed.

[Third-party notices](THIRD_PARTY.md) and [sample licences](samples/LICENSE.md) cover reused software and teaching assets. The application source is released under the repository's [MIT licence](LICENSE).
