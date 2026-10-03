"""Relay one QEMU output monitor to Windows speakers; never open an input device."""
import argparse
import array
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import uuid

RATE = 44100
CHANNELS = 2
FRAME_BYTES = CHANNELS * 2
BLOCK_FRAMES = 882  # 20 ms; at most 200 ms queued before old audio is discarded.
BLOCK_BYTES = BLOCK_FRAMES * FRAME_BYTES
CONTROL_TIMEOUT = 5


def run_wsl(distribution, *command):
    return subprocess.run(
        ['wsl.exe', '--distribution', distribution, '--exec', *command],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=CONTROL_TIMEOUT, creationflags=subprocess.CREATE_NO_WINDOW).stdout


def select_stream(args):
    processes = run_wsl(args.distribution, 'ps', '-eo', 'pid=,args=').decode().splitlines()
    pids = []
    for row in processes:
        fields = row.strip().split(None, 1)
        if len(fields) != 2:
            continue
        # ps renders argv as text, not shell quoting. Ignore unrelated commands first.
        executable = fields[1].split(None, 1)[0]
        if (Path(executable).name.startswith('qemu-system-')
                and f'hostfwd=tcp:{args.device}-:' in fields[1]):
            pids.append(fields[0])
    if len(pids) != 1:
        raise RuntimeError('Expected exactly one QEMU process for this HDC address.')

    def pulse(kind):
        return json.loads(run_wsl(args.distribution, 'pactl',
                                 f'--server={args.pulse_server}', '-f', 'json', 'list', kind))

    matches = [item for item in pulse('sink-inputs')
               if str(item.get('properties', {}).get('application.process.id')) == pids[0]]
    if len(matches) != 1:
        raise RuntimeError('Expected exactly one output stream for this QEMU on the selected server.')
    selected = matches[0]
    sinks = [item for item in pulse('sinks') if item['index'] == selected['sink']]
    if len(sinks) != 1:
        raise RuntimeError('The selected QEMU output has no unique sink.')
    sink = sinks[0]
    monitor = sink.get('monitor_source_name', sink.get('monitor_source'))
    if monitor is None:
        raise RuntimeError('The selected sink has no output monitor.')
    return {'qemuPid': int(pids[0]), 'sinkInput': selected['index'],
            'sink': sink['name'], 'monitor': str(monitor)}


