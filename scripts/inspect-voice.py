"""Inspect a small, non-secret subset of the voice catalogue; never print credentials."""
import json
import os
import urllib.request

def get(path):
    req = urllib.request.Request('https://api.elevenlabs.io' + path, headers={'xi-api-key': os.environ['ELEVENLABS_API_KEY']})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)

voices = get('/v2/voices?page_size=100')['voices']
defaults = [v for v in voices if v.get('category') == 'premade']
chosen = next((v for v in defaults if v['name'].lower().startswith('rachel')), defaults[0] if defaults else None)
if not chosen:
    raise SystemExit('No premade licensed voice available; configure your own authorised voice.')
print(json.dumps({'voiceId': chosen['voice_id'], 'name': chosen['name'], 'category': chosen['category']}))
subscription = get('/v1/user/subscription')
print(json.dumps({'tier': subscription.get('tier'), 'status': subscription.get('status')}))
