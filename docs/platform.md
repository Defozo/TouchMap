# Native build and runtime

TouchMap is an ArkTS/ArkUI Stage application. The `openharmonyApi20` product declares OpenHarmony, compile API 20 and minimum API 20. Its application identity is `org.touchmap.app`, module `entry`, ability `EntryAbility`. The app requests only `INTERNET` and `VIBRATE`.

## Reproducible Linux or Windows/WSL setup

The tested build route uses the Eclipse Oniro App Builder CLI, so DevEco Studio is optional. Windows users need WSL2 Ubuntu with working nested virtualization. Linux users can call the `.sh` files directly. Install Node.js 20, a Java 17 runtime with `keytool`, Python 3, `unzip`, and QEMU x86_64. On Ubuntu:

```sh
sudo apt-get update
sudo apt-get install qemu-system-x86 openjdk-17-jre-headless unzip python3
sudo usermod -aG kvm "$USER"
```

Start a new Linux login session after the group change. Verify read/write access to `/dev/kvm`. No host reboot or firmware change is performed by the project scripts. Node.js must already be on PATH.

From the project directory in PowerShell:

```powershell
./scripts/setup-platform.ps1
./scripts/build.ps1 -Product openharmonyApi20
./scripts/start-emulator.ps1
./scripts/doctor.ps1
./scripts/install.ps1 -Target 127.0.0.1:55555
```

All wrappers accept `-Distribution` for another WSL distribution. Setup pins `@oniroproject/oniro-app` to `0.11.0`, SDK to OpenHarmony `6.0` (API 20), and emulator to Oniro `v6.1` (API 23). The exact installed component versions and runtime test results are recorded in `toolchain.lock.json` and `docs/evidence/`. Newer runtime success alone does not verify API 20 runtime compatibility.

By default the CLI is installed at `~/touchmap-toolchain`, SDK at `~/setup-ohos-sdk`, command tools at `~/command-line-tools`, and emulator at `~/oniro-emulator`. Environment variables `TOUCHMAP_TOOLS_DIR`, `ONIRO_SDK_ROOT_DIR`, `ONIRO_CMD_TOOLS_PATH`, and `ONIRO_EMULATOR_DIR` override these paths. No coordinator directory or private provider account is required for the native build.

The actual public commands run by the wrapper are:

```sh
oniro-app sign <private-build-directory> --bootstrap
oniro-app build <private-build-directory> --product openharmonyApi20 --mode debug --json
oniro-app app install app --hap dist/touchmap-signed.hap --device 127.0.0.1:55555
oniro-app app launch app --ability EntryAbility --device 127.0.0.1:55555
```

Oniro invokes OHPM and hvigor under the matching command-line tools. `scripts/build.ps1` stages the source in a private Linux build directory, resolves the pinned OHPM dependencies, generates normal-application development signing material there, builds a signed HAP, checks metadata from the resulting archive, and emits SHA-256. It copies only the HAP, dependency lock and non-secret evidence back to the project. The private staging path is recorded in ignored `.native-build-path` for troubleshooting. Signing configuration, keystore and provisioning files are never written into tracked application configuration.

## Signing and portability

OpenHarmony development signing uses the SDK development certificate offline. It is suitable for the emulator and compatible development targets and is not a commercial distribution certificate or an identity certification. A second developer generates their own local configuration by running the same build script. Normal application privileges are used; no system permission or operating-system modification is needed by TouchMap.

HarmonyOS has separate SDK, device registration and signing requirements. This project does not claim that an OpenHarmony HAP can install unchanged on a HarmonyOS commercial device. Such a target needs a separate product and successful installation evidence.

## Evidence requirements

A HAP archive and successful compiler exit are build evidence. Installation, process launch, UI screenshot, reader-enabled interaction, local audio, forced restarts, WAN-blocked flow, and physical vibration each need separate runtime evidence. The emulator is not a physical vibration test. See the current evidence files and final test report for the checks actually completed.

After building and installing the production HAP, run the native Hypium suite on a selected development target:

```powershell
./scripts/test-native.ps1 -Target 127.0.0.1:55556
```

