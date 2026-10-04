# Deployment, maintenance and product value

## What an installation provides

TouchMap lets teachers distribute one reviewed lesson containing the original source, labelled objects, relationships, questions and local recordings. Learners choose touch, an object list or single-button scanning and resume an unfinished answer after reopening the app. The same package can be copied to another installation while learning history remains local.

The intended value is independent exploration of connections in educational diagrams and reuse of reviewed materials. The implemented workflow supports those activities; measured learning improvement and teacher time savings require participant evaluation. [Verification results](TEST_REPORT.md) describe the evidence available today.

## Deployment model

The native application and prepared lessons work offline without a learner account, hosted backend or provider key. Install the signed HAP using the [platform guide](platform.md). Test the selected hardware and its spoken reader before deployment to learners; the released runtime evidence is from an emulator.

Schools and content authors can prepare material with the local Python CLI or operate their own preparation service. Optional cloud image analysis and speech generation use the operator's provider accounts. The source is MIT-licensed; third-party software and sample-asset terms are listed separately. No subscription, payment processing, managed hosting service or service-level agreement is included in the application.

## Routine maintenance

1. Retain the source commit, dependency locks, toolchain lock and artifact checksums for each installation. Verify the HAP hash before updating, and keep a known working installer.
2. Back up reviewed `.touchmap` teaching packages outside the device. A teaching package excludes personal progress. Export learning history separately only when needed and handle it as learner data.
3. Review a changed material as a new revision. Edits invalidate dependent facts, questions and recordings; complete the review and offline-asset checks before distributing the revision.
4. Keep provider credentials on the preparation server, inject them through the configured secret manager and rotate them there. Remote service access requires TLS, a signing key and short-lived paired sessions.
5. Check `/health/live` and `/health/ready` when operating a backend. Verify connectivity from the actual client device. A loopback-only service cannot be reached directly from another device.
6. Review per-session analysis limits, the generation ceiling and the local spending reservations before enabling cloud features. Check the provider invoice separately; local reservations are not billing reconciliation.
7. Use the [backend retention and recovery guide](backend.md) when investigating interrupted jobs. Do not automatically retry an outcome marked unknown, because the provider may already have performed billable work.

The [privacy guide](PRIVACY.md) explains local revisions, deletion, exported copies and provider boundaries. The [release guide](RELEASE.md) describes source and artifact verification.
