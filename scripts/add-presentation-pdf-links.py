"""Preserve the rendered PDF and add clickable links that Office SaveAs omits."""
from pathlib import Path
import sys
from pypdf import PdfReader, PdfWriter
from pypdf.annotations import Link

path = Path(sys.argv[1])
reader = PdfReader(path)
assert len(reader.pages) == 10
writer = PdfWriter()
writer.clone_document_from_reader(reader)
for rect, url in [
    ((48, 337.5, 912, 378.75), 'https://github.com/Defozo/TouchMap'),
    ((48, 225, 912, 263.25), 'https://github.com/Defozo/TouchMap/releases/tag/v1.0.0'),
]:
    writer.add_annotation(9, Link(rect=rect, url=url))
temporary = path.with_suffix('.linked.pdf')
with temporary.open('wb') as stream:
    writer.write(stream)
temporary.replace(path)
