"""Reconstruct acknowledged restoration samples and summarize the split native run."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/evidence'


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding='utf-8-sig'))


def stats(values):
    values = sorted(values)
    return {'count': len(values), 'p95Ms': values[(95 * len(values) + 99) // 100 - 1],
            'maxMs': values[-1], 'minMs': values[0]}


def main():
    progress = read('native-restore-run1-progress.json')
    acknowledged = progress['completed']
    recovered = {}
    for line in (EVIDENCE / 'native-restore-run1-hilog.txt').read_text(encoding='utf-8-sig').splitlines():
        if 'TOUCHMAP_RESTORE_RENDER ' in line:
            sample = json.loads(line.split('TOUCHMAP_RESTORE_RENDER ', 1)[1])
            recovered[sample['sequence']] = sample
    if not set(range(1, acknowledged + 1)).issubset(recovered):
        raise RuntimeError('Some acknowledged native observations are missing from the retained log.')
    first = [dict(recovered[index], runId='run1', uiCheck='Native Resume heading verified before fsynced acknowledgement')
             for index in range(1, acknowledged + 1)]
    first_report = {'status': 'interrupted-by-uitest-stall', 'requested': progress['total'],
                    'acknowledgedSamples': acknowledged, 'samples': first,
                    'excludedObservations': [value for key, value in sorted(recovered.items()) if key > acknowledged],
                    'recovery': 'Only sequence numbers at or below the fsynced native progress count are accepted. These follow full Progress comparison and a successful native Resume heading lookup. The subsequent sample rendered but its heading lookup stalled; it is excluded. Restarting the owned UiTest daemon did not resolve the pending RPC, so the test process was stopped.'}
    (EVIDENCE / 'native-restore-run1.json').write_text(json.dumps(first_report, indent=2) + '\n')
    second = read('native-restore-run2.json')
    if second['status'] != 'passed' or len(second['samples']) != second['count']:
        raise RuntimeError('The continuation run did not complete all its UI checks.')
    samples = first + [dict(sample, runId='run2', uiCheck='Native Resume heading verified in completed runner')
                       for sample in second['samples']]
    if len(samples) != 100:
        raise RuntimeError('Exactly 100 acknowledged samples are required.')
    artifacts = [read('native-restore-run1-artifact.json'), read('native-restore-run2-artifact.json')]
    for field in ['productionHapSha256', 'testHapSha256', 'sourceFingerprint']:
        if artifacts[0][field] != artifacts[1][field]:
            raise RuntimeError('The two runs used different native artifacts: ' + field)
    expected = samples[0]['progress']
    for sample in samples:
        if sample['page'] != 'Resume' or sample['progress'] != expected:
            raise RuntimeError('The full restored context differs between acknowledged samples.')
        if not sample['intentAtMs'] <= sample['stateAppliedAtMs'] <= sample['layoutDoneAtMs'] <= sample['drawCommandAtMs']:
            raise RuntimeError('An acknowledged sample has invalid state/layout/draw ordering.')
        if sample['durationMs'] != sample['drawCommandAtMs'] - sample['intentAtMs']:
            raise RuntimeError('Recorded duration disagrees with the actual callback timestamps.')
    timings = stats([sample['durationMs'] for sample in samples])
    idle = [sample['idleDurationMs'] for sample in samples if sample['idleAtMs'] > 0]
    report = {'status': 'passed' if timings['p95Ms'] < 1000 else 'failed', 'count': 100,
              'runCount': 2, 'p95Ms': timings['p95Ms'], 'maxMs': timings['maxMs'],
              'idleP95Ms': stats(idle)['p95Ms'] if idle else 0, 'idleSamples': len(idle),
              'scope': '100 actual active-app Library open intents across two native runs after an explicit UiTest harness restart (92 + 8). Every included sample passed complete saved Progress equality and native Resume-heading verification. Timing ends at ArkUI willDraw after layout; it excludes physical display scanout, human selection and cold process launch. The unacknowledged 93rd observation from the interrupted run is retained separately and excluded.',
              'phaseStatistics': {
                  'intentToCheckpointLoaded': stats([s['checkpointLoadedAtMs'] - s['intentAtMs'] for s in samples]),
                  'checkpointLoadedToStateApplied': stats([s['stateAppliedAtMs'] - s['checkpointLoadedAtMs'] for s in samples]),
                  'stateAppliedToLayoutDone': stats([s['layoutDoneAtMs'] - s['stateAppliedAtMs'] for s in samples]),
                  'layoutDoneToDrawCommand': stats([s['drawCommandAtMs'] - s['layoutDoneAtMs'] for s in samples])},
              'samples': samples, 'error': ''}
    (EVIDENCE / 'native-restore-benchmark.json').write_text(json.dumps(report, indent=2) + '\n')
    evidence_names = ['native-restore-run1.json', 'native-restore-run1-progress.json', 'native-restore-run1-hilog.txt',
                      'native-restore-run1-artifact.json', 'native-restore-run1-host-vmstat.txt',
                      'native-restore-run2.json', 'native-restore-run2-artifact.json', 'native-restore-run2-host-vmstat.txt']
    artifact = {'status': report['status'], 'device': artifacts[0]['device'],
                'startedUtc': artifacts[0]['startedUtc'], 'finishedUtc': artifacts[1]['finishedUtc'],
                'productionHapSha256': artifacts[0]['productionHapSha256'], 'testHapSha256': artifacts[0]['testHapSha256'],
                'sourceFingerprint': artifacts[0]['sourceFingerprint'], 'runs': artifacts,
                'evidenceSha256': {name: hashlib.sha256((EVIDENCE / name).read_bytes()).hexdigest() for name in evidence_names}}
    (EVIDENCE / 'native-restore-artifact.json').write_text(json.dumps(artifact, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'samples'}, indent=2))
    if report['status'] != 'passed':
        raise SystemExit('The restoration p95 target was not met.')


if __name__ == '__main__':
    main()
