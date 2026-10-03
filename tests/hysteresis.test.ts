import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Diagram, Point, Region } from '../app/entry/src/main/ets/domain/types';
import { hitTest, retainRegionNearBoundary } from '../app/entry/src/main/ets/domain/geometry';

function fixture(): Diagram {
  const diagram: Diagram = JSON.parse(readFileSync('samples/water-cycle/diagram.json', 'utf8'));
  const prototype = diagram.regions[0];
  const rectangle = (id: string, left: number, right: number): Region => ({
    ...structuredClone(prototype), id, zIndex: 0, line: [], lineWidth: 0,
    polygons: [{ outer: [{ x: left, y: 0 }, { x: right, y: 0 }, { x: right, y: 10 }, { x: left, y: 10 }], holes: [] }]
  });
  diagram.regions = [rectangle('left', 0, 10), rectangle('right', 10, 20)];
  return diagram;
}

test('pointer jitter does not alternate neighbouring objects; deliberate crossing and exit do', () => {
  const diagram = fixture();
  let current = 'left';
  const changes: string[] = [];
  for (const x of [9.9, 10.3, 9.8, 11.9, 10.1, 12.1, 10.1, 8.1, 7.9, -2.1]) {
    const point: Point = { x, y: 5 };
    const exact = hitTest(diagram, point, current);
    const held = retainRegionNearBoundary(diagram, point, current, 2);
    const next = held?.id || exact[0]?.id || '';
    if (current !== next) changes.push(next);
    current = next;
  }
  assert.deepEqual(changes, ['right', 'left', '']);
  assert.deepEqual(hitTest(diagram, { x: -1, y: 5 }), []);
  assert.equal(retainRegionNearBoundary(diagram, { x: -1, y: 5 }, '', 2), undefined);
  assert.equal(retainRegionNearBoundary(diagram, { x: -1, y: 5 }, 'deleted', 2), undefined);
});

test('hole edges and line stroke edges retain only within the explicit margin', () => {
  const diagram = fixture();
  const region = diagram.regions[0];
  region.polygons[0].holes = [[{ x: 3, y: 3 }, { x: 7, y: 3 }, { x: 7, y: 7 }, { x: 3, y: 7 }]];
  assert.equal(hitTest(diagram, { x: 3.2, y: 5 }).length, 0);
  assert.equal(retainRegionNearBoundary(diagram, { x: 3.2, y: 5 }, 'left', 0.5)?.id, 'left');
  assert.equal(retainRegionNearBoundary(diagram, { x: 5, y: 5 }, 'left', 0.5), undefined);
  region.polygons = [];
  region.line = [{ x: 0, y: 0 }, { x: 10, y: 0 }];
  region.lineWidth = 2;
  assert.equal(retainRegionNearBoundary(diagram, { x: 5, y: 1.4 }, 'left', 0.5)?.id, 'left');
  assert.equal(retainRegionNearBoundary(diagram, { x: 5, y: 1.6 }, 'left', 0.5), undefined);
});

test('two display pixels stay constant across fit and zoom, with exact geometry unchanged', () => {
  const diagram = fixture();
  for (const fit of [0.25, 0.5, 1]) for (const zoom of [1, 2, 8]) {
    const scale = fit * zoom;
    assert.equal(retainRegionNearBoundary(diagram, { x: 10 + 1.9 / scale, y: 5 }, 'left', 2 / scale)?.id, 'left');
    assert.equal(retainRegionNearBoundary(diagram, { x: 10 + 2.1 / scale, y: 5 }, 'left', 2 / scale), undefined);
  }
  for (const margin of [-1, NaN, Infinity]) assert.equal(retainRegionNearBoundary(diagram, { x: 5, y: 5 }, 'left', margin), undefined);
  assert.equal(retainRegionNearBoundary(diagram, { x: NaN, y: 5 }, 'left', 2), undefined);
  assert.equal(retainRegionNearBoundary(diagram, { x: 10.01, y: 5 }, 'left', 0), undefined);
});
