"""Bind a reviewed presentation to its exact portable PDF and editable PPTX bytes."""
from __future__ import annotations
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

MANIFEST = 'docs/evidence/presentation-manifest.json'
MAX_ARTIFACT_BYTES = 10_000_000
PRESENTATION_NS = 'http://schemas.openxmlformats.org/presentationml/2006/main'
DRAWING_NS = 'http://schemas.openxmlformats.org/drawingml/2006/main'
REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships'
OFFICE_REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'


def inspect_pdf(path: Path) -> int:
    executable = shutil.which('pdfinfo')
    if not executable:
        raise ValueError('pdfinfo is required to verify presentation pages; install Poppler utilities')
    result = subprocess.run([executable, str(path)], capture_output=True, text=True, timeout=30,
                            env={**os.environ, 'LC_ALL': 'C'})
    match = re.search(r'^Pages:\s+(\d+)\s*$', result.stdout, re.MULTILINE)
    if result.returncode or not match:
        raise ValueError('Presentation PDF is unreadable or has no verifiable page count')
    return int(match.group(1))


def inspect_pptx(data: bytes) -> tuple[int, int]:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Presentation PPTX contains duplicate archive entries')

        def xml(name: str):
            info = archive.getinfo(name)
            if info.file_size > 2 * 1024 * 1024:
                raise ValueError('Presentation XML part exceeds the 2 MiB metadata bound')
            value = archive.read(name)
            if b'<!DOCTYPE' in value.upper() or b'<!ENTITY' in value.upper():
                raise ValueError('Presentation XML declarations are not permitted')
            try:
                return ET.fromstring(value)
            except ET.ParseError as error:
                raise ValueError('Presentation contains malformed XML') from error

        def target(base: str, relation) -> str:
            value = relation.get('Target', '')
            if relation.get('TargetMode') == 'External' or not value or '\\' in value or ':' in value:
                raise ValueError('Presentation slide/notes relationship must reference an internal part')
            name = posixpath.normpath(posixpath.join(posixpath.dirname(base), value))
            if name.startswith('/') or name.startswith('../'):
                raise ValueError('Presentation relationship escapes its package')
            return name

        # The editable slide list is authoritative, rather than filenames alone.
        xml('[Content_Types].xml')
        xml('_rels/.rels')
        presentation = xml('ppt/presentation.xml')
        if presentation.tag != f'{{{PRESENTATION_NS}}}presentation':
            raise ValueError('Presentation PPTX has an invalid presentation root')
        slides = presentation.findall(f'{{{PRESENTATION_NS}}}sldIdLst/{{{PRESENTATION_NS}}}sldId')
        relations = xml('ppt/_rels/presentation.xml.rels')
        relation_map = {item.get('Id'): item for item in relations.findall(f'{{{REL_NS}}}Relationship')}
        if len(relation_map) != len(relations.findall(f'{{{REL_NS}}}Relationship')):
            raise ValueError('Presentation contains duplicate relationship identifiers')
        slide_parts = []
        note_parts = []
        for slide_id in slides:
            relation = relation_map.get(slide_id.get(f'{{{OFFICE_REL_NS}}}id'))
            if relation is None or relation.get('Type') != f'{OFFICE_REL_NS}/slide':
                raise ValueError('Presentation PPTX has an unresolved slide relationship')
            slide_name = target('ppt/presentation.xml', relation)
            if slide_name in slide_parts or xml(slide_name).tag != f'{{{PRESENTATION_NS}}}sld':
                raise ValueError('Presentation PPTX slide parts are duplicate or invalid')
            slide_parts.append(slide_name)
            slide_path = PurePosixPath(slide_name)
            relation_name = str(slide_path.parent / '_rels' / (slide_path.name + '.rels'))
            notes = [item for item in xml(relation_name).findall(f'{{{REL_NS}}}Relationship')
                     if item.get('Type') == f'{OFFICE_REL_NS}/notesSlide']
            if len(notes) != 1:
                raise ValueError('Every presentation slide must have speaker notes')
            note_name = target(slide_name, notes[0])
            note = xml(note_name)
            if note.tag != f'{{{PRESENTATION_NS}}}notes':
                raise ValueError('Presentation speaker notes have an invalid root')
            # A slide-number placeholder is not a speaker script.
            bodies = [shape for shape in note.findall(f'.//{{{PRESENTATION_NS}}}sp')
                      if any(ph.get('type') == 'body' for ph in shape.findall(f'.//{{{PRESENTATION_NS}}}ph'))]
            if note_name in note_parts or not any(
                    ''.join(shape.itertext()).strip() and any((item.text or '').strip()
                    for item in shape.findall(f'.//{{{DRAWING_NS}}}t')) for shape in bodies):
                raise ValueError('Every presentation slide needs distinct nonempty speaker notes')
            note_parts.append(note_name)
        return len(slide_parts), len(note_parts)


