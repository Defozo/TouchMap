# TouchMap presentation

The English presentation contains 10 slides, an editable PowerPoint file and a PDF. Every slide has a speaker script and source references in its PowerPoint notes. The cover and document metadata identify **DEFOZO SOFTWARE HOUSE** and its sole human member, **Michał Kiełtyka**.

Release outputs are `dist/touchmap-presentation.pdf` and `dist/touchmap-presentation.pptx`. Both fit the HackTribe 10 MB attachment limit. Their exact hashes and review decision are in [the presentation manifest](evidence/presentation-manifest.json). The public release destination is [TouchMap v1.0.0](https://github.com/Defozo/TouchMap/releases/tag/v1.0.0). External publication and anonymous access verification are separate from the local artifact review.

| Slide | Purpose |
| --- | --- |
| 1 | Product, intended use and team attribution |
| 2 | Diagram relationships and the learning hypothesis |
| 3 | Equivalent touch, list and scanning routes |
| 4 | Explicit answers, context restoration and private history |
| 5 | Source review, publication and separate offline readiness |
| 6 | Local architecture and optional preparation service |
| 7 | Native OpenHarmony integration and tested API boundary |
| 8 | Measured developer verification, with timing definitions |
| 9 | Accessibility evidence, remaining hardware checks and planned study |
| 10 | Source, release assets and installation instructions |

The screenshots show real native application captures. The cover uses the installed HAP `1209c8712549…`. Other screenshots document the specific earlier sessions recorded in their evidence. They do not imply that every flow ran on the same HAP. The original water-cycle source remains unchanged. [Image provenance](evidence/presentation-sources.json) binds the exact embedded image bytes. [Speaker notes](evidence/presentation-notes.json) contain the complete narration and citations.

Publication and Ready offline are distinct. The deck does not claim a completed study with blind or low-vision learners, a successful genuine-reader flow, physical vibration perception or physical speaker timing. The audio p95 ends at the first accepted PCM write. The restoration p95 ends at the active-app layout/draw boundary and includes 100 observations across explicitly reported batches of 92 and 8. Native tests run on the API 23 emulator, with API 20 as the build target and minimum.

## Editing and reproduction

Edit the PPTX directly in PowerPoint, or rebuild it from [the JavaScript generator](../scripts/build-presentation.mjs). The generator uses `@oai/artifact-tool` 2.8.59 from the supplied Presentations runtime 26.909.12148. Set `SKILL_DIR`, `RUNTIME_NODE_MODULES`, `RUNTIME_PYTHON` and `DECK_REVISION` to that runtime and a new revision name, then run the script with its Node executable. No provider credential is required. The generator keeps all narrative text and the two evidence tables editable, validates every local citation, sets the team metadata and invokes the skill finalizer.

`scripts/export-presentation.ps1 -Revision <revision> -RuntimePython <python-with-pypdf>` opens the candidate read-only in Microsoft PowerPoint and creates a separate PDF plus a PNG of every slide. It closes only that deck and quits PowerPoint only when this run started it and no other presentations remain. The Python helper adds two PDF link annotations because Office SaveAs omitted them. Each revision writes new files. After reviewing all rendered slides, copy the accepted bytes to the stable release names and update the manifest.

`python scripts/verify-presentation.py` checks exact manifest hashes, the 10-page/10-slide bounds, each slide's notes against the reviewed script, all local citations, native tables, PDF title text and final-page hyperlinks. It requires `pypdf` and Poppler `pdfinfo`. The release packager repeats the PDF/PPTX structure, notes, size and hash checks independently.

## Review

The final PPTX opened successfully in Microsoft PowerPoint 16.0. All 10 exported slides were inspected individually at 1600 × 900. All 10 PDF pages were also rendered with Poppler and inspected individually. Metadata attribution and invisible PDF link annotations were the only changes after the final content review. All 10 PowerPoint PNGs remained byte-identical after the metadata change, and all 10 final PDF renders remained byte-identical after adding links. [Quality checks](evidence/presentation-qc.json), [visual review](evidence/presentation-review.json) and [independent review](evidence/presentation-independent-review.json) record the actual coverage. This does not claim a genuine screen-reader audit of the deck itself.
