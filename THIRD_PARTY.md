# Third-party notices and pre-existing work

TouchMap application logic, native screens, contracts, converter, examples and tests were developed during the implementation of the 3 October 2026 challenge plan. The pre-existing task materials and proposals are planning inputs, not previously implemented product code.

- The native project configuration and initial icon assets derive from the official Eclipse Oniro `EmptyAbility` template, Apache License 2.0. Source: https://github.com/eclipse-oniro4openharmony/oniro-app-builder . Preserve upstream notices when redistributing template assets.
- OpenHarmony SDK and system libraries retain their upstream licences; they are build/runtime dependencies rather than TouchMap-owned software. Only the app HAP is a product artifact.
- Python dependencies and exact transitive versions are in `backend/uv.lock`: FastAPI, Pydantic, Uvicorn, Pillow, defusedxml, svgpathtools, Shapely, httpx, google-genai, python-multipart, mutagen and their dependencies. Their installed licence metadata is the source of record. They are not copied into the HAP.
- Host verification uses TypeScript, tsx, esbuild and Node type definitions under their upstream licences, pinned in `package-lock.json`. These are development tools, not shipped native runtime modules.
- SVG previews use the pinned `resvg_py 0.5.0` binding to the resvg renderer. The preparation service bundles DejaVu Sans for deterministic text rendering; its complete redistribution notice is [DejaVu-LICENSE.txt](backend/touchmap/assets/DejaVu-LICENSE.txt). Missing source fonts are substituted explicitly and layout still requires author review. PNG previews are generated from the actual source, independently of proposed diagram semantics.
- [Sample provenance](samples/LICENSE.md) covers owned illustrations and generated audio. ElevenLabs and Gemini are optional external services, not embedded open-source model weights.

The challenge PDFs, quoted requirements and organiser names remain their respective owners' materials. Their presence as local planning references does not relicense them under the root MIT software licence. Public release packaging should include product code and the relevant notices, not private service-catalog references or raw tool histories.
