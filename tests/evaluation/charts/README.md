# Owned numeric chart corpus

Five fixed bar/line charts supplement the separate twenty process fixtures. Their original SVGs and deterministic PNGs contain explicitly authored values, units, domains, ticks and category labels. They are not observational data. `truth.json` was generated before the first provider evaluation; it includes critical values, source text, approximate region bounds and the original PNG hashes.

Cases cover a missing rainfall value, decimal energy values with reduced contrast, negative temperature values with a missing sample, rotated labels and a decimal distance series. Unknowns are drawn with an explicit question mark and no numeric bar/point. A line never interpolates across a missing value. Chart 04 and chart 05 are held out and must not be used to tune the model prompt.

Run `render-charts.py` in the pinned backend Python environment to reproduce the source and PNGs using the bundled licensed font. The fixtures use CC BY 4.0, attribution TouchMap contributors, as documented in [sample provenance](../../../samples/LICENSE.md). Raw model results and scoring are engineering evidence, separate from source-reviewed publication and representative teacher studies.
