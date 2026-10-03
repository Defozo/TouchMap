"""Portable release audio is bounded PCM WAV, matching the native validator."""
import struct
from .errors import TouchMapError

def wav_duration(data: bytes) -> int:
    def invalid():
        raise TouchMapError("audio_invalid","Use an intact PCM WAV recording: mono/stereo, 8-192 kHz, 8/16/24/32 bits, at most 10 MiB")
    if not 44<=len(data)<=10*1024*1024 or data[:4]!=b"RIFF" or data[8:12]!=b"WAVE" or struct.unpack_from("<I",data,4)[0]+8!=len(data):invalid()
    position=12;rate=0;block=0;audio_bytes=-1
    while position+8<=len(data):
        kind=data[position:position+4];size=struct.unpack_from("<I",data,position+4)[0];start=position+8
        if start+size>len(data):invalid()
        if kind==b"fmt ":
            if rate or size<16:invalid()
            format,channels,sample_rate,rate,block,bits=struct.unpack_from("<HHIIHH",data,start)
            if format!=1 or channels not in (1,2) or not 8000<=sample_rate<=192000 or bits not in (8,16,24,32) or block!=channels*bits//8 or rate!=sample_rate*block:invalid()
        elif kind==b"data":
            if audio_bytes!=-1:invalid()
            audio_bytes=size
        position=start+size+size%2
    if position!=len(data) or not rate or audio_bytes<=0 or audio_bytes%block:invalid()
    duration=int(audio_bytes/rate*1000+.5)
    if not 1<=duration<=3600000:invalid()
    return duration
