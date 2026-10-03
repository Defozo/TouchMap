"""Render the original vector app mark into native media resources; no network calls."""
from pathlib import Path
import resvg_py

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT/'assets/brand/touchmap.svg').read_text()
foreground = source.replace('<rect width="512" height="512" rx="112" fill="#071E2A"/>', '')
background = '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><rect width="512" height="512" fill="#071E2A"/></svg>'
for directory in [ROOT/'app/AppScope/resources/base/media', ROOT/'app/entry/src/main/resources/base/media']:
    for name, svg in [('foreground', foreground), ('background', background)]:
        (directory/f'{name}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=svg, width=512, height=512))
(ROOT/'app/entry/src/main/resources/base/media/startIcon.png').write_bytes(resvg_py.svg_to_bytes(svg_string=source, width=144, height=144))
print('Rendered original TouchMap native icon and launch mark.')
