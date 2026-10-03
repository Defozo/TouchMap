"""Deliberate process exit for durable backend job state verification."""
import os
import sys
from pathlib import Path
from touchmap.settings import Settings
from touchmap.store import Store

store=Store(Settings(state_dir=Path(sys.argv[1])))
request_id="crash-"+sys.argv[2]
store.begin(request_id,"crash-test",request_id)
if sys.argv[3]=="complete":store.finish(request_id,{"acknowledged":True,"requestId":request_id})
os._exit(17)
