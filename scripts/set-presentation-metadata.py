"""Set attribution on an Artifact Tool candidate before its finalizer checks it."""
from pathlib import Path
import sys
import re
from xml.sax.saxutils import escape
import zipfile

path = Path(sys.argv[1])
with zipfile.ZipFile(path) as archive:
    entries = [(item, archive.read(item.filename)) for item in archive.infolist()]
with zipfile.ZipFile(path, 'w') as archive:
    for item, value in entries:
        if item.filename == 'docProps/core.xml':
            xml = value.decode('utf-8-sig')
            for field, text in [('title', 'TouchMap'), ('creator', 'DEFOZO SOFTWARE HOUSE / Michał Kiełtyka'),
                                ('subject', 'Native OpenHarmony diagram exploration'), ('language', 'en')]:
                tag = 'dc:' + field
                replacement = f'<{tag}>{escape(text)}</{tag}>'
                # Preserve namespace declarations used by QName attribute values.
                if f'<{tag}>' in xml:
                    xml = re.sub(f'<{tag}>.*?</{tag}>', replacement, xml, flags=re.DOTALL)
                else:
                    xml = xml.replace('</coreProperties>', replacement + '</coreProperties>')
            xml = xml.replace('<lastModifiedBy>Walnut Exporter</lastModifiedBy>',
                              '<lastModifiedBy>DEFOZO SOFTWARE HOUSE</lastModifiedBy>')
            value = xml.encode('utf-8')
        archive.writestr(item, value)
