import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

// Uses the supplied Presentations runtime. See docs/PRESENTATION.md.
const workspaceDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SKILL_DIR = process.env.SKILL_DIR;
const RUNTIME_PYTHON = process.env.RUNTIME_PYTHON;
if (!SKILL_DIR || !RUNTIME_PYTHON) throw new Error('Set SKILL_DIR, RUNTIME_PYTHON and RUNTIME_NODE_MODULES to the supplied runtime.');
const { importRuntimeModule } = await import(pathToFileURL(path.join(SKILL_DIR, 'container_tools/runtime_helpers.mjs')).href);
const { Presentation, PresentationFile } = await importRuntimeModule('@oai/artifact-tool');
const { finalizePresentation } = await import(pathToFileURL(path.join(SKILL_DIR, 'container_tools/artifact_tool_utils.mjs')).href);
const revision = process.env.DECK_REVISION ?? 'v1';
const buildDir = path.join(workspaceDir, '.local/presentation', revision);
const candidatePath = path.join(buildDir, 'candidate.pptx');
const finalPath = path.join(workspaceDir, 'dist', `touchmap-presentation-${revision}.pptx`);
await fs.mkdir(buildDir, { recursive: true });
await fs.mkdir(path.dirname(finalPath), { recursive: true });
const p = Presentation.create({ slideSize: { width: 1280, height: 720 } });
const C = { bg: '#071E2A', text: '#F5FAFC', muted: '#B9CDD5', mint: '#8EDFCC', table: '#10313F', border: '#35606E' };
p.theme.colorScheme = { name: 'TouchMap', themeColors: {
  accent1: C.mint, accent2: '#6EB7FF', accent3: '#E5BF85', accent4: '#EFB1B1', accent5: '#C0B9EF', accent6: '#90D6AA',
  bg1: C.bg, bg2: C.table, tx1: C.text, tx2: C.muted, dk1: C.bg, dk2: C.table, lt1: C.text, lt2: C.muted,
  hlink: C.mint, folHlink: C.mint
} };
const font = 'Arial';
const notes = [];
const sources = [];
function text(slide, value, x, y, w, h, size = 28, color = C.text, bold = false) {
  const sh = slide.shapes.add({ geometry: 'textbox', name: value.slice(0, 60), position: { left: x, top: y, width: w, height: h }, fill: 'none', line: { fill: 'none', width: 0 } });
  sh.text = value;
  sh.text.style = { typeface: font, fontSize: size, color, bold, wrap: 'square', autoFit: 'none', verticalAlignment: 'top', insets: { left: 0, right: 0, top: 0, bottom: 0 } };
  return sh;
}
function slide(title, narration, citations = []) {
  const s = p.slides.add();
  s.background.fill = C.bg;
  const number = p.slides.items.length;
  if (title) text(s, title, 64, 48, 1136, 70, 48, C.text, true);
  text(s, number === 1 ? 'Native OpenHarmony emulator demo' : 'TouchMap', 64, 679, 700, 22, 16, C.muted);
  text(s, String(number).padStart(2, '0'), 1164, 679, 50, 22, 16, C.muted);
  const full = narration + '\n\nSources and evidence:\n' + citations.join('\n');
  s.speakerNotes.textFrame.setText(full);
  notes.push({ slide: number, title: title || 'TouchMap', narration, citations });
  return s;
}
async function photo(s, relative, x, y, w, h, alt) {
  const data = await fs.readFile(path.join(workspaceDir, relative));
  s.images.add({ blob: new Uint8Array(data), contentType: relative.endsWith('.png') ? 'image/png' : 'image/jpeg', alt, fit: 'contain', position: { left: x, top: y, width: w, height: h } });
  sources.push({ slide: p.slides.items.length, path: relative, sha256: createHash('sha256').update(data).digest('hex'), alt });
}
function section(s, heading, body, y, width = 700) {
  text(s, heading, 64, y, width, 38, 29, C.mint, true);
  text(s, body, 64, y + 45, width, 85, 27);
}
function table(s, values, top, rowHeights, widths) {
  const t = s.tables.add({ rows: values.length, columns: values[0].length, left: 64, top, width: 1152, height: rowHeights.reduce((a, b) => a + b, 0), columnWidths: widths, values });
  t.styleOptions = { headerRow: false, bandedRows: false };
  t.borders.assign({ fill: C.border, width: 1, style: 'solid' });
  for (let r = 0; r < values.length; r++) {
    t.rows[r].height = rowHeights[r];
    for (let c = 0; c < values[0].length; c++) {
      const cell = t.getCell(r, c);
      cell.fill = r === 0 ? C.table : C.bg;
      cell.text.style = { typeface: font, fontSize: 25, bold: r === 0, color: r === 0 ? C.mint : C.text, autoFit: 'none' };
    }
  }
  t.cells.block({ row: 0, column: 0, rowCount: values.length, columnCount: values[0].length }).assign({ margins: { top: 14, bottom: 12, left: 18, right: 16 }, anchor: 'center' });
  return t;
}

