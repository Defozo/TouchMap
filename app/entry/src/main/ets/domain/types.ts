export interface Point { x: number; y: number }
export interface Polygon { outer: Point[]; holes: Point[][] }
export interface Evidence { sourceId: string; reference: string; origin: 'source-derived' | 'human-authored' | 'AI-proposed' }
export interface Review { status: 'draft' | 'needs_review' | 'reviewed'; revision: number; reviewer: string; issues: string[] }
export interface Source { id: string; sha256: string; width: number; height: number; path: string; attribution: string; license: string; viewBox: number[] }
export interface Region { id: string; label: string; description: string; polygons: Polygon[]; line: Point[]; lineWidth: number; zIndex: number; readingOrder: number; evidence: Evidence[]; geometryReview: Review; meaningReview: Review }
export interface Relation { id: string; fromId: string; toId: string; label: string; type: string; direction: 'forward' | 'both' | 'unknown'; path: Point[] | null; evidence: Evidence[]; review: Review }
export interface Tick { value: number; label: string }
export interface Axis { label: string; unit: string; scale: 'linear' | 'log' | 'category'; domain: number[]; ticks: Tick[] }
export interface ChartValue { id: string; regionId: string; x: string; value: number | null; precision: number; evidence: Evidence[] }
export interface Series { id: string; label: string; values: ChartValue[] }
export interface Chart { id: string; title: string; kind: 'bar' | 'line'; xAxis: Axis; yAxis: Axis; series: Series[]; evidence: Evidence[]; review: Review }
export interface AnswerOption { id: string; label: string }
export interface Question { id: string; prompt: string; type: 'adjacency' | 'direction' | 'sequence' | 'comparison' | 'value'; factIds: string[]; options: AnswerOption[]; acceptedAnswers: string[]; hint: string; explanation: string; requiredRevision: number; review: Review }
export interface Audio { id: string; targetId: string; kind: 'label' | 'description' | 'question' | 'overview'; path: string; textHash: string; language: string; provider: string; voice: string; sha256: string; durationMs: number }
export interface Diagram { schemaVersion: number; packageId: string; revision: number; title: string; language: string; source: Source; regions: Region[]; relations: Relation[]; charts: Chart[]; questions: Question[]; audio: Audio[]; description: string }
export interface Asset { path: string; sha256: string; bytes: number; mediaType: string }
export interface Author { name: string; declaration: string }
export interface Manifest { schemaVersion: number; packageId: string; revision: number; title: string; language: string; author: Author; license: string; assets: Asset[] }
export interface Viewport { scale: number; offsetX: number; offsetY: number; rotation: number }
export interface Submission { questionId: string; answers: string[]; correct: boolean; eventId: string; timestamp: number }
export interface Progress { packageId: string; revision: number; stateRevision: number; status: 'not_started' | 'exploring' | 'answering' | 'submitted'; paused: boolean; lastRegionId: string; activeRelationId: string; activeQuestionId: string; selectedAnswers: string[]; submissions: Submission[]; viewport: Viewport; bookmarks: string[]; appliedEvents: string[]; updatedAt: number }
export interface Action { eventId: string; expectedRevision: number; type: string; targetId?: string; answerIds?: string[]; viewport?: Viewport; timestamp?: number }
export interface ActionResult { state: Progress; feedback: string; correct?: boolean; duplicate: boolean }
export interface Profile { labelDelayMs: number; repeatDelayMs: number; volume: number; vibration: boolean; highContrast: boolean; textScale: number; reducedMotion: boolean; scanningMs: number; mode: 'touch' | 'list' | 'scan'; readerSpeech: boolean }
export function defaultProfile(): Profile { return { labelDelayMs: 250, repeatDelayMs: 500, volume: 0.8, vibration: true, highContrast: false, textScale: 1, reducedMotion: false, scanningMs: 1500, mode: 'touch', readerSpeech: false }; }
