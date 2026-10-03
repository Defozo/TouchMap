import { tr } from '../domain/i18n';
import { englishKey } from '../domain/EnglishStrings';
import { common } from '@kit.AbilityKit';
import { Diagram, Region, Relation, Question, Chart, Progress, Action, Point, Viewport, Series, ChartValue, AnswerOption, Submission } from '../domain/types';
import { initialProgress, orderedRegions, resumeContext, applyAction } from '../domain/engine';
import { hitTest, sourcePoint, guidePath, retainRegionNearBoundary } from '../domain/geometry';
import { assertPassiveSvg } from '../domain/media';
import { publicationIssues } from '../domain/validate';
import { Repository, Material, Profile, defaultProfile, uid, readBytes, writeBytes, digest, decode } from '../platform/Repository';
import { Preparation, sanitizeImage, Crop } from '../platform/Preparation';
import { feedback } from '../platform/Feedback';
import { RestorationFrame, RestorationObservation, RestorationFramePhases } from '../platform/RestorationFrame';
import { EditorPanel } from '../components/EditorPanel';

@Entry
@Component
struct Index {
  @StorageLink('openedUri') @Watch('incomingUri') openedUri: string = '';
  @StorageLink('appActive') @Watch('activityChanged') appActive: boolean = true;
  @State @Watch('pageChanged') page: string = 'Library';
  @State items: Material[] = [];
  @State active: Material | undefined = undefined;
  @State progress: Progress | undefined = undefined;
  @State profile: Profile = defaultProfile();
  @State ready: boolean = false;
  @State @Watch('busyChanged') busy: boolean = false;
  @State busyOperation: string = tr('tm_485918f135a4');
  @State status: string = tr('tm_eaa684aba094');
  @State interaction: string = 'Touch';
  @State overlaps: Region[] = [];
  @State scanIndex: number = 0;
  @State scanning: boolean = false;
  @State showConnections: boolean = false;
  @State tutorialStep: number = 0;
  @State tutorialFocused: string = '';
  @State pairingCode: string = '';
  @State sourceName: string = tr('tm_6d560311a68a');
  @State attribution: string = '';
  @State license: string = '';
  @State cropX: string = '0';
  @State cropY: string = '0';
  @State cropW: string = '';
  @State cropH: string = '';
  @State sourcePreview: string = '';
  @State sourceType: string = '';
  @State importWidth: number = 0;
  @State importHeight: number = 0;
  private sourceViewBox: number[] = [];
  @State deleteId: string = '';
  @State libraryQuery: string = '';
  @State libraryPage: number = 0;
  @State viewWidth: number = 320;
  @State guide: string = '';
  private sourceBytes: Uint8Array | undefined = undefined;
  private repository: Repository | undefined = undefined;
  private preparation: Preparation = new Preparation();
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private scroller: Scroller = new Scroller();
  private scanner: number = -1;
  private inputTime: number = 0;
  private dispatching: boolean = false;
  private pendingFocus: string = '';
  private feedbackEpoch: number = 0;
  private hoveredRegion: string = '';
  private restorationSequence: number = 0;
  @State exploringTouch: boolean = false;

