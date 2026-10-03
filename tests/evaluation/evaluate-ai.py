"""Run a bounded, explicit owned-image evaluation through the product adapter.

Run using backend's environment, via psst GOOGLE_AI_STUDIO_API_KEY.
Preserves unsuccessful inputs in the denominator. Does not grade teacher effort.
"""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'backend'))
from touchmap.settings import Settings
from touchmap.providers import Providers
from touchmap.errors import TouchMapError
from touchmap.images import normalize_image

ROOT=Path(__file__).resolve().parents[2]
def normalized(s):return ' '.join(s.lower().strip().split())
async def evaluate(args):
    truth=json.loads((ROOT/'tests/evaluation/corpus/truth.json').read_text())
    cfg=Settings(ai_enabled=True);cfg.validate();provider=Providers(cfg);records=[]
    output=ROOT/'docs/evidence/ai-evaluation';output.mkdir(parents=True,exist_ok=True)
    for item in truth[:args.limit]:
        path=output/(item['id']+'.json')
        if path.exists() and not args.refresh:
            records.append(json.loads(path.read_text()));continue
        start=time.monotonic();result={'id':item['id'],'variant':item['variant'],'split':item['split'],'model':cfg.gemini_model,'schemaSuccess':False,'usableDraft':False,'labelRecall':0,'directionAccuracy':0}
        try:
            data,w,h=normalize_image((ROOT/'tests/evaluation/corpus'/item['imageFile']).read_bytes())
            response=await provider.analyze(data,w,h,1,'en');d=response['diagram']
            (output/(item['id']+'.draft.json')).write_text(json.dumps(d,indent=2),encoding='utf-8')
            labels={normalized(r['label']):r['id'] for r in d['regions']}
            matched=[labels.get(normalized(label)) for label in item['labels']]
            correct=sum(1 for relation in item['relations'] if any(r['fromId']==matched[relation['fromIndex']] and r['toId']==matched[relation['toIndex']] and r['direction']==relation['direction'] for r in d['relations']))
            critical_label_count=sum(bool(m) for m in matched)
            exact_directions=correct==len(item['relations'])
            # Ambiguous cases must retain unknowns, not infer arrow direction.
            unsupported_numeric=any(v['value'] is not None for c in d['charts'] for s in c['series'] for v in s['values'])
            result.update(schemaSuccess=True,labelRecall=critical_label_count/len(matched),directionAccuracy=correct/len(item['relations']),regionCount=len(d['regions']),relationCount=len(d['relations']),unsupportedNumericFacts=unsupported_numeric,usableDraft=critical_label_count==len(matched) and exact_directions and not unsupported_numeric,report=response['report'],usage=response.get('usage'))
        except TouchMapError as exc:result['error']={'code':exc.code,'message':exc.message}
        result['durationMs']=round((time.monotonic()-start)*1000);path.write_text(json.dumps(result,indent=2),encoding='utf-8');records.append(result)
        print(json.dumps({k:result.get(k) for k in ['id','schemaSuccess','usableDraft','durationMs','error']}),flush=True)
    def aggregate(items):
        n=len(items);return {'inputs':n,'schemaSuccesses':sum(x['schemaSuccess'] for x in items),'usableDrafts':sum(x['usableDraft'] for x in items),'usableDraftRate':sum(x['usableDraft'] for x in items)/n if n else None,'labelRecallMean':sum(x['labelRecall'] for x in items)/n if n else None,'directionAccuracyMean':sum(x['directionAccuracy'] for x in items)/n if n else None}
    report={'model':cfg.gemini_model,'scope':'Owned small process diagrams only. Exact-label scoring; no human review or representative participant study. Unknown arrows counted explicitly. All requests retained in denominator.','all':aggregate(records),'heldOut':aggregate([x for x in records if x['split']=='held-out']),'clearHeldOut':aggregate([x for x in records if x['split']=='held-out' and x['variant']=='clear']),'records':records,'authorTime':None,'editCount':None,'actualProviderInvoiceCost':None,'costNote':'Raw provider usage is retained where supplied. No author time, correction time or billed cost was measured.'}
    (output/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps({k:report[k] for k in ['all','heldOut','clearHeldOut']}))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--limit',type=int,default=20);parser.add_argument('--refresh',action='store_true');args=parser.parse_args()
    if not 1<=args.limit<=20:raise SystemExit('Limit must be between1 and20')
    asyncio.run(evaluate(args))
