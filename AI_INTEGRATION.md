# Optional AI and speech preparation

TouchMap's offline learner path makes no inference request. The model assists a teacher in producing a draft from one selected image. It does not grade learner answers, publish material or control a device.

## Providers and payloads

The default image model is Google Gemini `gemini-3.8-flash`, through the pinned `google-genai` SDK. The service sends a metadata-stripped, size-bounded image and schema instructions. Text in an image is untrusted content, including instructions that ask the model to ignore rules or reveal secrets. The model has no browsing, execution, file-reading or other tools. IDs, coordinates, references, numeric values and graph structure are validated after inference. Structured output establishes syntax, not factual accuracy.

Speech uses ElevenLabs `eleven_flash_v2_5` at its documented text-to-speech endpoint. The configured voice is selected from the account's accessible catalogue. The sample generation run used the premade Bella voice `hpp4J3VqNfWAUOO0d1Us` on an active pay-as-you-go account. It sent only original nonsensitive teaching text. Audio is cached by text hash, language and voice and packaged for local playback. Imported authorised recordings provide a cloud-free alternative.

The native interface shows the selected source and provider before image upload and asks separately before sending reviewed speech text. Cropping and metadata removal happen before raster upload. An SVG conversion through the local CLI requires no cloud service. A conversion request through the preparation server sends the chosen source to that server but does not imply model inference.

## Review, failures and revisions

All model facts enter as drafts. Teachers separately review geometry, labels, directed connections, chart units/values, unknowns and lesson facts. Changing a relevant fact invalidates its dependent questions and recordings. Unreviewed or unknown values cannot silently become exact-value answers.

Each request has an ID, source hash and draft revision. A cancelled or stale result cannot overwrite newer edits. The client distinguishes provider configuration failure, authentication, rate limits, refusals, malformed output, timeout and cancellation. There is no automatic transfer to a different provider. A provider may have performed billable work even when a response is lost; an unknown outcome requires an explicit retry and is not advertised as exactly-once billing.

## Credentials, pairing and retention

Provider keys and session-signing material are backend-only. `psst` injects named values into a backend process. Public examples contain placeholders. Remote access requires HTTPS, expiring sessions obtained from one-use operator pairing codes, per-session limits and a global spend ceiling. A caller cannot choose an arbitrary provider URL, model or server file.

Application progress, profiles, bookmarks and local acceptance stay on the device. The service keeps bounded job metadata and a short retry cache, cleans expired work and avoids logging source images, label text or authorization headers. Exact retention/configuration is described in `docs/backend.md`. Local deletion cannot guarantee provider deletion or European data residency. Provider account terms and request-storage behavior remain distinct from local application policy.

## Validation and cost

Real provider smoke results, failure tests and corpus evaluation outputs belong in `docs/evidence/`. A live successful schema response does not establish diagram accuracy. The corpus reports acceptance and failures, omissions and direction errors separately, with held-out cases identified. Teacher-reviewed packages are evaluated separately from raw drafts.

The default service reserves a bounded budget before issuing provider calls, permits at most twenty analyses per paired session, and exposes operator configuration. Budget reservation is a guard, not a provider invoice. Sample generation is an explicit reproducibility script and does not run during install or application launch. A clean checkout includes its audio, so rebuilding samples does not require paid inference.

Primary API references: [Gemini model documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash), [ElevenLabs speech endpoint](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), [voice catalogue](https://elevenlabs.io/docs/api-reference/voices/search).
