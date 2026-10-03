import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Diagram } from '../app/entry/src/main/ets/domain/types';
import { DraftEditor } from '../app/entry/src/main/ets/domain/editor';
import { publicationIssues, offlineReadiness } from '../app/entry/src/main/ets/domain/validate';

test('editing the material overview invalidates its recording while preserving reviewed source facts', () => {
  const original: Diagram = JSON.parse(readFileSync('samples/water-cycle/diagram.json', 'utf8'));
  const editor = new DraftEditor(original);
  editor.setDescription('Explore the cycle from collection through evaporation, condensation and precipitation.');
  const next = editor.diagram;
  assert.equal(next.revision, original.revision + 1);
  assert.notEqual(next.description, original.description);
  assert.equal(next.audio.some(a => a.targetId === next.packageId), false);
  assert.deepEqual(next.audio, original.audio.filter(a => a.targetId !== original.packageId));
  assert.deepEqual(publicationIssues(next), []);
  assert.ok(offlineReadiness(next, [next.source.path, next.source.previewPath!, ...next.audio.map(a => a.path)]).missing.includes(`audio:${next.packageId}:overview`));
  assert.equal(editor.undo(), true);
  assert.deepEqual(editor.diagram, original);
  assert.equal(editor.redo(), true);
  assert.deepEqual(editor.diagram, next);
});

test('adopting a stored revision keeps undo and redo without changing another material', () => {
  const original: Diagram = JSON.parse(readFileSync('samples/water-cycle/diagram.json', 'utf8'));
  const editor = new DraftEditor(original);
  editor.setDescription('Temporary overview');
  assert.equal(editor.undo(), true);
  const saved = editor.diagram; saved.revision = 3;
  editor.adoptSaved(saved);
  assert.equal(editor.diagram.revision, 3);
  assert.equal(editor.canRedo, true);
  assert.equal(editor.redo(), true);
  assert.equal(editor.diagram.description, 'Temporary overview');
  const unrelated = editor.diagram; unrelated.packageId = 'different-material';
  assert.throws(() => editor.adoptSaved(unrelated), /identity/);
});

test('an editor rollback snapshot preserves both histories and isolates later mutations', () => {
  const original: Diagram = JSON.parse(readFileSync('samples/water-cycle/diagram.json', 'utf8'));
  const editor = new DraftEditor(original);
  editor.setTitle('Saved title'); editor.setDescription('Saved overview'); editor.undo();
  const checkpoint = editor.clone();
  editor.setTitle('Rejected change');
  assert.equal(checkpoint.diagram.title, 'Saved title');
  assert.equal(checkpoint.canUndo, true); assert.equal(checkpoint.canRedo, true);
  checkpoint.redo(); assert.equal(checkpoint.diagram.description, 'Saved overview');
  checkpoint.undo(); checkpoint.undo(); assert.deepEqual(checkpoint.diagram, original);
});
