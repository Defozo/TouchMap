# Formative evaluation protocol

No participant results are implied by this protocol. Participant recruitment and representative usefulness evidence remain unfulfilled until consenting learners and authors complete the sessions.

Recruit 6-10 consenting blind or low-vision learners, with optional smaller formative sessions explicitly reported as such, and 2-4 teachers/content authors. Explain what is collected, allow withdrawal and breaks, and use participant codes without names. Do not collect a diagnosis or unrelated personal information. Physical help must be recorded as assistance, not silently supplied.

Compare three conditions with equivalent facts and comparable unfamiliar diagrams: complete linear spoken description with pause/replay and section navigation; accessible structured object/relationship list; and TouchMap exploration. All conditions have the same labels, directions, chart units, questions and hints. Counterbalance the six possible condition orders across participants. Use different but structurally comparable diagrams to avoid memorising answers. Train each condition to a comparable criterion and include setup/training time in reporting.

Ask for both direct relationships and at least one inference across two connections. Record submitted answers, elapsed time, hints, human assistance, navigation errors, interruptions, setup effort, perceived workload (0-10), preference and open observations. Record whether a path is known or semantic-only. For unknown chart values, success means retaining unknown rather than guessing zero.

For authors, compare manual authoring with AI draft plus source review on equivalent diagrams. Measure time until valid publication and offline readiness, source-review effort, residual errors, correction count, package transfer/setup and willingness to reuse. Model latency alone is not preparation time. Count failed and rejected sources.

Report each participant and condition, the actual sample size and all meaningful tradeoffs. If the accessible list performs equally or better, report it. Do not extrapolate a sighted developer's test with eyes closed to the intended population. Automated corpus quality and developer flow tests establish engineering observations only.

Suggested CSV fields: `participant_code,role,condition,order,diagram_id,training_seconds,task_seconds,correct,total_questions,hints,human_assists,navigation_errors,workload_0_10,preference,observation,consent_record_id`. The CSV belongs outside shared teaching packages and must not be committed with identifiable data.
