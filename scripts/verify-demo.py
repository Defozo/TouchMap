"""Verify exact video frames, audio provenance and every captioned scene of the candidate."""
from pathlib import Path
import argparse, json, subprocess, hashlib, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'dist/_video_work'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--video', type=Path, default=ROOT / 'dist/touchmap-demo.mp4')
args = parser.parse_args()
VIDEO = args.video.resolve()
manifest = json.loads((ROOT/'docs/evidence/demo-manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256(VIDEO.read_bytes()).hexdigest() == manifest['videoSha256'], 'Video differs from its manifest.'
assert hashlib.sha256((ROOT/manifest['storyboard']).read_bytes()).hexdigest() == manifest['storyboardSha256'], 'Storyboard differs from its manifest.'
frames = WORK/'frames'/VIDEO.stem
frames.mkdir(parents=True,exist_ok=True)
probe = json.loads(subprocess.check_output(['ffprobe','-v','error','-threads','1','-count_frames','-show_streams','-show_format','-of','json',str(VIDEO)]))
video = next(item for item in probe['streams'] if item['codec_type']=='video')
sound = next(item for item in probe['streams'] if item['codec_type']=='audio')
expected = manifest['expectedVideoFrames']
assert int(video['nb_read_frames']) == expected, (video['nb_read_frames'],expected)
assert (video['width'],video['height'],video['avg_frame_rate'],video['pix_fmt']) == (1920,1080,'24/1','yuv420p')
assert abs(float(video['duration'])-180)<1/24
assert abs(float(sound['duration'])-float(video['duration']))<1/24
subprocess.run(['ffmpeg','-v','error','-xerror','-err_detect','explode','-threads','1',
                '-i',str(VIDEO),'-map','0:v:0','-map','0:a:0','-f','null','-'],check=True)

def pcm(path,start,duration):
    raw = subprocess.check_output(['ffmpeg','-v','error','-threads','1','-ss',str(start),'-i',str(path),'-t',str(duration),'-vn','-ac','1','-ar','8000','-f','f32le','pipe:1'])
    return np.frombuffer(raw,dtype='<f4')

offset=0
audio_checks=[]
timeline=[]
font=ImageFont.truetype(str(ROOT/'backend/touchmap/assets/DejaVuSans.ttf'),22)
for index,scene in enumerate(manifest['scenes']):
    duration=scene['duration']
    middle=offset+duration/2
    still=frames/f'scene-{index:02d}.png'
    subprocess.run(['ffmpeg','-y','-v','error','-threads','1','-ss',str(middle),'-i',str(VIDEO),'-frames:v','1','-threads','1',str(still)],check=True)
    for edge,at in [('in',offset),('out',offset+duration-1/24)]:
        target=frames/f'boundary-{index:02d}-{edge}.png'
        subprocess.run(['ffmpeg','-y','-v','error','-threads','1','-ss',str(at),'-i',str(VIDEO),'-frames:v','1','-threads','1',str(target)],check=True)
    if scene.get('audio'):
        final=pcm(VIDEO,offset,duration)
        source=pcm(ROOT/scene['clip'],scene['start'],duration)*scene.get('audioGain',1)
        size=min(len(final),len(source));final=final[:size];source=source[:size]
        correlation=float(np.corrcoef(final,source)[0,1])
        check={'scene':index,'outputStart':offset,'sourceStart':scene['start'],'duration':duration,
               'correlation':correlation,'peak':float(np.max(np.abs(final))),'rms':float(np.sqrt(np.mean(final**2))),
               'method':'Direct sample correlation of decoded mono 8000 Hz final excerpt and its captured source, with recorded gain. No retiming.'}
        assert correlation>0.98,check
        assert check['peak']<0.98 and check['rms']>0.0001,check
        audio_checks.append(check)
    timeline.append({'index':index,'start':offset,'end':offset+duration,'title':scene['title'],'frame':str(still.relative_to(ROOT))})
    offset+=duration

for page in range(math.ceil(len(timeline)/4)):
    contact=Image.new('RGB',(1920,1140),'#132534')
    draw=ImageDraw.Draw(contact)
    for cell,item in enumerate(timeline[page*4:page*4+4]):
        x=(cell%2)*960;y=(cell//2)*570
        picture=Image.open(ROOT/item['frame']).resize((960,540))
        contact.paste(picture,(x,y+30))
        draw.text((x+12,y+4),f"Scene {item['index']:02d}: {item['start']:03d}-{item['end']:03d}s",font=font,fill='white')
    contact.save(frames/f'contact-{page+1}.jpg',quality=94)

report={'videoSha256':hashlib.sha256(VIDEO.read_bytes()).hexdigest(),'technicalPassed':True,'durationSeconds':float(probe['format']['duration']),
        'decodedFrames':int(video['nb_read_frames']),'expectedFrames':expected,'videoCodec':video['codec_name'],'audioCodec':sound['codec_name'],
        'frameRate':video['avg_frame_rate'],'dimensions':[video['width'],video['height']],
        'audioVideoDeltaSeconds':float(sound['duration'])-float(video['duration']),'audioChecks':audio_checks,'timeline':timeline,
        'reviewLimits':'Strict technical decoding and sample correlation support integrity. Visual contact and boundary review and independent factual review are recorded separately; no full human audiovisual perception is inferred.'}
(ROOT/'docs/evidence/demo-qc.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
(WORK/'render/final-ffprobe.json').write_text(json.dumps(probe,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:report[k] for k in ['technicalPassed','durationSeconds','decodedFrames','videoSha256','audioChecks']},indent=2))
