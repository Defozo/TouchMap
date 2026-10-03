# Optional AI and speech preparation

Team: **DEFOZO SOFTWARE HOUSE**. Sole human member: **Michał Kiełtyka**.

TouchMap's offline learner path makes no inference request. The model assists a teacher in producing a draft from one selected image. It does not grade learner answers, publish material or control a device.

## Providers and payloads

The default image model is Google Gemini `gemini-3.8-flash`, through the pinned `google-genai` SDK. The service sends a metadata-stripped, size-bounded image and schema instructions. Text in an image is untrusted content, including instructions that ask the model to ignore rules or reveal secrets. The model has no browsing, execution, file-reading or other tools. IDs, coordinates, references, numeric values and graph structure are validated after inference. Structured output establishes syntax, not factual accuracy.

Speech uses ElevenLabs `eleven_flash_v2_5` at its documented text-to-speech endpoint. The configured voice is selected from the account's accessible catalogue. The sample generation run used the premade Bella voice `hpp4J3VqNfWAUOO0d1Us` on an active pay-as-you-go account. It sent only original nonsensitive teaching text. Audio is cached by text hash, language, voice and model and packaged for local playback. Imported authorised recordings provide a cloud-free alternative.

The native interface shows the selected source and provider before image upload and asks separately before sending reviewed speech text. Cropping and metadata removal happen before raster upload. An SVG conversion through the local CLI requires no cloud service. A conversion request through the preparation server sends the chosen source to that server but does not imply model inference.

## Review, failures and revisions

All model facts enter as drafts. Teachers separately review geometry, labels, directed connections, chart units/values, unknowns and lesson facts. Changing a relevant fact invalidates its dependent questions and recordings. Unreviewed or unknown values cannot silently become exact-value answers.

Each request has an ID, source hash and draft revision. A cancelled or stale result cannot overwrite newer edits. The client distinguishes provider configuration failure, authentication, rate limits, refusals, malformed output, timeout and cancellation. There is no automatic transfer to a different provider. A provider may have performed billable work even when a response is lost; an unknown outcome requires an explicit retry and is not advertised as exactly-once billing.

## Credentials, pairing and retention

Provider keys and session-signing material are backend-only. `psst` injects named values into a backend process. Public examples contain placeholders. Remote access requires HTTPS, expiring sessions obtained from one-use operator pairing codes, per-session limits and a global spend ceiling. A caller cannot choose an arbitrary provider URL, model or server file.

Application progress, profiles, bookmarks and local acceptance stay on the device. The service keeps bounded job metadata and a short retry cache, cleans expired work and avoids logging source images, label text or authorization headers. Exact retention/configuration is described in [the backend guide](docs/backend.md). Local deletion cannot guarantee provider deletion or European data residency. Provider account terms and request-storage behavior remain distinct from local application policy.

## Validation and cost

The first real-provider evaluations used 25 owned synthetic images, with the two corpora reported separately. A valid schema response does not establish factual accuracy or teacher usability.

| Corpus | First-attempt result | Scope and retained failures |
| --- | --- | --- |
| [20 process diagrams](docs/evidence/ai-evaluation/summary.json), five held out | 20/20 met the constrained diagram scorer | Label, object and directed-edge checks on a small authored corpus; not representative classroom accuracy. |
| [Five charts](docs/evidence/ai-chart-evaluation/summary.json), two held out | 5/5 schema-valid; 16/16 source values and 2/2 unknowns exact; 2/5 strict representation matches, 0/2 held-out matches | One source-supported connecting line absent from the truth structure; two axis headings repeated their correctly extracted units. Units, domains, ticks and scales matched. No unsupported numeric assertions were found. |

The [chart source audit](docs/evidence/ai-chart-evaluation/INTERPRETATION.md) retains all three strict mismatches without changing the scorer or tuning on held-out results. These drafts remain unreviewed. No participant study, representative author-review time or general accuracy claim follows from these results.

A separate [actual native authoring flow](docs/evidence/native-authoring-flow.json) imported an owned raster, obtained three objects and two relationships from Gemini, corrected geometry, reviewed the facts, added one deterministic direction question, obtained separate speech consent, generated ten audio references backed by nine unique WAV files, played recordings, published and exported [the resulting package](docs/evidence/native-authored.touchmap). Its reviewer is explicitly `TouchMap developer verification (Codex)`, not the human team member. The original playback capture and machine transcription are retained, including an ASR error in the question. A [second offline device import](docs/evidence/second-import-integrity.json) independently matched all eleven packaged assets. The shared cached recording for identical relation text exposed a native duplicate-path rejection; deduplication by verified audio content fixed it, with a backend regression test.

The default service reserves a bounded budget before issuing provider calls, permits at most twenty analyses per paired session, and exposes operator configuration. Budget reservation is a guard, not a provider invoice. Sample generation is an explicit reproducibility script and does not run during install or application launch. A clean checkout includes its audio, so rebuilding samples does not require paid inference.

The [saved cost calculation](docs/evidence/provider-cost-estimates.json) uses public rates checked on 3 October 2026. Gemini input/output rates are $0.75/$3.75 per million tokens through 31 December 2026. The SDK exposes differing summary and raw invocation token counts, so both estimates are retained. [Google pricing](https://ai.google.dev/gemini-api/docs/pricing).

| Saved requests | Summary-usage estimate, USD | Raw-invocation estimate, USD | Request median / p95 |
| --- | ---: | ---: | --- |
| 20 process diagrams | 0.06035625 | 0.09089625 | 6,070 / 12,579 ms |
| Five charts | 0.03302625 | 0.04066125 | 8,078 / 9,547 ms |
| Combined 25 images | 0.09338250 | 0.13155750 | Reported separately above |

These are estimates for those saved corpus calls, not invoices; development smokes and the separate native authoring flow are outside this total. The process-only mean is approximately $0.00302 per draft meeting its narrow script criterion. Cost through teacher-approved publication remains unknown.

Bundled speech estimates count the exact submitted teaching text at the currently listed Flash/Turbo API rate of $0.04 per thousand characters. Reusing the bundled recordings makes no new generation request. [ElevenLabs API pricing](https://elevenlabs.io/pricing/api). No representative author-review time or cost through teacher-approved publication has been measured; those fields remain explicitly unknown. Run `python scripts/report-provider-cost.py` to reproduce the calculation from the saved usage, without making provider calls.

Primary API references: [Gemini model documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash), [ElevenLabs speech endpoint](https://elevenlabs.io/docs/api-reference/text-to-speech/convert), [voice catalogue](https://elevenlabs.io/docs/api-reference/voices/search).
