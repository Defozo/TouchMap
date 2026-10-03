# Try TouchMap

Hear each stage of the water cycle, follow where it leads, and pick up your lesson after a restart. The native demo includes four teaching materials and runs offline without a TouchMap account.

- [Watch the three-minute demonstration](https://github.com/Defozo/TouchMap/releases/download/v1.0.1/touchmap-demo.mp4)
- [Open the presentation](https://github.com/Defozo/TouchMap/releases/download/v1.0.1/touchmap-presentation.pdf)
- [Download the signed application](https://github.com/Defozo/TouchMap/releases/download/v1.0.1/touchmap-signed.hap)
- [Get the source, editable slides and complete release](https://github.com/Defozo/TouchMap/releases/tag/v1.0.1)

All downloads are public. The interactive demo runs on the OpenHarmony emulator; the video shows the native app in action.

## Your first three minutes

Start in **Library**. On a fresh installation, complete the short three-shape tutorial. Open **The water cycle**, marked **READY OFFLINE**, read its author declaration, and choose **Accept this author declaration**.

1. **Find a stage.** Choose **List**, then **2. Evaporation**. Replay its label and describe the object. You can also explore the same diagram through **Touch** or **Scan**.
2. **Follow the relationship.** Open **Connections**. Find the outgoing connection **Vapour cools into droplets** and press its **Follow to destination** button. You arrive at **Condensation** with its explanation.
3. **Test your understanding.** Open a lesson question, choose an answer and press **Submit selected answer**. Your result appears immediately. Choosing an option alone does not submit it.
4. **Continue after an interruption.** Select an option in the next question without submitting. Close and reopen TouchMap, then reopen the same material and use **Resume**. Your completed answer and unfinished selection are retained.

Next, try **Lumina** to explore an unfamiliar process, or the rainfall chart to compare values. Export a teaching package from Library and import it on another installation to share the lesson. Your private learning history stays on your device.

## Run the native demo

Follow the prerequisites in [platform setup](platform.md). With the documented Windows/WSL2 environment ready, download and install the signed release:

```powershell
git clone --branch v1.0.1 --depth 1 https://github.com/Defozo/TouchMap.git
cd TouchMap
./scripts/setup-platform.ps1
New-Item -ItemType Directory -Force dist
Invoke-WebRequest -Uri https://github.com/Defozo/TouchMap/releases/download/v1.0.1/touchmap-signed.hap -OutFile dist/touchmap-signed.hap
$releaseMetadata = Get-Content docs/evidence/hap-metadata.json -Raw | ConvertFrom-Json
if ((Get-FileHash dist/touchmap-signed.hap -Algorithm SHA256).Hash -ne $releaseMetadata.sha256) { throw 'Downloaded HAP does not match this release.' }
./scripts/start-emulator.ps1
./scripts/configure-emulator-audio.ps1 -Target 127.0.0.1:55555 -Action apply
./scripts/doctor.ps1
./scripts/install.ps1 -Target 127.0.0.1:55555
```

Connect a local VNC viewer to `127.0.0.1:5900` to control the emulator. Lesson audio plays through the host sound service; [audio setup and Windows playback](platform.md#audio-configuration-of-the-pinned-emulator) also cover the isolated emulator route used for final verification. The install command launches TouchMap with the bundled materials ready to explore.

Prepared lessons need no preparation server or provider credentials. To create your own material, follow [the authoring guide](../README.md#prepare-and-review-a-material). For runtime details and measured results, see [the test report](TEST_REPORT.md).

DEFOZO SOFTWARE HOUSE · Michał Kiełtyka