The test script uses the same private build directory and development certificate. Hvigor 5.18.5 exposes `ohosTest` under the `default` product, whose OpenHarmony API 20 settings match `openharmonyApi20`. The signed test HAP is separate from the production HAP. The script enables the official arkXtest development setting `persist.ace.testmode.enabled=1` on the selected target and starts its UiTest daemon immediately before the tests. This is test-device setup; TouchMap does not need this setting to run. The script reads the Hypium result counts because the device test launcher can return exit code zero even when tests fail. Inspect `docs/evidence/native-test-results.txt` and `native-test-build.log`.

With that native test HAP installed, measure 100 local recording starts:

```powershell
./scripts/test-audio.ps1 -Target 127.0.0.1:55556 -Count 100
```

This measures the first actual AudioRenderer write accepting PCM samples, including integrity checks and renderer preparation. The report separately records the configured exploration dwell. It does not measure acoustic speaker latency or physical finger input. The command fails if a playback fails or measured onset p95 misses the 150 ms target. `scripts/test-recovery.py --device 127.0.0.1:55556` runs inside WSL and checks 100 forced process restarts after fsynced save, unfinished-answer, submission and package-import acknowledgements. These checks are post-commit recovery evidence; they do not inject faults into a transaction in progress.

To verify a committed revision from a fresh local clone, with separate dependency installation and signing, run:

```powershell
./scripts/verify-clean-checkout.ps1 -Revision HEAD
```

This requires `uv` for Python 3.12 dependency resolution in addition to the native toolchain. It runs the host tests, type checker, Python tests and signed native build in the new clone, preserving logs and the source commit in `docs/evidence/clean-checkout.json`. Uncommitted changes are deliberately excluded. Independent development signing can change the HAP bytes; the report records its own artifact hash.

The tested Oniro image fails to display the standard modal `DocumentViewPicker` UIExtension. `SystemPicker.ets` uses the system FilePicker's full-page `OPEN_FILE` and `CREATE_FILE` abilities through the normal `startAbilityForResult` API. The system grants temporary access to the user-selected file. TouchMap copies imports immediately and flushes exports before reporting success. It requests no broad filesystem or system privilege. The result contract is implemented by the official [FilePicker application](https://github.com/openharmony/applications_filepicker).

## Audio configuration of the pinned emulator

The Oniro v6.1 image has two audio configuration defects: its HDI adapter declares `Generic_1` at card 2, but QEMU exposes `AudioPCI` at card 0; `/dev/snd/controlC0` belongs to `midi_server`, which the `audio_host` service cannot access. The unmodified image therefore reports no audio adapters even though the kernel and host PulseAudio detect the sound device. On this development emulator, run inside WSL:

```sh
python3 scripts/configure-emulator-audio.py --device 127.0.0.1:55555 apply
```

The helper checks the exact expected ES1370 hardware and mapping, corrects the vendor JSON, restores the vendor mount to read-only, assigns the control node to the existing audio group and restarts only the native audio services. TouchMap stays running and retains ordinary application permissions. The JSON correction persists in that emulator image; the node group resets on reboot, so reapply after boot. To restore the original image mapping and group:

```sh
python3 scripts/configure-emulator-audio.py --device 127.0.0.1:55555 restore
```

The original JSON and per-target applied configuration are saved in `docs/evidence/emulator-audio-*.json`. This is a repair to the development image, separate from TouchMap installation. Do not apply it to other hardware.

## Primary references

- [Oniro environment setup](https://docs.oniroproject.org/application-development/environment-setup-guide/oniro/setup/)
- [Official App Builder command and signing reference](https://github.com/eclipse-oniro4openharmony/oniro-app-builder/tree/main/packages/cli)
- [Oniro emulator and QEMU requirements](https://docs.oniroproject.org/device-development/developer-boards/emulator/)
- [Pinned emulator v6.1](https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/tag/v6.1)

The app configuration and initial icon resources originate from the Apache-2.0 Oniro `EmptyAbility` template. Product logic and screens were implemented for TouchMap; retain the template attribution in `THIRD_PARTY.md`.
