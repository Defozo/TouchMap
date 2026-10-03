import { tr } from './i18n';
import { Diagram, Point, Polygon, Region, Viewport } from './types';
const EPS = 1e-7;
export function distanceToSegment(p: Point, a: Point, b: Point): number {
  const dx = b.x - a.x, dy = b.y - a.y;
  const l = dx * dx + dy * dy;
  const t = l === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l));
  return Math.hypot(p.x - a.x - t * dx, p.y - a.y - t * dy);
}
function ringContains(p: Point, ring: Point[]): number {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const a = ring[j], b = ring[i];
    if (distanceToSegment(p, a, b) < EPS) return 0;
    if ((a.y > p.y) !== (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside ? 1 : -1;
}
export function pointInPolygon(p: Point, polygon: Polygon): boolean {
  if (ringContains(p, polygon.outer) < 0) return false;
  return !polygon.holes.some(hole => ringContains(p, hole) >= 0);
}
export function pathDistance(p: Point, path: Point[]): number {
  let d = Infinity;
  for (let i = 1; i < path.length; i++) d = Math.min(d, distanceToSegment(p, path[i - 1], path[i]));
  return d;
}
export function contains(region: Region, point: Point): boolean {
  return region.polygons.some(p => pointInPolygon(point, p)) || pathDistance(point, region.line) <= region.lineWidth / 2 + EPS;
}
/** Keep an already focused object across small pointer jitter, without enlarging initial hit targets. */
export function retainRegionNearBoundary(diagram: Diagram, point: Point, currentId: string, margin: number): Region | undefined {
  if (!currentId || !Number.isFinite(point.x) || !Number.isFinite(point.y) || !Number.isFinite(margin) || margin < 0) return undefined;
  const region = diagram.regions.find(item => item.id === currentId);
  if (!region) return undefined;
  if (contains(region, point)) return region;
  if (margin === 0) return undefined;
  if (region.line.length > 1 && pathDistance(point, region.line) <= region.lineWidth / 2 + margin) return region;
  for (const polygon of region.polygons) {
    for (const ring of [polygon.outer, ...polygon.holes]) {
      for (let i = 0, previous = ring.length - 1; i < ring.length; previous = i++) {
        if (distanceToSegment(point, ring[previous], ring[i]) <= margin) return region;
      }
    }
  }
  return undefined;
}
export function sourcePoint(p: Point, v: Viewport): Point {
  if (!Number.isFinite(v.scale) || v.scale <= 0) throw new Error(tr('tm_0a6c4a4c5aff'));
  const a = -v.rotation * Math.PI / 180, x = (p.x - v.offsetX) / v.scale, y = (p.y - v.offsetY) / v.scale;
  return { x: x * Math.cos(a) - y * Math.sin(a), y: x * Math.sin(a) + y * Math.cos(a) };
}
export function screenPoint(p: Point, v: Viewport): Point {
  const a = v.rotation * Math.PI / 180;
  return { x: v.offsetX + v.scale * (p.x * Math.cos(a) - p.y * Math.sin(a)), y: v.offsetY + v.scale * (p.x * Math.sin(a) + p.y * Math.cos(a)) };
}
export class SpatialGrid {
  private cells: Map<string, Region[]> = new Map<string, Region[]>();
  constructor(private diagram: Diagram, private cellSize: number = 64) {
    for (const region of diagram.regions) {
      const points: Point[] = region.line.slice();
      region.polygons.forEach(p => p.outer.forEach(point => points.push(point)));
      if (!points.length) continue;
      const pad = region.line.length ? region.lineWidth / 2 : 0;
      let lowX=Infinity,highX=-Infinity,lowY=Infinity,highY=-Infinity;
      for(const point of points){lowX=Math.min(lowX,point.x);highX=Math.max(highX,point.x);lowY=Math.min(lowY,point.y);highY=Math.max(highY,point.y);}
      const minX = Math.floor((lowX - pad) / cellSize), maxX = Math.floor((highX + pad) / cellSize);
      const minY = Math.floor((lowY - pad) / cellSize), maxY = Math.floor((highY + pad) / cellSize);
      if ((maxX - minX + 1) * (maxY - minY + 1) > 200000) throw new Error(tr('tm_a9b99d6be867'));
      for (let x = minX; x <= maxX; x++) for (let y = minY; y <= maxY; y++) {
        const key = `${x}:${y}`, items = this.cells.get(key) || [];
        items.push(region); this.cells.set(key, items);
      }
    }
  }
  hit(point: Point, preferredId: string = ''): Region[] {
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return [];
    const found = (this.cells.get(`${Math.floor(point.x / this.cellSize)}:${Math.floor(point.y / this.cellSize)}`) || []).filter(r => contains(r, point));
    found.sort((a, b) => b.zIndex - a.zIndex || a.readingOrder - b.readingOrder || a.id.localeCompare(b.id));
    const preferred = found.findIndex(r => r.id === preferredId);
    if (preferred > 0) found.unshift(found.splice(preferred, 1)[0]);
    return found;
  }
}
let cachedDiagram: Diagram | undefined;
let cachedGrid: SpatialGrid | undefined;
export function hitTest(diagram: Diagram, point: Point, preferredId: string = ''): Region[] {
  if (cachedDiagram !== diagram || !cachedGrid) { cachedGrid = new SpatialGrid(diagram); cachedDiagram = diagram; }
  return cachedGrid.hit(point, preferredId);
}
export interface PathGuidance { known: boolean; onPath: boolean; distance: number; remaining: number; destination: string }
export function guidePath(point: Point, path: Point[] | null, tolerance: number, destination: string): PathGuidance {
  if (!path || path.length < 2) return { known: false, onPath: false, distance: 0, remaining: 0, destination };
  let best = Infinity, remaining = 0, total = 0;
  for (let i = path.length - 1; i > 0; i--) {
    const a = path[i - 1], b = path[i], length = Math.hypot(b.x - a.x, b.y - a.y), distance = distanceToSegment(point, a, b);
    const t = length ? Math.max(0, Math.min(1, ((point.x-a.x)*(b.x-a.x)+(point.y-a.y)*(b.y-a.y))/(length*length))) : 0;
    if (distance < best) { best = distance; remaining = total + length * (1-t); } total += length;
  }
  return { known: true, onPath: best <= tolerance, distance: best, remaining, destination };
}
