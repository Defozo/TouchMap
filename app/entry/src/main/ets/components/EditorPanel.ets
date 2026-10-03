import { Diagram, Region, Relation, Question, Chart, Review, Polygon, Point, Audio, AnswerOption, Series, ChartValue, Tick } from '../domain/types';
import { DraftEditor } from '../domain/editor';
import { wavDuration } from '../domain/media';
import { publicationIssues, validateDiagram, validateQuestion, offlineReadiness } from '../domain/validate';
import { Material, Repository, digest, encode, readBytes, writeBytes, uid, safePath } from '../platform/Repository';
import { Preparation, AudioLabel, PreparedAudio, base64Bytes, verifySourcePreview } from '../platform/Preparation';
import { feedback } from '../platform/Feedback';

interface StagedAudio { path: string; bytes: Uint8Array; }

@Component
export struct EditorPanel {
  material: Material = undefined!;
  repository: Repository = undefined!;
  onSaved: (material: Material) => void = () => {};
  @State diagram: Diagram | undefined = undefined;
  @State section: string = 'Objects';
  @State selectedId: string = '';
  @State label: string = '';
  @State materialTitle: string = '';
  @State materialDescription: string = '';
  @State speechReviewed: boolean = false;
  @State description: string = '';
  @State reference: string = '';
  @State geometry: string = '';
  @State lines: string = '';
  @State x: string = '20';
  @State y: string = '20';
  @State regionWidth: string = '100';
  @State regionHeight: string = '80';
  @State order: string = '1';
  @State layer: string = '1';
  @State fromId: string = '';
  @State toId: string = '';
  @State relationDirection: string = 'forward';
  @State relationType: string = 'process';
  @State path: string = 'null';
  @State questionType: string = 'direction';
  @State facts: string = '';
  @State options: string = '';
  @State answers: string = '';
  @State hint: string = '';
  @State chartJson: string = '';
  @State chartTitle: string = '';
  @State xLabel: string = '';
  @State xUnit: string = '';
  @State yLabel: string = '';
  @State yUnit: string = '';
  @State xScale: string = 'category';
  @State xDomain: string = '';
  @State xTicks: string = '';
  @State yTicks: string = '';
  @State seriesLabel: string = '';
  @State chartKind: string = 'bar';
  @State yScale: string = 'linear';
  @State yMinimum: string = '0';
  @State yMaximum: string = '100';
  @State seriesId: string = '';
  @State valueId: string = '';
  @State valueLabel: string = '';
  @State valueRegion: string = '';
  @State valueNumber: string = '';
  @State valuePrecision: string = '0';
  @State reviewer: string = '';
  @State audioTarget: string = '';
  @State audioKind: string = 'label';
  @State audioText: string = '';
  @State audioProvenance: string = '';
  @State audioDuration: string = '1000';
  @State aiConsent: boolean = false;
  @State ttsConsent: boolean = false;
  @State busy: boolean = false;
  @State preparing: boolean = false;
  @State status: string = 'Choose an object or create a region. Every change is saved as a draft.';
  @State lateResult: Diagram | undefined = undefined;
  private editor: DraftEditor | undefined = undefined;
  private current: Material | undefined = undefined;
  private preparation: Preparation = new Preparation();
  private lateBytes: Uint8Array | undefined = undefined;
  private latePreview: Uint8Array | undefined = undefined;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasWidth: number = 320;
  private lifetime: number = 0;

