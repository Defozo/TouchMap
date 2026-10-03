"""Record only the selected QEMU emulator's PulseAudio output, never a microphone."""
import argparse
import array
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import signal
import subprocess
import time
import wave

def read_pulse(kind):
    try:
        return json.loads(subprocess.check_output(
            ['pactl', '-f', 'json', 'list', kind], timeout=10))
    except subprocess.TimeoutExpired:
        raise SystemExit('PulseAudio did not respond within 10 seconds. Check the selected PULSE_SERVER and emulator output before recording.')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--seconds', type=int, default=20)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300:
        raise SystemExit('Choose 1..300 seconds.')
    rows = subprocess.check_output(['ps', '-eo', 'pid=,args='], text=True).splitlines()
    pids = [row.strip().split(None, 1)[0] for row in rows
            if row.strip().split(None, 1)[1].startswith('qemu-system-')
            and f'hostfwd=tcp:{args.device}-:' in row]
    streams = read_pulse('sink-inputs')
    matches = [stream for stream in streams if stream.get('properties', {}).get('application.process.id') in pids]
    if len(matches) != 1:
        raise SystemExit('Expected exactly one PulseAudio output stream for the selected emulator.')
    selected = matches[0]
    sinks = read_pulse('sinks')
    sink = next(item for item in sinks if item['index'] == selected['sink'])
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    print(f'Recording emulator {args.device} output only for {args.seconds}s: {output}', flush=True)
    monitor = sink.get('monitor_source_name', sink['monitor_source'])
    started_utc = datetime.now(timezone.utc).isoformat()
    started_monotonic = time.monotonic()
    process = subprocess.Popen(['parec', f'--device={monitor}',
                                f'--monitor-stream={selected["index"]}', '--file-format=wav',
                                '--rate=44100', '--channels=2', '--format=s16le', str(output)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        _, stderr = process.communicate(timeout=args.seconds)
    except subprocess.TimeoutExpired:
        process.send_signal(signal.SIGINT)
        _, stderr = process.communicate(timeout=10)
    wall_seconds = time.monotonic() - started_monotonic
    if not output.exists():
        raise SystemExit(stderr.decode(errors='replace'))
    with wave.open(str(output), 'rb') as recording:
        samples = array.array('h', recording.readframes(recording.getnframes()))
        report = {'device': args.device, 'startedUtc': started_utc, 'wallSeconds': wall_seconds,
                  'seconds': recording.getnframes() / recording.getframerate(),
                  'channels': recording.getnchannels(), 'sampleRate': recording.getframerate(),
                  'peakPcm16': max((abs(value) for value in samples), default=0),
                  'rmsPcm16': math.sqrt(sum(value * value for value in samples) / max(1, len(samples))),
                  'scope': 'Host monitor of this emulator output stream only; not a microphone recording or physical acoustic latency measurement.'}
    output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main()
