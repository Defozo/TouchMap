"""Record actual native frames with only the selected emulator's emitted audio.

The two captures run independently and use their recorded UTC starts for alignment.
This does not capture a microphone, synthesize speech, or claim acoustic latency.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--port', type=int, default=5900)
    parser.add_argument('--seconds', type=int, default=180)
    parser.add_argument('--fps', type=int, default=8)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 300:
        parser.error('Use a capture duration between1 and300 seconds.')
    target = args.output.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    frames = target.with_name(target.stem+'-frames.mp4')
    sound = target.with_name(target.stem+'-audio.wav')
    audio_log = target.with_name(target.stem+'-audio.log')
    with audio_log.open('w', encoding='utf-8') as log:
        recorder = subprocess.Popen([sys.executable, str(ROOT/'scripts/record-emulator-audio.py'),
                                     '--device', args.device, '--seconds', str(args.seconds), '--output', str(sound)],
                                    stdout=log, stderr=subprocess.STDOUT)
        try:
            subprocess.run([sys.executable, str(ROOT/'scripts/record-emulator.py'), '--port', str(args.port),
                            '--seconds', str(args.seconds), '--fps', str(args.fps), '--output', str(frames)], check=True)
        finally:
            # Let the audio recorder finish and close its WAV header cleanly.
            recorder.wait(timeout=args.seconds+30)
    if recorder.returncode:
        raise RuntimeError('Emulator audio capture failed; inspect '+str(audio_log))
    video_info = json.loads(frames.with_suffix('.capture.json').read_text())
    audio_info = json.loads(sound.with_suffix('.json').read_text())
    offset = (datetime.fromisoformat(audio_info['startedUtc'])-datetime.fromisoformat(video_info['startedUtc'])).total_seconds()
    filters = f'atrim=start={max(0,-offset)},asetpts=PTS-STARTPTS'
    if offset > 0:
        filters += f',adelay={round(offset*1000)}:all=1'
    filters += ',apad'
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', str(frames), '-i', str(sound),
                    '-map', '0:v', '-map', '1:a', '-af', filters, '-t', str(video_info['videoSeconds']),
                    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', str(target)], check=True)
    report = {'videoCapture': video_info, 'audioCapture': audio_info, 'audioStartMinusVideoStartSeconds': offset,
              'outputSha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'policy': 'Actual framebuffer and isolated QEMU audio aligned by capture start UTC. Capture alignment is approximate, not an acoustic latency measurement.'}
    target.with_suffix('.sync.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({'output': str(target), 'seconds': video_info['videoSeconds'], 'audioPeak': audio_info['peakPcm16']}))


if __name__ == '__main__':
    main()
