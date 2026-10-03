"""Keep the HDC server alive across separate WSL invocations."""
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

def listening():
    try:
        with socket.create_connection(("127.0.0.1", 8710), timeout=0.3):
            return True
    except OSError:
        return False

if not listening():
    log = Path.home() / ".cache" / "touchmap-hdc.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("ab") as output:
        subprocess.Popen(
            [sys.argv[1], "-l", "2", "-m"],
            stdin=subprocess.DEVNULL, stdout=output, stderr=output,
            start_new_session=True, close_fds=True,
        )
    for _ in range(30):
        if listening():
            break
        time.sleep(0.1)
    else:
        raise SystemExit("HDC server did not start. Inspect ~/.cache/touchmap-hdc.log.")
