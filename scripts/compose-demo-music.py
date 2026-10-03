"""Original instrumental score, composed and synthesized for TouchMap.

No samples, soundfonts, outside melodies or recorded music are used. Deterministic
PCM stems retain exact timing; narration and original application audio stay primary.
"""
from pathlib import Path
import hashlib, json
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'dist/_video_work'
OUT = WORK / 'audio/pitch-v2'
OUT.mkdir(parents=True, exist_ok=True)
RATE, DURATION, BPM = 44100, 180, 90
total = int(RATE * DURATION)
track = np.zeros((total, 2), dtype=np.float64)
rng = np.random.default_rng(2601003)
beat = 60/BPM

def note(midi, start, length, level, kind='pluck', pan=0):
    count = min(int(length*RATE), total-int(start*RATE))
    if count <= 0:
        return
    t = np.arange(count)/RATE
    f = 440 * 2**((midi-69)/12)
    if kind == 'pad':
        envelope = np.minimum(t/0.55, 1)*np.minimum((length-t)/1.0, 1)
        wave = (np.sin(2*np.pi*f*t) + .22*np.sin(2*np.pi*f*2.001*t) + .08*np.sin(2*np.pi*f*3*t))
    elif kind == 'bass':
        envelope = (1-np.exp(-t*38))*np.exp(-t*1.4)*np.minimum((length-t)/.12, 1)
        wave = np.sin(2*np.pi*f*t)+.16*np.sin(2*np.pi*f*2*t)
    else:
        envelope = (1-np.exp(-t*130))*np.exp(-t*3.2)*np.minimum((length-t)/.05, 1)
        wave = np.sin(2*np.pi*f*t)+.25*np.sin(2*np.pi*f*2*t)*np.exp(-t*4)+.12*np.sin(2*np.pi*f*3*t)*np.exp(-t*9)
    sound = wave * np.maximum(envelope, 0) * level
    idx = int(start*RATE)
    track[idx:idx+count,0] += sound*np.sqrt((1-pan)/2)
    track[idx:idx+count,1] += sound*np.sqrt((1+pan)/2)

# C add9, A minor7, F major7, G sus2. Sparse original five-note figures.
chords = [(48, [60,64,67,74]), (45,[57,60,64,67]), (41,[57,60,64,65]), (43,[55,57,62,67])]
bar = beat*4
for measure, start in enumerate(np.arange(0, 173, bar)):
    bass, chord = chords[(measure//2)%4]
    for j, pitch in enumerate(chord):
        note(pitch, start, bar+1.0, .14, 'pad', -.48+j*.32)
    note(bass, start, bar*.82, .30, 'bass')
    if measure%2:
        note(bass+12, start+beat*2.5, beat, .11, 'bass', -.1)
    pattern = [(0,0), (.75,2), (1.5,1), (2.5,3), (3.25,2)]
    for j, (b, degree) in enumerate(pattern):
        note(chord[degree]+12, start+b*beat, 1.6, .11 if j else .15, 'pluck', (-1)**j*.34)
    if start > 8:
        for b in (1,3):
            at = int((start+b*beat)*RATE)
            n = int(.075*RATE)
            noise = rng.standard_normal(n)
            # Light brushed pulse with rapid decay, deliberately below melody.
            noise = np.diff(np.r_[0,noise]) * np.exp(-np.arange(n)/(RATE*.013))*.018
            track[at:at+n] += noise[:,None]

# Resolve to a soft C major add9 chord before the four-second fade.
for j, pitch in enumerate([48,60,64,67,74]):
    note(pitch, 174, 6, .13, 'pad', -.35+j*.17)
for j, pitch in enumerate([72,76,79,86]):
    note(pitch, 174+j*.28, 3.5, .12, 'pluck', -.25+j*.17)

# Quiet bed, with no added sound at all during the native audio demonstration.
t = np.arange(total)/RATE
rms = np.sqrt(np.mean(track**2))
track *= (10**(-37/20))/rms
envelope = np.minimum(t/2,1) * np.clip((180-t)/4,0,1)
envelope *= np.where(t < 33, np.clip((33-t)/.7,0,1), np.where(t < 48, 0, np.clip((t-48)/.7,0,1)))
track *= envelope[:,None]
path = OUT/'music-original.wav'
sf.write(path, track, RATE, subtype='PCM_24')
report = {
    'title': 'TouchMap exploration bed', 'origin': 'Original deterministic composition and synthesis by agent for this project',
    'license': 'Project-created composition and recording, MIT; no third-party samples, soundfonts or copied melody.',
    'durationSeconds': DURATION, 'sampleRate': RATE, 'channels': 2, 'bpm': BPM,
    'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    'compositionScriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'nativeAudioProtectedRangeSeconds': [33,48], 'fadeOutRangeSeconds': [176,180],
    'finalRmsDbfs': float(20*np.log10(np.sqrt(np.mean(track**2)))),
    'peakDbfs': float(20*np.log10(np.max(np.abs(track))))
}
(OUT/'music-original.manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
