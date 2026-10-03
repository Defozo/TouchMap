"""Owned chart evaluation fixtures with explicit numeric truth, no observed data.

Fixed before the first model request. The two held-out fixtures must not be used
to tune prompts. Rendering uses the same pinned font across machines.
"""
from pathlib import Path
import hashlib
from html import escape
import json
import resvg_py

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = Path(__file__).resolve().parent / 'charts'
CASES = [
    {'id': 'chart-01', 'title': 'Illustrative rainfall', 'kind': 'bar', 'variant': 'clear-unknown', 'split': 'development',
     'xLabel': 'Month', 'yLabel': 'Rainfall', 'unit': 'mm', 'labels': ['April', 'May', 'June'], 'values': [40, 65, None],
     'domain': [0, 80], 'ticks': [0, 20, 40, 60, 80], 'precision': 0},
    {'id': 'chart-02', 'title': 'Illustrative energy use', 'kind': 'bar', 'variant': 'low-contrast-decimal', 'split': 'development',
     'xLabel': 'Station', 'yLabel': 'Energy', 'unit': 'kWh', 'labels': ['Aster', 'Birch', 'Cedar'], 'values': [12.5, 17, 9.5],
     'domain': [0, 20], 'ticks': [0, 5, 10, 15, 20], 'precision': 1},
    {'id': 'chart-03', 'title': 'Illustrative temperature', 'kind': 'line', 'variant': 'negative-and-unknown', 'split': 'development',
     'xLabel': 'Day', 'yLabel': 'Temperature', 'unit': '°C', 'labels': ['Day 1', 'Day 2', 'Day 3', 'Day 4'], 'values': [-2, 1, None, 4],
     'domain': [-5, 5], 'ticks': [-5, 0, 5], 'precision': 0},
    {'id': 'chart-04', 'title': 'Illustrative stored water', 'kind': 'bar', 'variant': 'rotated-labels', 'split': 'held-out',
     'xLabel': 'Store', 'yLabel': 'Volume', 'unit': 'L', 'labels': ['North', 'Southwest', 'East'], 'values': [14, 9, 22],
     'domain': [0, 30], 'ticks': [0, 10, 20, 30], 'precision': 0},
    {'id': 'chart-05', 'title': 'Illustrative distance', 'kind': 'line', 'variant': 'clear-decimal', 'split': 'held-out',
     'xLabel': 'Time', 'yLabel': 'Distance', 'unit': 'km', 'labels': ['08:00', '09:00', '10:00'], 'values': [0, 1.25, 2.5],
     'domain': [0, 3], 'ticks': [0, 1, 2, 3], 'precision': 2},
]


