# TouchMap: three-minute English demonstration

Team: **DEFOZO SOFTWARE HOUSE**. Sole human member: **Michał Kiełtyka**.

The film uses English captions beside actual native framebuffer recordings. It contains no generated application screens, substituted provider responses, invented reader audio or physical-device claims. The audible excerpt is the captured output of the selected QEMU emulator during ordinary touch exploration, aligned using the recording's UTC capture starts. Other scenes are intentionally silent.

The local machine transcript recognizes **Evaporation** in the touch excerpt. It does not recognize Precipitation, and no later recording was identified by the signal-activity check. The film therefore demonstrates one audible object label and does not claim both visual selections were heard. The initial two-label expectation is retained as a non-passing diagnostic in the audio evidence; no human listening or continuous audiovisual review is implied.

The exact source ranges and captions are in [the storyboard](demo-storyboard.json). The [demo manifest](evidence/demo-manifest.json) records source and output hashes, build provenance and review coverage. Historical footage is not described as a recording of every final release change.

| Output time | Demonstrated action |
| --- | --- |
| 00:00–00:07 | Show the actual Library of the installed final release HAP `1209c8712549`, with TouchMap's intended blind/low-vision audience and the team. |
| 00:07–00:21 | Import a teaching package through the native picker with outbound networking blocked. |
| 00:21–00:33 | Read the source and author declaration, then accept locally. Distinguish integrity from certification. |
| 00:33–00:48 | Ordinary emulator touch changes the selected object and plays its actual local recording. |
| 00:48–01:02 | Show the object list and reviewed directed-connection controls. Unknown picture routes remain explicit. |
| 01:02–01:12 | Submit the selected answer and show the deterministic correct result. |
| 01:12–01:21 | Start another question and save an unfinished selection. |
| 01:21–01:27 | Show the actual process restart returning to Library. |
| 01:27–01:37 | Restore the previous correct answer and the new, still-unsubmitted selection. Search waiting is omitted. |
| 01:37–01:51 | Show separate consent, a real Gemini request and review-required draft output for an owned source. |
| 01:51–01:58 | Show that request's retained source and proposed geometry. |
| 01:58–02:10 | Review geometry and meaning in an earlier session on the same source. This frame-driven source is labelled a condensed developer authoring excerpt. |
| 02:10–02:17 | Show recording controls and actual playback status from the successful earlier speech session. This UI excerpt has no captured sound. |
| 02:17–02:27 | Show published revision 6 marked Ready offline. This is a result view, not a reconstructed publication click. |
| 02:27–02:45 | Reimport the package offline on the second installation. Existing acceptance and private learning progress are preserved. |
| 02:45–03:00 | Show measured developer verification and remaining reader, physical-vibration and representative-user-study limits. |

The opening shows the final release HAP `1209c87125492cd145ea06a0480d84cc16b5e37c5f6f8fe34908f8e76609c4bd`, installed from committed application source `2642efe`. The remaining scenes retain explicit historical build labels. The new AI request and published revision are separate verified runs on the same owned source. The edit does not imply the newly requested draft was immediately published. The visible reviewer is the recorded developer verification identity, not a claim that Michał personally performed the on-screen review or that a blind participant used the application.

The second-installation footage shows idempotent reimport. Its original first import, local acceptance and offline answer are documented in [the UI ledger](evidence/native-ui-observations.json) and [asset verification](evidence/second-import-integrity.json). The clip is not labelled a fresh installation or first acceptance.

Closing numbers are tied to their evidence: 18 native tests and 100 audio starts on build `a40c63d2`, audio p95 25 ms to the first accepted PCM write, and 100 acknowledged-commit restart cycles recorded separately. PCM acceptance is not physical acoustic onset. The application targets API 20; the recorded emulator runtime is API 23. Genuine-reader complete-flow testing, physical vibration and representative-user studies remain unverified.

Reproduce with `python3 scripts/render-demo.py docs/demo-storyboard.json` and FFmpeg including `drawtext`. The verified renderer runs in Ubuntu/WSL. It preserves sources, caches two-thread scene renders under `dist/_video_work`, uses PCM intermediates to avoid per-cut AAC padding accumulation, and encodes the final 1920×1080, 24 fps H.264/AAC MP4 once. `--prepare` caches available scenes without assembling an incomplete film.

Run `python scripts/verify-demo.py` with NumPy, Pillow and FFmpeg for strict frame decoding, audio/sample alignment checks and final scene/boundary contact sheets. This does not mark the film reviewed automatically; the exact resulting film still receives a factual and visual review. `python scripts/verify-demo-audio.py` additionally transcribes the retained touch-audio excerpt using an already cached local faster-whisper `small` model. The machine transcript is supporting evidence and does not claim human listening.

Assembly and bounded corrections follow the user's complete PLAN implementation request and delegated demo brief. The final storyboard records that authorization without claiming the user personally reviewed each cut.
