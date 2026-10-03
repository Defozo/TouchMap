"""Evaluate the five fixed owned charts through the real product adapter.

Run with backend Python and psst GOOGLE_AI_STUDIO_API_KEY. Existing first-attempt
records are reused, never overwritten. A separate --output is required for a
subsequent experiment; held-out results must not be used for prompt tuning.
"""
from __future__ import annotations
import argparse
import asyncio
import hashlib
import json
from pathlib import Path
import sys
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
from touchmap import providers
from touchmap.errors import TouchMapError
from touchmap.images import normalize_image
from touchmap.settings import Settings


def normalized(text):
    return ' '.join(text.casefold().strip().split())


def grade(diagram, truth):
    charts = diagram['charts']
    result = {'chartCount': len(charts), 'kindCorrect': False, 'xLabelsCorrect': False,
              'yLabelCorrect': False, 'unitCorrect': False, 'domainCorrect': False,
              'ticksCorrect': False, 'scaleCorrect': False, 'exactValuesCorrect': 0,
              'expectedValues': len(truth['values']), 'unknownsCorrect': 0,
              'expectedUnknowns': sum(value is None for value in truth['values']),
              'unsupportedValueAssertions': [], 'usableChartDraft': False}
    if len(charts) != 1:
        result['unsupportedValueAssertions'] = [
            {'chart': c['id'], 'x': value['x'], 'value': value['value']}
            for c in charts for series in c['series'] for value in series['values']]
        return result
    chart = charts[0]
    expected = {normalized(label): value for label, value in zip(truth['labels'], truth['values'])}
    values = [value for series in chart['series'] for value in series['values']]
    found = {}
    for value in values:
        label = normalized(value['x'])
        found.setdefault(label, []).append(value['value'])
        if label not in expected or value['value'] != expected[label]:
            result['unsupportedValueAssertions'].append({'x': value['x'], 'value': value['value']})
    result.update(
        kindCorrect=chart['kind'] == truth['kind'],
        xLabelsCorrect=[normalized(t['label']) for t in chart['xAxis']['ticks']] == [normalized(x) for x in truth['labels']],
        yLabelCorrect=normalized(chart['yAxis']['label']) == normalized(truth['yLabel']),
        unitCorrect=chart['yAxis']['unit'] == truth['unit'],
        domainCorrect=chart['yAxis']['domain'] == truth['domain'],
        ticksCorrect=[t['value'] for t in chart['yAxis']['ticks']] == truth['ticks'],
        scaleCorrect=chart['xAxis']['scale'] == 'category' and chart['yAxis']['scale'] == 'linear',
        exactValuesCorrect=sum(found.get(label) == [value] for label, value in expected.items()),
        unknownsCorrect=sum(value is None and found.get(label) == [None] for label, value in expected.items()),
        unexpectedRelations=len(diagram['relations']),
        observed={'kind': chart['kind'], 'xAxis': chart['xAxis'], 'yAxis': chart['yAxis'],
                  'values': [{'x': v['x'], 'value': v['value'], 'precision': v['precision']} for v in values]},
    )
    result['usableChartDraft'] = (all(result[key] for key in ['kindCorrect', 'xLabelsCorrect', 'yLabelCorrect', 'unitCorrect', 'domainCorrect', 'ticksCorrect', 'scaleCorrect'])
                                   and result['exactValuesCorrect'] == len(expected)
                                   and not result['unsupportedValueAssertions'] and not diagram['relations'])
    return result


async def evaluate(args):
    corpus = ROOT / 'tests/evaluation/charts'
    truths = json.loads((corpus/'truth.json').read_text(encoding='utf-8'))
    output = ROOT / args.output
    output.mkdir(parents=True, exist_ok=True)
    settings = Settings(ai_enabled=True)
    settings.validate()
    adapter = providers.Providers(settings)
    adapter_hash = hashlib.sha256((ROOT/'backend/touchmap/providers.py').read_bytes()).hexdigest()
    records = []
    for truth in truths:
        target = output / (truth['id']+'.json')
        if target.exists():
            records.append(json.loads(target.read_text(encoding='utf-8')))
            continue
        start = time.monotonic()
        record = {'id': truth['id'], 'split': truth['split'], 'variant': truth['variant'],
                  'model': settings.gemini_model, 'adapterSha256': adapter_hash,
                  'startedAt': datetime.now(timezone.utc).isoformat(),
                  'schemaSuccess': False, 'usableChartDraft': False}
        original_reader = providers.read_json
        def capture_json(data):
            # Only model text for these owned fixtures; no credentials or request headers.
            (output/(truth['id']+'.provider-output.json')).write_bytes(data)
            return original_reader(data)
        try:
            image = (corpus/truth['imageFile']).read_bytes()
            record['sourceSha256'] = hashlib.sha256(image).hexdigest()
            if record['sourceSha256'] != truth['imageSha256']:
                raise ValueError('Fixture bytes differ from frozen truth')
            data, width, height = normalize_image(image)
            providers.read_json = capture_json
            response = await adapter.analyze(data, width, height, 1, 'en')
            (output/(truth['id']+'.draft.json')).write_text(json.dumps(response['diagram'], indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
            record.update(grade(response['diagram'], truth), schemaSuccess=True,
                          report=response['report'], usage=response.get('usage'))
        except TouchMapError as error:
            record['error'] = {'code': error.code, 'message': error.message}
        finally:
            providers.read_json = original_reader
        record['durationMs'] = round((time.monotonic()-start)*1000)
        target.write_text(json.dumps(record, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
        records.append(record)
        print(json.dumps({key: record.get(key) for key in ['id', 'schemaSuccess', 'usableChartDraft', 'exactValuesCorrect', 'unknownsCorrect', 'durationMs', 'error']}), flush=True)
    def aggregate(rows):
        return {'inputs': len(rows), 'schemaSuccesses': sum(row['schemaSuccess'] for row in rows),
                'usableChartDrafts': sum(row['usableChartDraft'] for row in rows),
                'exactValuesCorrect': sum(row.get('exactValuesCorrect', 0) for row in rows),
                'expectedValues': sum(len(t['values']) for t in truths if t['id'] in {r['id'] for r in rows}),
                'unknownsCorrect': sum(row.get('unknownsCorrect', 0) for row in rows),
                'expectedUnknowns': sum(sum(v is None for v in t['values']) for t in truths if t['id'] in {r['id'] for r in rows}),
                'unsupportedValueAssertions': sum(len(row.get('unsupportedValueAssertions', [])) for row in rows)}
    summary = {'scope': 'Five owned synthetic charts, separate from the 20 process diagrams. Exact printed values/nulls, units, categorical labels and numeric axes. Two held-out charts; no tuning on their results. All failed inputs retained. Not representative real-world accuracy or a participant study.',
               'model': settings.gemini_model, 'all': aggregate(records),
               'development': aggregate([r for r in records if r['split']=='development']),
               'heldOut': aggregate([r for r in records if r['split']=='held-out']),
               'records': records, 'actualProviderInvoiceCost': None,
               'costNote': 'Raw provider usage retained. Billed cost and human correction time were not measured.'}
    (output/'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print(json.dumps({key: summary[key] for key in ['all', 'development', 'heldOut']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='docs/evidence/ai-chart-evaluation')
    asyncio.run(evaluate(parser.parse_args()))