def render(case):
    color = '#A3ABA9' if case['variant'].startswith('low-contrast') else '#183B34'
    x0, x1, y0, y1 = 115, 825, 130, 450
    points = []
    shapes = [f'<svg xmlns="http://www.w3.org/2000/svg" width="960" height="640" viewBox="0 0 960 640">',
              '<rect width="960" height="640" fill="white"/>',
              f'<g fill="{color}" font-family="DejaVu Sans" font-size="24">',
              f'<text x="480" y="46" text-anchor="middle" font-size="30">{escape(case["title"])}</text>',
              f'<text x="115" y="95">{escape(case["yLabel"])} ({escape(case["unit"])})</text>']
    def y(value):
        return y1 - (value-case['domain'][0])/(case['domain'][1]-case['domain'][0])*(y1-y0)
    for tick in case['ticks']:
        yy = y(tick)
        shapes += [f'<path d="M{x0} {yy}H{x1}" stroke="{color}" stroke-width="1" opacity="0.35"/>',
                   f'<text x="98" y="{yy+8}" text-anchor="end">{tick}</text>']
    shapes += [f'<path d="M{x0} {y0}V{y1}H{x1}" stroke="{color}" stroke-width="2" fill="none"/>']
    truth_regions = []
    for index, (label, value) in enumerate(zip(case['labels'], case['values'])):
        x = x0 + (index + .5)*(x1-x0)/len(case['labels'])
        yy = y(value) if value is not None else y1-70
        if case['variant'] == 'rotated-labels':
            shapes.append(f'<text x="{x}" y="492" transform="rotate(-28 {x} 492)" text-anchor="end">{escape(label)}</text>')
        else:
            shapes.append(f'<text x="{x}" y="488" text-anchor="middle">{escape(label)}</text>')
        if value is None:
            shapes += [f'<circle cx="{x}" cy="{yy}" r="24" fill="white" stroke="{color}" stroke-dasharray="5 5"/>',
                       f'<text x="{x}" y="{yy+8}" text-anchor="middle">?</text>',
                       f'<text x="{x}" y="{yy-40}" text-anchor="middle">Unknown</text>']
            points.append(None)
        else:
            printed = f'{value:g} {case["unit"]}'
            if case['kind'] == 'bar':
                shapes.append(f'<rect x="{x-45}" y="{yy}" width="90" height="{y1-yy}" fill="{color}" opacity="0.7"/>')
            else:
                shapes.append(f'<circle cx="{x}" cy="{yy}" r="7" fill="{color}"/>')
            shapes.append(f'<text x="{x}" y="{yy-20}" text-anchor="middle">{escape(printed)}</text>')
            points.append((x, yy))
        truth_regions.append({'id': f'value-{index+1}', 'label': label,
                              'bounds': [x-60, min(yy-55, y1-55), x+60, y1+48],
                              'value': value, 'unit': case['unit'],
                              'sourceText': f'{label}: Unknown' if value is None else f'{label}: {value:g} {case["unit"]}'})
    if case['kind'] == 'line':
        for a, b in zip(points, points[1:]):
            if a is not None and b is not None:
                shapes.append(f'<path d="M{a[0]} {a[1]}L{b[0]} {b[1]}" fill="none" stroke="{color}" stroke-width="3"/>')
    shapes += [f'<text x="480" y="550" text-anchor="middle">{escape(case["xLabel"])}</text>',
               '<text x="480" y="600" text-anchor="middle" font-size="19">Authored teaching values. Unknown means no recorded value.</text>', '</g></svg>']
    source = '\n'.join(shapes) + '\n'
    font = str(ROOT/'backend/touchmap/assets/DejaVuSans.ttf')
    png = resvg_py.svg_to_bytes(svg_string=source, width=960, height=640, skip_system_fonts=True,
                                font_files=[font], font_family='DejaVu Sans', sans_serif_family='DejaVu Sans')
    (OUTPUT/f'{case["id"]}.svg').write_text(source, encoding='utf-8')
    (OUTPUT/f'{case["id"]}.png').write_bytes(png)
    return {**case, 'width': 960, 'height': 640, 'imageFile': case['id']+'.png',
            'imageSha256': hashlib.sha256(png).hexdigest(), 'regions': truth_regions,
            'xAxis': {'scale': 'category', 'label': case['xLabel'], 'unit': '',
                      'ticks': [{'value': i, 'label': label} for i,label in enumerate(case['labels'])]},
            'yAxis': {'scale': 'linear', 'label': case['yLabel'], 'unit': case['unit'], 'domain': case['domain'],
                      'ticks': [{'value': value, 'label': str(value)} for value in case['ticks']]},
            'relations': [], 'license': 'CC BY 4.0', 'attribution': 'TouchMap contributors',
            'truthOrigin': 'Owned explicit teaching data authored before provider evaluation; not measurements of real-world subjects'}


if __name__ == '__main__':
    OUTPUT.mkdir(parents=True, exist_ok=True)
    truth = [render(case) for case in CASES]
    (OUTPUT/'truth.json').write_text(json.dumps(truth, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print(json.dumps({'charts': len(truth), 'heldOut': sum(c['split']=='held-out' for c in truth)}))
