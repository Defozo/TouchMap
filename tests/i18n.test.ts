import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { englishText, englishKey } from '../app/entry/src/main/ets/domain/EnglishStrings';
import { tr, setTranslationResolver } from '../app/entry/src/main/ets/domain/i18n';
import { initialProgress, applyAction } from '../app/entry/src/main/ets/domain/engine';
import { Diagram } from '../app/entry/src/main/ets/domain/types';

test('every English UI resource has the same pure-domain fallback and stable reverse key', () => {
  const resources: { string: { name: string; value: string }[] } = JSON.parse(readFileSync('app/entry/src/main/resources/base/element/string.json', 'utf8'));
  const names = new Set<string>();
  for (const entry of resources.string.filter(item => item.name.startsWith('tm_'))) {
    assert.equal(names.has(entry.name), false, entry.name);
    names.add(entry.name);
    assert.equal(englishText(entry.name), entry.value, entry.name);
    assert.equal(englishKey(entry.value), entry.name, entry.value);
  }
  assert.ok(names.size > 500, 'UI, domain feedback and native error resources are present');
});

test('locale resolver formats dynamic values once and safely falls back when unavailable', () => {
  const key = englishKey('Continue authoring revision {0}');
  try {
    setTranslationResolver(() => 'Revision {0}: {1} / {0}');
    assert.equal(tr(key, ['12', '{0} $& $`']), 'Revision 12: {0} $& $` / 12');
    setTranslationResolver(() => { throw new Error('No native context'); });
    assert.equal(tr(key, ['12']), 'Continue authoring revision 12');
    setTranslationResolver(() => '');
    assert.equal(tr(key, ['13']), 'Continue authoring revision 13');
  } finally { setTranslationResolver(englishText); }
});

test('localized engine feedback cannot change stable content IDs, authored labels or lesson state', () => {
  const diagram: Diagram = JSON.parse(readFileSync('samples/water-cycle/diagram.json', 'utf8'));
  const region = diagram.regions[0]; region.label = 'Authored {0} $& label';
  try {
    setTranslationResolver(key => `Localized ${key}`);
    let result = applyAction(diagram, initialProgress(diagram), { type: 'focusRegion', targetId: region.id, eventId: 'focus', expectedRevision: 0 });
    assert.equal(result.feedback, region.label);
    assert.equal(result.state.lastRegionId, region.id);
    result = applyAction(diagram, result.state, { type: 'pause', eventId: 'pause', expectedRevision: 1 });
    assert.match(result.feedback, /^Localized tm_/);
    assert.equal(result.state.status, 'exploring');
    assert.equal(result.state.paused, true);
    assert.equal(result.state.lastRegionId, region.id);
    assert.deepEqual(result.state.submissions, []);
  } finally { setTranslationResolver(englishText); }
});
