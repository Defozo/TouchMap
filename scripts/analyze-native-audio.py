import json, math, statistics
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

root = Path(__file__).resolve().parents[1]
evidence = root / 'docs/evidence'
report = json.loads((evidence / 'native-audio-benchmark.json').read_text())
artifact = json.loads((evidence / 'native-audio-test-artifact.json').read_text())
inputs = json.loads((evidence / 'stage-input-fingerprint.json').read_text())
load = json.loads((evidence / 'native-audio-host.json').read_text())
measurements = report['measurements']
def summary(values):
    values = sorted(values)
    return {'count':len(values),'median':statistics.median(values),'p95':values[math.ceil(len(values)*.95)-1],'max':max(values)}
phases = ['integrityMs','controlWaitMs','prepareMs','volumeMs','startMs','firstWriteDispatchMs','firstWriteResolveMs']
start, finish = (datetime.fromisoformat(load[key]['at']) for key in ['before','after'])
host_rows = []
for line in (evidence / 'native-audio-host-vmstat.txt').read_text().splitlines():
    fields = line.split()
    if len(fields) != 19 or not fields[0].isdigit():
        continue
    at = datetime.fromisoformat(' '.join(fields[-2:])).replace(tzinfo=ZoneInfo('Europe/Warsaw'))
    if start <= at <= finish:
        host_rows.append([int(value) for value in fields[:17]])
result = {'status':report['status'],'requested':report['requested'],'succeeded':report['succeeded'],
          'productionHapSha256':artifact['productionHapSha256'],'testHapSha256':artifact['testHapSha256'],
          'appSourceSha256':artifact['sourceFingerprint']['appSourceSha256'],
          'audioImplementationInputs':[item for item in inputs['files'] if item['path'] in ['entry/src/main/ets/platform/Feedback.ets','entry/src/main/ets/domain/media.ts']],
          'onsetMs':summary([item['onsetMs'] for item in measurements]),
          'totalWithDwellMs':summary([item['scheduledLabelToPlayingMs'] for item in measurements]),
          'phaseMilliseconds':{key:summary([item['trace'][key] for item in measurements]) for key in phases},
          'bufferBytes':sorted({item['trace']['bufferBytes'] for item in measurements}),
          'bufferDurationMs':sorted({item['trace']['bufferDurationMs'] for item in measurements}),
          'coldCacheReads':sum(not item['trace']['cacheHit'] for item in measurements),
          'allFirstWritesAccepted':all(item['trace']['writeAttemptsBeforeOnset']==1 for item in measurements),
          'firstPlayback':measurements[0],
          'hostWindow':{'startUtc':load['before']['at'],'endUtc':load['after']['at'],'vmstatTimestampZone':'Europe/Warsaw (CEST header)',
                        'samples':len(host_rows),'cpuIdlePercent':summary([row[14] for row in host_rows]),
                        'cpuIoWaitPercent':summary([row[15] for row in host_rows]),'cpuStealPercent':summary([row[16] for row in host_rows])},
          'excludedPriorRun':{'file':'audio-idle-with-draft-fixture.json','reason':'The earlier runner included an unfinished authored draft. Four target regions had no recording. Its measurements and higher host load remain preserved as diagnostic evidence, not an acceptance run.'},
          'interpretation':'Prepared-material playback reports accepted native PCM writes, not acoustic onset. The phase distributions and first-playback fields distinguish integrity work, renderer start and write resolution. The final transport-tail fix pads only chunks of at most four bytes with frame-aligned silence; verified source bytes are unchanged. Host and fixture conditions differ from older diagnostic runs, so results are not attributed to one change alone.',
          'scope':report['scope']}
(evidence / 'native-audio-phase-analysis.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
