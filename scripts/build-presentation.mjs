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
  text(s, 'TouchMap', 64, 679, 700, 22, 16, C.muted);
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
    'TouchMap is a native OpenHarmony application for exploring reviewed diagrams. It is intended for blind and low-vision learners and for teachers who prepare accessible material. A learner can explore objects and their relationships, answer questions and resume a lesson offline. DEFOZO SOFTWARE HOUSE is the submitting team, with Michał Kiełtyka as its sole human member. The application and recordings demonstrate developer verification. We have not yet completed a study with the intended learners.',
    ['TEAM.json', 'SUBMISSION.md', 'docs/ACCESSIBILITY.md', 'docs/evidence/final-release-v2-library-ui.json', 'docs/presentation-assets/final-library.png']);
  text(s, 'TouchMap', 64, 150, 740, 118, 92, C.text, true);
  text(s, 'Reviewed diagrams for\nindependent exploration', 68, 290, 700, 134, 42, C.mint);
  text(s, 'DEFOZO SOFTWARE HOUSE', 68, 524, 725, 34, 27, C.text, true);
  text(s, 'Michał Kiełtyka', 68, 568, 700, 36, 28, C.muted);
  await photo(s, 'docs/presentation-assets/final-library.png', 885, 40, 306, 612, 'Actual TouchMap Library captured from installed final HAP 1209c8712549.');
}
{
  const s = slide('Following relationships in a diagram',
    'A diagram contains relationships as well as labels. Consider the water cycle: a learner may want to follow what comes after condensation, return to a previous object or check a connection. TouchMap represents objects, reviewed relationships and questions alongside the original image. Our hypothesis is that choosing an exploration order can help learners form and check a mental model. The project has implemented this interaction, but we do not claim a measured learning advantage. A planned comparative study will test that hypothesis.',
    ['SUBMISSION.md', 'docs/STUDY_PROTOCOL.md', 'app/entry/src/main/resources/rawfile/samples/water-cycle/diagram.json', 'app/entry/src/main/resources/rawfile/samples/water-cycle/source-preview.png']);
  text(s, '“What comes after\ncondensation?”', 64, 172, 530, 125, 43, C.mint, true);
  text(s, 'The learner chooses where to explore\nand which connection to follow.', 64, 333, 530, 124, 30);
  text(s, 'Intended users\nBlind and low-vision learners.\nTeachers prepare and review lessons.', 64, 507, 550, 119, 26, C.muted);
  await photo(s, 'app/entry/src/main/resources/rawfile/samples/water-cycle/source-preview.png', 660, 169, 556, 402, 'Original water-cycle diagram with four labelled regions and directed connections.');
  text(s, 'Original lesson image', 660, 593, 550, 35, 23, C.muted);
}
{
  const s = slide('Three ways to explore',
    'The native application offers three ways to reach the same reviewed content. Touch exploration uses the diagram geometry and local recordings. List navigation exposes objects and their connections through standard controls. Scan navigation advances the focus automatically and lets the user activate the current item. The learner can zoom, pan, bookmark an object or follow a reviewed path. Unknown path geometry remains explicitly unknown. Text and controls remain available alongside audio. A genuine system screen-reader session still needs hardware validation.',
    ['docs/ACCESSIBILITY.md', 'docs/evidence/native-ui-observations.json', 'docs/evidence/final-candidate-canvas.png', 'app/entry/src/main/ets/pages/Index.ets']);
  section(s, 'Touch', 'Explore the original diagram with local audio\nand reviewed geometry.', 158, 740);
  section(s, 'List', 'Reach objects and connections through\nstandard native controls.', 328, 740);
  section(s, 'Scan', 'Move focus automatically, then activate\nthe selected item.', 498, 740);
  await photo(s, 'docs/evidence/final-candidate-canvas.png', 890, 126, 265, 530, 'Actual Canvas exploration showing selected Precipitation and native controls, with the diagram partly above the scrolled viewport.');
}
{
  const s = slide('A lesson that survives interruption',
    'TouchMap saves the learner’s current context locally. Reopening a lesson restores the object, viewport, question, bookmarks and the rest of the saved progress. Selecting an answer does not submit it. Only the explicit Submit action records an answer, and a restart does not submit an unfinished selection. The native restart tests checked acknowledged writes, replayed event identifiers and unfinished selections. A portable lesson contains reviewed teaching material and audio. The learner’s private history stays on the device unless they deliberately export it through the separate history action.',
    ['docs/evidence/native-recovery.json', 'docs/evidence/native-restore-benchmark.json', 'docs/PRIVACY.md', 'docs/presentation-assets/resume.png', 'docs/evidence/demo-manifest.json']);
  section(s, 'Saved context', 'Return to the object, viewport and question\nwhere the lesson stopped.', 167, 740);
  section(s, 'Explicit answers', 'An unfinished selection remains unfinished\nuntil the learner submits it.', 337, 740);
  section(s, 'Private progress', 'Lesson packages travel between devices.\nLearning history uses a separate export.', 507, 740);
  await photo(s, 'docs/presentation-assets/resume.png', 890, 126, 265, 530, 'Actual Resume screen showing restored water-cycle learning context after restart.');
}
{
  const s = slide('Authors control publication',
    'An author can import a source, edit regions and relationships manually, or request an AI proposal after explicit consent. AI output always returns as a draft. The author checks geometry and meaning, then reviews relations and each question against its supporting facts. Speech generation requires separate consent, and recordings must match the current text and language. Publication records the current revision’s review. Ready offline separately requires complete matching local assets and recordings. The declaration records who performed the review. A valid checksum establishes file integrity, while teaching quality still depends on source review. Demonstration materials identify the developer review accurately. This screenshot comes from the earlier authoring session.',
    ['AI_WORKFLOW.md', 'contracts/CONTRACT.md', 'docs/evidence/native-author-tts-accepted.json', 'docs/evidence/native-authoring-flow.json', 'docs/presentation-assets/author-review.png']);
  section(s, 'Source and proposal', 'Keep the original image. Treat AI output\nas a draft that needs review.', 158, 740);
  section(s, 'Review the current revision', 'Confirm geometry, meaning, relations\nand question facts before publication.', 328, 740);
  section(s, 'Publication and offline readiness', 'Publish reviewed content. Complete local\nrecordings for Ready offline.', 498, 740);
  await photo(s, 'docs/presentation-assets/author-review.png', 890, 126, 265, 530, 'Actual author editor with separate geometry and meaning confirmation controls.');
}
{
  const s = slide('Local learning, optional preparation',
    'The learner path runs locally. ArkTS and ArkUI handle exploration and questions. Relational storage commits private progress, while verified immutable files hold source images and recordings. AudioRenderer plays local PCM recordings. Optional preparation runs in a separate service: Gemini proposes structured material, a controlled SVG renderer produces a faithful preview, and ElevenLabs creates speech after consent. Provider credentials stay on the service. A portable touchmap package includes its manifest, diagram, source, preview and matching audio. Its checksums allow another installation to verify the same assets without a backend connection.',
    ['ARCHITECTURE.md', 'AI_WORKFLOW.md', 'contracts/CONTRACT.md', 'docs/PRIVACY.md', 'docs/backend.md']);
  table(s, [
    ['Layer', 'Responsibility', 'Network'],
    ['ArkTS and ArkUI', 'Canvas, list, scan and questions', 'Offline'],
    ['Local storage', 'Progress and verified lesson assets', 'Offline'],
    ['AudioRenderer', 'PCM recordings and playback control', 'Offline'],
    ['Preparation service', 'AI proposals, SVG preview and speech', 'Separate consent']
  ], 157, [63, 82, 82, 82, 90], [284, 606, 262]);
  text(s, 'Portable lesson: source, reviewed structure, matching audio and checksums.', 64, 595, 1140, 40, 25, C.mint);
  text(s, 'Private learning history and provider credentials stay outside the package.', 64, 637, 1140, 32, 24, C.muted);
}
{
  const s = slide('OpenHarmony integration',
    'TouchMap uses native platform APIs for its core behaviour. ArkUI Canvas and standard controls provide exploration and editing. AudioRenderer handles PCM playback, including pause, resume and cancellation. Relational storage and file access protect durable progress. SystemPicker exports and imports packages through ordinary URI permissions. Tests also opened a package through cold viewData and warm sendData requests. The build targets API 20 and the emulator runtime reports API 23, OpenHarmony 6.1.0.31. This does not claim an independent runtime test on an API 20 device.',
    ['docs/platform.md', 'ARCHITECTURE.md', 'docs/evidence/native-share-verification.json', 'docs/evidence/native-audio-controls.json', 'docs/evidence/native-export-dialog.png']);
  section(s, 'Native interaction and storage', 'ArkUI Canvas, AudioRenderer and\ntransactional local progress.', 162, 740);
  section(s, 'Native file exchange', 'SystemPicker and ordinary URI grants\nfor import, export and shared opening.', 332, 740);
  section(s, 'Build and tested runtime', 'Target and minimum API 20.\nExecuted on the API 23 emulator.', 502, 740);
  await photo(s, 'docs/evidence/native-export-dialog.png', 890, 126, 265, 530, 'Actual native SystemPicker Save dialog for a touchmap lesson package.');
}
{
  const s = slide('Developer verification',
    'These are observed developer tests, not a user study. Eighteen native regression tests passed on the final application build. One hundred restart cycles verified acknowledged commits, unfinished selections and duplicate event handling. Separately, one hundred local audio starts achieved a 25 millisecond 95th percentile from the playback scheduler decision to the first accepted PCM write. The 250 millisecond dwell is excluded from that number. Including dwell, the 95th percentile was 303 milliseconds. One hundred restoration observations achieved a 130 millisecond 95th percentile from the active-app open intent to the post-layout draw boundary. That run used 92 plus 8 samples after a UiTest harness stall. Every included sample passed full progress equality and a visible Resume-heading check. These are software boundaries, not physical speaker or panel measurements.',
    ['docs/TEST_REPORT.md', 'docs/evidence/native-test-artifact.json', 'docs/evidence/native-audio-benchmark.json', 'docs/evidence/audio-source-equivalence.json', 'docs/evidence/native-restore-benchmark.json', 'docs/evidence/native-recovery.json']);
  table(s, [
    ['Check', 'Observed result', 'Measurement boundary'],
    ['Native regressions', '18 passed', 'Final release HAP'],
    ['Restart recovery', '100 cycles passed', 'Acknowledged commits'],
    ['Local audio starts', '100 starts, p95 25 ms', 'First accepted PCM write'],
    ['Context restoration', '100 opens, p95 130 ms', 'Active app, layout and draw']
  ], 157, [63, 72, 72, 83, 83], [310, 355, 487]);
  text(s, 'Audio includes 250 ms dwell: p95 303 ms. These are software timings.', 64, 554, 1152, 40, 24, C.mint);
  text(s, 'Restoration: 92 + 8 samples after a test-harness restart. Maximum 453 ms.', 64, 603, 1152, 40, 24, C.muted);
}
{
  const s = slide('Accessibility evidence and next checks',
    'The emulator evidence covers 200 percent text, native controls, scanning, tutorial navigation and manual authoring. The application offers touch, list and scan routes, visible status and local audio. However, the user has no physical HarmonyOS or OpenHarmony device available for this work. We have not verified a complete lesson with a genuine screen reader, physical vibrations, headphone hardware or the intended learners. The next evaluation should involve blind and low-vision learners plus teachers, comparing touch exploration, list navigation and a linear audio overview. It should measure successful answers, assistance, workload and recovery after interruption. Those results may change the interface and preparation workflow.',
    ['docs/ACCESSIBILITY.md', 'docs/STUDY_PROTOCOL.md', 'docs/evidence/native-settings-200.jpeg', 'docs/evidence/native-ui-observations.json']);
  section(s, 'Verified on the emulator', '200% text and controls, scanning,\ntutorial and manual editing flows.', 155, 740);
  section(s, 'Still unverified', 'A genuine reader, physical vibration,\nheadphone hardware and learner studies.', 325, 740);
  section(s, 'Planned comparison', 'Touch exploration, list navigation\nand a linear audio overview.', 495, 740);
  await photo(s, 'docs/evidence/native-settings-200.jpeg', 890, 126, 265, 530, 'Actual 200 percent Settings screen explicitly reporting that the system screen reader is disabled.');
}
{
  const s = slide('Source, install and demo',
    'The submission supplies the source repository, signed HAP, portable sample lessons, an English three-minute demonstration and setup documentation. Download the release assets, follow the emulator setup in docs/platform.md and install the signed HAP with hdc. The documented emulator audio configuration is required for the pinned image. A bundled prepared lesson works without a backend or provider key. For authors who want cloud preparation, the documentation explains service deployment, pairing and separate consent. The repository is github.com/Defozo/TouchMap and the release tag is v1.0.0. The submitting team is DEFOZO SOFTWARE HOUSE, with Michał Kiełtyka as its sole human member.',
    ['README.md', 'docs/platform.md', 'SUBMISSION.md', 'AI_WORKFLOW.md', 'https://github.com/Defozo/TouchMap', 'https://github.com/Defozo/TouchMap/releases/tag/v1.0.0']);
  text(s, 'Repository', 64, 166, 600, 42, 29, C.mint, true);
  const repo = text(s, 'github.com/Defozo/TouchMap', 64, 215, 1152, 55, 39);
  repo.text.get('github.com/Defozo/TouchMap').link = { uri: 'https://github.com/Defozo/TouchMap', isExternal: true };
  repo.text.get('github.com/Defozo/TouchMap').fill = C.mint;
  text(s, 'Release assets and 3-minute demo', 64, 320, 1136, 42, 29, C.mint, true);
  const release = text(s, 'github.com/Defozo/TouchMap/releases/tag/v1.0.0', 64, 369, 1152, 51, 31);
  release.text.get('github.com/Defozo/TouchMap/releases/tag/v1.0.0').link = { uri: 'https://github.com/Defozo/TouchMap/releases/tag/v1.0.0', isExternal: true };
  release.text.get('github.com/Defozo/TouchMap/releases/tag/v1.0.0').fill = C.mint;
  text(s, 'Download the HAP. Follow docs/platform.md. Open a bundled lesson offline.', 64, 495, 1140, 77, 29);
  text(s, 'Bundled lessons require no account, backend or provider key.', 64, 601, 1136, 38, 24, C.muted);
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
