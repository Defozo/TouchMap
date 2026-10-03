"""Start a separately provisioned Oniro image as a second installation target.

First provision it with:
ONIRO_EMULATOR_DIR=$HOME/oniro-emulator-clean oniro-app emulator install
"""
import subprocess
from pathlib import Path

root = Path.home() / "oniro-emulator-clean" / "images"
launcher = root / "run.sh"
if not launcher.exists():
    raise SystemExit("Install the separate clean emulator image first.")
log = Path.home() / ".cache" / "touchmap-clean-emulator.log"
log.parent.mkdir(parents=True, exist_ok=True)
with log.open("ab") as stream:
    process = subprocess.Popen(
        ["bash", str(launcher), "--headless", "--connect", "127.0.0.1:55556", "--vnc-display", "1", "--serial-port", "4445"],
        stdin=subprocess.DEVNULL, stdout=stream, stderr=stream,
        start_new_session=True, close_fds=True,
    )
print(f"Second emulator started, PID {process.pid}; HDC127.0.0.1:55556, VNC5901. Log: {log}")
