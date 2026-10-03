# TouchMap presentation

The English pitch contains 10 slides, an editable PowerPoint file and a PDF. It shows how a learner explores a diagram, follows connections and returns to a saved lesson. Every slide has a speaker script and source references in its PowerPoint notes. The cover and document metadata identify **DEFOZO SOFTWARE HOUSE** and its sole human member, **Michał Kiełtyka**.

Release outputs are `dist/touchmap-presentation.pdf` and `dist/touchmap-presentation.pptx`. Both fit the HackTribe 10 MB attachment limit. Their exact hashes and review decision are in [the presentation manifest](evidence/presentation-manifest.json). The release destination is [TouchMap v1.0.1](https://github.com/Defozo/TouchMap/releases/tag/v1.0.1). External publication and anonymous access verification are separate from the local artifact review.

| Slide | Purpose |
| --- | --- |
| 1 | Product, intended use and team attribution |
| 2 | A concrete question about connections in the water cycle |
| 3 | Equivalent touch, list and scanning routes |
| 4 | Explicit answers, context restoration and private history |
| 5 | Source review, publication and separate offline readiness |
| 6 | Offline learning and optional online preparation |
| 7 | Native interaction, audio, file sharing and storage |
| 8 | The four bundled examples and their learning activities |
| 9 | Larger controls, scanning pace and explained answers |
| 10 | Source, release assets and installation instructions |

The screenshots show real native application captures. The cover identifies the demonstration as a native OpenHarmony emulator session and uses [the revised Library capture](evidence/pitch-library-capture.json), from HAP `1cae6f5da819…` at source commit `943a5d8`. Other screenshots document the specific earlier sessions recorded in their evidence. They do not imply that every flow ran on the same HAP. The original water-cycle source remains unchanged. [Image provenance](evidence/presentation-sources.json) binds the exact embedded image bytes. [Speaker notes](evidence/presentation-notes.json) contain the complete narration and citations.

Publication and Ready offline are distinct. The deck describes implemented interaction and intended users without claiming a measured learning advantage or a completed participant study. Detailed measurements and remaining validation belong in [the test report](TEST_REPORT.md), [accessibility documentation](ACCESSIBILITY.md) and [study protocol](STUDY_PROTOCOL.md). Native tests run on the API 23 emulator, with API 20 as the build target and minimum.

## Editing and reproduction

Edit the PPTX directly in PowerPoint, or rebuild it from [the JavaScript generator](../scripts/build-presentation.mjs). The generator uses `@oai/artifact-tool` 2.8.59 from the supplied Presentations runtime 26.909.12148. Set `SKILL_DIR`, `RUNTIME_NODE_MODULES`, `RUNTIME_PYTHON` and `DECK_REVISION` to that runtime and a new revision name, then run the script with its Node executable. No provider credential is required. The generator keeps all narrative text and the two evidence tables editable, validates every local citation, sets the team metadata and invokes the skill finalizer.

`scripts/export-presentation.ps1 -Revision <revision> -RuntimePython <python-with-pypdf>` opens the candidate read-only in Microsoft PowerPoint and creates a separate PDF plus a PNG of every slide. It closes only that deck and quits PowerPoint only when this run started it and no other presentations remain. The Python helper adds two PDF link annotations because Office SaveAs omitted them. Each revision writes new files. After reviewing all rendered slides, copy the accepted bytes to the stable release names and update the manifest.

`python scripts/verify-presentation.py` checks exact manifest hashes, the 10-page/10-slide bounds, each slide's notes against the reviewed script, all local citations, native tables, PDF title text and final-page hyperlinks. It requires `pypdf` and Poppler `pdfinfo`. The release packager repeats the PDF/PPTX structure, notes, size and hash checks independently.

## Review

The current [visual review](evidence/presentation-review.json) records the exact PDF and PPTX hashes, PowerPoint rendering and individual slide inspection. [Quality checks](evidence/presentation-qc.json) verify the file structure, notes, citations and live hyperlink annotations. The [independent review](evidence/presentation-independent-review.json) identifies its reviewed version explicitly. A review of an earlier version does not certify later bytes. This does not claim a genuine screen-reader audit of the deck itself.
