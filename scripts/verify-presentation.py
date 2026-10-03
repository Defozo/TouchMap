"""Verify exact reviewed deck bytes, usable notes, citations, PDF text and links."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from pypdf import PdfReader
from presentation_artifacts import reviewed_presentation

root = Path(__file__).resolve().parents[1]
manifest_path = 'docs/evidence/presentation-manifest.json'
manifest = json.loads((root / manifest_path).read_text('utf-8-sig'))
details, _ = reviewed_presentation(root, {manifest_path: (root / manifest_path).read_bytes()})
notes = json.loads((root / 'docs/evidence/presentation-notes.json').read_text('utf-8-sig'))
pdf = PdfReader(root / manifest['pdf']['path'])
assert len(pdf.pages) == len(notes) == 10
assert pdf.metadata.author == 'DEFOZO SOFTWARE HOUSE / Michał Kiełtyka'
checks = []
native_tables = []
citations = set()
ns = {'p': 'http://schemas.openxmlformats.org/presentationml/2006/main',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}
with zipfile.ZipFile(root / manifest['pptx']['path']) as archive:
    for entry in notes:
        number = entry['slide']
        note = ET.fromstring(archive.read(f'ppt/notesSlides/notesSlide{number}.xml'))
        note_text = ''.join(note.itertext())
        assert entry['narration'] in note_text, f'Slide {number} lost narration'
        for citation in entry['citations']:
            assert citation in note_text
            if not citation.startswith('https://'):
                assert (root / citation).is_file(), citation
                citations.add(citation)
        source = ET.fromstring(archive.read(f'ppt/slides/slide{number}.xml'))
        if source.findall('.//a:tbl', ns):
            native_tables.append(number)
        page_text = re.sub(r'\s+', ' ', pdf.pages[number - 1].extract_text())
        assert entry['title'] in page_text, f'Slide {number} title missing in PDF'
        checks.append({'slide': number, 'notesMatchSource': True,
                       'narrationWords': len(entry['narration'].split()),
                       'pdfTitlePresent': True})
assert native_tables == [6, 8]
links = [a.get_object().get('/A', {}).get('/URI') for a in pdf.pages[-1].get('/Annots', [])]
assert 'https://github.com/Defozo/TouchMap' in links
assert 'https://github.com/Defozo/TouchMap/releases/tag/v1.0.1' in links
report = {'status': 'passed', 'artifacts': details, 'slideChecks': checks,
          'localCitationsChecked': len(citations), 'nativeTableSlides': native_tables,
          'pdfLinks': links, 'pdfAuthor': pdf.metadata.author,
          'limits': 'Structural and text checks do not replace the separately recorded visual review or anonymous public-link verification.'}
(root / 'docs/evidence/presentation-qc.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
print(json.dumps({'status': 'passed', 'slides': len(checks), 'notes': len(notes),
                  'localCitations': len(citations), 'nativeTableSlides': native_tables}))
