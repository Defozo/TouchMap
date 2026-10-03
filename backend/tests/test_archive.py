import io
import zipfile
import wave
import pytest
from touchmap.errors import TouchMapError
from touchmap.models import Diagram, Audio
from touchmap.packages import portable_archive, build_package, validate_package, sha256
from touchmap.svg import convert_svg, render_preview


def test_compression_preserves_utf8_and_repetitive_assets_without_exceeding_ratio():
    files={"manifest.json":b"{}","diagram.json":b"{}","audio/powtórzenie.wav":bytes(2*1024*1024)}
    archive=portable_archive(files)
    assert len(archive)<1024*1024
    with zipfile.ZipFile(io.BytesIO(archive)) as opened:
        assert opened.namelist()==list(files)
        assert opened.testzip() is None
        for info in opened.infolist():
            assert opened.read(info)==files[info.filename]
            assert info.file_size<=max(1024*1024,info.compress_size*200)


def test_compression_can_export_more_than_50MiB_expanded():
    repeated=bytes(range(256))*(18*1024*1024//256)
    files={"manifest.json":b"{}","diagram.json":b"{}",**{f"audio/{name}.wav":repeated for name in "abc"}}
    archive=portable_archive(files)
    assert len(archive)<1024*1024
    with zipfile.ZipFile(io.BytesIO(archive)) as opened:
        assert sum(info.file_size for info in opened.infolist())>50*1024*1024
        assert opened.testzip() is None
        assert all(info.file_size<=max(1024*1024,info.compress_size*200) for info in opened.infolist())


def test_package_with_long_silent_pcm_recording_roundtrips():
    svg=b'<svg width="100" height="100"><rect id="box" width="20" height="20" aria-label="Box"/></svg>'
    diagram=Diagram.model_validate(convert_svg(svg)["diagram"])
    buffer=io.BytesIO()
    with wave.open(buffer,"wb") as output:
        output.setnchannels(1);output.setsampwidth(2);output.setframerate(24000);output.writeframes(bytes(24000*2*60))
    recording=buffer.getvalue()
    diagram.audio=[Audio(id="silent-recording",targetId=diagram.regions[0].id,kind="label",path="audio/silent.wav",sha256=sha256(recording),textHash=sha256(diagram.regions[0].label.encode()),durationMs=60000,language=diagram.language,provider="local",voice="recorded")]
    archive=build_package(diagram,{diagram.source.path:svg,diagram.source.previewPath:render_preview(svg),"audio/silent.wav":recording},"Author","Reviewed source","CC0")
    assert validate_package(archive)[3]["audio/silent.wav"]==recording


@pytest.mark.parametrize("path",["../escape","audio/CON.wav","audio/A.wav"])
def test_compression_rejects_unsafe_and_duplicate_paths(path):
    with pytest.raises(TouchMapError):
        portable_archive({"manifest.json":b"{}","diagram.json":b"{}","audio/a.wav":b"x",path:b"x"})
