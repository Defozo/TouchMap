# Isolated emulator audio on Windows/WSL

The normal emulator route sends audio through WSLg PulseAudio to the Windows sound output. During final verification, the shared WSLg server stalled: native 160 ms PCM writes took about 600 ms, some writes returned zero after 1.5 seconds, and even read-only `pactl` requests timed out. The same signed application completed its long recording and all five audio controls after moving the selected emulator to a separate clocked audio server.

This route captures the emulator's actual PCM output in a WAV file. Its null sink has no direct speaker output. Use the [Windows playback helper](platform.md#audio-configuration-of-the-pinned-emulator) for live output, or play the captured WAV through a normal Windows media player. Neither a null-sink test nor the recording establishes physical speaker latency.

## Start a separate server

Run this shell block in the WSL system distribution (`wsl --system`). It creates a private Unix socket and does not restart the shared WSLg server:

```sh
mkdir -p /mnt/wslg/runtime-dir/touchmap-pitch-audio
chmod 700 /mnt/wslg/runtime-dir/touchmap-pitch-audio
cat > /mnt/wslg/runtime-dir/touchmap-pitch-audio/server.pa <<'EOF'
load-module module-null-sink sink_name=touchmap_pcm rate=44100 channels=2
set-default-sink touchmap_pcm
load-module module-native-protocol-unix socket=/mnt/wslg/runtime-dir/touchmap-pitch-audio/native auth-anonymous=1
EOF
export PULSE_RUNTIME_PATH=/mnt/wslg/runtime-dir/touchmap-pitch-audio
export PULSE_STATE_PATH=/mnt/wslg/runtime-dir/touchmap-pitch-audio/state
pulseaudio --check || pulseaudio -n --daemonize=yes --use-pid-file=yes \
  --exit-idle-time=-1 --disable-shm=yes --high-priority=no \
  --log-target=file:/mnt/wslg/runtime-dir/touchmap-pitch-audio/server.log \
  --file=/mnt/wslg/runtime-dir/touchmap-pitch-audio/server.pa
```

The socket is inside a directory accessible only to its owner. No TCP audio listener or microphone source is created. From Ubuntu, verify the selected server:

```sh
PULSE_SERVER=unix:/mnt/wslg/runtime-dir/touchmap-pitch-audio/native pactl info
```

The default sink must be `touchmap_pcm`. This is separate from `RDPSink` on `unix:/mnt/wslg/PulseServer`.

## Start the selected emulator

Use the existing image directory. If that emulator is already running, first stop TouchMap, run guest `sync`, and terminate only the QEMU process whose command line identifies the selected HDC port and image directory. Wait for that process to exit before launching another process on the same disk. Keep `userdata.img`; do not reprovision or uninstall the app.

For the primary target, run in Ubuntu:

```sh
PULSE_SERVER=unix:/mnt/wslg/runtime-dir/touchmap-pitch-audio/native \
  bash "$HOME/oniro-emulator/images/run.sh" --headless \
  --connect 127.0.0.1:55555 --vnc-display 0 --serial-port 4444
```

For an already provisioned second target, use its separate `oniro-emulator-clean/images/run.sh` and ports `55556`, VNC display `1`, serial `4445`. Never point both running emulators at the same image directory. After either guest reboot, rerun the documented `configure-emulator-audio.py --device HOST:PORT apply` command from the project to restore the development image's audio control-node group.

In another Ubuntu terminal, verify that only the intended QEMU client is connected:

```sh
PULSE_SERVER=unix:/mnt/wslg/runtime-dir/touchmap-pitch-audio/native \
  pactl -f json list sink-inputs
```

## Record and verify

From the project directory in Ubuntu, start a capture and then play a lesson or run the audio controls in another terminal:

```sh
PULSE_SERVER=unix:/mnt/wslg/runtime-dir/touchmap-pitch-audio/native \
  python3 scripts/record-emulator-audio.py --device 127.0.0.1:55555 \
  --seconds 20 --output .local/emulator-lesson.wav
```

The helper selects the QEMU output stream belonging to that HDC target. It captures that stream only. The adjacent JSON records PCM duration, elapsed wall time and signal levels. For a healthy clocked sink, recorded duration should closely follow elapsed wall time. The native control suite also checks natural completion, pause/resume and replacement of an active pending write using the original test deadlines.

Final investigation evidence is in [the audio environment report](evidence/pitch-demo/audio-environment-investigation.json). The [captured-source comparison](evidence/pitch-demo/captured-source-comparison.json) matches the complete 3.29725-second source recording with the emulator output, without time stretching. Application source fingerprints and HAP identities are recorded separately for diagnostic builds and the final release.

## Restore ordinary host audio

Stop only the selected emulator after stopping TouchMap and syncing the guest. Restart the same image with `PULSE_SERVER=unix:/mnt/wslg/PulseServer`, using the same HDC, VNC and serial arguments. Reapply the development guest audio configuration after reboot. Existing app data remains on the same `userdata.img`.

When no emulator uses the private server, stop that server from `wsl --system` with its private runtime and state paths:

```sh
PULSE_RUNTIME_PATH=/mnt/wslg/runtime-dir/touchmap-pitch-audio \
PULSE_STATE_PATH=/mnt/wslg/runtime-dir/touchmap-pitch-audio/state \
  pulseaudio --kill
```

Do not restart or kill the shared WSLg server as part of this procedure. A still-stalled shared server can reproduce the original slow output when an emulator is returned to it.
