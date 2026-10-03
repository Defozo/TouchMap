"""Record the actual local Oniro VNC framebuffer to MP4, without a web preview.

Usage (WSL): python3 scripts/record-emulator.py --seconds 180 --output dist/demo.mp4
The default output has no audio. Use --pulse-audio only after verifying the host
PulseAudio monitor carries the emulator audio; this records that entire monitor.
"""
import argparse
import socket
import struct
import subprocess
import time
import json
from datetime import datetime, timezone
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--host", default="127.0.0.1")
parser.add_argument("--port", type=int, default=5900)
parser.add_argument("--seconds", type=float, default=180)
parser.add_argument("--fps", type=int, default=10)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--pulse-audio", action="store_true")
args = parser.parse_args()
if args.fps < 1 or args.fps > 30 or args.seconds <= 0:
    parser.error("Use 1-30 fps and a positive duration.")
args.output.parent.mkdir(parents=True, exist_ok=True)

with socket.create_connection((args.host, args.port), timeout=10) as remote:
    def receive(count):
        buffer = bytearray()
        while len(buffer) < count:
            chunk = remote.recv(count - len(buffer))
            if not chunk:
                raise EOFError("The emulator VNC server disconnected.")
            buffer.extend(chunk)
        return bytes(buffer)

    protocol = receive(12)
    if not protocol.startswith(b"RFB "):
        raise RuntimeError("Not a VNC framebuffer server.")
    remote.sendall(b"RFB 003.008\n")
    security_types = receive(receive(1)[0])
    if 1 not in security_types:
        raise RuntimeError("This recorder supports only the local no-auth emulator.")
    remote.sendall(b"\x01")
    if struct.unpack(">I", receive(4))[0] != 0:
        raise RuntimeError("VNC handshake failed.")
    remote.sendall(b"\x01")
    width, height = struct.unpack(">HH", receive(4))
    receive(16)
    title = receive(struct.unpack(">I", receive(4))[0]).decode("utf-8", "replace")
    # 32-bit little-endian RGB888. The wire order is B,G,R,unused.
    remote.sendall(b"\x00\x00\x00\x00" + struct.pack(">BBBBHHHBBBxxx", 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
    remote.sendall(struct.pack(">BBHi", 2, 0, 1, 0))  # raw rectangles only
    command = ["ffmpeg", "-y", "-loglevel", "warning", "-f", "rawvideo", "-pixel_format", "bgra", "-video_size", f"{width}x{height}", "-framerate", str(args.fps), "-i", "pipe:0"]
    if args.pulse_audio:
        command += ["-f", "pulse", "-i", "@DEFAULT_MONITOR@", "-c:a", "aac", "-shortest"]
    command += ["-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(args.output)]
    framebuffer = bytearray(width * height * 4)
    encoder = subprocess.Popen(command, stdin=subprocess.PIPE)
    started = time.monotonic()
    started_utc = datetime.now(timezone.utc).isoformat()
    frames = 0
    captures = 0
    last_frame = None
    frame_limit = round(args.seconds * args.fps)
    try:
        while frames < frame_limit and time.monotonic() - started < args.seconds:
            remote.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, width, height))
            while True:
                kind = receive(1)[0]
                if kind == 0:
                    receive(1)
                    rectangle_count = struct.unpack(">H", receive(2))[0]
                    for _ in range(rectangle_count):
                        x, y, rectangle_width, rectangle_height, encoding = struct.unpack(">HHHHi", receive(12))
                        if encoding != 0:
                            raise RuntimeError(f"Unexpected framebuffer encoding {encoding}.")
                        data = receive(rectangle_width * rectangle_height * 4)
                        for row in range(rectangle_height):
                            offset = ((y + row) * width + x) * 4
                            source = row * rectangle_width * 4
                            framebuffer[offset:offset + rectangle_width * 4] = data[source:source + rectangle_width * 4]
                    break
                if kind == 2:  # bell
                    continue
                if kind == 3:  # clipboard text, ignored
                    receive(3)
                    receive(struct.unpack(">I", receive(4))[0])
                    continue
                raise RuntimeError(f"Unexpected VNC message {kind}.")
            captures += 1
            # A slow VNC response must not turn real interaction into an
            # unlabelled timelapse. Hold the previous actual frame for missed
            # wall-clock slots; never synthesize application state.
            target = min(frame_limit, int((time.monotonic() - started) * args.fps) + 1)
            if last_frame is None:
                last_frame = bytes(framebuffer)
            while frames < max(frames, target - 1):
                encoder.stdin.write(last_frame)
                frames += 1
            if frames < target:
                encoder.stdin.write(framebuffer)
                frames += 1
            last_frame = bytes(framebuffer)
            time.sleep(max(0, started + frames / args.fps - time.monotonic()))
        while frames < frame_limit and last_frame is not None:
            encoder.stdin.write(last_frame)
            frames += 1
    finally:
        encoder.stdin.close()
        result = encoder.wait(timeout=30)
    if result:
        raise SystemExit(result)
    args.output.with_suffix('.capture.json').write_text(json.dumps({
        'startedUtc': started_utc, 'wallSeconds': time.monotonic() - started,
        'videoSeconds': frames / args.fps, 'encodedFrames': frames, 'actualCaptures': captures,
        'policy': 'Wall-clock recording with held last actual framebuffer for missed VNC deadlines',
        'framebuffer': {'width': width, 'height': height, 'serverTitle': title},
        'audio': 'Entire default PulseAudio monitor' if args.pulse_audio else 'No audio in this file'
    }, indent=2) + '\n')
    print(f"Recorded {frames} actual framebuffer frames from {title}, {width}x{height}, to {args.output}.")
