# Try TouchMap without a project account

The [public release](https://github.com/Defozo/TouchMap/releases/tag/v1.0.0) provides the signed native application, English demonstration, presentation and complete source-and-evidence bundle. No GitHub login is required to download public release assets. Prepared lessons run offline without a TouchMap account, provider credential or preparation server.

- [Three-minute MP4 demonstration](https://github.com/Defozo/TouchMap/releases/download/v1.0.0/touchmap-demo.mp4)
- [Presentation PDF](https://github.com/Defozo/TouchMap/releases/download/v1.0.0/touchmap-presentation.pdf)
- [Editable presentation with speaker notes](https://github.com/Defozo/TouchMap/releases/download/v1.0.0/touchmap-presentation.pptx)
- [Signed native HAP](https://github.com/Defozo/TouchMap/releases/download/v1.0.0/touchmap-signed.hap)

The working interactive demonstration is the native application on the compatible OpenHarmony emulator. The MP4 records real emulator interaction. It is not an interactive browser version of the application.

## Install the release HAP

Use [platform setup](platform.md) for the pinned Oniro/OpenHarmony tooling, prerequisites and development-signing limits. A commercial HarmonyOS device has separate signing requirements and has not been verified here. On Windows with WSL2 Ubuntu and the stated prerequisites:

```powershell
git clone --branch v1.0.0 --depth 1 https://github.com/Defozo/TouchMap.git
cd TouchMap
./scripts/setup-platform.ps1
New-Item -ItemType Directory -Force dist
Invoke-WebRequest -Uri https://github.com/Defozo/TouchMap/releases/download/v1.0.0/touchmap-signed.hap -OutFile dist/touchmap-signed.hap
$releaseMetadata = Get-Content docs/evidence/hap-metadata.json -Raw | ConvertFrom-Json
if ((Get-FileHash dist/touchmap-signed.hap -Algorithm SHA256).Hash -ne $releaseMetadata.sha256) { throw 'Downloaded HAP does not match this release.' }
./scripts/start-emulator.ps1
./scripts/configure-emulator-audio.ps1 -Target 127.0.0.1:55555 -Action apply
./scripts/doctor.ps1
./scripts/install.ps1 -Target 127.0.0.1:55555
```

The released HAP SHA-256 is `1209c87125492cd145ea06a0480d84cc16b5e37c5f6f8fe34908f8e76609c4bd`. Its application-source fingerprint is recorded in [the HAP metadata](evidence/hap-metadata.json). The release-tag checkout supplies the matching application identity and metadata used by the install script; no local build or signing step is required. The script launches `org.touchmap.app` / `EntryAbility`. Building from source is a separate route documented in the README; an independent development signature can produce a different HAP hash from the same application sources.

The emulator wrapper runs headless. Open a VNC viewer on the same computer and connect to `127.0.0.1:5900` (VNC display `:0`) to see and control it. Under WSL2, this uses localhost forwarding. Audio is played by QEMU through the host sound service, such as WSLg PulseAudio; VNC supplies the display and input, not audio transport. Keep the emulator ports local to the development computer.

## Walk through a lesson

1. Open **The water cycle** in Library and read the material declaration. Accept it locally.
2. Complete the three-shape tutorial, then explore objects using touch, List or Scan. Use Connections to follow **Vapour cools into droplets** from Evaporation to Condensation.
3. Open a question, choose an option and explicitly press **Submit selected answer**.
4. Select an answer to the next question without submitting. Close and reopen the application, then reopen the material. Resume retains both the submitted result and unfinished selection.
5. Export the teaching package and import it into another installation. Local acceptance and private learning history do not travel with the teaching material.

The tutorial, unfamiliar Lumina process and rainfall chart are also bundled. The chart preserves its unknown June value. Optional AI authoring requires a separately configured preparation service and explicit consent. The complete [test report](TEST_REPORT.md) identifies measured builds and remaining reader, physical-hardware and representative-study gaps.