  aboutToAppear(): void {
    this.lifetime++;
    this.current = this.material;
    this.editor = new DraftEditor(this.material.diagram);
    this.diagram = this.editor.diagram; this.materialTitle = this.diagram.title; this.materialDescription = this.diagram.description;
    this.preparation.base = this.repository.profile.service;
  }
  aboutToDisappear(): void { this.lifetime++; this.preparation.cancel(); feedback.stop(); }
  private error(error: Error): void { this.status = error.message || 'The change could not be saved. Existing material is retained.'; }
  private review(): Review { return { status: 'needs_review', revision: this.diagram!.revision, reviewer: '', issues: [] }; }
  private async save(): Promise<void> {
    const lifetime = this.lifetime;
    this.diagram = this.editor!.diagram;
    const issues = validateDiagram(this.diagram); if (issues.length) { throw new Error(issues[0]); }
    this.current = await this.repository.saveDraft(this.diagram, this.current!);
    if (this.current.diagram.revision !== this.diagram.revision) { this.diagram = this.current.diagram; this.editor = new DraftEditor(this.diagram); }
    if (lifetime !== this.lifetime) { return; }
    this.onSaved(this.current);
    this.draw();
    this.status = `Draft revision ${this.diagram.revision} saved. Changed facts and recordings need review.`;
  }
  private async change(work: () => void): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    const previous = this.editor!.diagram; const selected = this.selectedId; const chart = this.chartJson;
    try { work(); await this.save(); if (this.diagram!.revision !== previous.revision) { this.speechReviewed = false; } } catch (error) { this.editor = new DraftEditor(previous); this.diagram = previous; this.selectedId = selected; this.chartJson = chart; this.error(error as Error); } finally { this.busy = false; }
  }
  private selectRegion(region: Region): void {
    this.selectedId = region.id; this.label = region.label; this.description = region.description;
    this.reference = region.evidence.map((e) => e.reference).join('; ');
    this.geometry = JSON.stringify(region.polygons); this.lines = JSON.stringify(region.line);
    this.order = String(region.readingOrder); this.layer = String(region.zIndex);
    if (region.polygons.length > 0) {
      const points = region.polygons[0].outer;
      const xs = points.map((p: Point) => p.x), ys = points.map((p: Point) => p.y);
      this.x = String(Math.min(...xs)); this.y = String(Math.min(...ys));
      this.regionWidth = String(Math.max(...xs) - Number(this.x)); this.regionHeight = String(Math.max(...ys) - Number(this.y));
    }
    this.draw();
  }
  private newRegion(): void {
    this.selectedId = ''; this.label = ''; this.description = ''; this.reference = ''; this.geometry = ''; this.lines = '[]';
    this.order = String(this.diagram!.regions.length + 1); this.layer = this.order;
  }
  private region(rectangle: boolean): Region {
    const x = Number(this.x), y = Number(this.y), w = Number(this.regionWidth), h = Number(this.regionHeight);
    if (rectangle && (![x, y, w, h].every(Number.isFinite) || w <= 0 || h <= 0)) { throw new Error('Use finite coordinates and positive width and height.'); }
    const polygons: Polygon[] = rectangle ? [{ outer: [{ x: x, y: y }, { x: x + w, y: y }, { x: x + w, y: y + h }, { x: x, y: y + h }], holes: [] }] : JSON.parse(this.geometry) as Polygon[];
    return { id: this.selectedId || `region-${uid()}`, label: this.label.trim(), description: this.description, polygons: polygons,
      line: rectangle ? [] : JSON.parse(this.lines) as Point[], lineWidth: 8, zIndex: Number(this.layer), readingOrder: Number(this.order),
      evidence: [{ sourceId: this.diagram!.source.id, reference: this.reference, origin: 'human-authored' }], geometryReview: this.review(), meaningReview: this.review() };
  }
  private storeRegion(rectangle: boolean): void {
    this.change(() => {
      const region = this.region(rectangle);
      const trial = JSON.parse(JSON.stringify(this.diagram)) as Diagram;
      trial.regions = trial.regions.filter((r) => r.id !== region.id).concat([region]);
      const issues = validateDiagram(trial); if (issues.length) { throw new Error(issues[0]); }
      if (this.selectedId) { this.editor!.updateRegion(region); } else { this.editor!.addRegion(region); }
      this.selectedId = region.id;
    });
  }
  private selectRelation(relation: Relation): void {
    this.selectedId = relation.id; this.label = relation.label; this.fromId = relation.fromId; this.toId = relation.toId;
    this.relationDirection = relation.direction; this.relationType = relation.type; this.path = JSON.stringify(relation.path);
    this.reference = relation.evidence.map((e) => e.reference).join('; ');
  }
  private storeRelation(): void {
    this.change(() => {
      const relation: Relation = { id: this.selectedId || `relation-${uid()}`, fromId: this.fromId, toId: this.toId, label: this.label,
        type: this.relationType, direction: this.relationDirection as 'forward' | 'both' | 'unknown', path: JSON.parse(this.path) as Point[] | null,
        evidence: [{ sourceId: this.diagram!.source.id, reference: this.reference, origin: 'human-authored' }], review: this.review() };
      const trial = JSON.parse(JSON.stringify(this.diagram)) as Diagram;
      trial.relations = trial.relations.filter((r) => r.id !== relation.id).concat([relation]);
      const issues = validateDiagram(trial); if (issues.length) { throw new Error(issues[0]); }
      this.editor!.updateRelation(relation); this.selectedId = relation.id;
    });
  }
  private selectQuestion(question: Question): void {
    this.selectedId = question.id; this.label = question.prompt; this.questionType = question.type;
    this.facts = question.factIds.join(', '); this.options = question.options.map((o) => `${o.id}|${o.label}`).join('\n');
    this.answers = question.acceptedAnswers.join(', '); this.hint = question.hint; this.description = question.explanation;
  }
  private storeQuestion(): void {
    this.change(() => {
      const question: Question = { id: this.selectedId || `question-${uid()}`, prompt: this.label,
        type: this.questionType as 'adjacency' | 'direction' | 'sequence' | 'comparison' | 'value',
        factIds: this.facts.split(',').map((s: string) => s.trim()).filter((s: string) => !!s),
        options: this.options.split('\n').filter((s: string) => !!s.trim()).map((s: string): AnswerOption => { const at = s.indexOf('|'); if (at <= 0) { throw new Error('Each answer option requires ID|label.'); } return { id: s.slice(0, at).trim(), label: s.slice(at + 1).trim() }; }),
        acceptedAnswers: this.answers.split(',').map((s: string) => s.trim()).filter((s: string) => !!s), hint: this.hint,
        explanation: this.description, requiredRevision: this.diagram!.revision, review: this.review() };
      if (!question.prompt || question.options.length < 2 || question.options.some((o) => !o.id || !o.label)) { throw new Error('A question needs a prompt and at least two ID|label options.'); }
      this.editor!.updateQuestion(question); this.selectedId = question.id;
    });
  }
  private currentChart(): Chart | undefined {
    try { return this.chartJson ? JSON.parse(this.chartJson) as Chart : undefined; } catch (error) { return undefined; }
  }
  private selectChart(chart: Chart): void {
    this.selectedId = chart.id; this.chartJson = JSON.stringify(chart, null, 2); this.chartTitle = chart.title;
    this.xLabel = chart.xAxis.label; this.xUnit = chart.xAxis.unit; this.yLabel = chart.yAxis.label; this.yUnit = chart.yAxis.unit;
    this.yScale = chart.yAxis.scale; this.yMinimum = String(chart.yAxis.domain[0] ?? 0); this.yMaximum = String(chart.yAxis.domain[1] ?? 100);
    this.seriesId = ''; this.valueId = ''; this.seriesLabel = ''; this.chartKind = chart.kind;
    this.xScale = chart.xAxis.scale; this.xDomain = chart.xAxis.domain.join(', ');
    this.xTicks = chart.xAxis.ticks.map((tick) => `${tick.value}|${tick.label}`).join('\n'); this.yTicks = chart.yAxis.ticks.map((tick) => `${tick.value}|${tick.label}`).join('\n');
    this.reference = chart.evidence.map((e) => e.reference).join('; ');
  }
  private newChart(): void {
    const chart: Chart = { id: `chart-${uid()}`, title: 'New chart', kind: 'bar',
      xAxis: { label: 'Category', unit: '', scale: 'category', domain: [], ticks: [] },
      yAxis: { label: 'Value', unit: '', scale: 'linear', domain: [0, 100], ticks: [{ value: 0, label: '0' }, { value: 100, label: '100' }] },
      series: [{ id: `series-${uid()}`, label: 'Series 1', values: [] }], evidence: [{ sourceId: this.diagram!.source.id, reference: '', origin: 'human-authored' }], review: this.review() };
    this.selectChart(chart);
  }
  private storeChartAxes(): void {
    this.change(() => {
      const chart = this.currentChart(); if (!chart) { throw new Error('Choose or create a chart.'); }
      chart.title = this.chartTitle; chart.kind = this.chartKind as 'bar' | 'line';
      chart.xAxis.scale = this.xScale as 'linear' | 'log' | 'category';
      chart.xAxis.domain = this.xDomain.trim() ? this.xDomain.split(',').map((value: string) => Number(value.trim())) : [];
      chart.xAxis.ticks = this.ticks(this.xTicks); chart.yAxis.ticks = this.ticks(this.yTicks);
      if (chart.xAxis.scale !== 'category' && (chart.xAxis.domain.length !== 2 || !chart.xAxis.domain.every(Number.isFinite) || chart.xAxis.domain[0] >= chart.xAxis.domain[1] || (chart.xAxis.scale === 'log' && chart.xAxis.domain[0] <= 0))) { throw new Error('A numerical horizontal axis needs two increasing finite domain values.'); }
      chart.xAxis.label = this.xLabel; chart.xAxis.unit = this.xUnit;
      chart.yAxis.label = this.yLabel; chart.yAxis.unit = this.yUnit; chart.yAxis.scale = this.yScale as 'linear' | 'log' | 'category';
      chart.yAxis.domain = [Number(this.yMinimum), Number(this.yMaximum)];
      if (!chart.yAxis.domain.every(Number.isFinite) || chart.yAxis.domain[0] >= chart.yAxis.domain[1] || (chart.yAxis.scale === 'log' && chart.yAxis.domain[0] <= 0)) { throw new Error('Choose a valid axis domain. Logarithmic axes require positive values.'); }
      chart.evidence = [{ sourceId: this.diagram!.source.id, reference: this.reference, origin: 'human-authored' }];
      this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2);
    });
  }
  private ticks(text: string): Tick[] {
    return text.split('\n').filter((line: string) => !!line.trim()).map((line: string): Tick => {
      const separator = line.indexOf('|'); const value = Number(line.slice(0, separator)); const label = line.slice(separator + 1).trim();
      if (separator < 1 || !Number.isFinite(value) || !label) { throw new Error('Use one numerical value|tick label per line.'); }
      return { value: value, label: label };
    });
  }
  private storeSeries(): void {
    this.change(() => {
      const chart = this.currentChart(); if (!chart || !this.seriesLabel.trim()) { throw new Error('Choose a chart and enter a series name.'); }
      const series = chart.series.find((item: Series) => item.id === this.seriesId);
      if (series) { series.label = this.seriesLabel.trim(); } else { this.seriesId = `series-${uid()}`; chart.series.push({ id: this.seriesId, label: this.seriesLabel.trim(), values: [] }); }
      this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2);
    });
  }
  private storeChartValue(): void {
    this.change(() => {
      const chart = this.currentChart(); if (!chart) { throw new Error('Choose a chart first.'); }
      const series = chart.series.find((s: Series) => s.id === this.seriesId);
      if (!series) { throw new Error('Choose a series first.'); }
      const value: ChartValue = { id: this.valueId || `value-${uid()}`, regionId: this.valueRegion, x: this.valueLabel,
        value: this.valueNumber.trim() ? Number(this.valueNumber) : null, precision: Number(this.valuePrecision),
        evidence: [{ sourceId: this.diagram!.source.id, reference: this.reference, origin: 'human-authored' }] };
      if (!this.diagram!.regions.some((r: Region) => r.id === value.regionId) || (value.value !== null && !Number.isFinite(value.value)) || !Number.isInteger(value.precision) || value.precision < 0 || value.precision > 10) { throw new Error('Use an existing region ID, a number or blank unknown value, and precision 0 to 10.'); }
      series.values = series.values.filter((v: ChartValue) => v.id !== value.id).concat([value]);
      this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2); this.valueId = value.id;
    });
  }
  private async mark(kind: string): Promise<void> {
    await this.change(() => {
      if (this.section === 'Questions') {
        const question = this.diagram!.questions.find((q) => q.id === this.selectedId);
        if (!question) { throw new Error('Save the question first.'); }
        const issues = validateQuestion(this.diagram!, question); if (issues.length) { throw new Error(issues.join('\n')); }
      }
      this.editor!.markReviewed(this.selectedId, kind, this.reviewer);
    });
  }
  private async publish(): Promise<void> {
    if (this.busy) { return; } this.busy = true; const lifetime = this.lifetime;
    try {
      if (this.diagram!.audio.length > 0 && !this.speechReviewed) { throw new Error('Listen to critical labels, names and units, then confirm the recording review before publishing.'); }
      const published = this.editor!.publish(this.reviewer);
      const material = await this.repository.saveDraft(published, this.current!);
      material.draft = false;
      material.manifest.author = { name: this.reviewer, declaration: 'I reviewed geometry, meaning, numerical facts and lesson answers against the stated source or an equivalent accessible reference.' };
      writeBytes(`${material.directory}/manifest.json`, encode(JSON.stringify(material.manifest)));
      await this.repository.saveMaterial(material); this.current = material; if (lifetime === this.lifetime) { this.onSaved(material); }
      this.status = material.ready ? 'Published and ready offline. Export from the library.' : 'Published. Required recordings are still missing, so this revision is not ready offline.';
    } catch (error) { this.error(error as Error); } finally { this.busy = false; }
  }
  private labels(): AudioLabel[] {
    const d = this.diagram!; const labels: AudioLabel[] = [];
    labels.push({ targetId: d.packageId, kind: 'overview', text: d.description, textHash: '' });
    d.regions.forEach((r) => { labels.push({ targetId: r.id, kind: 'label', text: r.label, textHash: '' }); if (r.description.trim()) { labels.push({ targetId: r.id, kind: 'description', text: r.description, textHash: '' }); } });
    d.relations.forEach((r) => { labels.push({ targetId: r.id, kind: 'label', text: r.label, textHash: '' }); });
    d.questions.forEach((q) => { labels.push({ targetId: q.id, kind: 'question', text: q.prompt, textHash: '' }); }); return labels;
  }
  private async importAudio(): Promise<void> {
    if (this.busy) { return; } this.busy = true; const lifetime = this.lifetime;
    const previous = this.editor!.diagram;
    try {
      const target = this.labels().find((l: AudioLabel) => l.targetId === this.audioTarget && l.kind === this.audioKind);
      if (!target || !this.audioProvenance.trim()) { throw new Error('Choose an existing audio target and provide recording rights/provenance.'); }
      const uri = await this.repository.pick(); if (!uri || lifetime !== this.lifetime) { return; }
      const bytes = readBytes(uri, 10 * 1024 * 1024);
      if (bytes.length < 44 || String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]) !== 'RIFF') { throw new Error('Import a WAV recording.'); }
      const duration = wavDuration(bytes); this.audioDuration = String(duration);
      const hash = await digest(bytes); const textHash = await digest(encode(target.text));
      if (lifetime !== this.lifetime) { return; } const path = `audio/${hash}.wav`;
      const audio: Audio = { id: `audio-${uid()}`, targetId: target.targetId, kind: target.kind as 'label' | 'description' | 'question' | 'overview',
        path: path, textHash: textHash, language: this.diagram!.language, provider: 'recording', voice: this.audioProvenance, sha256: hash, durationMs: duration };
      const diagram = this.editor!.diagram; diagram.audio = diagram.audio.filter((a) => a.targetId !== audio.targetId || a.kind !== audio.kind).concat([audio]);
      const issues = validateDiagram(diagram); if (issues.length) { throw new Error(issues[0]); }
      writeBytes(`${this.current!.directory}/${path}`, bytes);
      this.editor = new DraftEditor(diagram); await this.save(); this.speechReviewed = false; this.status = 'Recording imported. Play it and verify names and units before publication.';
    } catch (error) { this.editor = new DraftEditor(previous); this.diagram = previous; this.error(error as Error); } finally { this.busy = false; }
  }
  private async cloudSpeech(): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.preparing = true; const lifetime = this.lifetime;
    const previous = this.editor!.diagram;
    try {
      if (publicationIssues(this.diagram!).length > 0) { throw new Error('Review the content and questions before preparing speech.'); }
      const original = this.editor!.diagram;
      const labels = this.labels(); for (const item of labels) { item.textHash = await digest(encode(item.text)); }
      if (lifetime !== this.lifetime) { return; }
      const received: PreparedAudio[] = [];
      for (let offset = 0; offset < labels.length; offset += 100) {
        this.status = `Preparing recordings ${offset + 1} to ${Math.min(offset + 100, labels.length)} of ${labels.length}.`;
        const result = await this.preparation.speech(original, labels.slice(offset, offset + 100), this.ttsConsent);
        if (lifetime !== this.lifetime) { return; }
        if (!Array.isArray(result.result.audio)) { throw new Error('Speech response must contain recordings.'); }
        received.push(...result.result.audio);
      }
      if (this.editor!.diagram.revision !== original.revision || this.editor!.diagram.source.sha256 !== original.source.sha256) { throw new Error('The draft changed. This speech result was not applied; generate speech for the current revision.'); }
      if (received.length !== labels.length) { throw new Error('Speech response must include every requested recording exactly once.'); }
      const prepared: Audio[] = []; const staged: StagedAudio[] = []; const targets: string[] = [];
      for (const item of received) {
        const expected = labels.find((l: AudioLabel) => l.targetId === item.targetId && l.kind === item.kind);
        const bytes = base64Bytes(item.dataBase64);
        const target = `${item.targetId}:${item.kind}`;
        if (!expected || targets.includes(target) || expected.textHash !== item.textHash || item.language !== original.language || bytes.length > 10 * 1024 * 1024 || await digest(bytes) !== item.sha256 || !safePath(item.path) || !/^audio\/[a-zA-Z0-9_-][a-zA-Z0-9_.-]*\.wav$/.test(item.path)) { throw new Error('Speech integrity, target, language or path mismatch.'); }
        const actualDuration = wavDuration(bytes);
        if (!Number.isFinite(item.durationMs) || Math.abs(actualDuration - item.durationMs) > Math.max(100, item.durationMs * 0.05)) { throw new Error('Speech duration does not match the WAV recording.'); }
        const localPath = `audio/${item.sha256}.wav`;
        targets.push(target); if (!staged.some((asset: StagedAudio) => asset.path === localPath)) { staged.push({ path: localPath, bytes: bytes }); }
        prepared.push({ id: item.id, targetId: item.targetId, kind: item.kind, path: localPath, textHash: item.textHash, language: item.language,
          provider: item.provider, voice: item.voice, sha256: item.sha256, durationMs: actualDuration });
      }
      const diagram = this.editor!.diagram; diagram.audio = prepared;
      const issues = validateDiagram(diagram); if (issues.length) { throw new Error(`Invalid speech result: ${issues[0]}`); }
      if (lifetime !== this.lifetime) { return; }
      for (const asset of staged) { writeBytes(`${this.current!.directory}/${asset.path}`, asset.bytes); }
      this.editor = new DraftEditor(diagram); await this.save();
      this.speechReviewed = false; this.status = 'Speech prepared locally. Listen to critical labels, units and names before publication.';
    } catch (error) { this.editor = new DraftEditor(previous); this.diagram = previous; this.error(error as Error); } finally { this.busy = false; this.preparing = false; this.ttsConsent = false; }
  }
  private async analyze(): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.preparing = true; const lifetime = this.lifetime;
    const previous = this.editor!.diagram;
    try {
      const original = this.editor!.diagram;
      const result = await this.preparation.draft(readBytes(`${this.current!.directory}/${original.source.path}`), original, original.source.path.endsWith('.svg'), this.aiConsent);
      if (lifetime !== this.lifetime) { return; }
      result.result.diagram.packageId = original.packageId;
      result.result.diagram.source.attribution = original.source.attribution;
      result.result.diagram.source.license = original.source.license;
      const preview = result.result.previewBase64 ? base64Bytes(result.result.previewBase64) : undefined;
      if (result.result.diagram.source.previewPath && (!preview || preview.length > 10 * 1024 * 1024 || await digest(preview) !== result.result.diagram.source.previewSha256)) { throw new Error('Prepared source preview integrity mismatch.'); }
      if (preview) { await verifySourcePreview(preview, result.result.diagram.source.width, result.result.diagram.source.height); result.result.diagram.source.previewPath = `source-preview-${result.result.diagram.source.previewSha256}.png`; }
      const normalized = result.result.sourceBase64 ? base64Bytes(result.result.sourceBase64) : readBytes(`${this.current!.directory}/${original.source.path}`);
      if (normalized.length > 10 * 1024 * 1024 || await digest(normalized) !== result.result.diagram.source.sha256) { throw new Error('Prepared source integrity mismatch.'); }
      if (this.editor!.diagram.revision !== original.revision || this.editor!.diagram.source.sha256 !== original.source.sha256) {
        this.lateResult = result.result.diagram; this.lateBytes = normalized; this.latePreview = preview; this.status = 'The draft changed. The late result is retained separately; current edits are unchanged.'; return;
      }
      if (lifetime !== this.lifetime) { return; }
      if (result.result.diagram.source.sha256 !== original.source.sha256) {
        const next = result.result.diagram; next.revision = original.revision + 1; next.title = original.title; next.description = original.description;
        next.regions.forEach((r: Region) => { r.geometryReview = { status: 'needs_review', revision: next.revision, reviewer: '', issues: [] }; r.meaningReview = { status: 'needs_review', revision: next.revision, reviewer: '', issues: [] }; });
        next.relations.forEach((r: Relation) => { r.review = { status: 'needs_review', revision: next.revision, reviewer: '', issues: [] }; });
        next.charts.forEach((c: Chart) => { c.review = { status: 'needs_review', revision: next.revision, reviewer: '', issues: [] }; });
        next.audio = []; next.questions = [];
        this.current = await this.repository.createSource(next, normalized, preview); this.diagram = this.current.diagram;
        this.editor = new DraftEditor(this.diagram); if (lifetime === this.lifetime) { this.onSaved(this.current); this.draw(); }
        this.speechReviewed = false; this.status = `Prepared a normalized source revision with ${result.provider} ${result.model}. Review all geometry and meaning.`; return;
      }
      result.result.diagram.source.path = original.source.path;
      if (preview && result.result.diagram.source.previewPath) { writeBytes(`${this.current!.directory}/${result.result.diagram.source.previewPath}`, preview); }
      if (!this.editor!.replaceFromJob(result.result.diagram, original.source.sha256, original.revision)) { this.lateResult = result.result.diagram; this.status = 'The draft changed. The late result is retained separately; current edits are unchanged.'; return; }
      await this.save();
      this.speechReviewed = false; this.status = `Draft from ${result.provider} ${result.model}. Review every geometry and meaning. ${result.result.report.unsupported.join('; ')} ${result.result.report.unresolved.join('; ')}`;
    } catch (error) { this.editor = new DraftEditor(previous); this.diagram = previous; this.error(error as Error); } finally { this.busy = false; this.preparing = false; this.aiConsent = false; }
  }
  private draw(): void {
    if (!this.diagram) { return; }
    const ctx = this.context, d = this.diagram;
    const scale = Math.min(this.canvasWidth / d.source.width, 240 / d.source.height);
    ctx.clearRect(0, 0, this.canvasWidth, 240); ctx.save(); ctx.scale(scale, scale);
    const source = new ImageBitmap(`file://${this.current!.directory}/${d.source.previewPath || d.source.path}`);
    ctx.drawImage(source, 0, 0, d.source.width, d.source.height);
    d.regions.forEach((r) => {
      ctx.strokeStyle = r.id === this.selectedId ? '#ffbe72' : '#26dbc0'; ctx.lineWidth = 3 / scale; ctx.fillStyle = '#2226dbc0';
      r.polygons.forEach((poly) => { ctx.beginPath(); poly.outer.forEach((point: Point, i: number) => { if (i === 0) { ctx.moveTo(point.x, point.y); } else { ctx.lineTo(point.x, point.y); } }); ctx.closePath(); poly.holes.forEach((hole: Point[]) => { hole.forEach((point: Point, i: number) => { if (i === 0) { ctx.moveTo(point.x, point.y); } else { ctx.lineTo(point.x, point.y); } }); ctx.closePath(); }); ctx.stroke(); });
      if (r.line.length > 0) { ctx.beginPath(); r.line.forEach((point: Point, i: number) => { if (i === 0) { ctx.moveTo(point.x, point.y); } else { ctx.lineTo(point.x, point.y); } }); ctx.stroke(); }
    }); ctx.restore();
  }
  @Builder reviewControls() {
    Column({ space: 5 }) { Text('Reviewer name and source-access declaration').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.reviewer }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((text: string) => { this.reviewer = text; }).accessibilityText('Reviewer name and source-access declaration') }.width('100%').alignItems(HorizontalAlign.Start)
    Text('Confirm against the original source or an equivalent accessible reference. An editable form does not independently describe the source. Unknown facts must be marked unknown.').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2')
    if (this.section === 'Objects') {
      Button('Confirm geometry').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.mark('geometry'); })
      Button('Confirm meaning and evidence').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.mark('meaning'); })
    } else {
      Button('Confirm this fact and evidence').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.mark('fact'); })
    }
  }
  build() {
    Column({ space: 14 }) {
      Text('AUTHOR STUDIO').fontSize(13 * this.repository.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#69E2C5').letterSpacing(2).width('100%')
      Text(this.diagram?.title || 'Material').fontSize(28 * this.repository.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%')
      Text(`Source: ${this.diagram?.source.attribution || 'Add provenance'} · ${this.diagram?.source.license || 'Rights not declared'}`).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%')
      if (this.diagram?.source.path.endsWith('.svg') && !this.diagram?.source.previewPath) { Text('Source preview incomplete: this device may omit SVG text and arrowheads. Use Convert selected SVG in Publish to prepare an exact raster preview before reviewing the original image.').fontColor('#FFCE90').fontSize(16 * this.repository.profile.textScale).width('100%') }
      Canvas(this.context).width('100%').height(240).backgroundColor('#FFFFFF').borderRadius(12).accessibilityText('Source preview with region boundaries. All geometry can also be edited in the coordinate forms below.').onReady(() => { this.draw(); }).onAreaChange((_old: Area, area: Area) => { this.canvasWidth = Number(area.width); this.draw(); })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(['Objects', 'Connections', 'Questions', 'Chart facts', 'Speech', 'Publish'], (tab: string) => {
          Button(tab).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).borderRadius(8).margin(3).fontColor(this.section === tab ? '#09252A' : '#F3F8FA').backgroundColor(this.section === tab ? '#69E2C5' : '#284450').constraintSize({ minHeight: 46 * this.repository.profile.textScale }).padding(10).fontSize(16 * this.repository.profile.textScale).onClick(() => { this.section = tab; this.selectedId = ''; })
        })
      }.width('100%')
      Text(this.status).fontSize(16 * this.repository.profile.textScale).fontColor('#FFCE90').width('100%').accessibilityText(this.status)
      if (this.preparing) { Button('Cancel preparation request').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.lifetime++; this.preparation.cancel(); this.status = 'Cancellation requested. Existing edits are retained.'; }) }
      Row({ space: 8 }) {
        Button('Undo').fontSize(16 * this.repository.profile.textScale).constraintSize({ minHeight: 48 * this.repository.profile.textScale }).layoutWeight(1).enabled(!this.busy && !!this.editor?.canUndo).onClick(() => { this.change(() => { this.editor!.undo(); this.materialTitle = this.editor!.diagram.title; this.materialDescription = this.editor!.diagram.description; }); })
        Button('Redo').fontSize(16 * this.repository.profile.textScale).constraintSize({ minHeight: 48 * this.repository.profile.textScale }).layoutWeight(1).enabled(!this.busy && !!this.editor?.canRedo).onClick(() => { this.change(() => { this.editor!.redo(); this.materialTitle = this.editor!.diagram.title; this.materialDescription = this.editor!.diagram.description; }); })
      }.width('100%')
      if (this.section === 'Objects' && this.diagram) {
        ForEach(this.diagram.regions, (r: Region) => {
          Button(`${r.label} · ${r.geometryReview.status} / ${r.meaningReview.status}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).width('100%').constraintSize({ minHeight: 50 * this.repository.profile.textScale }).backgroundColor('#284450').onClick(() => { this.selectRegion(r); })
        }, (r: Region) => r.id)
        Button('Add a new object').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.newRegion(); })
        Column({ space: 5 }) { Text('Object label').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.label }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.label = s; }).accessibilityText('Object label') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Requested description').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.description }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.description = s; }).accessibilityText('Requested description') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Source evidence: location, text or accessible reference').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText('Source evidence: location, text or accessible reference') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Left coordinate').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.x }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.x = s; }).accessibilityText('Left coordinate') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Top coordinate').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.y }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.y = s; }).accessibilityText('Top coordinate') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Width in source coordinates').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.regionWidth }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.regionWidth = s; }).accessibilityText('Width in source coordinates') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Height in source coordinates').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.regionHeight }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.regionHeight = s; }).accessibilityText('Height in source coordinates') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Reading order').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.order }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.order = s; }).accessibilityText('Reading order') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Layer number').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.layer }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.layer = s; }).accessibilityText('Layer number') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Save rectangular region').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeRegion(true); })
        Column({ space: 5 }) { Text('Exact polygons and holes, JSON source coordinates').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.geometry }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.geometry = s; }).accessibilityText('Exact polygons and holes, JSON source coordinates') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Line points, JSON source coordinates').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.lines }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.lines = s; }).accessibilityText('Line points, JSON source coordinates') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Save exact geometry').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeRegion(false); })
        if (this.selectedId) {
          this.reviewControls()
          Button('Delete object and its connections').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeRegion(this.selectedId); this.newRegion(); }); })
        }
      } else if (this.section === 'Connections' && this.diagram) {
        ForEach(this.diagram.relations, (r: Relation) => { Button(`${r.label} (${r.fromId} to ${r.toId})`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectRelation(r); }) }, (r: Relation) => r.id)
        Button('New connection').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectedId = ''; this.label = ''; this.path = 'null'; })
        Text('Object IDs: ' + this.diagram.regions.map((r: Region) => `${r.id} = ${r.label}`).join('; ')).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        Column({ space: 5 }) { Text('Connection label').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.label }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.label = s; }).accessibilityText('Connection label') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Source object ID').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.fromId }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.fromId = s; }).accessibilityText('Source object ID') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Destination object ID').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.toId }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.toId = s; }).accessibilityText('Destination object ID') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Relationship type').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.relationType }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.relationType = s; }).accessibilityText('Relationship type') }.width('100%').alignItems(HorizontalAlign.Start)
        Select([{ value: 'forward' }, { value: 'both' }, { value: 'unknown' }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(this.relationDirection).onSelect((_i: number, value: string) => { this.relationDirection = value; }).accessibilityText('Direction')
        Column({ space: 5 }) { Text('Known path points, or null when route is unspecified').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.path }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.path = s; }).accessibilityText('Known path points, or null when route is unspecified') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Source evidence for meaning and direction').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText('Source evidence for meaning and direction') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Save connection').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeRelation(); })
        if (this.selectedId) {
          this.reviewControls()
          Button('Delete connection').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeRelation(this.selectedId); this.selectedId = ''; }); })
        }
      } else if (this.section === 'Questions' && this.diagram) {
        ForEach(this.diagram.questions, (q: Question) => { Button(`${q.prompt} · ${q.review.status}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectQuestion(q); }) }, (q: Question) => q.id)
        Button('New question').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectedId = ''; this.label = ''; this.facts = ''; this.options = ''; this.answers = ''; this.description = ''; this.hint = ''; })
        Column({ space: 5 }) { Text('Question prompt').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.label }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.label = s; }).accessibilityText('Question prompt') }.width('100%').alignItems(HorizontalAlign.Start)
        Select([{ value: 'adjacency' }, { value: 'direction' }, { value: 'sequence' }, { value: 'comparison' }, { value: 'value' }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(this.questionType).onSelect((_i: number, value: string) => { this.questionType = value; }).accessibilityText('Question type')
        Column({ space: 5 }) { Text('Referenced fact IDs, comma separated').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.facts }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.facts = s; }).accessibilityText('Referenced fact IDs, comma separated') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Answer options: one ID|label on each line').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.options }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.options = s; }).accessibilityText('Answer options: one ID|label on each line') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Accepted option IDs in order, comma separated').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.answers }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.answers = s; }).accessibilityText('Accepted option IDs in order, comma separated') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Optional hint').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.hint }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.hint = s; }).accessibilityText('Optional hint') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Explanation grounded in reviewed facts').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.description }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.description = s; }).accessibilityText('Explanation grounded in reviewed facts') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Save question').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeQuestion(); })
        if (this.selectedId) {
          this.reviewControls()
          Button('Delete question').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeQuestion(this.selectedId); this.selectedId = ''; }); })
        }
      } else if (this.section === 'Chart facts' && this.diagram) {
        ForEach(this.diagram.charts, (chart: Chart) => { Button(chart.title).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectChart(chart); }) }, (chart: Chart) => chart.id)
        Button('Add a new chart').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.newChart(); })
        Text('Edit axes, scale, domains, tick labels, units, source values and evidence. A null value is explicitly unknown. Never estimate an exact value from pixel height.').fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        if (this.currentChart()) {
          Select([{ value: 'bar' }, { value: 'line' }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(this.chartKind).onSelect((_i: number, value: string) => { this.chartKind = value; }).accessibilityText('Chart type')
          Column({ space: 5 }) { Text('Chart title').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.chartTitle }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.chartTitle = s; }).accessibilityText('Chart title') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Horizontal axis label').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.xLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.xLabel = s; }).accessibilityText('Horizontal axis label') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Horizontal axis unit').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.xUnit }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.xUnit = s; }).accessibilityText('Horizontal axis unit') }.width('100%').alignItems(HorizontalAlign.Start)
          Select([{ value: 'category' }, { value: 'linear' }, { value: 'log' }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(this.xScale).onSelect((_i: number, value: string) => { this.xScale = value; }).accessibilityText('Horizontal scale type')
          Column({ space: 5 }) { Text('Horizontal domain minimum and maximum, comma separated for numerical axes').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.xDomain }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.xDomain = s; }).accessibilityText('Horizontal domain minimum and maximum, comma separated for numerical axes') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Horizontal ticks: numerical coordinate|label, one per line').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.xTicks }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.xTicks = s; }).accessibilityText('Horizontal ticks: numerical coordinate|label, one per line') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Vertical axis label').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yLabel = s; }).accessibilityText('Vertical axis label') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Vertical axis unit').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yUnit }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yUnit = s; }).accessibilityText('Vertical axis unit') }.width('100%').alignItems(HorizontalAlign.Start)
          Select([{ value: 'linear' }, { value: 'log' }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(this.yScale).onSelect((_i: number, value: string) => { this.yScale = value; }).accessibilityText('Vertical scale type')
          Column({ space: 5 }) { Text('Vertical domain minimum').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yMinimum }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yMinimum = s; }).accessibilityText('Vertical domain minimum') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Vertical domain maximum').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yMaximum }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yMaximum = s; }).accessibilityText('Vertical domain maximum') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Vertical ticks: numerical coordinate|label, one per line').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.yTicks }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.yTicks = s; }).accessibilityText('Vertical ticks: numerical coordinate|label, one per line') }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text('Source evidence for axes and units').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText('Source evidence for axes and units') }.width('100%').alignItems(HorizontalAlign.Start)
          Button('Save axes and units').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeChartAxes(); })
          Column({ space: 5 }) { Text('Series name').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.seriesLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.seriesLabel = s; }).accessibilityText('Series name') }.width('100%').alignItems(HorizontalAlign.Start)
          Button('Save series name').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeSeries(); })
          Button('New series').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.seriesId = ''; this.seriesLabel = ''; this.valueId = ''; })
          ForEach(this.currentChart()!.series, (series: Series) => {
            Button(`Add value to ${series.label}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.seriesId = series.id; this.seriesLabel = series.label; this.valueId = ''; this.valueLabel = ''; this.valueRegion = ''; this.valueNumber = ''; })
            ForEach(series.values, (value: ChartValue) => {
              Button(`${value.x}: ${value.value === null ? 'unknown' : value.value} ${this.yUnit}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.seriesId = series.id; this.valueId = value.id; this.valueLabel = value.x; this.valueRegion = value.regionId; this.valueNumber = value.value === null ? '' : String(value.value); this.valuePrecision = String(value.precision); this.reference = value.evidence.map((e) => e.reference).join('; '); })
            }, (value: ChartValue) => value.id)
          }, (series: Series) => series.id)
          if (this.seriesId) {
            Column({ space: 5 }) { Text('Category or x value').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valueLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valueLabel = s; }).accessibilityText('Category or x value') }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text('Matching region ID').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valueRegion }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valueRegion = s; }).accessibilityText('Matching region ID') }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text('Exact source value, leave blank for unknown').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valueNumber }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valueNumber = s; }).accessibilityText('Exact source value, leave blank for unknown') }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text('Decimal precision').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valuePrecision }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valuePrecision = s; }).accessibilityText('Decimal precision') }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text('Source evidence for this value').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText('Source evidence for this value') }.width('100%').alignItems(HorizontalAlign.Start)
            Button('Save source-backed value').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeChartValue(); })
            if (this.valueId) { Button('Delete this value').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { const chart = this.currentChart()!; const series = chart.series.find((s: Series) => s.id === this.seriesId)!; series.values = series.values.filter((v: ChartValue) => v.id !== this.valueId); this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2); this.valueId = ''; }); }) }
          }
        }
        Column({ space: 5 }) { Text('Chart data: axes, series, values and evidence').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.chartJson }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.chartJson = s; }).accessibilityText('Chart data: axes, series, values and evidence') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Save chart facts').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { const chart = JSON.parse(this.chartJson) as Chart; this.editor!.updateChart(chart); this.selectedId = chart.id; }); })
        if (this.selectedId) { this.reviewControls(); Button('Delete this chart and invalidate dependent questions').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeChart(this.selectedId); this.selectedId = ''; this.chartJson = ''; }); }) }
      } else if (this.section === 'Speech' && this.diagram) {
        Text('Recordings stay with the material and play offline. Import licensed WAV files or explicitly consent to cloud speech.').fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        ForEach(this.labels(), (item: AudioLabel) => {
          Button(`${item.kind}: ${item.text}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.audioTarget = item.targetId; this.audioKind = item.kind; this.audioText = item.text; })
        }, (item: AudioLabel) => `${item.targetId}:${item.kind}`)
        Text(`Selected: ${this.audioKind} ${this.audioText}`).fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA')
        Column({ space: 5 }) { Text('Recording rights and speaker provenance').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.audioProvenance }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.audioProvenance = s; }).accessibilityText('Recording rights and speaker provenance') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Verified recording duration, milliseconds').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.audioDuration }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.audioDuration = s; }).accessibilityText('Verified recording duration, milliseconds') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Import WAV recording').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.importAudio(); })
        Button('Listen to selected recording').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { feedback.speak(this.current!, this.audioTarget, this.audioKind, this.repository.profile, true); })
        Row({ space: 8 }) { Checkbox().select(this.ttsConsent).onChange((value: boolean) => { this.ttsConsent = value; }); Text('Send these reviewed texts to ElevenLabs for speech preparation.').fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA').layoutWeight(1) }.width('100%')
        Button('Generate reviewed speech').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.cloudSpeech(); })
      } else if (this.section === 'Publish' && this.diagram) {
        Column({ space: 5 }) { Text('Material title').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.materialTitle }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.materialTitle = s; }).accessibilityText('Material title') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Save title').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { if (!this.materialTitle.trim()) { throw new Error('Enter a material title.'); } this.editor!.setTitle(this.materialTitle.trim()); }); })
        Column({ space: 5 }) { Text('Material overview and listening introduction').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.materialDescription }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(160 * this.repository.profile.textScale).onChange((s: string) => { this.materialDescription = s; }).accessibilityText('Material overview and listening introduction') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Save material overview').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { if (!this.materialDescription.trim()) { throw new Error('Enter an overview of the source and its learning context.'); } this.editor!.setDescription(this.materialDescription.trim()); }); })
        Column({ space: 5 }) { Text('Author and review declaration').fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.reviewer }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.reviewer = s; }).accessibilityText('Author and review declaration') }.width('100%').alignItems(HorizontalAlign.Start)
        Text(publicationIssues(this.diagram).join('\n') || 'All geometry, facts and questions have been reviewed.').fontSize(16 * this.repository.profile.textScale).fontColor('#FFCE90')
        Text(offlineReadiness(this.diagram, this.current!.manifest.assets.map((a) => a.path)).missing.join('\n') || 'All required assets are available locally.').fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        if (this.diagram.audio.length > 0) {
          Row({ space: 8 }) { Checkbox().select(this.speechReviewed).onChange((value: boolean) => { this.speechReviewed = value; }).accessibilityText('Confirm recordings reviewed'); Text('I listened to the recordings and checked critical labels, names and units.').fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA').layoutWeight(1) }.width('100%')
        }
        Button('Publish reviewed revision').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.publish(); })
        Text(`Optional preparation service: ${this.repository.profile.service || 'Configure and pair in Settings'}`).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        Text('The preview above is the exact local source sent to the preparation service. Raster analysis uses Gemini. Source text is untrusted input. Every proposed fact still requires author review.').fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        Row({ space: 8 }) { Checkbox().select(this.aiConsent).onChange((value: boolean) => { this.aiConsent = value; }); Text('Upload this selected image to the configured service and Gemini.').fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA').layoutWeight(1) }.width('100%')
        Button(this.diagram.source.path.endsWith('.svg') ? 'Convert selected SVG with service' : 'Request image draft from Gemini').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.analyze(); })
        if (this.lateResult) { Button('Save late result as a separate material').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.lateResult!.packageId = `late-${uid()}`; this.repository.createSource(this.lateResult!, this.lateBytes || readBytes(`${this.current!.directory}/${this.diagram!.source.path}`), this.latePreview).then((material: Material) => { this.onSaved(material); this.lateResult = undefined; this.status = 'Late result saved separately for review.'; }).catch((error: Error) => { this.error(error); }); }) }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
