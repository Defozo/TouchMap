"""Summarize saved inference usage and public-rate estimates without provider calls."""
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
rates = {'checkedOn': '2026-10-03', 'currency': 'USD',
         'geminiInputPerMillion': 0.75, 'geminiOutputPerMillion': 3.75,
         'geminiSource': 'https://ai.google.dev/gemini-api/docs/pricing',
         'geminiRateValidity': 'Introductory standard rate through 2026-12-31',
         'elevenFlashPerThousandCharacters': 0.04,
         'elevenSource': 'https://elevenlabs.io/pricing/api',
         'scope': 'Public API rates read on the stated date; not an account invoice or historical charge.'}

def usage_records(summary, score_field, score_name):
    records = []
    for item in summary['records']:
        usage = item.get('usage') or {}
        input_tokens = usage.get('total_input_tokens', 0)
        output_tokens = usage.get('total_output_tokens', 0)
        raw_input = max(input_tokens, usage.get('raw_prompt_token', 0))
        invocations = usage.get('model_invocation_token_counts', [])
        raw_output = max(output_tokens, sum(part.get('tokens', 0) for invocation in invocations
                                           for part in invocation.get('candidates_tokens_details', [])))
        def estimate(input_count, output_count):
            return round((input_count * rates['geminiInputPerMillion'] + output_count * rates['geminiOutputPerMillion'])/1_000_000, 8)
        records.append({'id': item['id'], score_name: item[score_field], 'durationMs': item.get('durationMs'),
                        'reportedInputTokens': input_tokens, 'reportedOutputTokens': output_tokens,
                        'estimateReportedUsageUsd': estimate(input_tokens, output_tokens),
                        'estimateWithRawInvocationUsageUsd': estimate(raw_input, raw_output)})
    return records


summary = json.loads((ROOT/'docs/evidence/ai-evaluation/summary.json').read_text())
records = usage_records(summary, 'usableDraft', 'usableDraft')
chart_summary = json.loads((ROOT/'docs/evidence/ai-chart-evaluation/summary.json').read_text())
chart_records = usage_records(chart_summary, 'usableChartDraft', 'strictRepresentationMatch')

speech = []
for path in sorted((ROOT/'samples').glob('*/diagram.json')):
    d = json.loads(path.read_text())
    texts = {}
    texts[(d['packageId'], 'overview')] = d['description'] or d['title']
    for region in d['regions']:
        texts[(region['id'], 'label')] = region['label']
        texts[(region['id'], 'description')] = region['description']
    for relation in d['relations']:
        texts[(relation['id'], 'label')] = relation['label']
    for question in d['questions']:
        texts[(question['id'], 'question')] = question['prompt']
    characters = sum(len(texts[(asset['targetId'], asset['kind'])]) for asset in d['audio'])
    speech.append({'packageId': d['packageId'], 'audioAssets': len(d['audio']), 'characters': characters,
                   'fullRegenerationPublicRateEstimateUsd': round(characters/1000*rates['elevenFlashPerThousandCharacters'], 6)})

usable = sum(item['usableDraft'] for item in records)
durations = sorted(item['durationMs'] for item in records if item['durationMs'] is not None)
result = {'rates': rates, 'requests': len(records), 'usableDraftsByConstrainedEvaluationRule': usable,
          'scope': 'Top-level request statistics retain the twenty process diagrams. The five charts are reported separately; combined totals sum both without conflating their scoring rules.',
          'totalEstimateReportedUsageUsd': round(sum(item['estimateReportedUsageUsd'] for item in records), 8),
          'totalEstimateWithRawInvocationUsageUsd': round(sum(item['estimateWithRawInvocationUsageUsd'] for item in records), 8),
          'meanPublicRateEstimatePerUsableRawDraftUsd': round(sum(item['estimateReportedUsageUsd'] for item in records)/usable, 8) if usable else None,
          'providerRequestMedianMs': statistics.median(durations) if durations else None,
          'providerRequestP95Ms': durations[math.ceil(.95*len(durations))-1] if durations else None,
          'authorReviewTime': None, 'costPerTeacherReviewedUsablePackage': None,
          'limitations': ['Raw SDK usage exposes differing summary and invocation token counts; both estimates are retained, billing reconciliation is not claimed.',
                         'Includes every saved request from the twenty process diagrams and five charts, with separate corpus totals. Does not include development smoke calls or the separate native authoring flow.',
                         'The constrained usable-draft criterion is not teacher-reviewed usability. Author effort and total cost through accepted publication were not measured in a representative study.',
                         'Speech figures estimate full regeneration at current public rates. Existing recordings are bundled and their reuse incurs no new generation. Taxes, discounts, free quotas and failed or unknown-outcome requests are excluded.'],
          'records': records, 'bundledSpeech': speech}
chart_durations = sorted(item['durationMs'] for item in chart_records if item['durationMs'] is not None)
result['chartEvaluation'] = {
    'requests': len(chart_records), 'strictRepresentationMatches': sum(item['strictRepresentationMatch'] for item in chart_records),
    'exactSourceValues': chart_summary['all']['exactValuesCorrect'], 'expectedSourceValues': chart_summary['all']['expectedValues'],
    'unknownsCorrect': chart_summary['all']['unknownsCorrect'], 'expectedUnknowns': chart_summary['all']['expectedUnknowns'],
    'totalEstimateReportedUsageUsd': round(sum(item['estimateReportedUsageUsd'] for item in chart_records), 8),
    'totalEstimateWithRawInvocationUsageUsd': round(sum(item['estimateWithRawInvocationUsageUsd'] for item in chart_records), 8),
    'providerRequestMedianMs': statistics.median(chart_durations) if chart_durations else None,
    'providerRequestP95Ms': chart_durations[math.ceil(.95*len(chart_durations))-1] if chart_durations else None,
    'scoreMeaning': 'Strict chart representation match, not teacher-reviewed usability. See ai-chart-evaluation/INTERPRETATION.md for all retained mismatches.',
    'records': chart_records,
}
result['combinedCorpus'] = {
    'requests': len(records) + len(chart_records),
    'totalEstimateReportedUsageUsd': round(sum(item['estimateReportedUsageUsd'] for item in records + chart_records), 8),
    'totalEstimateWithRawInvocationUsageUsd': round(sum(item['estimateWithRawInvocationUsageUsd'] for item in records + chart_records), 8),
    'costPerTeacherReviewedUsablePackage': None,
}
(ROOT/'docs/evidence/provider-cost-estimates.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({key:value for key,value in result.items() if key not in ['records','limitations','rates','bundledSpeech','chartEvaluation']}, indent=2))
