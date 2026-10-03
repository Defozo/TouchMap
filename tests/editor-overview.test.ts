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
