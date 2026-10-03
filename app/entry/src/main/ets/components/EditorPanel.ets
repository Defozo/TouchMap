import { tr } from '../domain/i18n';
import { englishKey } from '../domain/EnglishStrings';
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
  @State status: string = tr('tm_82bef666fe34');
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
  private error(error: Error): void { this.status = error.message || tr('tm_a83949096d79'); }
  private review(): Review { return { status: 'needs_review', revision: this.diagram!.revision, reviewer: '', issues: [] }; }
  private async save(): Promise<void> {
    const lifetime = this.lifetime;
    this.diagram = this.editor!.diagram;
    const issues = validateDiagram(this.diagram); if (issues.length) { throw new Error(issues[0]); }
    this.current = await this.repository.saveDraft(this.diagram, this.current!);
    if (this.current.diagram.revision !== this.diagram.revision) { this.diagram = this.current.diagram; this.editor!.adoptSaved(this.diagram); }
    if (lifetime !== this.lifetime) { return; }
    this.onSaved(this.current);
    this.draw();
    this.status = tr('tm_a4eef70108dd', [String(this.diagram.revision)]);
  }
  private async change(work: () => void): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    const checkpoint = this.editor!.clone(); const previous = checkpoint.diagram; const selected = this.selectedId; const chart = this.chartJson;
    try { work(); await this.save(); if (this.diagram!.revision !== previous.revision) { this.speechReviewed = false; } } catch (error) { this.editor = checkpoint; this.diagram = previous; this.selectedId = selected; this.chartJson = chart; this.error(error as Error); } finally { this.busy = false; }
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
  private syncSelectedForm(): void {
    if (!this.diagram || !this.selectedId) { return; }
    if (this.section === 'Objects') { const selected = this.diagram.regions.find((item: Region) => item.id === this.selectedId); if (selected) { this.selectRegion(selected); } else { this.newRegion(); } }
    else if (this.section === 'Connections') { const selected = this.diagram.relations.find((item: Relation) => item.id === this.selectedId); if (selected) { this.selectRelation(selected); } else { this.selectedId = ''; } }
    else if (this.section === 'Questions') { const selected = this.diagram.questions.find((item: Question) => item.id === this.selectedId); if (selected) { this.selectQuestion(selected); } else { this.selectedId = ''; } }
    else if (this.section === 'Chart facts') { const selected = this.diagram.charts.find((item: Chart) => item.id === this.selectedId); if (selected) { this.selectChart(selected); } else { this.selectedId = ''; } }
  }
  private region(rectangle: boolean): Region {
    const x = Number(this.x), y = Number(this.y), w = Number(this.regionWidth), h = Number(this.regionHeight);
    if (rectangle && (![x, y, w, h].every(Number.isFinite) || w <= 0 || h <= 0)) { throw new Error(tr('tm_3f4aa48e91b0')); }
    const polygons: Polygon[] = rectangle ? [{ outer: [{ x: x, y: y }, { x: x + w, y: y }, { x: x + w, y: y + h }, { x: x, y: y + h }], holes: [] }] : JSON.parse(this.geometry) as Polygon[];
    return { id: this.selectedId || `region-${uid()}`, label: this.label.trim(), description: this.description, polygons: polygons,
      line: rectangle ? [] : JSON.parse(this.lines) as Point[], lineWidth: this.diagram!.regions.find((item: Region) => item.id === this.selectedId)?.lineWidth || 8, zIndex: Number(this.layer), readingOrder: Number(this.order),
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
    }).then(() => { this.syncSelectedForm(); });
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
        options: this.options.split('\n').filter((s: string) => !!s.trim()).map((s: string): AnswerOption => { const at = s.indexOf('|'); if (at <= 0) { throw new Error(tr('tm_2f1b319822b4')); } return { id: s.slice(0, at).trim(), label: s.slice(at + 1).trim() }; }),
        acceptedAnswers: this.answers.split(',').map((s: string) => s.trim()).filter((s: string) => !!s), hint: this.hint,
        explanation: this.description, requiredRevision: this.diagram!.revision, review: this.review() };
      if (!question.prompt || question.options.length < 2 || question.options.some((o) => !o.id || !o.label)) { throw new Error(tr('tm_df510917bf62')); }
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
      const chart = this.currentChart(); if (!chart) { throw new Error(tr('tm_4a1668bca31c')); }
      chart.title = this.chartTitle; chart.kind = this.chartKind as 'bar' | 'line';
      chart.xAxis.scale = this.xScale as 'linear' | 'log' | 'category';
      chart.xAxis.domain = this.xDomain.trim() ? this.xDomain.split(',').map((value: string) => Number(value.trim())) : [];
      chart.xAxis.ticks = this.ticks(this.xTicks); chart.yAxis.ticks = this.ticks(this.yTicks);
      if (chart.xAxis.scale !== 'category' && (chart.xAxis.domain.length !== 2 || !chart.xAxis.domain.every(Number.isFinite) || chart.xAxis.domain[0] >= chart.xAxis.domain[1] || (chart.xAxis.scale === 'log' && chart.xAxis.domain[0] <= 0))) { throw new Error(tr('tm_88ecd79788f9')); }
      chart.xAxis.label = this.xLabel; chart.xAxis.unit = this.xUnit;
      chart.yAxis.label = this.yLabel; chart.yAxis.unit = this.yUnit; chart.yAxis.scale = this.yScale as 'linear' | 'log' | 'category';
      chart.yAxis.domain = [Number(this.yMinimum), Number(this.yMaximum)];
      if (!chart.yAxis.domain.every(Number.isFinite) || chart.yAxis.domain[0] >= chart.yAxis.domain[1] || (chart.yAxis.scale === 'log' && chart.yAxis.domain[0] <= 0)) { throw new Error(tr('tm_3c0eb14c1cab')); }
      chart.evidence = [{ sourceId: this.diagram!.source.id, reference: this.reference, origin: 'human-authored' }];
      this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2);
    });
  }
  private ticks(text: string): Tick[] {
    return text.split('\n').filter((line: string) => !!line.trim()).map((line: string): Tick => {
      const separator = line.indexOf('|'); const value = Number(line.slice(0, separator)); const label = line.slice(separator + 1).trim();
      if (separator < 1 || !Number.isFinite(value) || !label) { throw new Error(tr('tm_2f38e77fad1b')); }
      return { value: value, label: label };
    });
  }
  private storeSeries(): void {
    this.change(() => {
      const chart = this.currentChart(); if (!chart || !this.seriesLabel.trim()) { throw new Error(tr('tm_489e8f8a2411')); }
      const series = chart.series.find((item: Series) => item.id === this.seriesId);
      if (series) { series.label = this.seriesLabel.trim(); } else { this.seriesId = `series-${uid()}`; chart.series.push({ id: this.seriesId, label: this.seriesLabel.trim(), values: [] }); }
      this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2);
    });
  }
  private storeChartValue(): void {
    this.change(() => {
      const chart = this.currentChart(); if (!chart) { throw new Error(tr('tm_ed7a903c0ef3')); }
      const series = chart.series.find((s: Series) => s.id === this.seriesId);
      if (!series) { throw new Error(tr('tm_c575271cd9f7')); }
      const value: ChartValue = { id: this.valueId || `value-${uid()}`, regionId: this.valueRegion, x: this.valueLabel,
        value: this.valueNumber.trim() ? Number(this.valueNumber) : null, precision: Number(this.valuePrecision),
        evidence: [{ sourceId: this.diagram!.source.id, reference: this.reference, origin: 'human-authored' }] };
      if (!this.diagram!.regions.some((r: Region) => r.id === value.regionId) || (value.value !== null && !Number.isFinite(value.value)) || !Number.isInteger(value.precision) || value.precision < 0 || value.precision > 10) { throw new Error(tr('tm_ff745d267793')); }
      series.values = series.values.filter((v: ChartValue) => v.id !== value.id).concat([value]);
      this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2); this.valueId = value.id;
    });
  }
  private async mark(kind: string): Promise<void> {
    await this.change(() => {
      if (this.diagram!.source.path.endsWith('.svg') && !this.diagram!.source.previewPath && (kind === 'geometry' || kind === 'meaning')) { throw new Error(tr('tm_3afc991dde4b')); }
      if (this.section === 'Questions') {
        const question = this.diagram!.questions.find((q) => q.id === this.selectedId);
        if (!question) { throw new Error(tr('tm_155d2d5a8f2f')); }
        const issues = validateQuestion(this.diagram!, question); if (issues.length) { throw new Error(issues.join('\n')); }
      }
      this.editor!.markReviewed(this.selectedId, kind, this.reviewer);
    });
  }
  private async publish(): Promise<void> {
    if (this.busy) { return; } this.busy = true; const lifetime = this.lifetime;
    try {
      if (this.diagram!.source.path.endsWith('.svg') && !this.diagram!.source.previewPath) { throw new Error(tr('tm_8b38125aa713')); }
      if (this.diagram!.audio.length > 0 && !this.speechReviewed) { throw new Error(tr('tm_37c97921c5a7')); }
      const published = this.editor!.publish(this.reviewer);
      const material = await this.repository.saveDraft(published, this.current!);
      material.draft = false;
      material.manifest.author = { name: this.reviewer, declaration: 'I reviewed geometry, meaning, numerical facts and lesson answers against the stated source or an equivalent accessible reference.' };
      writeBytes(`${material.directory}/manifest.json`, encode(JSON.stringify(material.manifest)));
      await this.repository.saveMaterial(material); this.current = material; if (lifetime === this.lifetime) { this.onSaved(material); }
      this.status = material.ready ? tr('tm_cd85425931b2') : tr('tm_f8847e9dae6d');
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
    const checkpoint = this.editor!.clone(); const previous = checkpoint.diagram;
    try {
      const target = this.labels().find((l: AudioLabel) => l.targetId === this.audioTarget && l.kind === this.audioKind);
      if (!target || !this.audioProvenance.trim()) { throw new Error(tr('tm_e70ac56176a9')); }
      const uri = await this.repository.pick(); if (!uri || lifetime !== this.lifetime) { return; }
      const bytes = readBytes(uri, 10 * 1024 * 1024);
      if (bytes.length < 44 || String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]) !== 'RIFF') { throw new Error(tr('tm_2b393958a4ea')); }
      const duration = wavDuration(bytes); this.audioDuration = String(duration);
      const hash = await digest(bytes); const textHash = await digest(encode(target.text));
      if (lifetime !== this.lifetime) { return; } const path = `audio/${hash}.wav`;
      const audio: Audio = { id: `audio-${uid()}`, targetId: target.targetId, kind: target.kind as 'label' | 'description' | 'question' | 'overview',
        path: path, textHash: textHash, language: this.diagram!.language, provider: 'recording', voice: this.audioProvenance, sha256: hash, durationMs: duration };
      const diagram = this.editor!.diagram; diagram.audio = diagram.audio.filter((a) => a.targetId !== audio.targetId || a.kind !== audio.kind).concat([audio]);
      const issues = validateDiagram(diagram); if (issues.length) { throw new Error(issues[0]); }
      writeBytes(`${this.current!.directory}/${path}`, bytes);
      this.editor = new DraftEditor(diagram); await this.save(); this.speechReviewed = false; this.status = tr('tm_298a218c2f72');
    } catch (error) { this.editor = checkpoint; this.diagram = previous; this.error(error as Error); } finally { this.busy = false; }
  }
  private async cloudSpeech(): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.preparing = true; const lifetime = this.lifetime;
    const checkpoint = this.editor!.clone(); const previous = checkpoint.diagram;
    try {
      if (publicationIssues(this.diagram!).length > 0) { throw new Error(tr('tm_85a9713a4ba0')); }
      const original = this.editor!.diagram;
      const labels = this.labels(); for (const item of labels) { item.textHash = await digest(encode(item.text)); }
      if (lifetime !== this.lifetime) { return; }
      const received: PreparedAudio[] = [];
      for (let offset = 0; offset < labels.length; offset += 100) {
        this.status = tr('tm_cc68b223546d', [String(offset + 1), String(Math.min(offset + 100, labels.length)), String(labels.length)]);
        const result = await this.preparation.speech(original, labels.slice(offset, offset + 100), this.ttsConsent);
        if (lifetime !== this.lifetime) { return; }
        if (!Array.isArray(result.result.audio)) { throw new Error(tr('tm_be91f9952bc3')); }
        received.push(...result.result.audio);
      }
      if (this.editor!.diagram.revision !== original.revision || this.editor!.diagram.source.sha256 !== original.source.sha256) { throw new Error(tr('tm_0be1cbc73551')); }
      if (received.length !== labels.length) { throw new Error(tr('tm_1d23255ff9d4')); }
      const prepared: Audio[] = []; const staged: StagedAudio[] = []; const targets: string[] = [];
      for (const item of received) {
        const expected = labels.find((l: AudioLabel) => l.targetId === item.targetId && l.kind === item.kind);
        const bytes = base64Bytes(item.dataBase64);
        const target = `${item.targetId}:${item.kind}`;
        if (!expected || targets.includes(target) || expected.textHash !== item.textHash || item.language !== original.language || bytes.length > 10 * 1024 * 1024 || await digest(bytes) !== item.sha256 || !safePath(item.path) || !/^audio\/[a-zA-Z0-9_-][a-zA-Z0-9_.-]*\.wav$/.test(item.path)) { throw new Error(tr('tm_24876d4d404d')); }
        const actualDuration = wavDuration(bytes);
        if (!Number.isFinite(item.durationMs) || Math.abs(actualDuration - item.durationMs) > Math.max(100, item.durationMs * 0.05)) { throw new Error(tr('tm_ed4efe89c160')); }
        const localPath = `audio/${item.sha256}.wav`;
        targets.push(target); if (!staged.some((asset: StagedAudio) => asset.path === localPath)) { staged.push({ path: localPath, bytes: bytes }); }
        prepared.push({ id: item.id, targetId: item.targetId, kind: item.kind, path: localPath, textHash: item.textHash, language: item.language,
          provider: item.provider, voice: item.voice, sha256: item.sha256, durationMs: actualDuration });
      }
      const diagram = this.editor!.diagram; diagram.audio = prepared;
      const issues = validateDiagram(diagram); if (issues.length) { throw new Error(tr('tm_a1fcd5327c96', [String(issues[0])])); }
      if (lifetime !== this.lifetime) { return; }
      for (const asset of staged) { writeBytes(`${this.current!.directory}/${asset.path}`, asset.bytes); }
      this.editor = new DraftEditor(diagram); await this.save();
      this.speechReviewed = false; this.status = tr('tm_3055a392d70a');
    } catch (error) { this.editor = checkpoint; this.diagram = previous; this.error(error as Error); } finally { this.busy = false; this.preparing = false; this.ttsConsent = false; }
  }
  private async analyze(): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.preparing = true; const lifetime = this.lifetime;
    const checkpoint = this.editor!.clone(); const previous = checkpoint.diagram;
    try {
      const original = this.editor!.diagram;
      const result = await this.preparation.draft(readBytes(`${this.current!.directory}/${original.source.path}`), original, original.source.path.endsWith('.svg'), this.aiConsent);
      if (lifetime !== this.lifetime) { return; }
      result.result.diagram.packageId = original.packageId;
      result.result.diagram.source.id = original.source.id;
      result.result.diagram.regions.forEach((region: Region) => { region.evidence.forEach((evidence) => { evidence.sourceId = original.source.id; }); });
      result.result.diagram.relations.forEach((relation: Relation) => { relation.evidence.forEach((evidence) => { evidence.sourceId = original.source.id; }); });
      result.result.diagram.charts.forEach((chart: Chart) => { chart.evidence.forEach((evidence) => { evidence.sourceId = original.source.id; }); chart.series.forEach((series: Series) => { series.values.forEach((value: ChartValue) => { value.evidence.forEach((evidence) => { evidence.sourceId = original.source.id; }); }); }); });
      result.result.diagram.source.attribution = original.source.attribution;
      result.result.diagram.source.license = original.source.license;
      const preview = result.result.previewBase64 ? base64Bytes(result.result.previewBase64) : undefined;
      if (result.result.diagram.source.previewPath && (!preview || preview.length > 10 * 1024 * 1024 || await digest(preview) !== result.result.diagram.source.previewSha256)) { throw new Error(tr('tm_a35a386cd6e4')); }
      if (preview) { await verifySourcePreview(preview, result.result.diagram.source.width, result.result.diagram.source.height); result.result.diagram.source.previewPath = `source-preview-${result.result.diagram.source.previewSha256}.png`; }
      const normalized = result.result.sourceBase64 ? base64Bytes(result.result.sourceBase64) : readBytes(`${this.current!.directory}/${original.source.path}`);
      if (normalized.length > 10 * 1024 * 1024 || await digest(normalized) !== result.result.diagram.source.sha256) { throw new Error(tr('tm_c0f0d2248b27')); }
      if (this.editor!.diagram.revision !== original.revision || this.editor!.diagram.source.sha256 !== original.source.sha256) {
        this.lateResult = result.result.diagram; this.lateBytes = normalized; this.latePreview = preview; this.status = tr('tm_22260806af30'); return;
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
        this.speechReviewed = false; this.status = tr('tm_82ca7565c4aa', [String(result.provider), String(result.model)]); return;
      }
      result.result.diagram.source.path = original.source.path;
      if (preview && result.result.diagram.source.previewPath) { writeBytes(`${this.current!.directory}/${result.result.diagram.source.previewPath}`, preview); }
      if (!this.editor!.replaceFromJob(result.result.diagram, original.source.sha256, original.revision)) { this.lateResult = result.result.diagram; this.status = tr('tm_22260806af30'); return; }
      await this.save();
      this.speechReviewed = false; this.status = tr('tm_0980e2c898d3', [String(result.provider), String(result.model), String(result.result.report.unsupported.join('; ')), String(result.result.report.unresolved.join('; '))]);
    } catch (error) { this.editor = checkpoint; this.diagram = previous; this.error(error as Error); } finally { this.busy = false; this.preparing = false; this.aiConsent = false; }
  }
  private draw(): void {
    if (!this.diagram) { return; }
    const ctx = this.context, d = this.diagram;
    const scale = Math.min(this.canvasWidth / d.source.width, 240 / d.source.height);
    ctx.clearRect(0, 0, this.canvasWidth, 240); ctx.save(); ctx.scale(scale, scale);
    if (!d.source.path.endsWith('.svg') || d.source.previewPath) { const source = new ImageBitmap(`file://${this.current!.directory}/${d.source.previewPath || d.source.path}`); ctx.drawImage(source, 0, 0, d.source.width, d.source.height); }
    d.regions.forEach((r) => {
      ctx.strokeStyle = r.id === this.selectedId ? '#ffbe72' : '#26dbc0'; ctx.lineWidth = 3 / scale; ctx.fillStyle = '#2226dbc0';
      r.polygons.forEach((poly) => { ctx.beginPath(); poly.outer.forEach((point: Point, i: number) => { if (i === 0) { ctx.moveTo(point.x, point.y); } else { ctx.lineTo(point.x, point.y); } }); ctx.closePath(); poly.holes.forEach((hole: Point[]) => { hole.forEach((point: Point, i: number) => { if (i === 0) { ctx.moveTo(point.x, point.y); } else { ctx.lineTo(point.x, point.y); } }); ctx.closePath(); }); ctx.stroke(); });
      if (r.line.length > 0) { ctx.beginPath(); r.line.forEach((point: Point, i: number) => { if (i === 0) { ctx.moveTo(point.x, point.y); } else { ctx.lineTo(point.x, point.y); } }); ctx.stroke(); }
    }); ctx.restore();
  }
  @Builder reviewControls() {
    Column({ space: 5 }) { Text(tr('tm_32a93cdc9546')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.reviewer }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((text: string) => { this.reviewer = text; }).accessibilityText(tr('tm_32a93cdc9546')) }.width('100%').alignItems(HorizontalAlign.Start)
    Text(tr('tm_7d579750dd34')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2')
    if (this.section === 'Objects') {
      Button(tr('tm_ce58fe5c1b1f')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.mark('geometry'); })
      Button(tr('tm_1ef25a109052')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.mark('meaning'); })
    } else {
      Button(tr('tm_797c1d4e2bc5')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.mark('fact'); })
    }
  }
  build() {
    Column({ space: 14 }) {
      Text(tr('tm_d2762a8a845f')).fontSize(13 * this.repository.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#69E2C5').letterSpacing(2).width('100%')
      Text(this.diagram?.title || tr('tm_616cb218a65b')).fontSize(28 * this.repository.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%')
      Text(tr('tm_72ed767cd17d', [String(this.diagram?.source.attribution || tr('tm_cae059c8c263')), String(this.diagram?.source.license || tr('tm_33c2301284ff'))])).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%')
      if (this.diagram?.source.path.endsWith('.svg') && !this.diagram?.source.previewPath) { Text(tr('tm_ed9057110dfa')).fontColor('#FFCE90').fontSize(16 * this.repository.profile.textScale).width('100%') }
      Canvas(this.context).width('100%').height(240).backgroundColor('#FFFFFF').borderRadius(12).accessibilityText(tr('tm_c3421818a16b')).onReady(() => { this.draw(); }).onAreaChange((_old: Area, area: Area) => { this.canvasWidth = Number(area.width); this.draw(); })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(['Objects', 'Connections', 'Questions', 'Chart facts', 'Speech', 'Publish'], (tab: string) => {
          Button(tr(englishKey(tab))).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).borderRadius(8).margin(3).fontColor(this.section === tab ? '#09252A' : '#F3F8FA').backgroundColor(this.section === tab ? '#69E2C5' : '#284450').constraintSize({ minHeight: 46 * this.repository.profile.textScale }).padding(10).fontSize(16 * this.repository.profile.textScale).onClick(() => { this.section = tab; this.selectedId = ''; })
        })
      }.width('100%')
      Text(this.status).fontSize(16 * this.repository.profile.textScale).fontColor('#FFCE90').width('100%').accessibilityText(this.status)
      if (this.preparing) { Button(tr('tm_a6f4b10f5151')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.lifetime++; this.preparation.cancel(); this.status = tr('tm_975d2775a80c'); }) }
      Row({ space: 8 }) {
        Button(tr('tm_a8283ade3185')).fontSize(16 * this.repository.profile.textScale).constraintSize({ minHeight: 48 * this.repository.profile.textScale }).layoutWeight(1).enabled(!this.busy && !!this.editor?.canUndo).onClick(() => { this.change(() => { this.editor!.undo(); this.materialTitle = this.editor!.diagram.title; this.materialDescription = this.editor!.diagram.description; }).then(() => { this.syncSelectedForm(); }); })
        Button(tr('tm_74273989b096')).fontSize(16 * this.repository.profile.textScale).constraintSize({ minHeight: 48 * this.repository.profile.textScale }).layoutWeight(1).enabled(!this.busy && !!this.editor?.canRedo).onClick(() => { this.change(() => { this.editor!.redo(); this.materialTitle = this.editor!.diagram.title; this.materialDescription = this.editor!.diagram.description; }).then(() => { this.syncSelectedForm(); }); })
      }.width('100%')
      if (this.section === 'Objects' && this.diagram) {
        ForEach(this.diagram.regions, (r: Region) => {
          Button(tr('tm_b8671a49e61d', [String(r.label), String(tr(englishKey(r.geometryReview.status))), String(tr(englishKey(r.meaningReview.status)))])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).width('100%').constraintSize({ minHeight: 50 * this.repository.profile.textScale }).backgroundColor('#284450').onClick(() => { this.selectRegion(r); })
        }, (r: Region) => r.id)
        Button(tr('tm_3048b961ca0e')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.newRegion(); })
        Column({ space: 5 }) { Text(tr('tm_2d88b0b248c3')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.label }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.label = s; }).accessibilityText(tr('tm_2d88b0b248c3')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_6006592e34ef')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.description }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.description = s; }).accessibilityText(tr('tm_6006592e34ef')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_47cada6bf598')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText(tr('tm_47cada6bf598')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_81a0b4c37665')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.x }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.x = s; }).accessibilityText(tr('tm_81a0b4c37665')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_7bb361017864')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.y }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.y = s; }).accessibilityText(tr('tm_7bb361017864')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_0393ab9eaed4')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.regionWidth }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.regionWidth = s; }).accessibilityText(tr('tm_0393ab9eaed4')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_71641220e3e8')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.regionHeight }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.regionHeight = s; }).accessibilityText(tr('tm_71641220e3e8')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_b24ec2941e99')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.order }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.order = s; }).accessibilityText(tr('tm_b24ec2941e99')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_321f15782538')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.layer }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.layer = s; }).accessibilityText(tr('tm_321f15782538')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_be8f46901c59')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeRegion(true); })
        Column({ space: 5 }) { Text(tr('tm_70fab8c02082')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.geometry }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.geometry = s; }).accessibilityText(tr('tm_70fab8c02082')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_0acd6ced873a')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.lines }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.lines = s; }).accessibilityText(tr('tm_0acd6ced873a')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_43797f284f73')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeRegion(false); })
        if (this.selectedId) {
          this.reviewControls()
          Button(tr('tm_cfdef3adfaaf')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeRegion(this.selectedId); this.newRegion(); }); })
        }
      } else if (this.section === 'Connections' && this.diagram) {
        ForEach(this.diagram.relations, (r: Relation) => { Button(tr('tm_1d437955c648', [String(r.label), String(r.fromId), String(r.toId)])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectRelation(r); }) }, (r: Relation) => r.id)
        Button(tr('tm_729bceeec816')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectedId = ''; this.label = ''; this.path = 'null'; })
        Text(tr('tm_88c0ad66a9f1') + this.diagram.regions.map((r: Region) => `${r.id} = ${r.label}`).join('; ')).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        Column({ space: 5 }) { Text(tr('tm_052e8911351a')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.label }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.label = s; }).accessibilityText(tr('tm_052e8911351a')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_a241984ca8f3')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.fromId }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.fromId = s; }).accessibilityText(tr('tm_a241984ca8f3')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_3809adb386ba')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.toId }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.toId = s; }).accessibilityText(tr('tm_3809adb386ba')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_fb68abc68c75')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.relationType }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.relationType = s; }).accessibilityText(tr('tm_fb68abc68c75')) }.width('100%').alignItems(HorizontalAlign.Start)
        Select([{ value: tr('tm_9dc08e403382') }, { value: tr('tm_ff7772053abf') }, { value: tr('tm_b23a6a8439c0') }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(tr(englishKey(this.relationDirection))).onSelect((index: number) => { this.relationDirection = ['forward', 'both', 'unknown'][index]; }).accessibilityText(tr('tm_9c8a9579abe5'))
        Column({ space: 5 }) { Text(tr('tm_16265fe9e149')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.path }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.path = s; }).accessibilityText(tr('tm_16265fe9e149')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_56f2c2277683')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText(tr('tm_56f2c2277683')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_df24ef128adf')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeRelation(); })
        if (this.selectedId) {
          this.reviewControls()
          Button(tr('tm_e960651babb1')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeRelation(this.selectedId); this.selectedId = ''; }); })
        }
      } else if (this.section === 'Questions' && this.diagram) {
        ForEach(this.diagram.questions, (q: Question) => { Button(tr('tm_cd55a9d95751', [String(q.prompt), String(tr(englishKey(q.review.status)))])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectQuestion(q); }) }, (q: Question) => q.id)
        Button(tr('tm_bef593642651')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectedId = ''; this.label = ''; this.facts = ''; this.options = ''; this.answers = ''; this.description = ''; this.hint = ''; })
        Column({ space: 5 }) { Text(tr('tm_25b953a5005d')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.label }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.label = s; }).accessibilityText(tr('tm_25b953a5005d')) }.width('100%').alignItems(HorizontalAlign.Start)
        Select([{ value: tr('tm_35e786aa7fb8') }, { value: tr('tm_93c4abe27cf1') }, { value: tr('tm_bf37c7c20871') }, { value: tr('tm_c271f2bb9318') }, { value: tr('tm_cd42404d52ad') }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(tr(englishKey(this.questionType))).onSelect((index: number) => { this.questionType = ['adjacency', 'direction', 'sequence', 'comparison', 'value'][index]; }).accessibilityText(tr('tm_efe8656fc7c2'))
        Column({ space: 5 }) { Text(tr('tm_410d02d8aee8')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.facts }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.facts = s; }).accessibilityText(tr('tm_410d02d8aee8')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_50d33b6c8c20')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.options }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.options = s; }).accessibilityText(tr('tm_50d33b6c8c20')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_872695b262ce')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.answers }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.answers = s; }).accessibilityText(tr('tm_872695b262ce')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_a19403240930')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.hint }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.hint = s; }).accessibilityText(tr('tm_a19403240930')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_6c25007b3429')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.description }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.description = s; }).accessibilityText(tr('tm_6c25007b3429')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_7f94c0ba49b2')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeQuestion(); })
        if (this.selectedId) {
          this.reviewControls()
          Button(tr('tm_1d1979df7a81')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeQuestion(this.selectedId); this.selectedId = ''; }); })
        }
      } else if (this.section === 'Chart facts' && this.diagram) {
        ForEach(this.diagram.charts, (chart: Chart) => { Button(chart.title).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.selectChart(chart); }) }, (chart: Chart) => chart.id)
        Button(tr('tm_b4aed33bb52c')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.newChart(); })
        Text(tr('tm_47f19350c9aa')).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        if (this.currentChart()) {
          Select([{ value: tr('tm_fcde2b2edba5') }, { value: tr('tm_38a9c1e72158') }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(tr(englishKey(this.chartKind))).onSelect((index: number) => { this.chartKind = ['bar', 'line'][index]; }).accessibilityText(tr('tm_30e43125e8a0'))
          Column({ space: 5 }) { Text(tr('tm_f11cdc8d1a1d')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.chartTitle }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.chartTitle = s; }).accessibilityText(tr('tm_f11cdc8d1a1d')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_f5f7687e5903')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.xLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.xLabel = s; }).accessibilityText(tr('tm_f5f7687e5903')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_374b716806e6')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.xUnit }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.xUnit = s; }).accessibilityText(tr('tm_374b716806e6')) }.width('100%').alignItems(HorizontalAlign.Start)
          Select([{ value: tr('tm_edb2cd3b74c9') }, { value: tr('tm_7f2fe580edb3') }, { value: tr('tm_836ff184e7b4') }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(tr(englishKey(this.xScale))).onSelect((index: number) => { this.xScale = ['category', 'linear', 'log'][index]; }).accessibilityText(tr('tm_69f0af3db9bc'))
          Column({ space: 5 }) { Text(tr('tm_25884fb4eb21')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.xDomain }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.xDomain = s; }).accessibilityText(tr('tm_25884fb4eb21')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_b8d7e6966be0')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.xTicks }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.xTicks = s; }).accessibilityText(tr('tm_b8d7e6966be0')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_d6eb4b9eaa69')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yLabel = s; }).accessibilityText(tr('tm_d6eb4b9eaa69')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_575b012abe5a')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yUnit }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yUnit = s; }).accessibilityText(tr('tm_575b012abe5a')) }.width('100%').alignItems(HorizontalAlign.Start)
          Select([{ value: tr('tm_7f2fe580edb3') }, { value: tr('tm_836ff184e7b4') }]).font({ size: 16 * this.repository.profile.textScale }).optionFont({ size: 16 * this.repository.profile.textScale }).width('100%').value(tr(englishKey(this.yScale))).onSelect((index: number) => { this.yScale = ['linear', 'log'][index]; }).accessibilityText(tr('tm_00f7e90e48ad'))
          Column({ space: 5 }) { Text(tr('tm_26abf7f1d651')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yMinimum }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yMinimum = s; }).accessibilityText(tr('tm_26abf7f1d651')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_371cd2fe3cf5')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.yMaximum }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.yMaximum = s; }).accessibilityText(tr('tm_371cd2fe3cf5')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_151a02175b97')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.yTicks }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.yTicks = s; }).accessibilityText(tr('tm_151a02175b97')) }.width('100%').alignItems(HorizontalAlign.Start)
          Column({ space: 5 }) { Text(tr('tm_1fe108692ec5')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText(tr('tm_1fe108692ec5')) }.width('100%').alignItems(HorizontalAlign.Start)
          Button(tr('tm_cb9002ea4db5')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeChartAxes(); })
          Column({ space: 5 }) { Text(tr('tm_3613c931274a')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.seriesLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.seriesLabel = s; }).accessibilityText(tr('tm_3613c931274a')) }.width('100%').alignItems(HorizontalAlign.Start)
          Button(tr('tm_33bacce6036c')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeSeries(); })
          Button(tr('tm_572fc65bbe00')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.seriesId = ''; this.seriesLabel = ''; this.valueId = ''; })
          ForEach(this.currentChart()!.series, (series: Series) => {
            Button(tr('tm_37254c4dc292', [String(series.label)])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.seriesId = series.id; this.seriesLabel = series.label; this.valueId = ''; this.valueLabel = ''; this.valueRegion = ''; this.valueNumber = ''; })
            ForEach(series.values, (value: ChartValue) => {
              Button(tr('tm_1bb63916aa36', [String(value.x), String(value.value === null ? tr('tm_b23a6a8439c0') : value.value), String(this.yUnit)])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.seriesId = series.id; this.valueId = value.id; this.valueLabel = value.x; this.valueRegion = value.regionId; this.valueNumber = value.value === null ? '' : String(value.value); this.valuePrecision = String(value.precision); this.reference = value.evidence.map((e) => e.reference).join('; '); })
            }, (value: ChartValue) => value.id)
          }, (series: Series) => series.id)
          if (this.seriesId) {
            Column({ space: 5 }) { Text(tr('tm_15b4e487fba0')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valueLabel }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valueLabel = s; }).accessibilityText(tr('tm_15b4e487fba0')) }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text(tr('tm_04e01846e2b9')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valueRegion }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valueRegion = s; }).accessibilityText(tr('tm_04e01846e2b9')) }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text(tr('tm_c67c9cb8ec87')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valueNumber }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valueNumber = s; }).accessibilityText(tr('tm_c67c9cb8ec87')) }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text(tr('tm_380f41186ad7')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.valuePrecision }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.valuePrecision = s; }).accessibilityText(tr('tm_380f41186ad7')) }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 5 }) { Text(tr('tm_62fea484541c')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.reference }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.reference = s; }).accessibilityText(tr('tm_62fea484541c')) }.width('100%').alignItems(HorizontalAlign.Start)
            Button(tr('tm_3add7f06d365')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.storeChartValue(); })
            if (this.valueId) { Button(tr('tm_d457d5d1c986')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { const chart = this.currentChart()!; const series = chart.series.find((s: Series) => s.id === this.seriesId)!; series.values = series.values.filter((v: ChartValue) => v.id !== this.valueId); this.editor!.updateChart(chart); this.chartJson = JSON.stringify(chart, null, 2); this.valueId = ''; }); }) }
          }
        }
        Column({ space: 5 }) { Text(tr('tm_488ba29b605b')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.chartJson }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(100 * this.repository.profile.textScale).onChange((s: string) => { this.chartJson = s; }).accessibilityText(tr('tm_488ba29b605b')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_380358513dd3')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { const chart = JSON.parse(this.chartJson) as Chart; this.editor!.updateChart(chart); this.selectedId = chart.id; }); })
        if (this.selectedId) { this.reviewControls(); Button(tr('tm_0d8d5dac77bd')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { this.editor!.removeChart(this.selectedId); this.selectedId = ''; this.chartJson = ''; }); }) }
      } else if (this.section === 'Speech' && this.diagram) {
        Text(tr('tm_23184fe68aaa')).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        ForEach(this.labels(), (item: AudioLabel) => {
          Button(tr('tm_fb62fe2ae6b2', [String(tr(englishKey(item.kind))), String(item.text)])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.audioTarget = item.targetId; this.audioKind = item.kind; this.audioText = item.text; })
        }, (item: AudioLabel) => `${item.targetId}:${item.kind}`)
        Text(tr('tm_76ec3151dd66', [String(tr(englishKey(this.audioKind))), String(this.audioText)])).fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA')
        Column({ space: 5 }) { Text(tr('tm_b094b1aeffa5')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.audioProvenance }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.audioProvenance = s; }).accessibilityText(tr('tm_b094b1aeffa5')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_949b9368f46f')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.audioDuration }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.audioDuration = s; }).accessibilityText(tr('tm_949b9368f46f')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_36c5f684ff7c')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.importAudio(); })
        Button(tr('tm_74532a87507f')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { feedback.speak(this.current!, this.audioTarget, this.audioKind, this.repository.profile, true); })
        Row({ space: 8 }) { Checkbox().select(this.ttsConsent).onChange((value: boolean) => { this.ttsConsent = value; }); Text(tr('tm_28d46a1b6b9a')).fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA').layoutWeight(1) }.width('100%')
        Button(tr('tm_4dd95d968c9d')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.cloudSpeech(); })
      } else if (this.section === 'Publish' && this.diagram) {
        Column({ space: 5 }) { Text(tr('tm_f5e2ce5b03c3')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.materialTitle }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.materialTitle = s; }).accessibilityText(tr('tm_f5e2ce5b03c3')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_c4ecfe02822e')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { if (!this.materialTitle.trim()) { throw new Error(tr('tm_daae03881f7a')); } this.editor!.setTitle(this.materialTitle.trim()); }); })
        Column({ space: 5 }) { Text(tr('tm_59087d84a871')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextArea({ text: this.materialDescription }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(160 * this.repository.profile.textScale).onChange((s: string) => { this.materialDescription = s; }).accessibilityText(tr('tm_59087d84a871')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_c10e39f5393c')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.change(() => { if (!this.materialDescription.trim()) { throw new Error(tr('tm_c072daa1cc0a')); } this.editor!.setDescription(this.materialDescription.trim()); }); })
        Column({ space: 5 }) { Text(tr('tm_a58e1ab05e2c')).fontSize(14 * this.repository.profile.textScale).fontColor('#B7C8D2').width('100%'); TextInput({ text: this.reviewer }).fontSize(16 * this.repository.profile.textScale).fontColor('#102B34').backgroundColor('#ECF4F7').borderRadius(9).height(50 * this.repository.profile.textScale).onChange((s: string) => { this.reviewer = s; }).accessibilityText(tr('tm_a58e1ab05e2c')) }.width('100%').alignItems(HorizontalAlign.Start)
        Text(publicationIssues(this.diagram).join('\n') || tr('tm_e1c6c0f162d6')).fontSize(16 * this.repository.profile.textScale).fontColor('#FFCE90')
        Text(offlineReadiness(this.diagram, this.current!.manifest.assets.map((a) => a.path)).missing.join('\n') || tr('tm_75ccfa3dbe81')).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        if (this.diagram.audio.length > 0) {
          Row({ space: 8 }) { Checkbox().select(this.speechReviewed).onChange((value: boolean) => { this.speechReviewed = value; }).accessibilityText(tr('tm_2faffce66200')); Text(tr('tm_1e36f7b05cce')).fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA').layoutWeight(1) }.width('100%')
        }
        Button(tr('tm_59299bc3e8b7')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.publish(); })
        Text(tr('tm_1f3fccace9c2', [String(this.repository.profile.service || tr('tm_4def603a0559'))])).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        Text(tr('tm_9f74efb63257')).fontSize(16 * this.repository.profile.textScale).fontColor('#B7C8D2')
        Row({ space: 8 }) { Checkbox().select(this.aiConsent).onChange((value: boolean) => { this.aiConsent = value; }); Text(tr('tm_ca06b4c0a8be')).fontSize(16 * this.repository.profile.textScale).fontColor('#F3F8FA').layoutWeight(1) }.width('100%')
        Button(this.diagram.source.path.endsWith('.svg') ? tr('tm_724d40e4bebb') : tr('tm_912ea17c26bc')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.analyze(); })
        if (this.lateResult) { Button(tr('tm_780e83c5e202')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.repository.profile.textScale).padding(12).borderRadius(10).constraintSize({ minHeight: 50 * this.repository.profile.textScale }).width('100%').fontColor('#09252A').backgroundColor('#69E2C5').onClick(() => { this.lateResult!.packageId = `late-${uid()}`; this.repository.createSource(this.lateResult!, this.lateBytes || readBytes(`${this.current!.directory}/${this.diagram!.source.path}`), this.latePreview).then((material: Material) => { this.onSaved(material); this.lateResult = undefined; this.status = tr('tm_e1d9614dc867'); }).catch((error: Error) => { this.error(error); }); }) }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