  aboutToAppear(): void { this.initialize(); }
  aboutToDisappear(): void { feedback.stop(); this.stopScan(); }
  private async initialize(): Promise<void> {
    try {
      this.repository = new Repository(getContext(this) as common.UIAbilityContext);
      await this.repository.initialize(); this.profile = this.repository.profile;
      this.items = await this.repository.list(); await feedback.initialize();
      feedback.onStatus = (message: string) => { this.status = message; };
      this.preparation.base = this.profile.service;
      this.ready = true; this.status = tr('tm_e2435ca7facc');
      if (this.openedUri) { await this.incomingUri(); }
    } catch (error) { this.fail(error as Error); }
  }
  private fail(error: Error): void { this.status = error.message || tr('tm_9d79c0988606'); feedback.announce(this.status); }
  private busyChanged(): void { if (!this.busy && this.openedUri) { this.incomingUri(); } }
  private async incomingUri(): Promise<void> {
    if (!this.repository || !this.ready || !this.openedUri || this.busy) { return; }
    const uri = this.openedUri; this.openedUri = '';
    await this.importUri(uri);
  }
  private activityChanged(): void {
    if (!this.appActive) { this.cancelTouch(); feedback.stop(); this.stopScan(); }
    else if (this.active && this.repository && this.progress) {
      const material = this.active;
      this.repository.progress(material).then((progress: Progress) => {
        if (this.active?.key !== material.key) { return; }
        this.progress = progress;
        if (this.page === 'Explore' || this.page === 'Lesson') { this.page = 'Resume'; }
      }).catch((error: Error) => { this.fail(error); });
    }
  }
  private pageChanged(): void { this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false }); }
  private go(page: string): void { this.cancelTouch(); feedback.stop(); this.stopScan(); this.page = page; this.showConnections = false; }
  private async load(material: Material): Promise<boolean> {
    const sequence = ++this.restorationSequence;
    const measure = AppStorage.get<boolean>('measureRestoration') === true;
    const intentAtMs = Date.now();
    try {
      feedback.stop(); this.stopScan(); this.active = material;
      const restored = await this.repository!.progress(material);
      const checkpointLoadedAtMs = Date.now();
      if (this.active?.key !== material.key) { return false; }
      this.progress = restored;
      this.overlaps = [];
      if (material.draft) { this.go('Editor'); }
      else if (!material.accepted) { this.go('Accept'); }
      else if (this.progress.stateRevision > 0) { this.go('Resume'); }
      else if (!this.profile.tutorial) { this.tutorialStep = 0; this.go('Tutorial'); }
      else { this.go('Explore'); }
      this.status = tr('tm_ce0923cb334c', [String(material.diagram.regions.length), String(material.diagram.relations.length), String(material.ready ? tr('tm_c96bc61756af') : tr('tm_f579e0746646'))]);
      if (measure) {
        const expectedPage = this.page;
        const stateAppliedAtMs = Date.now();
        const frameQueuedAtMs = Date.now();
        this.getUIContext().postFrameCallback(new RestorationFrame(this.getUIContext(), (phases: RestorationFramePhases) => {
          if (sequence !== this.restorationSequence || this.active?.key !== material.key || this.page !== expectedPage || !this.progress) { return; }
          const idleAtMs = phases.idleAtMs;
          const report: RestorationObservation = { sequence: sequence, intentAtMs: intentAtMs, idleAtMs: idleAtMs,
            checkpointLoadedAtMs: checkpointLoadedAtMs, stateAppliedAtMs: stateAppliedAtMs,
            frameQueuedAtMs: frameQueuedAtMs, frameStartedAtMs: phases.frameStartedAtMs,
            layoutDoneAtMs: phases.layoutDoneAtMs, drawCommandAtMs: phases.drawCommandAtMs,
            idleDurationMs: idleAtMs > 0 ? idleAtMs - intentAtMs : 0,
            durationMs: phases.drawCommandAtMs - intentAtMs, page: this.page, packageId: material.diagram.packageId,
            contentRevision: material.diagram.revision, stateRevision: this.progress.stateRevision, lastRegionId: this.progress.lastRegionId,
            activeQuestionId: this.progress.activeQuestionId, selectedAnswers: this.progress.selectedAnswers.slice(),
            submittedCount: this.progress.submissions.length, paused: this.progress.paused,
            progress: JSON.parse(JSON.stringify(this.progress)) as Progress };
          const encoded = JSON.stringify(report);
          AppStorage.setOrCreate('restorationObservation', encoded);
          console.info(`TOUCHMAP_RESTORE_RENDER ${encoded}`);
        }));
      }
      return true;
    } catch (error) { this.fail(error as Error); return false; }
  }
  private async accept(): Promise<void> {
    try { this.active = await this.repository!.accept(this.active!); this.items = await this.repository!.list(); this.go(this.profile.tutorial ? 'Explore' : 'Tutorial'); }
    catch (error) { this.fail(error as Error); }
  }
  private focus(): Region | undefined { return this.active?.diagram.regions.find((r: Region) => r.id === this.progress?.lastRegionId); }
  private question(): Question | undefined { return this.active?.diagram.questions.find((q: Question) => q.id === this.progress?.activeQuestionId); }
  private async action(type: string, target: string = '', answerIds?: string[], viewport?: Viewport): Promise<boolean> {
    if (!this.active || !this.progress || this.dispatching) { if (type === 'focusRegion') { this.pendingFocus = target; } return false; }
    this.dispatching = true;
    const epoch = this.feedbackEpoch;
    const material = this.active; const previous = this.progress;
    try {
      const action: Action = { eventId: uid(), expectedRevision: previous.stateRevision, type: type, targetId: target, answerIds: answerIds, viewport: viewport };
      const result = applyAction(material.diagram, previous, action);
      const committed = await this.repository!.dispatch(material, action);
      if (this.active?.key !== material.key) { return false; }
      this.progress = committed;
      if (committed.activeRelationId !== previous.activeRelationId || type === 'viewport') { this.guide = ''; }
      if (epoch !== this.feedbackEpoch || !this.appActive) { return false; }
      this.status = result.feedback;
      if (['focusRegion', 'nextRegion', 'previousRegion', 'followRelation'].includes(type)) {
        feedback.speak(this.active, this.progress.lastRegionId, 'label', this.profile); feedback.cue(this.profile);
      } else if (type === 'describe') { feedback.speak(this.active, target || this.progress.lastRegionId, 'description', this.profile, true); }
      else if (type === 'openQuestion') { feedback.speak(this.active, target, 'question', this.profile, true); this.page = 'Lesson'; }
      else if (type === 'selectRelation') { feedback.speak(this.active, target, 'label', this.profile, true); }
      else if (type === 'pause') { this.go('Resume'); }
      if (!['focusRegion', 'nextRegion', 'previousRegion', 'followRelation', 'describe', 'openQuestion', 'selectRelation'].includes(type)) { feedback.announce(this.status); }
      this.draw(); return true;
    } catch (error) { if (this.active?.key === material.key) { this.fail(error as Error); this.progress = await this.repository!.progress(material); } return false; }
    finally {
      this.dispatching = false;
      if (this.pendingFocus && this.pendingFocus !== this.progress?.lastRegionId) { const next = this.pendingFocus; this.pendingFocus = ''; this.action('focusRegion', next); }
    }
  }
  private async selectAnswer(id: string): Promise<void> {
    const question = this.question(); if (!question || !this.progress) { return; }
    let selected = this.progress.selectedAnswers.slice();
    if (question.type === 'sequence' || question.acceptedAnswers.length > 1) {
      if (selected.includes(id)) { selected = selected.filter((s: string) => s !== id); } else { selected.push(id); }
    } else { selected = [id]; }
    await this.action('selectAnswer', id, selected);
  }
  private cancelTouch(): void {
    this.feedbackEpoch++; this.hoveredRegion = ''; this.pendingFocus = ''; this.exploringTouch = false; this.guide = ''; feedback.stop();
  }
  private touch(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.type === TouchType.HOVER_EXIT || event.type === TouchType.HOVER_CANCEL || event.touches.length !== 1) { this.cancelTouch(); return; }
    if (![TouchType.Down, TouchType.Move, TouchType.HOVER_ENTER, TouchType.HOVER_MOVE].includes(event.type)) { return; }
    if (this.interaction !== 'Touch') { return; }
    this.exploringTouch = true;
    this.point(event.touches[0].x, event.touches[0].y);
  }
  private point(x: number, y: number): void {
    if (!this.active || !this.progress) { return; }
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x > this.viewWidth || y > 300) { this.cancelTouch(); return; }
    if (Date.now() - this.inputTime < 35) { return; }
    this.inputTime = Date.now();
    const d = this.active.diagram;
    const fit = Math.min(this.viewWidth / d.source.width, 300 / d.source.height);
    const point = sourcePoint({ x: (x - (this.viewWidth - d.source.width * fit) / 2) / fit, y: (y - (300 - d.source.height * fit) / 2) / fit }, this.progress.viewport);
    const found = hitTest(d, point, this.progress.lastRegionId); this.overlaps = found;
    const held = found.find((region: Region) => region.id === this.hoveredRegion) || retainRegionNearBoundary(d, point, this.hoveredRegion, 2 / (fit * this.progress.viewport.scale));
    const focused = held || found[0];
    if (focused && focused.id !== this.hoveredRegion) { this.hoveredRegion = focused.id; this.action('focusRegion', focused.id); }
    else if (!focused && this.hoveredRegion) { this.feedbackEpoch++; this.hoveredRegion = ''; this.pendingFocus = ''; feedback.stop(); }
    const relation = d.relations.find((r: Relation) => r.id === this.progress!.activeRelationId);
    if (relation) {
      const reverse = relation.direction === 'both' && this.progress.lastRegionId === relation.toId;
      const destinationId = reverse ? relation.fromId : relation.toId;
      const destination = d.regions.find((r: Region) => r.id === destinationId)?.label || destinationId;
      const route = reverse && relation.path ? relation.path.slice().reverse() : relation.path;
      const guidance = guidePath(point, route, 10 / (fit * this.progress.viewport.scale), destination);
      this.guide = guidance.known ? tr('tm_a7dbfd58ee7b', [String(guidance.onPath ? tr('tm_3b3eb10961e0') : tr('tm_2e96d1a0c368')), String(Math.round(guidance.distance)), String(destination)]) : tr('tm_fe90763018c1', [String(destination)]);
    } else { this.guide = ''; }
  }
  private draw(): void {
    if (!this.active || !this.progress) { return; }
    const d = this.active.diagram, ctx = this.canvas, viewport = this.progress.viewport;
    const fit = Math.min(this.viewWidth / d.source.width, 300 / d.source.height);
    ctx.clearRect(0, 0, this.viewWidth, 300); ctx.save();
    ctx.translate((this.viewWidth - d.source.width * fit) / 2, (300 - d.source.height * fit) / 2); ctx.scale(fit, fit);
    ctx.translate(viewport.offsetX, viewport.offsetY); ctx.rotate(viewport.rotation * Math.PI / 180); ctx.scale(viewport.scale, viewport.scale);
    if (!d.source.path.endsWith('.svg') || d.source.previewPath) { const source = new ImageBitmap(`file://${this.active.directory}/${d.source.previewPath || d.source.path}`); ctx.drawImage(source, 0, 0, d.source.width, d.source.height); }
    d.regions.forEach((region: Region) => {
      const focused = region.id === this.progress!.lastRegionId;
      ctx.strokeStyle = focused ? '#D76108' : '#006857'; ctx.lineWidth = (focused ? 5 : 2) / fit / viewport.scale;
      region.polygons.forEach((poly) => { ctx.beginPath(); poly.outer.forEach((p: Point, i: number) => { if (i === 0) { ctx.moveTo(p.x, p.y); } else { ctx.lineTo(p.x, p.y); } }); ctx.closePath(); poly.holes.forEach((hole: Point[]) => { hole.forEach((p: Point, i: number) => { if (i === 0) { ctx.moveTo(p.x, p.y); } else { ctx.lineTo(p.x, p.y); } }); ctx.closePath(); }); ctx.stroke(); });
      if (region.line.length > 0) { ctx.beginPath(); region.line.forEach((p: Point, i: number) => { if (i === 0) { ctx.moveTo(p.x, p.y); } else { ctx.lineTo(p.x, p.y); } }); ctx.stroke(); }
    });
    const relation = d.relations.find((r: Relation) => r.id === this.progress!.activeRelationId);
    if (relation?.path) { ctx.beginPath(); relation.path.forEach((p: Point, i: number) => { if (i === 0) { ctx.moveTo(p.x, p.y); } else { ctx.lineTo(p.x, p.y); } }); ctx.strokeStyle = '#AD218E'; ctx.lineWidth = 6 / fit / viewport.scale; ctx.stroke(); }
    ctx.restore();
  }
  private viewport(scale: number, x: number, y: number, rotation: number = 0): void {
    if (!this.progress) { return; }
    const old = this.progress.viewport;
    this.action('viewport', '', undefined, { scale: Math.min(4, Math.max(0.5, old.scale * scale)), offsetX: old.offsetX + x, offsetY: old.offsetY + y, rotation: (old.rotation + rotation) % 360 });
  }
  private stopScan(): void { if (this.scanner >= 0) { clearInterval(this.scanner); this.scanner = -1; } this.scanning = false; }
  private scanLabel(): string {
    if (!this.active) { return ''; }
    const regions = orderedRegions(this.active.diagram);
    return this.scanIndex < regions.length ? regions[this.scanIndex].label : this.scanIndex === regions.length ? tr('tm_dc273117482b') : tr('tm_874eafc16fe2');
  }
  private announceScan(): void {
    if (!this.active) { return; }
    const regions = orderedRegions(this.active.diagram);
    const label = this.scanIndex < regions.length ? regions[this.scanIndex].label : this.scanIndex === regions.length ? tr('tm_dc273117482b') : tr('tm_874eafc16fe2');
    this.status = tr('tm_2d2cdc4f4bc4', [String(label)]); feedback.announce(this.status);
    if (!feedback.reader && this.scanIndex < regions.length) { feedback.speak(this.active, regions[this.scanIndex].id, 'label', this.profile, true); }
  }
  private startScan(): void {
    this.stopScan(); this.scanning = true; this.scanIndex = 0; this.announceScan();
    this.scanner = setInterval(() => {
      if (!this.active || !this.scanning) { return; }
      this.scanIndex = (this.scanIndex + 1) % (this.active.diagram.regions.length + 2); this.announceScan();
    }, this.profile.scanMs);
  }
  private chooseScan(): void {
    if (!this.active) { return; }
    if (this.scanIndex < this.active.diagram.regions.length) { this.action('focusRegion', orderedRegions(this.active.diagram)[this.scanIndex].id); }
    else if (this.scanIndex === this.active.diagram.regions.length) { this.showConnections = true; this.stopScan(); }
    else { this.stopScan(); this.action('pause'); }
  }
  private async saveProfile(): Promise<void> {
    try { await this.repository!.saveProfile(this.profile); this.preparation.base = this.profile.service; this.status = tr('tm_17241fe073a7'); }
    catch (error) { this.fail(error as Error); }
  }
  private async pick(): Promise<void> {
    try { const uri = await this.repository!.pick(); if (uri) { await this.importUri(uri); } }
    catch (error) { this.fail(error as Error); }
  }
  private async importUri(uri: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    this.busyOperation = tr('tm_485918f135a4');
    this.status = tr('tm_52bcdf071634');
    await new Promise<void>((resolve) => { setTimeout(resolve, 20); });
    try {
      const bytes = readBytes(uri);
      if (bytes[0] === 0x50 && bytes[1] === 0x4B) {
        const material = await this.repository!.importPackage(uri); this.items = await this.repository!.list(); await this.load(material);
        this.status = material.draft ? tr('tm_fe1159191d87') : material.accepted ? tr('tm_fb127c662d64') : tr('tm_ca5d8dbc0ae4');
      } else {
        let first = bytes.length >= 3 && bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191 ? 3 : 0;
        while (first < bytes.length && [9, 10, 13, 32].includes(bytes[first])) { first++; }
        const text = first < bytes.length && bytes[first] === 60 ? decode(bytes) : '';
        if (text.includes('<svg')) {
          if (bytes.length > 10 * 1024 * 1024) { throw new Error(tr('tm_0ad2f32d4985')); }
          assertPassiveSvg(text);
          this.sourceType = 'svg'; this.sourceBytes = bytes;
          const root = text.match(/<svg\b[^>]*>/i)?.[0] || '';
          const viewBox = root.match(/viewBox\s*=\s*["']\s*([-+0-9.eE]+)[ ,]+([-+0-9.eE]+)[ ,]+([-+0-9.eE]+)[ ,]+([-+0-9.eE]+)\s*["']/i);
          const width = root.match(/\bwidth\s*=\s*["']([+0-9.eE-]+)(?:px)?["']/i), height = root.match(/\bheight\s*=\s*["']([+0-9.eE-]+)(?:px)?["']/i);
          if ((!width && /\bwidth\s*=/.test(root)) || (!height && /\bheight\s*=/.test(root))) { throw new Error(tr('tm_be91bf9e8d5a')); }
          this.importWidth = width ? Number(width[1]) : viewBox ? Number(viewBox[3]) : 0;
          this.importHeight = height ? Number(height[1]) : viewBox ? Number(viewBox[4]) : 0;
          this.sourceViewBox = viewBox ? [Number(viewBox[1]), Number(viewBox[2]), Number(viewBox[3]), Number(viewBox[4])] : [0, 0, this.importWidth, this.importHeight];
          if (![this.importWidth, this.importHeight, ...this.sourceViewBox].every(Number.isFinite) || this.importWidth <= 0 || this.importHeight <= 0 || this.importWidth * this.importHeight > 20000000 || this.sourceViewBox[2] <= 0 || this.sourceViewBox[3] <= 0) { throw new Error(tr('tm_c15bc2e7108f')); }
        } else {
          const sanitized = await sanitizeImage(bytes); this.sourceBytes = sanitized.bytes; this.sourceType = 'png'; this.importWidth = sanitized.width; this.importHeight = sanitized.height; this.sourceViewBox = [0, 0, this.importWidth, this.importHeight];
        }
        this.cropW = String(this.importWidth); this.cropH = String(this.importHeight);
        this.sourcePreview = `${this.repository!.context.cacheDir}/source-${uid()}.${this.sourceType}`;
        writeBytes(this.sourcePreview, this.sourceBytes!); this.go('Import'); this.status = tr('tm_2f7a4e95208c');
      }
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async crop(): Promise<void> {
    try {
      if (this.sourceType !== 'png' || !this.sourceBytes) { throw new Error(tr('tm_2883907f7b76')); }
      const crop: Crop = { x: Number(this.cropX), y: Number(this.cropY), width: Number(this.cropW), height: Number(this.cropH) };
      const sanitized = await sanitizeImage(this.sourceBytes, crop); this.sourceBytes = sanitized.bytes;
      this.importWidth = sanitized.width; this.importHeight = sanitized.height; this.sourceViewBox = [0, 0, this.importWidth, this.importHeight];
      this.sourcePreview = `${this.repository!.context.cacheDir}/crop-${uid()}.png`; writeBytes(this.sourcePreview, this.sourceBytes);
      this.cropX = '0'; this.cropY = '0'; this.cropW = String(this.importWidth); this.cropH = String(this.importHeight);
      this.status = tr('tm_c94e6c3c0d9a');
    } catch (error) { this.fail(error as Error); }
  }
  private async createDraft(): Promise<void> {
    if (!this.sourceBytes || this.busy) { return; } this.busy = true;
    try {
      if (!this.attribution.trim() || !this.license.trim() || !this.sourceName.trim()) { throw new Error(tr('tm_688d6c612081')); }
      const diagram: Diagram = { schemaVersion: 1, packageId: `material-${uid()}`, revision: 1, title: this.sourceName, language: 'en',
        source: { id: 'source', sha256: await digest(this.sourceBytes), width: this.importWidth, height: this.importHeight, path: `source.${this.sourceType}`, attribution: this.attribution, license: this.license, viewBox: this.sourceViewBox.slice() },
        regions: [], relations: [], charts: [], questions: [], audio: [], description: this.sourceName };
      this.active = await this.repository!.createSource(diagram, this.sourceBytes); this.progress = initialProgress(diagram);
      this.items = await this.repository!.list(); this.go('Editor');
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async remove(material: Material): Promise<void> {
    try {
      await this.repository!.deleteMaterial(material);
      this.cancelTouch(); this.stopScan(); feedback.release();
      this.items = await this.repository!.list(); this.deleteId = '';
      if (this.active?.key === material.key) { this.active = undefined; this.progress = undefined; }
      this.status = tr('tm_a6b0a1a757c5', [String(material.diagram.revision)]);
    } catch (error) { this.fail(error as Error); }
  }
  private async exportMaterial(material: Material): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.busyOperation = tr('tm_f1b430fcd8af'); this.status = tr('tm_4b330d8b0572');
    try { this.status = await this.repository!.exportPackage(material) ? tr('tm_e77bd9099eca') : tr('tm_47c8e0cee4bd'); }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private palette(): string { return this.profile.contrast ? '#071B25' : '#142D38'; }
  private libraryMaterials(): Material[] {
    const query = this.libraryQuery.trim().toLowerCase();
    return this.items.filter((item: Material) => item.diagram.packageId !== 'tutorial' && (!query || `${item.diagram.title} ${item.diagram.packageId} revision ${item.diagram.revision}`.toLowerCase().includes(query))).sort((a: Material, b: Material) => a.diagram.title.localeCompare(b.diagram.title) || b.diagram.revision - a.diagram.revision || a.diagram.packageId.localeCompare(b.diagram.packageId));
  }
  private libraryStart(): number { return Math.min(this.libraryPage, Math.max(0, Math.ceil(this.libraryMaterials().length / 3) - 1)) * 3; }
  private tutorialSelect(id: string): void {
    const sample = this.items.find((item: Material) => item.diagram.packageId === 'tutorial');
    if (!sample) { this.status = tr('tm_8aefda887337'); return; }
    this.tutorialFocused = id;
    const region = sample.diagram.regions.find((r: Region) => r.id === id);
    if (region) { this.status = tr('tm_3f4f403ebf04', [String(region.label), String(region.description)]); feedback.speak(sample, id, 'label', this.profile, true); feedback.cue(this.profile); }
  }
  @Builder library() {
    Column({ space: 8 }) { Text(tr('tm_73a3e7573256')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_4ab1408d52fb')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Row({ space: 10 }) {
      Text(tr('tm_beaa2b2db8bb')).fontSize(11).fontWeight(FontWeight.Bold).fontColor('#69E2C5').letterSpacing(1.6)
      Text(tr('tm_4ee918926f68')).fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFCE90').letterSpacing(1.6)
    }.margin({ top: 6, bottom: 8 }).width('100%')
    Button(tr('tm_a0362561d1b4')).enabled(!this.busy).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.pick(); })
    TextInput({ text: this.libraryQuery, placeholder: tr('tm_10dc8a4ccfd1') }).id('library-search').fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').constraintSize({ minHeight: 52 * this.profile.textScale }).borderRadius(9).onChange((value: string) => { this.libraryQuery = value; this.libraryPage = 0; }).accessibilityText(tr('tm_71766e5d06f7'))
    ForEach(this.libraryMaterials().slice(this.libraryStart(), this.libraryStart() + 3), (material: Material) => {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(material.draft ? tr('tm_53dd5f4b25e5') : material.ready ? tr('tm_a6df8294316e') : tr('tm_8497303f673c')).fontSize(11 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor(material.draft ? '#FFCE90' : '#69E2C5').layoutWeight(1)
          Text(tr('tm_9288e1863a98', [String(material.diagram.revision)])).fontSize(11 * this.profile.textScale).fontColor('#A6BBC8')
        }.width('100%')
        Text(material.diagram.title).fontSize(23 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%')
        Text(material.diagram.description).fontSize(15 * this.profile.textScale).fontColor('#B7C8D2').maxLines(3).width('100%')
        Text(tr('tm_d3d45ba508d2', [String(material.diagram.regions.length), String(material.diagram.relations.length), String(material.diagram.questions.length)])).fontSize(13 * this.profile.textScale).fontColor('#A6BBC8').width('100%')
        Button(material.draft ? tr('tm_03072fec9bb5', [String(material.diagram.revision)]) : material.accepted ? tr('tm_f4174a4c9ac4') : tr('tm_0f7bbb4d122f')).id(`open-material-${material.key}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.load(material); }).accessibilityText(tr('tm_818b4b91f139', [String(material.draft ? tr('tm_db34f714f639') : material.accepted ? tr('tm_f4174a4c9ac4') : tr('tm_0f7bbb4d122f')), String(material.diagram.title), String(material.diagram.revision)]))
        Flex({ wrap: FlexWrap.Wrap }) {
          Button(tr('tm_464c4ffd019e')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 46 }).padding(10).margin(3).backgroundColor('#284854').onClick(() => { this.load(material).then((loaded: boolean) => { if (loaded) { this.go('Editor'); } }); })
          Button(tr('tm_3664895579f0')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 46 }).padding(10).margin(3).backgroundColor('#284854').onClick(() => { this.exportMaterial(material); })
          Button(tr('tm_e2d0a54968ea')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 46 }).padding(10).margin(3).backgroundColor('#563736').onClick(() => { this.deleteId = material.key; }).accessibilityText(tr('tm_32df77faab46', [String(material.diagram.title), String(material.diagram.revision)]))
        }.width('100%')
        if (this.deleteId === material.key) {
          Text(tr('tm_8584e46bdad7', [String(material.diagram.revision)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
          Button(tr('tm_92ef241d29e9')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.remove(material); })
          Button(tr('tm_b2b1982c346b')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.deleteId = ''; })
        }
      }.padding(20).width('100%').backgroundColor('#142F3C').borderRadius(18).alignItems(HorizontalAlign.Start)
    }, (material: Material) => material.key)
    if (this.libraryMaterials().length > 0) {
      Text(tr('tm_4d964d496277', [String(this.libraryStart() + 1), String(Math.min(this.libraryStart() + 3, this.libraryMaterials().length)), String(this.libraryMaterials().length)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      if (this.libraryStart() > 0) { Button(tr('tm_ccdbb90eafaa')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.libraryPage = this.libraryStart() / 3 - 1; this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false }); }) }
      if (this.libraryStart() + 3 < this.libraryMaterials().length) { Button(tr('tm_9752b5741765')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.libraryPage = this.libraryStart() / 3 + 1; this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false }); }) }
    } else if (this.libraryQuery.trim()) { Text(tr('tm_bee4ebaebc2c')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
    if (this.items.length === 0 && this.ready) { Text(tr('tm_a301c36f3686')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
  }
  @Builder acceptance() {
    Column({ space: 8 }) { Text(tr('tm_05b95ce36d35')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(this.active!.diagram.title).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Text(tr('tm_ba32da0c32db', [String(this.active!.manifest.author.name)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(this.active!.manifest.author.declaration).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(tr('tm_693ce1c206ce', [String(this.active!.diagram.source.attribution)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(tr('tm_b21b24a53220', [String(this.active!.manifest.license)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(tr('tm_1013ae47de7e')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(publicationIssues(this.active!.diagram).length > 0 ? tr('tm_2808c69c533d') : tr('tm_747380d4bc83')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button(tr('tm_2d0c5bf8040d')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.accept(); })
    Button(tr('tm_8534ab72f196')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('Library'); })
  }
  @Builder tutorial() {
    Column({ space: 8 }) { Text(tr('tm_a842dccfccc0')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_041777a52275')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Row({ space: 14 }) {
      Circle().width(64).height(64).fill('#69E2C5').accessibilityText(tr('tm_0d7fd9c15f1d')).onClick(() => { this.tutorialSelect('circle'); })
      Rect().width(64).height(64).fill('#FFCE90').accessibilityText(tr('tm_ed9595df3a04')).onClick(() => { this.tutorialSelect('square'); })
      Polygon().points([[32, 0], [64, 64], [0, 64]]).width(64).height(64).fill('#A9BDFB').accessibilityText(tr('tm_4c08824d208a')).onClick(() => { this.tutorialSelect('triangle'); })
    }.width('100%').justifyContent(FlexAlign.Center).padding(24)
    Text(tr('tm_c33ea79bbca2')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button(tr('tm_7de2aef289eb')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { const ids: string[] = ['circle', 'square', 'triangle']; this.tutorialSelect(ids[(ids.indexOf(this.tutorialFocused) + 1) % 3]); })
    Text(this.tutorialStep === 0 ? tr('tm_80d9d3a2b3d3') : this.tutorialStep === 1 ? tr('tm_27fa5d6f5d47') : tr('tm_a8ca67bbd79d')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button(this.tutorialStep < 2 ? tr('tm_298a9207a732') : tr('tm_16b98aa8bc32')).id('tutorial-next').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => {
      if (this.tutorialStep < 2) { this.tutorialStep++; } else { this.profile.tutorial = true; this.saveProfile(); this.go(this.active ? 'Explore' : 'Library'); }
    })
    Button(tr('tm_fde940f55dc8')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('Settings'); })
  }
  @Builder exploration() {
    Column({ space: 8 }) { Text(this.active!.diagram.title).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_3266b429f899')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(['Touch', 'List', 'Scan'], (mode: string) => {
        Button(tr(englishKey(mode))).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).backgroundColor(this.interaction === mode ? '#69E2C5' : '#25424F').fontColor(this.interaction === mode ? '#09252A' : '#F3F8FA').onClick(() => { this.cancelTouch(); this.stopScan(); this.interaction = mode; })
      })
    }.width('100%')
    if (this.interaction === 'Touch') {
      if (this.active!.diagram.source.path.endsWith('.svg') && !this.active!.diagram.source.previewPath) { Text(tr('tm_a01c6d8c016f')).fontSize(16 * this.profile.textScale).fontColor('#FFCE90').width('100%') }
      Canvas(this.canvas).width('100%').height(300).backgroundColor('#FFFFFF').borderRadius(16)
        .hitTestBehavior(HitTestMode.Block).accessibilityLevel('no').onReady(() => { this.draw(); })
        .onAreaChange((_old: Area, area: Area) => { this.viewWidth = Number(area.width); this.draw(); })
        .onTouch((event: TouchEvent) => { this.touch(event); })
        .onAccessibilityHoverTransparent((event: TouchEvent) => { console.info(`TOUCHMAP_ACCESSIBILITY_HOVER type=${event.type} contacts=${event.touches.length}`); this.touch(event); })
      Text(tr('tm_e3862530f6d2')).fontSize(12 * this.profile.textScale).fontColor('#A6BBC8').width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Button(tr('tm_a69bfe8650bf')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.viewport(1.25, 0, 0); })
        Button(tr('tm_263f36611134')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.viewport(0.8, 0, 0); })
        Button(tr('tm_58eb9032e3bb')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.viewport(1, 30, 0); })
        Button(tr('tm_883361d5d682')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.viewport(1, -30, 0); })
        Button(tr('tm_55490a4bf3a8')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.viewport(1, 0, 30); })
        Button(tr('tm_b86d11af7918')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.viewport(1, 0, -30); })
        Button(tr('tm_c3613b1704f5')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.viewport(1, 0, 0, 90); })
        Button(tr('tm_ce89ae822e8b')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { this.action('viewport', '', undefined, { scale: 1, offsetX: 0, offsetY: 0, rotation: 0 }); })
      }.width('100%')
    }
    Column({ space: 10 }) {
      Text(this.focus()?.label || tr('tm_7738b91a4a46')).fontSize(24 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#69E2C5').width('100%')
      if (this.focus()) {
        Text(this.focus()!.description).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
        Row({ space: 10 }) { Button(tr('tm_a57b08a480b8')).fontSize(16 * this.profile.textScale).labelStyle({ maxLines: 2, minFontSize: 0 }).constraintSize({ minHeight: 50 }).layoutWeight(1).onClick(() => { this.action('previousRegion'); }); Button(tr('tm_1ff57a29d7c9')).fontSize(16 * this.profile.textScale).labelStyle({ maxLines: 2, minFontSize: 0 }).constraintSize({ minHeight: 50 }).layoutWeight(1).onClick(() => { this.action('nextRegion'); }) }.width('100%')
        Button(tr('tm_ce517eefc158')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.speak(this.active!, this.progress!.lastRegionId, 'label', this.profile, true); })
        Button(tr('tm_5edccba90bf3')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('describe'); })
        Button(this.progress!.bookmarks.includes(this.progress!.lastRegionId) ? tr('tm_b4836106f489') : tr('tm_9cd94e235c3b')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('bookmark', this.progress!.lastRegionId); })
      }
    }.padding(18).width('100%').backgroundColor('#142F3C').borderRadius(16)
    if (this.overlaps.length > 1) {
      Text(tr('tm_c61ababd1eb8', [String(this.overlaps.length)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      ForEach(this.overlaps, (r: Region) => { Button(tr('tm_91f693ce2df6', [String(r.zIndex), String(r.label)])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', r.id); }) }, (r: Region) => r.id)
    }
    if (this.interaction === 'Scan') {
      Text(this.scanning ? tr('tm_48619efed4d7', [String(this.scanLabel())]) : tr('tm_bcbdfa0bb33a')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      Button(this.scanning ? tr('tm_b2a56b5857c1') : tr('tm_3e95e8f3eebd')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { if (this.scanning) { this.chooseScan(); } else { this.startScan(); } })
      if (this.scanning) { Button(tr('tm_cfc1be58d9b7')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.stopScan(); }) }
    }
    Button(tr('tm_dc273117482b')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.showConnections = !this.showConnections; })
    if (this.showConnections) {
      ForEach(this.active!.diagram.relations.filter((r: Relation) => !this.progress!.lastRegionId || r.fromId === this.progress!.lastRegionId || r.toId === this.progress!.lastRegionId), (r: Relation) => {
        Column({ space: 8 }) {
          Text(tr('tm_abf8dc0900f9', [String(!this.progress!.lastRegionId ? tr('tm_639a40e82b9a') : r.direction === 'both' ? tr('tm_11781b75fdac') : r.fromId === this.progress!.lastRegionId ? tr('tm_3619cf0b9092') : tr('tm_e301820ac839')), String(r.label), String(r.direction === 'unknown' ? tr('tm_0d81a3d0c66f') : r.direction === 'both' ? tr('tm_1341cbe8d35b') : tr('tm_0386c095d19f')), String(r.path ? tr('tm_988a74152e6a') : tr('tm_899c2327ecbb'))])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
          Button(tr('tm_e8f4cfc5f18d')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('selectRelation', r.id); })
          if (r.toId === this.progress!.lastRegionId && r.direction === 'forward') {
            Button(tr('tm_4ab8f40b5319')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', r.fromId); })
          }
          Button(tr('tm_34a3df43a965')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('followRelation', r.id); })
        }.padding(12).backgroundColor('#142F3C').borderRadius(12)
      }, (r: Relation) => r.id)
      if (this.guide) { Text(this.guide).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
    }
    Text(tr('tm_34caa1c368e7')).fontSize(12 * this.profile.textScale).letterSpacing(2).fontWeight(FontWeight.Bold).fontColor('#A6BBC8').width('100%')
    ForEach(orderedRegions(this.active!.diagram), (r: Region, index: number) => {
      Button(tr('tm_866bedaaec19', [String(index + 1), String(r.label), String(this.progress!.bookmarks.includes(r.id) ? tr('tm_f99eb7d660c1') : ''), String(this.scanning && this.scanIndex === index ? tr('tm_ac75dc284f40') : '')])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', r.id); })
    }, (r: Region) => r.id)
    ForEach(this.active!.diagram.charts, (chart: Chart) => {
      Column({ space: 8 }) { Text(chart.title).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_93bd2aff4d63', [String(chart.yAxis.label), String(chart.yAxis.unit), String(chart.yAxis.scale)])).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
      ForEach(chart.series, (series: Series) => {
        Text(series.label).fontColor('#69E2C5').fontSize(18 * this.profile.textScale)
        ForEach(series.values, (value: ChartValue) => { Text(tr('tm_fb62fe2ae6b2', [String(value.x), String(value.value === null ? tr('tm_b23a6a8439c0') : value.value.toFixed(value.precision) + ' ' + chart.yAxis.unit)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }, (value: ChartValue) => value.id)
      }, (series: Series) => series.id)
    }, (chart: Chart) => chart.id)
    Button(tr('tm_b4ee1ee32878')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.speak(this.active!, this.active!.diagram.packageId, 'overview', this.profile, true); })
    Flex({ wrap: FlexWrap.Wrap }) {
      Button(tr('tm_bb6591385f67')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { feedback.pauseRecording(); })
      Button(tr('tm_0a1b9d7e9aee')).fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { feedback.resumeRecording(); })
    }.width('100%')
    Text(tr('tm_6565943fb816')).fontSize(14 * this.profile.textScale).fontColor('#B7C8D2').width('100%')
    Button(tr('tm_4923f7d2f830')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.go('Lesson'); })
    Button(tr('tm_006977794ed4')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('pause'); })
  }
  @Builder lesson() {
    Column({ space: 8 }) { Text(tr('tm_3305fde5b4bc')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_879eac5e513b')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    ForEach(this.active!.diagram.questions, (q: Question) => {
      Button(q.prompt).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('openQuestion', q.id); })
    }, (q: Question) => q.id)
    if (this.question()) {
      Column({ space: 14 }) {
        Text(this.question()!.prompt).fontSize(24 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%')
        Text(this.question()!.type === 'sequence' ? tr('tm_47b8cfc543d7') : this.question()!.acceptedAnswers.length > 1 ? tr('tm_113dd86c7f3a') : tr('tm_336bcb612c43')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
        ForEach(this.question()!.options, (option: AnswerOption) => {
          Button(tr('tm_8391da809dd9', [String(this.progress!.selectedAnswers.includes(option.id) ? tr('tm_1f153fd1824c') : ''), String(option.label)])).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).width('100%').constraintSize({ minHeight: 54 }).padding(12).fontSize(17 * this.profile.textScale)
            .backgroundColor(this.progress!.selectedAnswers.includes(option.id) ? '#69E2C5' : '#2A4653').fontColor(this.progress!.selectedAnswers.includes(option.id) ? '#09252A' : '#F3F8FA')
            .accessibilityText(tr('tm_b5e7ec28c3fb', [String(option.label), String(this.progress!.selectedAnswers.includes(option.id) ? tr('tm_d7cbbb688b2e') : tr('tm_5ad0f897690e'))])).onClick(() => { this.selectAnswer(option.id); })
        }, (option: AnswerOption) => option.id)
        if (this.question()!.type === 'sequence' && this.progress!.selectedAnswers.length > 0) { Text(tr('tm_24fb80d91f7c') + this.progress!.selectedAnswers.join(', ')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
        if (this.progress!.status === 'submitted') {
          Text((this.progress!.submissions[this.progress!.submissions.length - 1]?.correct ? tr('tm_8d3bc8b6da70') : tr('tm_76949438336d')) + this.question()!.explanation).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
        } else { Button(tr('tm_10992ed7982e')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.action('submitAnswer'); }) }
        if (this.question()!.hint) { Button(tr('tm_4eab2f444cce')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.status = this.question()!.hint; }) }
        Button(tr('tm_7b28a86e5d97')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('Explore'); })
        Button(this.progress!.status === 'answering' ? tr('tm_db3c04ee0e8a') : tr('tm_006977794ed4')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('pause'); })
      }.padding(20).backgroundColor('#142F3C').borderRadius(16).width('100%')
    }
    Text(tr('tm_c7b1eaaed7bc', [String(this.progress!.submissions.length)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button(tr('tm_d10674385e87')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('History'); })
  }
  @Builder resume() {
    Column({ space: 8 }) { Text(tr('tm_50e3bb39718a')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(this.active!.diagram.title).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Column({ space: 14 }) {
      Text(tr('tm_891f2fb7cc05')).fontSize(12 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#69E2C5').letterSpacing(1.8).width('100%')
      Text(resumeContext(this.active!.diagram, this.progress!)).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      Text(tr('tm_b435920322f2', [String(this.progress!.revision)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    }.width('100%').padding(20).borderRadius(16).backgroundColor('#142F3C')
    Button(tr('tm_d640c7421da0')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.action('resume').then((saved: boolean) => { if (saved) { this.go(this.progress!.activeQuestionId ? 'Lesson' : 'Explore'); } }); })
    Button(tr('tm_ad4df5185efc')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.status = resumeContext(this.active!.diagram, this.progress!); if (this.progress!.lastRegionId) { feedback.speak(this.active!, this.progress!.lastRegionId, 'description', this.profile, true); } })
    Button(tr('tm_a6e84cc9f405')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('startAgain').then((saved: boolean) => { if (saved) { this.go('Explore'); } }); })
    Button(tr('tm_d10674385e87')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('History'); })
  }
  @Builder history() {
    Column({ space: 8 }) { Text(tr('tm_40a05b04a075')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_e747d4df967b')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    ForEach(this.progress!.submissions, (submission: Submission) => {
      Text(tr('tm_965c92b43daa', [String(this.active!.diagram.questions.find((q: Question) => q.id === submission.questionId)?.prompt || submission.questionId), String(submission.correct ? tr('tm_aca01a1a3a27') : tr('tm_8802ea90e287')), String(submission.answers.join(', ')), String(new Date(submission.timestamp).toLocaleString())])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    }, (submission: Submission) => submission.eventId)
    ForEach(this.progress!.bookmarks, (id: string) => { Button(this.active!.diagram.regions.find((r: Region) => r.id === id)?.label || id).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', id); this.go('Explore'); }) })
    Button(tr('tm_f73fa31ef678')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.repository!.exportHistory(this.active!).then((saved: boolean) => { this.status = saved ? tr('tm_140a526dc331') : tr('tm_2f4a35c7650c'); }).catch((error: Error) => { this.fail(error); }); })
    Button(tr('tm_c74dc961ee67')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.repository!.clearHistory(this.active!).then(async () => { this.progress = await this.repository!.progress(this.active!); this.status = tr('tm_665b34529708'); }).catch((error: Error) => { this.fail(error); }); })
  }
  @Builder importSource() {
    Column({ space: 8 }) { Text(tr('tm_5c27058e76cb')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_7cb3cb4b73f7')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Button(tr('tm_a4f60b1acf54')).enabled(!this.busy).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.pick(); })
    if (this.sourcePreview) {
      if (this.sourceType === 'svg') { Text(tr('tm_5b0d37bd4b80')).fontSize(16 * this.profile.textScale).fontColor('#FFCE90').width('100%') }
      else { Image(`file://${this.sourcePreview}`).width('100%').height(240).objectFit(ImageFit.Contain).backgroundColor('#FFFFFF').borderRadius(12).accessibilityText(tr('tm_b58f558ec6b6')) }
      Text(tr('tm_9b692c57d1bb', [String(this.importWidth), String(this.importHeight), String(this.sourceType === 'png' ? tr('tm_482ce0caa75c') : tr('tm_ff9dae927123'))])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      Column({ space: 5 }) { Text(tr('tm_f5e2ce5b03c3')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.sourceName }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.sourceName = s; }).accessibilityText(tr('tm_f5e2ce5b03c3')) }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 5 }) { Text(tr('tm_40d6582fd8aa')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.attribution }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.attribution = s; }).accessibilityText(tr('tm_40d6582fd8aa')) }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 5 }) { Text(tr('tm_9f4cfe7361db')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.license }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.license = s; }).accessibilityText(tr('tm_9f4cfe7361db')) }.width('100%').alignItems(HorizontalAlign.Start)
      if (this.sourceType === 'png') {
        Column({ space: 5 }) { Text(tr('tm_f6884a2fed7e')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropX }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropX = s; }).accessibilityText(tr('tm_f6884a2fed7e')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_8a5103c43803')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropY }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropY = s; }).accessibilityText(tr('tm_8a5103c43803')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_aac319f3bb78')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropW }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropW = s; }).accessibilityText(tr('tm_aac319f3bb78')) }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text(tr('tm_b6d82bff7898')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropH }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropH = s; }).accessibilityText(tr('tm_b6d82bff7898')) }.width('100%').alignItems(HorizontalAlign.Start)
        Button(tr('tm_dc5c057bb74c')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.crop(); })
      }
      Button(tr('tm_b8e928a361ea')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.createDraft(); })
      Text(tr('tm_4ee39cf3433c')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    }
  }
  @Builder settings() {
    Column({ space: 8 }) { Text(tr('tm_71f9debfc349')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_39d324dc7f61')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Text(tr('tm_9d75285c3bf9', [String(this.profile.dwell)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.dwell, min: 0, max: 1500, step: 50 }).onChange((value: number) => { this.profile.dwell = value; }).accessibilityText(tr('tm_f9dd6ab1a25c'))
    Text(tr('tm_ab7c554b2206', [String(Math.round(this.profile.volume * 100))])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.volume, min: 0, max: 1, step: 0.1 }).onChange((value: number) => { this.profile.volume = value; }).accessibilityText(tr('tm_d8885610a2ef'))
    Text(tr('tm_59815d2189a9', [String(Math.round(this.profile.textScale * 100))])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.textScale, min: 1, max: 2, step: 0.25 }).onChange((value: number) => { this.profile.textScale = value; }).accessibilityText(tr('tm_3d708d9044b4'))
    Text(tr('tm_093ee4489f4a', [String(this.profile.scanMs)])).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.scanMs, min: 700, max: 5000, step: 100 }).onChange((value: number) => { this.profile.scanMs = value; }).accessibilityText(tr('tm_56883ea179dc'))
    Row({ space: 10 }) { Toggle({ type: ToggleType.Switch, isOn: this.profile.vibration }).onChange((value: boolean) => { this.profile.vibration = value; }); Text(tr('tm_794c953e76ae')).fontColor('#EAF5F8').fontSize(17 * this.profile.textScale).layoutWeight(1) }.width('100%')
    Text(feedback.vibrationAvailable ? tr('tm_3b058c486f12') : tr('tm_74964c2142f8')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button(tr('tm_3489dbd61fb8')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.cue(this.profile); })
    Row({ space: 10 }) { Toggle({ type: ToggleType.Switch, isOn: this.profile.contrast }).onChange((value: boolean) => { this.profile.contrast = value; }); Text(tr('tm_415a8336713e')).fontColor('#EAF5F8').fontSize(17 * this.profile.textScale).layoutWeight(1) }.width('100%')
    Row({ space: 10 }) { Toggle({ type: ToggleType.Switch, isOn: this.profile.readerSpeech }).onChange((value: boolean) => { this.profile.readerSpeech = value; }); Text(tr('tm_a2cf26482dbd')).fontColor('#EAF5F8').fontSize(17 * this.profile.textScale).layoutWeight(1) }.width('100%')
    Text(feedback.reader ? tr('tm_38225c2dfbb8') : tr('tm_e3d348ad84a6')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button(tr('tm_089e57e38f93')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.saveProfile(); })
    Button(tr('tm_593861333a1f')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.tutorialStep = 0; this.go('Tutorial'); })
    Column({ space: 8 }) { Text(tr('tm_bad4cce25739')).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(tr('tm_4ce61e8e8e02')).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Text(tr('tm_8cc33b8309b8')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(tr('tm_0ee6577bbbe5')).fontSize(12 * this.profile.textScale).letterSpacing(1.5).fontColor('#69E2C5').width('100%').margin({ top: 18 })
    Column({ space: 5 }) { Text(tr('tm_443e8d0d3236')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.profile.service }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.profile.service = s; }).accessibilityText(tr('tm_443e8d0d3236')) }.width('100%').alignItems(HorizontalAlign.Start)
    Column({ space: 5 }) { Text(tr('tm_b0bc64c9ddbb')).fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.pairingCode }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.pairingCode = s; }).accessibilityText(tr('tm_b0bc64c9ddbb')) }.width('100%').alignItems(HorizontalAlign.Start)
    Button(tr('tm_d23977611acd')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => {
      this.preparation.base = this.profile.service;
      this.preparation.pair(this.pairingCode).then(async () => { this.pairingCode = ''; await this.saveProfile(); this.status = tr('tm_4f6a8fb5912c'); }).catch((error: Error) => { this.fail(error); });
    })
    Text(tr('tm_c2a5032d9206')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
  }
  build() {
    Column() {
      Row({ space: 10 }) {
        Text('◉').fontSize(30).fontColor('#69E2C5')
        Column({ space: 1 }) { Text(tr('tm_12e6c5f9b896')).fontSize(23).fontWeight(FontWeight.Bold).fontColor('#F3F8FA'); Text(tr('tm_a14ac52cbf2e')).fontSize(8).letterSpacing(1.3).fontColor('#A6BBC8') }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button(tr('tm_d69657bc9d03')).id('stop-audio').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(13 * this.profile.textScale).constraintSize({ minHeight: 46 }).padding(10).backgroundColor('#29434E').fontColor('#F3F8FA').borderRadius(9).onClick(() => { feedback.stop(); this.status = tr('tm_29f56803784e'); }).accessibilityText(tr('tm_0718a25ab9e2'))
      }.padding({ left: 22, right: 22, top: 18, bottom: 14 }).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Button(tr('tm_dc20b3d5d2cd')).id('nav-library').fontSize(14 * this.profile.textScale).constraintSize({ minHeight: 46 }).width(this.profile.textScale > 1.5 ? '50%' : '33.333%').padding(8).backgroundColor(this.page === 'Library' ? '#69E2C5' : '#203A46').fontColor(this.page === 'Library' ? '#09252A' : '#F3F8FA').onClick(() => { this.go('Library'); this.repository?.list().then((items: Material[]) => { this.items = items; }).catch((error: Error) => { this.fail(error); }); })
        Button(tr('tm_2cff9baabf56')).fontSize(14 * this.profile.textScale).constraintSize({ minHeight: 46 }).width(this.profile.textScale > 1.5 ? '50%' : '33.333%').padding(8).backgroundColor('#203A46').onClick(() => { this.go('Import'); })
        Button(tr('tm_74a883a037bc')).id('nav-settings').fontSize(14 * this.profile.textScale).constraintSize({ minHeight: 46 }).width(this.profile.textScale > 1.5 ? '50%' : '33.333%').padding(8).backgroundColor('#203A46').onClick(() => { this.go('Settings'); })
      }.padding({ left: 20, right: 20, bottom: 10 }).width('100%')
      if (this.busy) { Row({ space: 10 }) { LoadingProgress().width(28).height(28); Text(this.busyOperation).fontSize(16 * this.profile.textScale).fontColor('#FFCE90').layoutWeight(1) }.padding(12).width('100%').accessibilityText(this.busyOperation + tr('tm_a53b76347f13')) }
      Scroll(this.scroller) {
        Column({ space: 18 }) {
          if (!this.ready) { LoadingProgress().width(48).height(48); Text(this.status).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
          else if (this.page === 'Library') { this.library() }
          else if (this.page === 'Import') { this.importSource() }
          else if (this.page === 'Settings') { this.settings() }
          else if (this.page === 'Tutorial') { this.tutorial() }
          else if (this.active && this.progress) {
            if (this.page === 'Accept') { this.acceptance() }
            else if (this.page === 'Explore') { this.exploration() }
            else if (this.page === 'Lesson') { this.lesson() }
            else if (this.page === 'Resume') { this.resume() }
            else if (this.page === 'History') { this.history() }
            else if (this.page === 'Editor') {
              EditorPanel({ material: this.active, repository: this.repository!, onSaved: (material: Material) => { this.active = material; this.repository!.list().then((items: Material[]) => { this.items = items; }).catch((error: Error) => { this.fail(error); }); } })
            }
          }
          Text(this.status).fontSize(14 * this.profile.textScale).fontColor('#FFCE90').width('100%').padding(14).backgroundColor('#213541').borderRadius(10)
          if (this.active && this.page !== 'Library' && this.page !== 'Accept') {
            Button(tr('tm_ca24da6134f7')).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.stop(); this.stopScan(); this.go('Library'); })
          }
          Text(tr('tm_260f59cb0bbb')).fontSize(12).fontColor('#A6BBC8').padding({ top: 6, bottom: 24 })
        }.padding({ left: 22, right: 22, top: 12 }).width('100%').alignItems(HorizontalAlign.Start)
      }.id('main-scroll').layoutWeight(1).width('100%').scrollBar(BarState.Auto).enableScrollInteraction(!this.exploringTouch)
    }.height('100%').width('100%').backgroundColor(this.palette())
  }
}