def reviewed_presentation(root: Path, committed_files: dict[str, bytes]) -> tuple[dict | None, dict[str, bytes]]:
    """Absence is allowed only for earlier releases without a declared presentation."""
    if MANIFEST not in committed_files:
        if (root / MANIFEST).exists():
            raise ValueError('Presentation manifest exists but is not committed; freeze it before release')
        return None, {}
    manifest_bytes = committed_files[MANIFEST]
    manifest = json.loads(manifest_bytes)
    if not isinstance(manifest, dict) or manifest.get('reviewed') is not True:
        raise ValueError('Presentation has no completed committed review')
    count = manifest.get('slideCount')
    if manifest.get('language') != 'en' or type(count) is not int or not 1 <= count <= 10:
        raise ValueError('Reviewed presentation must be English with 1 to 10 slides')
    result = {'reviewed': True, 'language': 'en', 'slideCount': count,
              'manifestSha256': hashlib.sha256(manifest_bytes).hexdigest()}
    assets = {}
    for kind in ['pdf', 'pptx']:
        item = manifest.get(kind)
        if not isinstance(item, dict) or not isinstance(item.get('path'), str):
            raise ValueError(f'Presentation manifest must identify its {kind.upper()} artifact')
        relative = PurePosixPath(item['path'])
        if (relative.is_absolute() or '..' in relative.parts or '\\' in item['path'] or ':' in item['path']
                or not relative.parts or relative.parts[0] != 'dist' or relative.suffix != '.' + kind):
            raise ValueError('Presentation artifacts must use safe dist-relative PDF/PPTX paths')
        path = root.joinpath(*relative.parts)
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f'Missing or empty presentation {kind.upper()}: {relative}')
        if path.stat().st_size > MAX_ARTIFACT_BYTES:
            raise ValueError(f'Presentation {kind.upper()} exceeds the 10 MB upload limit')
        if not path.resolve().is_relative_to(root.resolve() / 'dist'):
            raise ValueError('Presentation artifact resolves outside the release dist directory')
        data = path.read_bytes()
        if len(data) > MAX_ARTIFACT_BYTES:
            raise ValueError(f'Presentation {kind.upper()} exceeds the 10 MB upload limit')
        digest = hashlib.sha256(data).hexdigest()
        if item.get('sha256') != digest:
            raise ValueError(f'Presentation {kind.upper()} hash differs from the reviewed committed manifest')
        bundle_path = 'presentation/' + relative.name
        details = {'path': relative.as_posix(), 'bundlePath': bundle_path,
                   'sha256': digest, 'bytes': len(data)}
        if kind == 'pdf':
            if not data.startswith(b'%PDF-'):
                raise ValueError('Presentation PDF has an invalid file signature')
            pages = inspect_pdf(path)
            # Recheck after pdfinfo so the archived bytes are the inspected bytes.
            if path.read_bytes() != data:
                raise ValueError('Presentation PDF changed during verification')
            if pages != count:
                raise ValueError('Presentation PDF page count differs from its reviewed slide count')
            details['pages'] = pages
        else:
            slides, notes = inspect_pptx(data)
            if slides != count:
                raise ValueError('Presentation PPTX slide count differs from its reviewed slide count')
            details.update({'slides': slides, 'notes': notes})
        assets[bundle_path] = data
        result[kind] = details
    return result, assets
