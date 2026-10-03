"""Transcribe only the demo's retained audio using an already cached local model.

Requires faster-whisper and a cached small model. Nothing is uploaded or downloaded.
Machine recognition supports, but does not replace, perceptual listening review.
"""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import subprocess

from faster_whisper import WhisperModel

ROOT = Path(__file__).resolve().parents[1]
video = ROOT / 'dist/touchmap-demo.mp4'
manifest = json.loads((ROOT / 'docs/evidence/demo-manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256(video.read_bytes()).hexdigest() == manifest['videoSha256']
retained = []
offset = 0
for index, scene in enumerate(manifest['scenes']):
    if scene.get('audio'):
        retained.append((index, offset, scene))
    offset += scene['duration']
assert len(retained) == 1, 'Review the audio scope when the storyboard changes.'
index, offset, scene = retained[0]
audio = ROOT / 'dist/_video_work/audio/final-touch.wav'
audio.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-threads', '1', '-ss', str(offset),
                '-i', str(video), '-t', str(scene['duration']), '-vn', '-ac', '1',
                '-ar', '16000', '-c:a', 'pcm_s16le', str(audio)], check=True)
model = WhisperModel('small', device='cpu', compute_type='int8', cpu_threads=2,
                     local_files_only=True)
segments, info = model.transcribe(str(audio), language='en', beam_size=5, vad_filter=True)
transcript = [{'start': segment.start, 'end': segment.end, 'text': segment.text,
               'averageLogProbability': segment.avg_logprob} for segment in segments]
text = ' '.join(segment['text'] for segment in transcript).casefold()
expected = ['Evaporation', 'Precipitation']
matched = {label: label.casefold() in text for label in expected}
report = {
    'recordedAtUtc': datetime.now(timezone.utc).isoformat(),
    'videoSha256': manifest['videoSha256'],
    'sceneIndex': index, 'outputStartSeconds': offset,
    'durationSeconds': scene['duration'],
    'audioSha256': hashlib.sha256(audio.read_bytes()).hexdigest(),
    'method': 'Local faster-whisper small, CPU int8, two threads, cached model only, English, beam5 and VAD. No vocabulary prompt.',
    'segments': transcript, 'expectedLabels': expected, 'matchedLabels': matched,
    'expectedLabelsRecognized': all(matched.values()),
    'limits': 'Machine transcription is supporting evidence. It is not human listening, physical acoustic timing, intelligibility certification or a user study.'
}
target = ROOT / 'docs/evidence/demo-audio-transcript.json'
target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2, ensure_ascii=False))
if not all(matched.values()):
    raise SystemExit('Expected labels were not both recognized; review the actual audio before drawing a conclusion.')
