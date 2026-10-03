# Native accessibility dispatch probe

This separate normal-privilege test application declares the public AccessibilityExtensionAbility capabilities `retrieve`, `gesture` and `touchGuide`. It records only event types. It has no speech implementation and must never be described as a screen reader or counted as reader-enabled usability evidence.

Build in the configured Linux/WSL environment with `python3 scripts/build-hover-probe.py`. The signed test HAP is generated under `~/.cache/touchmap-probes/hover-probe`. Install it with `oniro-app app install` for that project directory. Enable it using the emulator's accessibility settings, test dispatch, then disable it. A `TOUCHMAP_PROBE_CONNECTED` event proves only that the test service connected; a `TOUCHMAP_ACCESSIBILITY_HOVER` event emitted by the product proves the callback ran.

The manifest approach is based on the Apache-2.0 [official OpenHarmony AccessibilityExtAbility sample](https://github.com/eclipse-oniro-mirrors/applications_app_samples/tree/OpenHarmony-3.2-Release/code/SystemFeature/ApplicationModels/AccessibilityExtAbility). The test implementation is newly written for TouchMap.
