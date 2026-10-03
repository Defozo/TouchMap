# First chart evaluation and source audit

Five real Gemini 3.8 Flash calls used the unchanged product adapter, with the two predeclared held-out images included once. All raw model JSON, validated drafts, provider usage and first-attempt scores are retained. No result was retried or used to tune the prompt. This is a small owned synthetic corpus, not a real-world accuracy estimate or a teacher usability study.

All five responses passed the schema. All 16 category values, including two explicit unknowns, matched the source exactly. Units, numerical domains, tick coordinates, axis scales and categorical tick labels matched in all five images. The numeric scoring found no unsupported value assertions. The five response durations were 9547, 7484, 8218, 7110 and 8078 ms; these are measured adapter call durations, not editor latency or human correction time.

The original scorer's `usableChartDraft` key means **strict representation match to the authored truth structure**. It is 2/5 overall and 0/2 on the held-out images. It does not measure human usability. The three strict mismatches are retained:

| Image | Strict mismatch | Source audit |
| --- | --- | --- |
| chart-03 | One additional relation; truth encodes no chart relations | The source visibly joins Day 1 and Day 2. The proposed relation says connecting line and keeps direction unknown. It does not assert a causal arrow or interpolate the missing Day 3 value. |
| chart-04, held out | Vertical label `Volume (L)` differs from truth label `Volume` | The complete printed axis heading includes `(L)`; the separate unit field correctly contains `L`. This is duplicate unit representation, not a changed quantity. |
| chart-05, held out | Vertical label `Distance (km)` differs from truth label `Distance` | The complete printed heading includes `(km)`; the separate unit correctly contains `km`. All decimal values are exact. |

The strict score was not relaxed after observing these results. Every draft remains unreviewed in the application. Authors must still inspect geometry, evidence, text, axes, units and any additional relations before publishing. Billed cost and human review time were not measured.
