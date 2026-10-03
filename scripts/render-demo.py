"""Compose English captions beside actual native recordings, retaining source hashes.

No application pixels are generated or replaced. A storyboard lists source clips,
start/duration in seconds, title, body and an explicit excerpt annotation. The
source audio is used only when requested. Informational title cards have no clip.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import textwrap

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    subprocess.run(command, check=True)


def require_approval(story):
    if not story.get('approved') or not story.get('approval', {}).get('authorization'):
        raise ValueError('The storyboard must record the real delegated authorization before assembly.')
    normalized = {**story, 'approved': False, 'approval': {}}
    digest = hashlib.sha256(json.dumps(normalized, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    if story['approval'].get('planSha256') != digest:
        raise ValueError('The storyboard changed after its delegated approval record.')


def render_soundtrack_derivative(story, args):
    """Reproduce an approved bounded soundtrack correction from its retained master.

    The captured scene sequence and text must remain identical. A complete audio
    delivery stem replaces the old soundtrack; original app audio is already in it.
    """
    require_approval(story)
    source = story['sourceMaster']
    work = (ROOT / 'dist/_video_work').resolve()
    paths = {}
    for key, digest_key in [('path', 'sha256'), ('storyboard', 'storyboardSha256'), ('manifest', 'manifestSha256')]:
        path = (ROOT / source[key]).resolve()
        if not path.is_relative_to(work) or not path.is_file():
            raise ValueError('Retained source-master dependencies must exist inside the private video work directory.')
        if hashlib.sha256(path.read_bytes()).hexdigest() != source[digest_key]:
            raise ValueError(f'Source-master dependency changed: {key}')
        paths[key] = path
    baseline = json.loads(paths['storyboard'].read_text(encoding='utf-8'))
    baseline_manifest = json.loads(paths['manifest'].read_text(encoding='utf-8'))
    if not baseline_manifest.get('reviewed') or baseline_manifest['videoSha256'] != source['sha256']:
        raise ValueError('The retained master must match its historical reviewed manifest.')
    require_approval(baseline)
    if len(story['scenes']) != len(baseline['scenes']):
        raise ValueError('A soundtrack derivative cannot add or remove scenes.')
    for index, (current, prior) in enumerate(zip(story['scenes'], baseline['scenes'])):
        expected = dict(prior)
        if index == len(story['scenes']) - 1:
            expected['duration'] = prior['duration'] - source['trimFinalFrames'] / 24
        if current != expected:
            raise ValueError('A soundtrack derivative must preserve all scene contents and timings except the declared final frame trim.')
    audio = story['audio']
    mix = (ROOT / audio['deliveryAsset']).resolve()
    if not mix.is_relative_to(work) or hashlib.sha256(mix.read_bytes()).hexdigest() != audio['deliverySha256']:
        raise ValueError('The complete delivery soundtrack differs from the approved plan.')
    frames = round(sum(float(scene['duration']) for scene in story['scenes']) * 24)
    duration = frames / 24
    if not 0 < duration < 180 or frames != story['expectedVideoFrames']:
        raise ValueError('The bounded pitch delivery must have its exact approved frame count and remain below 180 seconds.')
    if args.prepare:
        print(json.dumps({'prepared': True, 'sourceMasterSha256': source['sha256'], 'deliverySha256': audio['deliverySha256'], 'frames': frames}))
        return
    if args.output.resolve() == paths['path']:
        raise ValueError('A retained source master must never be overwritten.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    run(['ffmpeg', '-y', '-v', 'error', '-i', str(paths['path']), '-i', str(mix),
         '-map', '0:v:0', '-map', '1:a:0', '-frames:v', str(frames), '-t', str(duration),
         '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16', '-threads', '2', '-pix_fmt', 'yuv420p',
         '-video_track_timescale', '24000', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart',
         '-metadata', 'title=TouchMap - narrated demo, repaired audio', str(args.output.resolve())])
    probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(args.output)]))
    report = {**baseline_manifest, 'createdAt': datetime.now(timezone.utc).isoformat(),
              'videoSha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'durationSeconds': float(probe['format']['duration']), 'scenes': story['scenes'],
              'storyboard': str(args.storyboard.resolve().relative_to(ROOT)),
              'storyboardSha256': hashlib.sha256(args.storyboard.read_bytes()).hexdigest(),
              'approval': story['approval'], 'audio': audio, 'sourceMaster': source,
              'expectedVideoFrames': frames, 'reviewed': False,
              'policy': 'Approved soundtrack derivative from the preserved native-recording master. Scene contents are unchanged; only the final declared static frames are trimmed.'}
    report.pop('reviewEvidence', None)
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps({'output': str(args.output), 'durationSeconds': report['durationSeconds'], 'sha256': report['videoSha256']}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('storyboard', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/touchmap-demo.mp4')
    parser.add_argument('--manifest', type=Path, default=ROOT / 'docs/evidence/demo-manifest.json')
    parser.add_argument('--prepare', action='store_true', help='Cache available scenes without assembling pending transfer footage.')
    args = parser.parse_args()
    story = json.loads(args.storyboard.read_text(encoding='utf-8'))
    if story.get('sourceMaster'):
        return render_soundtrack_derivative(story, args)
    font = ROOT / 'backend/touchmap/assets/DejaVuSans.ttf'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    evidence = []
    work = ROOT / 'dist/_video_work'
    stage = work / 'render/scenes'
    stage.mkdir(parents=True, exist_ok=True)
    # A short relative font path avoids filtergraph escaping of host paths.
    (stage / 'font.ttf').write_bytes(font.read_bytes())
    outputs = []
    for index, scene in enumerate(story['scenes']):
        if scene.get('pending'):
            if args.prepare:
                continue
            raise ValueError('Pending footage must be replaced and reviewed before final assembly.')
        duration = float(scene['duration'])
        if not 0 < duration <= 300:
            raise ValueError('Each scene must have a positive duration of at most 300 seconds.')
        clip = (ROOT / scene['clip']).resolve() if scene.get('clip') else None
        if clip and (not clip.is_file() or not clip.is_relative_to(ROOT)):
            raise ValueError('Recorded clips must exist inside the project.')
        start = float(scene.get('start', 0))
        speed = float(scene.get('speed', 1))
        if start < 0 or speed <= 0 or speed > 8:
            raise ValueError('Invalid excerpt start or playback speed.')
        if speed != 1 and (not scene.get('annotation') or scene.get('audio')):
            raise ValueError('Sped excerpts require an explicit annotation and cannot reuse unsynchronized audio.')
        source_hash = hashlib.sha256(clip.read_bytes()).hexdigest() if clip else None
        if clip:
            source_probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(clip)]))
            if start + duration * speed > float(source_probe['format']['duration']) + 0.001:
                raise ValueError(f'Excerpt exceeds source duration: {clip.name}')
            if scene.get('audio') and not any(stream['codec_type'] == 'audio' for stream in source_probe['streams']):
                raise ValueError(f'No captured audio stream: {clip.name}')
            if scene.get('audio') and not clip.with_suffix('.sync.json').is_file():
                raise ValueError('Captured application audio requires its synchronization provenance.')
            if scene.get('audio') and json.loads(clip.with_suffix('.sync.json').read_text())['outputSha256'] != source_hash:
                raise ValueError('Captured audio synchronization sidecar belongs to a different source file.')
        body = '\n\n'.join('\n'.join(textwrap.wrap(p, 43 if clip else 66)) for p in scene['body'].split('\n\n'))
        for name, content in [('title', scene['title']), ('body', body),
                              ('footer', scene.get('annotation', 'TouchMap | DEFOZO SOFTWARE HOUSE | Michał Kiełtyka'))]:
            (stage / f'{index}-{name}.txt').write_text(content, encoding='utf-8')
        cache_key = hashlib.sha256(json.dumps({'version': 3, 'scene': scene, 'source': source_hash,
                                              'font': hashlib.sha256(font.read_bytes()).hexdigest()}, sort_keys=True).encode()).hexdigest()[:20]
        destination = stage / f'scene-{cache_key}.mov'
        command = ['ffmpeg', '-y', '-v', 'error', '-threads', '2', '-filter_complex_threads', '2']
        if clip:
            command += ['-ss', str(start), '-t', str(duration * speed), '-i', str(clip)]
        command += ['-f', 'lavfi', '-i', f'color=c=0x071E2A:s=1920x1080:r=24:d={duration}',
                    '-f', 'lavfi', '-i', f'anullsrc=r=44100:cl=stereo:d={duration}']
        base = 1 if clip else 0
        graph = ''
        if clip:
            graph += f'[0:v]setpts=(PTS-STARTPTS)/{speed},fps=24,scale=540:1056:force_original_aspect_ratio=decrease[phone];'
            graph += f'[{base}:v][phone]overlay=48:(H-h)/2[back];'
        else:
            graph += f'[{base}:v]null[back];'
        x = 680 if clip else 130
        graph += f"[back]drawbox=x={x}:y=88:w=90:h=8:color=0x67D6BC:t=fill,"
        graph += f"drawtext=fontfile=font.ttf:textfile={index}-title.txt:x={x}:y=140:fontsize=58:fontcolor=white:expansion=none,"
        graph += f"drawtext=fontfile=font.ttf:textfile={index}-body.txt:x={x}:y=255:fontsize=39:line_spacing=14:fontcolor=0xD4E3EC:expansion=none,"
        graph += f"drawtext=fontfile=font.ttf:textfile={index}-footer.txt:x={x}:y=998:fontsize=22:fontcolor=0x8DADBC:expansion=none[v]"
        if scene.get('audio'):
            gain = float(scene.get('audioGain', 1))
            if not 0 < gain <= 4:
                raise ValueError('Audio gain must be positive and at most four.')
            graph += f';[0:a]asetpts=PTS-STARTPTS,aresample=44100,volume={gain},apad,atrim=duration={duration}[a]'
            audio_map = '[a]'
        else:
            audio_map = f'{base + 1}:a'
        command += ['-filter_complex', graph, '-map', '[v]', '-map', audio_map,
                    '-t', str(duration), '-c:v', 'libx264', '-threads', '2', '-preset', 'veryfast', '-crf', '19',
                    '-pix_fmt', 'yuv420p', '-video_track_timescale', '24000', '-c:a', 'pcm_s16le', str(destination)]
        if not destination.exists():
            subprocess.run(command, cwd=stage, check=True)
        outputs.append(destination)
        evidence.append({**scene, 'sourceSha256': source_hash, 'renderCache': str(destination.relative_to(ROOT)),
                         'visualSource': 'actual recorded native framebuffer' if clip else 'English information card'})
        print(json.dumps({'preparedScene': index, 'title': scene['title'], 'durationSeconds': duration}), flush=True)
    if args.prepare:
        (work / 'render/prepared-scenes.json').write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        print(json.dumps({'prepared': len(outputs), 'assembly': False}), flush=True)
        return
    require_approval(story)
    concat = stage / 'concat.txt'
    concat.write_text(''.join(f"file '{path.name}'\n" for path in outputs))
    assembly = ['ffmpeg', '-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', str(concat)]
    audio = story.get('audio', {})
    if audio.get('mixAsset'):
        mix = (ROOT / audio['mixAsset']).resolve()
        if not mix.is_relative_to(work) or not mix.is_file():
            raise ValueError('The reviewed narration/music mix must exist under the video work directory.')
        if hashlib.sha256(mix.read_bytes()).hexdigest() != audio.get('mixSha256'):
            raise ValueError('The narration/music mix differs from the approved storyboard.')
        assembly += ['-i', str(mix), '-filter_complex',
                     '[0:a][1:a]amix=inputs=2:duration=first:normalize=0[a]',
                     '-map', '0:v:0', '-map', '[a]']
    assembly += ['-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', str(args.output.resolve())]
    run(assembly)
    probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(args.output)]))
    report = {'createdAt': datetime.now(timezone.utc).isoformat(), 'team': json.loads((ROOT / 'TEAM.json').read_text()),
              'videoSha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'durationSeconds': float(probe['format']['duration']), 'scenes': evidence,
              'storyboard': str(args.storyboard.resolve().relative_to(ROOT)), 'storyboardSha256': hashlib.sha256(args.storyboard.read_bytes()).hexdigest(),
              'approval': story['approval'], 'sourceBuilds': story.get('sourceBuilds', {}), 'audio': audio,
              'expectedVideoFrames': round(sum(float(scene['duration']) for scene in story['scenes']) * 24),
              'sourceCaptureLimits': 'Actual framebuffer captures may hold the last received frame between VNC updates. Authoring excerpts are condensed. Native application audio is isolated QEMU output with approximate UTC start alignment, not physical acoustic timing. Added narration and original instrumental music have separate provenance and whole-audio review.',
              'policy': 'Captions beside actual native recordings. Cuts and accelerated author excerpts are labelled. No fabricated UI state.',
              'reviewed': False}
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps({'output': str(args.output), 'durationSeconds': report['durationSeconds'], 'sha256': report['videoSha256']}))


if __name__ == '__main__':
    main()