{
  const s = slide('',
    'TouchMap turns a diagram into a lesson the learner can explore by touch and sound. A learner chooses an object, hears its description and follows its connections. Teachers prepare and review the material. The lesson then works offline, including questions and saved progress. This native OpenHarmony app is designed for blind and low-vision learners. DEFOZO SOFTWARE HOUSE presents TouchMap, created by Michał Kiełtyka. The screenshots show the running native app on an emulator.',
    ['TEAM.json', 'SUBMISSION.md', 'docs/ACCESSIBILITY.md', 'docs/evidence/pitch-library-capture.json', 'docs/evidence/pitch-library.png']);
  text(s, 'TouchMap', 64, 150, 740, 118, 92, C.text, true);
  text(s, 'Diagrams you can explore\nby touch and sound', 68, 290, 700, 134, 42, C.mint);
  text(s, 'DEFOZO SOFTWARE HOUSE', 68, 524, 725, 34, 27, C.text, true);
  text(s, 'Michał Kiełtyka', 68, 568, 700, 36, 28, C.muted);
  await photo(s, 'docs/evidence/pitch-library.png', 885, 40, 306, 612, 'Actual TouchMap Library captured from installed HAP 1cae6f5da819, built from source 943a5d8.');
}
{
  const s = slide('The next step in a diagram',
    'Imagine studying the water cycle without seeing its arrows. Hearing each label still leaves a question: what comes next? TouchMap lets the learner choose condensation and follow the connection to precipitation. They can replay a description, return to an earlier object and check their understanding with a question. The original diagram stays attached to the lesson so the teacher can review each connection against its source.',
    ['SUBMISSION.md', 'docs/STUDY_PROTOCOL.md', 'app/entry/src/main/resources/rawfile/samples/water-cycle/diagram.json', 'app/entry/src/main/resources/rawfile/samples/water-cycle/source-preview.png']);
  text(s, '“What comes after\ncondensation?”', 64, 172, 530, 125, 43, C.mint, true);
  text(s, 'Hear the object you choose, then follow\nthe connection that answers\nyour question.', 64, 333, 530, 124, 30);
  text(s, 'For blind and low-vision learners\nand the teachers preparing their lessons.', 64, 528, 550, 92, 26, C.muted);
  await photo(s, 'app/entry/src/main/resources/rawfile/samples/water-cycle/source-preview.png', 660, 169, 556, 402, 'Original water-cycle diagram with four labelled regions and directed connections.');
  text(s, 'Original lesson image', 660, 593, 550, 35, 23, C.muted);
}
{
  const s = slide('Exploration at the learner’s pace',
    'The same lesson supports touch, list navigation and automatic scanning. Touch plays the recording for the selected object. List navigation makes objects and their connections available through native controls. Scanning moves the highlight automatically, and the learner activates the current choice. Zoom and pan preserve the original spatial arrangement. Bookmarks make it easy to return to an object.',
    ['docs/ACCESSIBILITY.md', 'docs/evidence/native-ui-observations.json', 'docs/evidence/final-candidate-canvas.png', 'app/entry/src/main/ets/pages/Index.ets']);
  section(s, 'Touch', 'Hear the object under your finger.\nZoom in and follow its connections.', 158, 740);
  section(s, 'List', 'Move between objects with labelled controls.\nReplay a description whenever you need it.', 328, 740);
  section(s, 'Scan', 'Let the highlight move automatically.\nSelect the object you want to explore.', 498, 740);
  await photo(s, 'docs/evidence/final-candidate-canvas.png', 890, 126, 265, 530, 'Actual Canvas exploration showing selected Precipitation and native controls, with the diagram partly above the scrolled viewport.');
}
{
  const s = slide('The lesson resumes where you stopped',
    'An interruption should not mean finding your place again. TouchMap saves the current object, zoom, question and bookmarks on the device. Reopen the lesson and Resume brings that context back. An unfinished answer stays available until the learner chooses Submit. When a teacher shares the lesson, the learner’s history stays private on their own device. They can export that history separately when they choose.',
    ['docs/evidence/native-recovery.json', 'docs/evidence/native-restore-benchmark.json', 'docs/PRIVACY.md', 'docs/presentation-assets/resume.png', 'docs/evidence/demo-manifest.json']);
  section(s, 'Your place stays saved', 'Return to the same object, zoom level\nand question after reopening the app.', 167, 740);
  section(s, 'Answers wait for Submit', 'Keep a selection while you explore.\nSubmit it when you are ready.', 337, 740);
  section(s, 'Your history stays private', 'Share the lesson with another learner.\nKeep personal progress on your device.', 507, 740);
  await photo(s, 'docs/presentation-assets/resume.png', 890, 126, 265, 530, 'Actual Resume screen showing restored water-cycle learning context after restart.');
}
{
  const s = slide('Teachers prepare the lesson',
    'A teacher starts with a diagram they have permission to use. They can mark objects manually or ask AI for a draft. The editor lets them correct the geometry and descriptions, review connections and check the facts behind each question. They choose when to generate speech and when to publish. Once matching recordings are complete, Ready offline tells the learner that the lesson is available locally. Here is the material created, reviewed and exported in the native authoring demo.',
    ['AI_WORKFLOW.md', 'contracts/CONTRACT.md', 'docs/evidence/native-author-tts-accepted.json', 'docs/evidence/native-authoring-flow.json', 'docs/evidence/native-author-ready.png']);
  section(s, 'Start with your diagram', 'Mark objects yourself or use an AI draft.\nKeep the source beside your edits.', 158, 740);
  section(s, 'Keep control of the content', 'Correct descriptions and connections.\nCheck the facts behind each question.', 328, 740);
  section(s, 'Publish a lesson learners can take away', 'Add matching audio and publish your review.\nReady offline confirms the local recordings.', 498, 740);
  await photo(s, 'docs/evidence/native-author-ready.png', 890, 126, 265, 530, 'Actual Library showing the authored revision 6 lesson ready offline, with its objects, connections and question.');
}
{
  const s = slide('The lesson works offline',
    'Once prepared, the lesson needs no network connection. Its image, reviewed structure and matching recordings travel together in one touchmap file. The native app plays audio and saves progress locally. Optional AI preparation and speech generation run separately and only after the author gives consent. Learners can open a bundled lesson immediately without creating an account.',
    ['ARCHITECTURE.md', 'AI_WORKFLOW.md', 'contracts/CONTRACT.md', 'docs/PRIVACY.md', 'docs/backend.md']);
  table(s, [
    ['Activity', 'What the learner gets', 'Connection'],
    ['Explore a diagram', 'Objects, descriptions and connections', 'Offline'],
    ['Listen and replay', 'Recordings stored with the lesson', 'Offline'],
    ['Answer and resume', 'Questions and progress on the device', 'Offline'],
    ['Prepare with AI', 'An optional draft and generated speech', 'Online, by consent']
  ], 157, [63, 82, 82, 82, 90], [284, 594, 274]);
  text(s, 'One .touchmap file carries the reviewed lesson and its recordings.', 64, 595, 1140, 40, 27, C.mint);
  text(s, 'Bundled lessons open without an account.', 64, 637, 1140, 32, 25, C.muted);
}
{
  const s = slide('Native on OpenHarmony',
    'TouchMap uses the platform directly. ArkUI draws the exploration surface and provides the native controls. AudioRenderer plays local recordings with pause and replay. The relational store keeps progress across restarts. The system file picker lets authors export a lesson and learners import it on another installation. TouchMap also opens shared files through normal URI permissions. The app targets API 20 and the demonstration runs on the API 23 emulator.',
    ['docs/platform.md', 'ARCHITECTURE.md', 'docs/evidence/native-share-verification.json', 'docs/evidence/native-audio-controls.json', 'docs/evidence/native-export-dialog.png']);
  section(s, 'Touch and audio', 'ArkUI Canvas connects the diagram to\nlocal playback through AudioRenderer.', 162, 740);
  section(s, 'Share through the system', 'Export a lesson with the native file picker.\nOpen it on another installation.', 332, 740);
  section(s, 'Progress on the device', 'Native relational storage preserves\nwhere the learner stopped.', 502, 740);
  await photo(s, 'docs/evidence/native-export-dialog.png', 890, 126, 265, 530, 'Actual native SystemPicker Save dialog for a touchmap lesson package.');
}
{
  const s = slide('Four examples to explore today',
    'The app includes four prepared examples. The tutorial introduces the controls through simple shapes. The water cycle lets learners follow a familiar sequence and answer questions about its connections. The invented Lumina process adds branches, so the learner has to trace a path. The rainfall chart presents labelled values and comparison questions. Its missing June value stays unknown. These examples are already packaged with local recordings.',
    ['app/entry/src/main/resources/rawfile/samples/tutorial/diagram.json', 'app/entry/src/main/resources/rawfile/samples/water-cycle/diagram.json', 'app/entry/src/main/resources/rawfile/samples/lumina-process/diagram.json', 'app/entry/src/main/resources/rawfile/samples/rainfall-chart/diagram.json']);
  table(s, [
    ['Example', 'What to explore', 'What to practise'],
    ['Shape tutorial', 'Simple shapes with spoken labels', 'Using the controls'],
    ['Water cycle', 'Stages linked by directed arrows', 'Following a sequence'],
    ['Lumina process', 'An invented process with branches', 'Tracing a path'],
    ['Rainfall chart', 'Recorded values and missing data', 'Reading and comparing']
  ], 157, [63, 82, 82, 82, 82], [264, 548, 340]);
  text(s, 'Each example includes local audio. The lessons add questions with explanations.', 64, 591, 1152, 65, 27, C.mint);
}
{
  const s = slide('Controls that adapt to the learner',
    'Learners can enlarge text and controls to 200 percent and choose a comfortable scan interval. Spoken labels stay available with visible descriptions, and playback can be repeated or stopped. Questions give an explanation after an explicit submission. This capture shows the enlarged answer flow running on the emulator. The same lesson remains available through touch, list navigation or scanning.',
    ['docs/ACCESSIBILITY.md', 'docs/evidence/second-correct-answer-200.jpeg', 'docs/evidence/native-ui-observations.json', 'app/entry/src/main/ets/pages/Index.ets']);
  section(s, 'Larger text and controls', 'Increase the interface to 200%.\nKeep navigation and answers within reach.', 155, 740);
  section(s, 'A pace you choose', 'Set the scan interval. Replay a description\nor stop the audio at any time.', 325, 740);
  section(s, 'Feedback that explains', 'Choose an answer, then press Submit.\nRead the explanation tied to the diagram.', 495, 740);
  await photo(s, 'docs/evidence/second-correct-answer-200.jpeg', 890, 126, 265, 530, 'Actual lesson at 200 percent text showing the selected Gate 1 answer and correct feedback.');
}
{
  const s = slide('TouchMap is ready to explore',
    'Open the release to watch the English demo or download the signed application. Follow the emulator setup guide and open a bundled lesson. The learner can explore, answer a question and resume offline without an account. The public repository includes the source and reproducible build instructions. TouchMap is a native OpenHarmony application from DEFOZO SOFTWARE HOUSE, with Michał Kiełtyka as the sole team member.',
    ['README.md', 'docs/DEMO_ACCESS.md', 'docs/platform.md', 'SUBMISSION.md', 'https://github.com/Defozo/TouchMap', 'https://github.com/Defozo/TouchMap/releases/tag/v1.0.1']);
  text(s, 'Repository', 64, 166, 600, 42, 29, C.mint, true);
  const repo = text(s, 'github.com/Defozo/TouchMap', 64, 215, 1152, 55, 39);
  repo.text.get('github.com/Defozo/TouchMap').link = { uri: 'https://github.com/Defozo/TouchMap', isExternal: true };
  repo.text.get('github.com/Defozo/TouchMap').fill = C.mint;
  text(s, 'Watch the demo or download the app', 64, 320, 1136, 42, 29, C.mint, true);
  const release = text(s, 'github.com/Defozo/TouchMap/releases/tag/v1.0.1', 64, 369, 1152, 51, 31);
  release.text.get('github.com/Defozo/TouchMap/releases/tag/v1.0.1').link = { uri: 'https://github.com/Defozo/TouchMap/releases/tag/v1.0.1', isExternal: true };
  release.text.get('github.com/Defozo/TouchMap/releases/tag/v1.0.1').fill = C.mint;
  text(s, 'Install the signed HAP using the setup guide. Open the water cycle lesson.', 64, 495, 1140, 77, 29);
  text(s, 'Your place stays saved, even when the app closes.', 64, 601, 1136, 38, 24, C.muted);
}

