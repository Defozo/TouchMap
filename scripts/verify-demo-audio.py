"""Verify final mix assets and a separate whole-audio perceptual review.

Local signal and transcript checks support the recorded actual-audio review;
they do not replace listening or claim a human reviewer. No provider is called.
"""
from datetime import datetime, timezone
from pathlib import Path
import argparse, difflib, hashlib, json, re, subprocess
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--video',type=Path,default=ROOT/'dist/touchmap-demo.mp4')
parser.add_argument('--review',type=Path,default=ROOT/'docs/evidence/demo-pitch-audio-review.json')
args=parser.parse_args()
video=args.video.resolve()
manifest=json.loads((ROOT/'docs/evidence/demo-manifest.json').read_text(encoding='utf-8'))
story=json.loads((ROOT/'docs/demo-storyboard.json').read_text(encoding='utf-8'))
review=json.loads(args.review.read_text(encoding='utf-8'))
video_hash=hashlib.sha256(video.read_bytes()).hexdigest()
assert video_hash==manifest['videoSha256']==review['videoSha256']
assert review['review']['coverage']['wholeAudioCovered'] is True
assert review['review']['overall']=='pass'
assert not [i for i in review['review'].get('materialIssues',[]) if i.get('severity') in ('critical','major','blocking')]

def pcm(path,start=0,duration=180):
    result=subprocess.check_output(['ffmpeg','-v','error','-threads','1','-ss',str(start),'-i',str(path),
        '-t',str(duration),'-vn','-ac','1','-ar','8000','-f','f32le','pipe:1'])
    return np.frombuffer(result,dtype='<f4')

final=pcm(video)
stem=pcm(ROOT/story['audio']['mixAsset'])
music=pcm(ROOT/story['audio']['musicAsset'])
checks=[]
for i,scene in enumerate(story['scenes']):
    item=scene.get('narration')
    if not item:
        continue
    start,end=item['outputStartSeconds'],item['outputEndSeconds']
    a,b=round(start*8000),round(end*8000)
    correlation=float(np.corrcoef(final[a:b],stem[a:b])[0,1])
    speech_power=float(np.sqrt(np.mean(stem[a:b]**2)))
    music_power=float(np.sqrt(np.mean(music[a:b]**2)))
    difference=20*np.log10(speech_power/max(music_power,1e-12))
    assert correlation>.98,(i,correlation)
    assert difference>16,(i,difference)
    checks.append({'scene':i,'outputStartSeconds':start,'outputEndSeconds':end,
        'finalToNarrationMusicCorrelation':correlation,'foregroundAboveMusicRmsDb':float(difference)})

stereo_raw=subprocess.check_output(['ffmpeg','-v','error','-threads','1','-i',str(video),
    '-vn','-ac','2','-ar','44100','-f','f32le','pipe:1'])
stereo=np.frombuffer(stereo_raw,dtype='<f4')
peak=float(np.max(np.abs(stereo)))
ending=float(np.sqrt(np.mean(final[-400:]**2)))
assert peak<.99 and ending<.0008,(peak,ending)
assert abs(len(final)/8000-180) <= 1024/44100, 'Decoded AAC duration may differ by at most one codec frame.'

def words(text):
    text=re.sub(r'\[App Audio:\s*(.*?)\]',r'\1',text,flags=re.IGNORECASE)
    return re.findall(r"[a-z]+(?:'[a-z]+)?",text.casefold().replace('re-import','reimport'))
expected=[]
for scene in story['scenes']:
    if scene.get('narration'):
        expected.extend(words(scene['narration']['text']))
    elif scene.get('audio'):
        expected.extend(words('Evaporation'))
heard=words(review['review']['transcript'])
matcher=difflib.SequenceMatcher(a=expected,b=heard,autojunk=False)
differences=[{'expected':expected[a:b],'heard':heard[c:d]} for tag,a,b,c,d in matcher.get_opcodes() if tag!='equal']
assert matcher.ratio()>.97,(matcher.ratio(),differences)
report={'recordedAtUtc':datetime.now(timezone.utc).isoformat(),'videoSha256':video_hash,
    'durationSeconds':manifest['durationSeconds'],'decodedAudioDurationSeconds':len(final)/8000,
    'aacFrameDurationToleranceSeconds':1024/44100,'narrationScenesChecked':len(checks),'checks':checks,
    'decodedNativeStereoPeak':peak,'endingLast50msRms':ending,
    'nativeApplicationAudio':'Separately verified in demo-qc.json; original 33-48second captured audio remains unmixed.',
    'actualAudioPerceptionReview':str(args.review.resolve().relative_to(ROOT)).replace('\\','/'),
    'perceptionReviewer':review['reviewer'],'completeAudioInputSha256':review['audioSha256'],
    'narrationTranscript':review['review']['transcript'],'scriptTranscriptWordAgreement':matcher.ratio(),
    'transcriptDifferences':differences,'passed':True,
    'limits':'Complete automated audio perception is recorded separately from signal checks. No human listening or exact model timestamp accuracy is claimed. Scene alignment comes from the approved timeline and measured utterance duration.'}
(ROOT/'docs/evidence/demo-audio-transcript.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps({k:report[k] for k in ['videoSha256','passed','narrationScenesChecked','decodedNativeStereoPeak','endingLast50msRms','scriptTranscriptWordAgreement','transcriptDifferences']},indent=2))
