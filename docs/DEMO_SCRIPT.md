# TouchMap: three-minute English demonstration

Team: **DEFOZO SOFTWARE HOUSE**. Sole human member: **Michał Kiełtyka**.

The 179.917-second English film shows a learner importing a lesson, exploring its objects and connections, answering a question and returning to saved progress. It then shows how an author prepares and shares a reviewed lesson. Clear narration and a quiet instrumental score accompany the actual native recordings.

The opening narration is: “Touch an object. Hear its name. Follow its connections. This is TouchMap.” Sixteen narration passages use the premade ElevenLabs Alice voice. The instrumental score is an original local composition. During the native interaction at 00:33 to 00:48, narration pauses while the score continues quietly. It is lowered around the original spoken label **Evaporation**, at 00:35.2 to 00:36.5. [Audio provenance and rights](evidence/demo-pitch-audio-provenance.json) identify the selected assets and their hashes.

The reviewed film is `dist/touchmap-demo.mp4`, SHA-256 `93d78eb05db424c70720c94aabd3a2f7c0c8d8c3435097f5babc77fe64e43dce`. [Whole-audio perception](evidence/demo-pitch-audio-review.json), [local mix verification](evidence/demo-audio-transcript.json) and [independent final-cut review](evidence/demo-independent-review.json) refer to those exact bytes. The audio review consumed the complete rendered sound, rather than inferring quality from a transcript or the existence of an audio stream.

The [soundtrack repair](evidence/demo-repair/TOUCHMAP_NARRATION_REPAIR.json) addresses the viewer-reported silence near 00:46. It restores the existing score over 00:32.3 to 00:48.7, preserves every narration passage and the captured application speech, and trims only the final two static picture frames. The complete closing sentence still ends more than one second before the film. The previous `520b…` master and its reports remain preserved separately; they are not presented as reviews of the repaired bytes.

The exact source ranges and captions are in [the storyboard](demo-storyboard.json). The [demo manifest](evidence/demo-manifest.json) records source and output hashes, build provenance and review coverage. Historical footage is not described as a recording of every final release change.

| Output time | Demonstrated action |
| --- | --- |
| 00:00–00:07 | Introduce TouchMap and the team beside the actual Library captured from HAP `1cae6f5da819`, with the revised entry copy. |
| 00:07–00:21 | Import a teaching package through the native picker with outbound networking blocked. |
| 00:21–00:33 | Read the source and author declaration, then accept locally. |
| 00:33–00:48 | Ordinary emulator touch changes the selected object and plays its actual local recording. |
| 00:48–01:02 | Move between objects using the reviewed connection controls. |
| 01:02–01:12 | Submit the selected answer and show the deterministic correct result. |
| 01:12–01:21 | Start another question and save an unfinished selection. |
| 01:21–01:27 | Show the actual process restart returning to Library. |
| 01:27–01:37 | Restore the previous correct answer and the new, still-unsubmitted selection. Search waiting is omitted. |
| 01:37–01:51 | Show permission and request controls for a real Gemini draft from an owned source. The preparation wait is omitted. |
| 01:51–01:58 | Show that request's retained source and proposed geometry. |
| 01:58–02:10 | Review geometry and meaning in an earlier session on the same source, labelled as an earlier authoring session. |
| 02:10–02:17 | Show recording controls and actual playback status from the successful earlier speech session, accompanied by the pitch narration. |
| 02:17–02:27 | Show published revision 6 marked Ready offline. This is a result view, not a reconstructed publication click. |
| 02:27–02:45 | Reimport the package offline on the second installation. Existing acceptance and private learning progress are preserved. |
| 02:45–02:59.917 | Invite the viewer to download TouchMap and the sample lessons, then import a diagram, follow a connection and try the lesson. |

The opening capture is bound to HAP `1cae6f5da819c826a76e524befa6780af8e848239f6f63216d5fe7b5fd6ef630`, source commit `943a5d8`, in [its capture evidence](evidence/pitch-library-capture.json). This identifies the recorded artifact, which can precede later release fixes. The remaining scenes retain their historical build identities in the storyboard and manifest. The new AI request and published revision are separate verified runs on the same owned source. The visible reviewer is the recorded developer verification identity. The film does not attribute that review to Michał or to a study participant.

The second-installation footage shows idempotent reimport. Its original first import, local acceptance and offline answer are documented in [the UI ledger](evidence/native-ui-observations.json) and [asset verification](evidence/second-import-integrity.json). The clip is not labelled a fresh installation or first acceptance.

The closing focuses on trying the product. Measurements, test scope and outstanding validation are kept in [the technical test report](TEST_REPORT.md). The application targets API 20 and the recorded emulator runtime is API 23. Automated media perception is recorded as automated review; it is not described as human listening or physical-device testing.

With the retained master and prepared audio assets present, reproduce the bounded correction with `python scripts/render-demo.py docs/demo-storyboard.json --output dist/_video_work/reproduced-repair.mp4 --manifest dist/_video_work/reproduced-repair.json`. The renderer checks the previous approved master, its storyboard and manifest, the complete delivery audio, the new plan hash and the exact 4318-frame duration. It rejects altered scene contents and never adds the old audio a second time. Rendering uses two threads and never calls a paid provider. `--prepare` validates these inputs without encoding. Earlier scene assembly used WSL FFmpeg with `drawtext`; this derivative uses the preserved encoded master and the prepared full soundtrack. [The original-score script](../scripts/compose-demo-music.py) uses NumPy and SoundFile; all original narrator requests remain recorded in the audio provenance.

Run `python scripts/verify-demo.py` with NumPy, Pillow and FFmpeg for strict frame decoding, approved-mix correlation, independent captured-label preservation and final scene/boundary contact sheets. `python scripts/verify-demo-audio.py` checks every prepared narration passage against the final mix, relative music level, native stereo peak, quiet ending, absence of long soundtrack dropouts and complete-script agreement. It also requires a separate whole-audio perceptual review tied to the exact film hash. These local commands do not call a provider or automatically promote a film as reviewed.

The initial pitch and its two copy-correction rounds followed the user's explicit pitch-and-audio instruction. The later viewer-reported soundtrack gap prompted a separate authorized repair and independent review. The final storyboard records both stages without claiming the user personally approved each cut. Earlier cuts, provider takes and review evidence are preserved in the local video work directory. The additional Polish song version is a separate experiment and is not this English submission film.