for (const entry of notes) {
  for (const reference of entry.citations) {
    if (!reference.startsWith('https://')) await fs.access(path.join(workspaceDir, reference));
  }
}
await (await PresentationFile.exportPptx(p)).save(candidatePath);
execFileSync(RUNTIME_PYTHON, [path.join(workspaceDir, 'scripts/set-presentation-metadata.py'), candidatePath], { stdio: 'inherit' });
const result = await finalizePresentation({
  workspaceDir, candidatePath, finalPath,
  explicitTotalSlideCount: 10,
  requiredNativeTableOwnerSlides: [6, 8],
  pythonExecutable: RUNTIME_PYTHON,
  integrityValidatorPath: path.join(SKILL_DIR, 'container_tools/inspect_presentation_package_integrity.py'),
  layoutValidatorPath: path.join(SKILL_DIR, 'container_tools/inspect_presentation_layout_geometry.py'),
  layoutArgs: ['--expected-slide-size-emu', '12192000,6858000', '--validate-bullet-geometry', '--validate-heading-fit', '--require-native-table-slide', '6', '--require-native-table-slide', '8'],
  fontPolicy: { basis: 'design', families: [font] },
  verifyArtifactToolImport: true,
  receiptPath: path.join(buildDir, 'validation.json'),
});
await fs.writeFile(path.join(buildDir, 'sources.json'), JSON.stringify(sources, null, 2) + '\n');
await fs.writeFile(path.join(buildDir, 'notes.json'), JSON.stringify(notes, null, 2) + '\n');
console.log(JSON.stringify({ finalPath, result, slides: notes.length, sources: sources.length }));