def pcm_peak(data):
    samples = array.array('h', data)
    if sys.byteorder != 'little':
        samples.byteswap()
    return max((abs(value) for value in samples), default=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', help='HDC address, for example 127.0.0.1:55555')
    parser.add_argument('--pulse-server', help='Explicit unix:/... PulseAudio socket')
    parser.add_argument('--distribution', default='Ubuntu')
    parser.add_argument('--output-device', help='Windows output index or unique device name')
    parser.add_argument('--list-output-devices', action='store_true')
    parser.add_argument('--seconds', type=int, default=60)
    parser.add_argument('--report', type=Path, help='Optional JSON result; no PCM file is saved')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Run this helper with Windows Python, not inside WSL.')
    try:
        import sounddevice as sd
    except ImportError:
        parser.error('This Windows Python needs the existing sounddevice package.')
    if args.list_output_devices:
        apis = sd.query_hostapis()
        print(json.dumps([{'index': i, 'name': item['name'],
                           'hostApi': apis[item['hostapi']]['name'],
                           'default': i == sd.default.device[1]}
                          for i, item in enumerate(sd.query_devices())
                          if item['max_output_channels'] >= CHANNELS], indent=2))
        return 0
    if not args.device or not re.fullmatch(r'127\.0\.0\.1:[0-9]{1,5}', args.device):
        parser.error('--device must be an explicit loopback HDC address 127.0.0.1:PORT.')
    if not 1 <= int(args.device.rsplit(':', 1)[1]) <= 65535:
        parser.error('HDC port must be 1..65535.')
    if not args.pulse_server or not args.pulse_server.startswith('unix:/'):
        parser.error('--pulse-server must name an explicit Unix socket.')
    if not 1 <= args.seconds <= 3600:
        parser.error('--seconds must be 1..3600.')
    output_device = args.output_device
    if output_device is not None and output_device.isdecimal():
        output_device = int(output_device)

    report = {'status': 'failed', 'device': args.device, 'pulseServer': args.pulse_server,
              'distribution': args.distribution, 'requestedSeconds': args.seconds,
              'startedUtc': datetime.now(timezone.utc).isoformat(),
              'sampleRate': RATE, 'channels': CHANNELS, 'format': 's16le',
              'sourcePcmBytesRead': 0, 'windowsCallbackPcmBytes': 0,
              'windowsCallbackPcmPeak': 0, 'windowsCallbackSilencePaddingBytes': 0,
              'queueDroppedPcmBytes': 0, 'outputUnderflows': 0,
              'scope': 'Selected QEMU sink-input output monitor only. PCM copied into Windows '
                       'PortAudio output callbacks; no microphone, audio file, human listening '
                       'confirmation or physical speaker latency measurement.'}
    pending = queue.Queue(maxsize=10)
    reader_done = threading.Event()
    capture_pid_ready = threading.Event()
    capture_pid = []
    last_read = [time.monotonic()]
    reader_errors = []
    stderr_tail = bytearray()
    capture = None
    output = None
    token = 'touchmap-play-' + uuid.uuid4().hex
    callback_remainder = bytearray()
    started = None

    def read_pcm():
        try:
            while True:
                data = capture.stdout.read(BLOCK_BYTES)
                if not data:
                    break
                if len(data) % FRAME_BYTES:
                    raise RuntimeError('The monitor ended with an incomplete PCM frame.')
                last_read[0] = time.monotonic()
                report['sourcePcmBytesRead'] += len(data)
                try:
                    pending.put_nowait(data)
                except queue.Full:
                    try:
                        report['queueDroppedPcmBytes'] += len(pending.get_nowait())
                    except queue.Empty:
                        pass
                    pending.put_nowait(data)
        except Exception as error:
            reader_errors.append(str(error))
        finally:
            reader_done.set()

    def read_stderr():
        for line in iter(capture.stderr.readline, b''):
            if line.startswith(b'TOUCHMAP_CAPTURE_PID='):
                try:
                    capture_pid.append(int(line.partition(b'=')[2]))
                    capture_pid_ready.set()
                except ValueError:
                    pass
            else:
                stderr_tail.extend(line)
                del stderr_tail[:-4096]

    def output_callback(outdata, frames, timing, status):
        if status.output_underflow:
            report['outputUnderflows'] += 1
        required = frames * FRAME_BYTES
        while len(callback_remainder) < required:
            try:
                callback_remainder.extend(pending.get_nowait())
            except queue.Empty:
                break
        payload = bytes(callback_remainder[:required])
        del callback_remainder[:required]
        outdata[:] = payload + bytes(required - len(payload))
        report['windowsCallbackPcmBytes'] += len(payload)
        report['windowsCallbackSilencePaddingBytes'] += required - len(payload)
        report['windowsCallbackPcmPeak'] = max(report['windowsCallbackPcmPeak'], pcm_peak(payload))

    try:
        report['selection'] = select_stream(args)
        device_info = sd.query_devices(output_device, 'output')
        sd.check_output_settings(device=output_device, channels=CHANNELS, dtype='int16', samplerate=RATE)
        report['windowsOutput'] = {'name': device_info['name'], 'index': device_info['index'],
                                   'hostApi': sd.query_hostapis(device_info['hostapi'])['name']}
        selected = report['selection']
        command = ['wsl.exe', '--distribution', args.distribution, '--exec', 'sh', '-c',
                   'printf "TOUCHMAP_CAPTURE_PID=%s\\n" "$$" >&2; exec "$@"', 'touchmap-capture',
                   'timeout', '--signal=TERM', '--kill-after=2s', f'{args.seconds + 10}s',
                   'parec', f'--server={args.pulse_server}', f'--device={selected["monitor"]}',
                   f'--monitor-stream={selected["sinkInput"]}', f'--client-name={token}',
                   '--raw', '--rate=44100', '--channels=2', '--format=s16le',
                   '--latency-msec=40', '--process-time-msec=20']
        capture = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        threading.Thread(target=read_pcm, daemon=True).start()
        threading.Thread(target=read_stderr, daemon=True).start()
        if not capture_pid_ready.wait(CONTROL_TIMEOUT):
            raise RuntimeError('The bounded WSL capture did not announce its process within 5 seconds.')
        ready_deadline = time.monotonic() + CONTROL_TIMEOUT
        while pending.qsize() < 2:
            if reader_done.is_set() or time.monotonic() >= ready_deadline:
                raise RuntimeError('No continuous PCM arrived from the selected output monitor.')
            time.sleep(0.02)
        output = sd.RawOutputStream(samplerate=RATE, blocksize=BLOCK_FRAMES, device=output_device,
                                    channels=CHANNELS, dtype='int16', callback=output_callback)
        output.start()
        started = time.monotonic()
        print(f'Playing {args.device} output only through {device_info["name"]} '
              f'for {args.seconds}s. Ctrl+C stops this relay.', flush=True)
        while time.monotonic() - started < args.seconds:
            if reader_done.is_set() or capture.poll() is not None:
                raise RuntimeError('The selected monitor stream ended before the requested deadline.')
            if time.monotonic() - last_read[0] > CONTROL_TIMEOUT:
                raise RuntimeError('No monitor PCM arrived for 5 seconds.')
            if not output.active:
                raise RuntimeError('The Windows output stream stopped unexpectedly.')
            time.sleep(0.05)
        report['status'] = 'completed'
    except KeyboardInterrupt:
        report['status'] = 'interrupted'
    except Exception as error:
        report['error'] = str(error)
    finally:
        if started is not None:
            report['outputWallSeconds'] = time.monotonic() - started
        if output is not None:
            try:
                output.abort()
            except Exception as error:
                report['windowsAbortError'] = str(error)
            try:
                output.close()
            except Exception as error:
                report['windowsCloseError'] = str(error)
        if capture is not None:
            if capture_pid:
                # Verify our unique command argument before terminating only our timeout group.
                cleanup = ('import os,signal,sys; p=int(sys.argv[1]); '
                           'f="/proc/%d/cmdline"%p; '
                           'sys.exit(0) if not os.path.exists(f) else None; '
                           'a=open(f,"rb").read().split(bytes([0])); '
                           'assert os.path.basename(a[0])==b"timeout" and sys.argv[2].encode() in a; '
                           'os.kill(p,signal.SIGTERM)')
                try:
                    run_wsl(args.distribution, 'python3', '-c', cleanup,
                            str(capture_pid[0]), f'--client-name={token}')
                    report['captureStopRequested'] = True
                except (subprocess.SubprocessError, OSError) as error:
                    report['captureCleanupError'] = str(error)
            try:
                capture.wait(timeout=3)
            except subprocess.TimeoutExpired:
                capture.kill()
                capture.wait(timeout=3)
                report['captureWrapperKilled'] = True
            report['captureWrapperExitCode'] = capture.returncode
            reader_done.wait(1)
            report['captureReaderEnded'] = reader_done.is_set()
        if reader_errors:
            report['readerErrors'] = reader_errors
        if stderr_tail:
            report['captureStderr'] = stderr_tail.decode(errors='replace')
        report['windowsCallbackPcmSeconds'] = report['windowsCallbackPcmBytes'] / FRAME_BYTES / RATE
        report['nonzeroPcmSubmitted'] = report['windowsCallbackPcmPeak'] > 0
        report['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(report, indent=2))
    return 0 if report['status'] == 'completed' else 130 if report['status'] == 'interrupted' else 1


if __name__ == '__main__':
    raise SystemExit(main())
