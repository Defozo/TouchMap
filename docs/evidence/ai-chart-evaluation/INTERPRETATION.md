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

## Decision after the held-out diagnostic failure

The plan's target is at least 80% usable drafts on clear, in-scope held-out images. This evaluation does **not establish that target**. The retained strict held-out score is 0/2; the clear-decimal held-out chart also fails that strict scorer. The representation audit does not convert these failures into passes or supply a missing usability measurement. This result triggered the following prompt/model evaluation.

The current production instruction explicitly asks the model to preserve printed labels and units exactly, retain unknown numerical values and distinguish connecting lines from causal arrows. The two complete printed headings and the undirected visible line are consistent with those instructions. The retained outputs contain no observed unsupported numerical assertion in these five cases. These particular mismatches therefore do not establish a production prompt defect or evidence that a different model would reduce author work. The decision is to retain the present production prompt/model while revising the evaluation protocol. This is an evidence-limited decision, not approval of general chart accuracy or a successful usefulness diagnostic. No provider call, prompt change or held-out retry was made for this decision.

The next evaluation must be preregistered before exposing new held-out inputs:

1. Keep the existing truth, scorer, first outputs and 2/5 and 0/2 scores immutable. Record future scores under a new protocol version.
2. Score source-supported facts separately from representational identity. Preserve the raw printed axis heading and its separate unit field in the reference; label harmless duplication distinctly. Annotate visible connecting lines separately from causal or directed relations. Do not assign these changes retroactively to the first score.
3. Define usable-draft acceptance with content authors before testing: critical omissions, unsupported assertions, correctly retained unknowns, geometry/evidence corrections, edit count and time through reviewed publication. Measure those fields rather than treating a schema or label match as author usefulness. Report rejections and incomplete drafts in the denominator.
4. Reserve a newly authored, unseen holdout with a declared clear in-scope stratum and a separate challenging stratum. The present chart-04 and chart-05 have now been inspected and cannot serve as unseen confirmation of revised criteria or a tuned prompt.
5. Compare any revised prompt/model with the frozen current adapter on development inputs first. Promote a change only with supported semantic/correction-effort improvement, then run the untouched new holdout once. If the measured clear-draft result remains below 80%, retain that failure and continue prompt/model investigation instead of claiming the diagnostic passed.

This protocol revision and the remaining evaluation are recorded work and an explicit gap respectively. They do not replace the planned teacher comparison or learner study.
