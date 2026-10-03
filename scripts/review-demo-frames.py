"""Extract labelled contact sheets from actual recorded demo frames for review."""
from pathlib import Path
import json
import subprocess
import argparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('clips', nargs='*')
parser.add_argument('--interval', type=int, default=20)
args = parser.parse_args()
clips = [ROOT / item for item in args.clips] if args.clips else sorted((ROOT / 'dist').glob('demo-*-raw.mp4'))
for clip in clips:
    probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_format', '-of', 'json', str(clip)]))
    duration = float(probe['format']['duration'])
    rows = max(1, (int(duration / args.interval) + 3) // 4)
    graph = (f'fps=1/{args.interval},scale=184:360,'
             "drawtext=text='%{pts\\:hms}':x=4:y=4:fontsize=14:fontcolor=white:box=1:boxcolor=black,"
             f'tile=4x{rows}')
    output = ROOT / '.local' / (clip.stem + '-sheet.jpg')
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', str(clip), '-vf', graph,
                    '-frames:v', '1', str(output)], check=True)
    print(json.dumps({'clip': str(clip.relative_to(ROOT)), 'seconds': duration, 'sheet': str(output.relative_to(ROOT))}))
