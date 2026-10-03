import { common } from '@kit.AbilityKit';
import { Diagram, Region, Relation, Question, Chart, Progress, Action, Point, Viewport, Series, ChartValue, AnswerOption, Submission } from '../domain/types';
import { initialProgress, orderedRegions, resumeContext, applyAction } from '../domain/engine';
import { hitTest, sourcePoint, guidePath } from '../domain/geometry';
import { assertSafeSvg } from '../domain/media';
import { publicationIssues } from '../domain/validate';
import { Repository, Material, Profile, defaultProfile, uid, readBytes, writeBytes, digest, decode } from '../platform/Repository';
import { Preparation, sanitizeImage, Crop } from '../platform/Preparation';
import { feedback } from '../platform/Feedback';
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
  @State busy: boolean = false;
  @State busyOperation: string = 'Importing and validating material';
  @State status: string = 'Opening your local library...';
  @State interaction: string = 'Touch';
  @State overlaps: Region[] = [];
  @State scanIndex: number = 0;
  @State scanning: boolean = false;
  @State showConnections: boolean = false;
  @State tutorialStep: number = 0;
  @State tutorialFocused: string = '';
  @State pairingCode: string = '';
  @State sourceName: string = 'My diagram';
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
      this.ready = true; this.status = 'Your materials stay on this device. No account is needed.';
      if (this.openedUri) { await this.incomingUri(); }
    } catch (error) { this.fail(error as Error); }
  }
  private fail(error: Error): void { this.status = error.message || 'This action could not be completed. Saved material is unchanged.'; feedback.announce(this.status); }
  private async incomingUri(): Promise<void> {
    if (!this.repository || !this.ready || !this.openedUri) { return; }
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
  private async load(material: Material): Promise<void> {
    try {
      feedback.stop(); this.stopScan(); this.active = material;
      const restored = await this.repository!.progress(material);
      if (this.active?.key !== material.key) { return; }
      this.progress = restored;
      this.overlaps = [];
      if (material.draft) { this.go('Editor'); }
      else if (!material.accepted) { this.go('Accept'); }
      else if (this.progress.stateRevision > 0) { this.go('Resume'); }
      else if (!this.profile.tutorial) { this.tutorialStep = 0; this.go('Tutorial'); }
      else { this.go('Explore'); }
      this.status = `${material.diagram.regions.length} objects. ${material.diagram.relations.length} connections. ${material.ready ? 'Ready offline.' : 'Recordings incomplete.'}`;
    } catch (error) { this.fail(error as Error); }
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
    this.feedbackEpoch++; this.hoveredRegion = ''; this.pendingFocus = ''; this.exploringTouch = false; feedback.stop();
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
    if (found.length > 0 && found[0].id !== this.hoveredRegion) { this.hoveredRegion = found[0].id; this.action('focusRegion', found[0].id); }
    else if (found.length === 0 && this.hoveredRegion) { this.feedbackEpoch++; this.hoveredRegion = ''; this.pendingFocus = ''; feedback.stop(); }
    const relation = d.relations.find((r: Relation) => r.id === this.progress!.activeRelationId);
    if (relation) {
      const reverse = relation.direction === 'both' && this.progress.lastRegionId === relation.toId;
      const destinationId = reverse ? relation.fromId : relation.toId;
      const destination = d.regions.find((r: Region) => r.id === destinationId)?.label || destinationId;
      const route = reverse && relation.path ? relation.path.slice().reverse() : relation.path;
      const guidance = guidePath(point, route, 10 / (fit * this.progress.viewport.scale), destination);
      this.guide = guidance.known ? `${guidance.onPath ? 'On path' : 'Off path'}, ${Math.round(guidance.distance)} source units from the route. Toward ${destination}.` : `Route in the picture is unspecified. Graph destination: ${destination}.`;
    }
  }
  private draw(): void {
    if (!this.active || !this.progress) { return; }
    const d = this.active.diagram, ctx = this.canvas, viewport = this.progress.viewport;
    const fit = Math.min(this.viewWidth / d.source.width, 300 / d.source.height);
    ctx.clearRect(0, 0, this.viewWidth, 300); ctx.save();
    ctx.translate((this.viewWidth - d.source.width * fit) / 2, (300 - d.source.height * fit) / 2); ctx.scale(fit, fit);
    ctx.translate(viewport.offsetX, viewport.offsetY); ctx.rotate(viewport.rotation * Math.PI / 180); ctx.scale(viewport.scale, viewport.scale);
    const source = new ImageBitmap(`file://${this.active.directory}/${d.source.previewPath || d.source.path}`); ctx.drawImage(source, 0, 0, d.source.width, d.source.height);
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
  private announceScan(): void {
    if (!this.active) { return; }
    const regions = orderedRegions(this.active.diagram);
    const label = this.scanIndex < regions.length ? regions[this.scanIndex].label : this.scanIndex === regions.length ? 'Connections' : 'Exit exploration';
    this.status = `Scan: ${label}. Press Select to apply.`; feedback.announce(this.status);
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
    try { await this.repository!.saveProfile(this.profile); this.preparation.base = this.profile.service; this.status = 'Preferences saved on this device.'; }
    catch (error) { this.fail(error as Error); }
  }
  private async pick(): Promise<void> {
    try { const uri = await this.repository!.pick(); if (uri) { await this.importUri(uri); } }
    catch (error) { this.fail(error as Error); }
  }
  private async importUri(uri: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    this.busyOperation = 'Importing and validating material';
    this.status = 'Importing and validating your selected material. Large packages may take a moment.';
    await new Promise<void>((resolve) => { setTimeout(resolve, 20); });
    try {
      const bytes = readBytes(uri);
      if (bytes[0] === 0x50 && bytes[1] === 0x4B) {
        const material = await this.repository!.importPackage(uri); this.items = await this.repository!.list(); await this.load(material);
        this.status = 'Package integrity checked. Read the author declaration before accepting.';
      } else {
        let first = bytes.length >= 3 && bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191 ? 3 : 0;
        while (first < bytes.length && [9, 10, 13, 32].includes(bytes[first])) { first++; }
        const text = first < bytes.length && bytes[first] === 60 ? decode(bytes) : '';
        if (text.includes('<svg')) {
          if (bytes.length > 10 * 1024 * 1024) { throw new Error('SVG exceeds the 10 MiB source limit.'); }
          assertSafeSvg(text);
          this.sourceType = 'svg'; this.sourceBytes = bytes;
          const root = text.match(/<svg\b[^>]*>/i)?.[0] || '';
          const viewBox = root.match(/viewBox\s*=\s*["']\s*([-+0-9.eE]+)[ ,]+([-+0-9.eE]+)[ ,]+([-+0-9.eE]+)[ ,]+([-+0-9.eE]+)\s*["']/i);
          const width = root.match(/\bwidth\s*=\s*["']([+0-9.eE-]+)(?:px)?["']/i), height = root.match(/\bheight\s*=\s*["']([+0-9.eE-]+)(?:px)?["']/i);
          if ((!width && /\bwidth\s*=/.test(root)) || (!height && /\bheight\s*=/.test(root))) { throw new Error('SVG viewport dimensions must use pixels. Normalize other units with the computer converter.'); }
          this.importWidth = width ? Number(width[1]) : viewBox ? Number(viewBox[3]) : 0;
          this.importHeight = height ? Number(height[1]) : viewBox ? Number(viewBox[4]) : 0;
          this.sourceViewBox = viewBox ? [Number(viewBox[1]), Number(viewBox[2]), Number(viewBox[3]), Number(viewBox[4])] : [0, 0, this.importWidth, this.importHeight];
          if (![this.importWidth, this.importHeight, ...this.sourceViewBox].every(Number.isFinite) || this.importWidth <= 0 || this.importHeight <= 0 || this.importWidth * this.importHeight > 20000000 || this.sourceViewBox[2] <= 0 || this.sourceViewBox[3] <= 0) { throw new Error('SVG requires bounded finite viewport dimensions and a valid viewBox.'); }
        } else {
          const sanitized = await sanitizeImage(bytes); this.sourceBytes = sanitized.bytes; this.sourceType = 'png'; this.importWidth = sanitized.width; this.importHeight = sanitized.height; this.sourceViewBox = [0, 0, this.importWidth, this.importHeight];
        }
        this.cropW = String(this.importWidth); this.cropH = String(this.importHeight);
        this.sourcePreview = `${this.repository!.context.cacheDir}/source-${uid()}.${this.sourceType}`;
        writeBytes(this.sourcePreview, this.sourceBytes!); this.go('Import'); this.status = 'Source copied into private storage. Raster metadata is removed before any upload. Add provenance and review the preview.';
      }
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async crop(): Promise<void> {
    try {
      if (this.sourceType !== 'png' || !this.sourceBytes) { throw new Error('Crop is available for raster images.'); }
      const crop: Crop = { x: Number(this.cropX), y: Number(this.cropY), width: Number(this.cropW), height: Number(this.cropH) };
      const sanitized = await sanitizeImage(this.sourceBytes, crop); this.sourceBytes = sanitized.bytes;
      this.importWidth = sanitized.width; this.importHeight = sanitized.height; this.sourceViewBox = [0, 0, this.importWidth, this.importHeight];
      this.sourcePreview = `${this.repository!.context.cacheDir}/crop-${uid()}.png`; writeBytes(this.sourcePreview, this.sourceBytes);
      this.cropX = '0'; this.cropY = '0'; this.cropW = String(this.importWidth); this.cropH = String(this.importHeight);
      this.status = 'Crop applied. The preview is the exact source that will be prepared.';
    } catch (error) { this.fail(error as Error); }
  }
  private async createDraft(): Promise<void> {
    if (!this.sourceBytes || this.busy) { return; } this.busy = true;
    try {
      if (!this.attribution.trim() || !this.license.trim() || !this.sourceName.trim()) { throw new Error('Enter a title, source attribution and rights/license declaration.'); }
      const diagram: Diagram = { schemaVersion: 1, packageId: `material-${uid()}`, revision: 1, title: this.sourceName, language: 'en',
        source: { id: 'source', sha256: await digest(this.sourceBytes), width: this.importWidth, height: this.importHeight, path: `source.${this.sourceType}`, attribution: this.attribution, license: this.license, viewBox: this.sourceViewBox.slice() },
        regions: [], relations: [], charts: [], questions: [], audio: [], description: this.sourceName };
      this.active = await this.repository!.createSource(diagram, this.sourceBytes); this.progress = initialProgress(diagram);
      this.items = await this.repository!.list(); this.go('Editor');
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async remove(material: Material): Promise<void> {
    try {
      await this.repository!.deleteMaterial(material); this.items = await this.repository!.list(); this.deleteId = '';
      if (this.active?.key === material.key) { this.active = undefined; this.progress = undefined; }
      this.status = 'Material, private assets, checkpoints and attempts deleted.';
    } catch (error) { this.fail(error as Error); }
  }
  private async exportMaterial(material: Material): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.busyOperation = 'Compressing and exporting material'; this.status = 'Preparing a portable compressed package.';
    try { this.status = await this.repository!.exportPackage(material) ? 'Teaching package exported. Learning history and preferences are excluded.' : 'Export cancelled.'; }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private palette(): string { return this.profile.contrast ? '#071B25' : '#142D38'; }
  private tutorialSelect(id: string): void {
    const sample = this.items.find((item: Material) => item.diagram.packageId === 'tutorial');
    if (!sample) { this.status = 'Tutorial material is unavailable. Import the bundled tutorial package.'; return; }
    this.tutorialFocused = id;
    const region = sample.diagram.regions.find((r: Region) => r.id === id);
    if (region) { this.status = `${region.label}. ${region.description}`; feedback.speak(sample, id, 'label', this.profile, true); feedback.cue(this.profile); }
  }
  @Builder library() {
    Column({ space: 8 }) { Text('A world you can explore.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('Touch a diagram. Hear what matters. Follow the connections at your own pace.').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Row({ space: 10 }) {
      Text('OFFLINE BY DESIGN').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#69E2C5').letterSpacing(1.6)
      Text('PRIVATE PROGRESS').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFCE90').letterSpacing(1.6)
    }.margin({ top: 6, bottom: 8 }).width('100%')
    Button('Import a material or source').enabled(!this.busy).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.pick(); })
    ForEach(this.items.filter((item: Material) => item.diagram.packageId !== 'tutorial'), (material: Material) => {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(material.draft ? 'DRAFT' : material.ready ? 'READY OFFLINE' : 'AUDIO INCOMPLETE').fontSize(11).fontWeight(FontWeight.Bold).fontColor(material.draft ? '#FFCE90' : '#69E2C5').layoutWeight(1)
          Text(`REV ${material.diagram.revision}`).fontSize(11).fontColor('#A6BBC8')
        }.width('100%')
        Text(material.diagram.title).fontSize(23 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%')
        Text(material.diagram.description).fontSize(15 * this.profile.textScale).fontColor('#B7C8D2').maxLines(3).width('100%')
        Text(`${material.diagram.regions.length} objects  ·  ${material.diagram.relations.length} connections  ·  ${material.diagram.questions.length} questions`).fontSize(13 * this.profile.textScale).fontColor('#A6BBC8').width('100%')
        Button(material.draft ? 'Continue authoring' : material.accepted ? 'Open material' : 'Review and accept').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.load(material); })
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('Edit').height(46).margin(3).backgroundColor('#284854').onClick(() => { this.load(material).then(() => { this.go('Editor'); }); })
          Button('Export').height(46).margin(3).backgroundColor('#284854').onClick(() => { this.exportMaterial(material); })
          Button('Delete').height(46).margin(3).backgroundColor('#563736').onClick(() => { this.deleteId = material.key; })
        }.width('100%')
        if (this.deleteId === material.key) {
          Text('Delete this material and all its private learning history from this device?').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
          Button('Delete material and history').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.remove(material); })
          Button('Keep material').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.deleteId = ''; })
        }
      }.padding(20).width('100%').backgroundColor('#142F3C').borderRadius(18).alignItems(HorizontalAlign.Start)
    }, (material: Material) => material.key)
    if (this.items.length === 0 && this.ready) { Text('Your library is empty. Import a .touchmap package or prepare your own image.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
  }
  @Builder acceptance() {
    Column({ space: 8 }) { Text('Know your material.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(this.active!.diagram.title).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Text(`Author: ${this.active!.manifest.author.name}`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(this.active!.manifest.author.declaration).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(`Source: ${this.active!.diagram.source.attribution}`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(`License: ${this.active!.manifest.license}`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text('This is the author’s declaration, not independent certification. Accepting it is your local choice and does not change the package.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text(publicationIssues(this.active!.diagram).length > 0 ? 'Some facts need review. Open the editor before using this as a lesson.' : 'Geometry, meanings and lesson questions are marked reviewed by the author.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button('Accept this author declaration').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.accept(); })
    Button('Return to library').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('Library'); })
  }
  @Builder tutorial() {
    Column({ space: 8 }) { Text('A small start.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('Three steps to explore confidently.').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Row({ space: 14 }) {
      Circle().width(64).height(64).fill('#69E2C5').accessibilityText('Circle, round shape on the left').onClick(() => { this.tutorialSelect('circle'); })
      Rect().width(64).height(64).fill('#FFCE90').accessibilityText('Square, four sided shape in the centre').onClick(() => { this.tutorialSelect('square'); })
      Polygon().points([[32, 0], [64, 64], [0, 64]]).width(64).height(64).fill('#A9BDFB').accessibilityText('Triangle, three sided shape on the right').onClick(() => { this.tutorialSelect('triangle'); })
    }.width('100%').justifyContent(FlexAlign.Center).padding(24)
    Text('Try all three shapes. Each selection plays a local recording and shows its description.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button('Next tutorial shape').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { const ids: string[] = ['circle', 'square', 'triangle']; this.tutorialSelect(ids[(ids.indexOf(this.tutorialFocused) + 1) % 3]); })
    Text(this.tutorialStep === 0 ? '1. Choose an object. In touch mode, move one finger over the diagram. Pause briefly for its local recording. The object list offers the same commands.' : this.tutorialStep === 1 ? '2. Ask for detail. Longer descriptions play only when you press Describe. Connections announce their direction and destination. Stop audio is always available.' : '3. Answer deliberately. Select an answer, then press Submit. Touching an object never submits an answer. Leaving keeps your unfinished selection available.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button(this.tutorialStep < 2 ? 'Next step' : 'Start exploring').id('tutorial-next').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => {
      if (this.tutorialStep < 2) { this.tutorialStep++; } else { this.profile.tutorial = true; this.saveProfile(); this.go(this.active ? 'Explore' : 'Library'); }
    })
    Button('Adjust interaction preferences').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('Settings'); })
  }
  @Builder exploration() {
    Column({ space: 8 }) { Text(this.active!.diagram.title).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('Move through the picture or use the accessible object list.').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(['Touch', 'List', 'Scan'], (mode: string) => {
        Button(mode).height(48).margin(3).backgroundColor(this.interaction === mode ? '#69E2C5' : '#25424F').fontColor(this.interaction === mode ? '#09252A' : '#F3F8FA').onClick(() => { this.cancelTouch(); this.stopScan(); this.interaction = mode; })
      })
    }.width('100%')
    if (this.interaction === 'Touch') {
      if (this.active!.diagram.source.path.endsWith('.svg') && !this.active!.diagram.source.previewPath) { Text('Source preview incomplete: this device may omit SVG text and arrowheads. Reviewed labels and connections remain available in the object list. Ask the author to export a version with an exact raster preview.').fontSize(16 * this.profile.textScale).fontColor('#FFCE90').width('100%') }
      Canvas(this.canvas).width('100%').height(300).backgroundColor('#FFFFFF').borderRadius(16)
        .hitTestBehavior(HitTestMode.Block).accessibilityLevel('no').onReady(() => { this.draw(); })
        .onAreaChange((_old: Area, area: Area) => { this.viewWidth = Number(area.width); this.draw(); })
        .onTouch((event: TouchEvent) => { this.touch(event); })
        .onAccessibilityHoverTransparent((event: TouchEvent) => { console.info(`TOUCHMAP_ACCESSIBILITY_HOVER type=${event.type} contacts=${event.touches.length}`); this.touch(event); })
      Text('Exploration surface. The controls and object list below remain accessible.').fontSize(12 * this.profile.textScale).fontColor('#A6BBC8').width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Button('Zoom +').height(48).margin(3).onClick(() => { this.viewport(1.25, 0, 0); })
        Button('Zoom −').height(48).margin(3).onClick(() => { this.viewport(0.8, 0, 0); })
        Button('Left').height(48).margin(3).onClick(() => { this.viewport(1, 30, 0); })
        Button('Right').height(48).margin(3).onClick(() => { this.viewport(1, -30, 0); })
        Button('Up').height(48).margin(3).onClick(() => { this.viewport(1, 0, 30); })
        Button('Down').height(48).margin(3).onClick(() => { this.viewport(1, 0, -30); })
        Button('Rotate').height(48).margin(3).onClick(() => { this.viewport(1, 0, 0, 90); })
        Button('Reset view').height(48).margin(3).onClick(() => { this.action('viewport', '', undefined, { scale: 1, offsetX: 0, offsetY: 0, rotation: 0 }); })
      }.width('100%')
    }
    Column({ space: 10 }) {
      Text(this.focus()?.label || 'Choose your first object').fontSize(24 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#69E2C5').width('100%')
      if (this.focus()) {
        Text(this.focus()!.description).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
        Row({ space: 10 }) { Button('Previous').fontSize(16 * this.profile.textScale).labelStyle({ maxLines: 2, minFontSize: 0 }).constraintSize({ minHeight: 50 }).layoutWeight(1).onClick(() => { this.action('previousRegion'); }); Button('Next').fontSize(16 * this.profile.textScale).labelStyle({ maxLines: 2, minFontSize: 0 }).constraintSize({ minHeight: 50 }).layoutWeight(1).onClick(() => { this.action('nextRegion'); }) }.width('100%')
        Button('Replay label').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.speak(this.active!, this.progress!.lastRegionId, 'label', this.profile, true); })
        Button('Describe this object').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('describe'); })
        Button(this.progress!.bookmarks.includes(this.progress!.lastRegionId) ? 'Remove bookmark' : 'Bookmark this object').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('bookmark', this.progress!.lastRegionId); })
      }
    }.padding(18).width('100%').backgroundColor('#142F3C').borderRadius(16)
    if (this.overlaps.length > 1) {
      Text(`${this.overlaps.length} overlapping objects. Choose a layer:`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      ForEach(this.overlaps, (r: Region) => { Button(`Layer ${r.zIndex}: ${r.label}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', r.id); }) }, (r: Region) => r.id)
    }
    if (this.interaction === 'Scan') {
      Text('Scanning highlights a choice. One press applies it. This is an on-screen selection mode.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      Button(this.scanning ? 'Select highlighted choice' : 'Start scanning').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { if (this.scanning) { this.chooseScan(); } else { this.startScan(); } })
      if (this.scanning) { Button('Pause scanning').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.stopScan(); }) }
    }
    Button('Connections').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.showConnections = !this.showConnections; })
    if (this.showConnections) {
      ForEach(this.active!.diagram.relations.filter((r: Relation) => !this.progress!.lastRegionId || r.fromId === this.progress!.lastRegionId || r.toId === this.progress!.lastRegionId), (r: Relation) => {
        Column({ space: 8 }) {
          Text(`${!this.progress!.lastRegionId ? 'Connection' : r.direction === 'both' ? 'Bidirectional' : r.fromId === this.progress!.lastRegionId ? 'Outgoing' : 'Incoming'}: ${r.label}. ${r.direction === 'unknown' ? 'Direction unknown.' : r.direction === 'both' ? 'Both directions.' : 'Forward direction.'} ${r.path ? 'Route is known.' : 'Route in the picture is unspecified.'}`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
          Button('Select this connection').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('selectRelation', r.id); })
          if (r.toId === this.progress!.lastRegionId && r.direction === 'forward') {
            Button('Visit the source of this incoming connection').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', r.fromId); })
          }
          Button('Follow to destination').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('followRelation', r.id); })
        }.padding(12).backgroundColor('#142F3C').borderRadius(12)
      }, (r: Relation) => r.id)
      if (this.guide) { Text(this.guide).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
    }
    Text('OBJECTS').fontSize(12).letterSpacing(2).fontWeight(FontWeight.Bold).fontColor('#A6BBC8').width('100%')
    ForEach(orderedRegions(this.active!.diagram), (r: Region, index: number) => {
      Button(`${index + 1}. ${r.label}${this.progress!.bookmarks.includes(r.id) ? ' · bookmarked' : ''}${this.scanning && this.scanIndex === index ? ' · scan highlighted' : ''}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', r.id); })
    }, (r: Region) => r.id)
    ForEach(this.active!.diagram.charts, (chart: Chart) => {
      Column({ space: 8 }) { Text(chart.title).fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(`${chart.yAxis.label}, ${chart.yAxis.unit}. ${chart.yAxis.scale} scale.`).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
      ForEach(chart.series, (series: Series) => {
        Text(series.label).fontColor('#69E2C5').fontSize(18 * this.profile.textScale)
        ForEach(series.values, (value: ChartValue) => { Text(`${value.x}: ${value.value === null ? 'unknown' : value.value.toFixed(value.precision) + ' ' + chart.yAxis.unit}`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }, (value: ChartValue) => value.id)
      }, (series: Series) => series.id)
    }, (chart: Chart) => chart.id)
    Button('Listen to material overview').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.speak(this.active!, this.active!.diagram.packageId, 'overview', this.profile, true); })
    Flex({ wrap: FlexWrap.Wrap }) {
      Button('Pause recording').fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { feedback.pauseRecording(); })
      Button('Resume recording').fontSize(16 * this.profile.textScale).constraintSize({ minHeight: 48 }).padding(10).margin(3).onClick(() => { feedback.resumeRecording(); })
    }.width('100%')
    Text('Use overview for the complete description, or choose objects and Describe for section navigation. Pause, resume and replay keep the reading pace under your control.').fontSize(14 * this.profile.textScale).fontColor('#B7C8D2').width('100%')
    Button('Open lesson questions').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.go('Lesson'); })
    Button('Pause and save context').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('pause'); })
  }
  @Builder lesson() {
    Column({ space: 8 }) { Text('Make the connection.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('Explore the material, choose an answer, then explicitly submit it.').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    ForEach(this.active!.diagram.questions, (q: Question) => {
      Button(q.prompt).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('openQuestion', q.id); })
    }, (q: Question) => q.id)
    if (this.question()) {
      Column({ space: 14 }) {
        Text(this.question()!.prompt).fontSize(24 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%')
        Text(this.question()!.type === 'sequence' ? 'Choose options in the required order. Selecting an option again removes it.' : this.question()!.acceptedAnswers.length > 1 ? 'Select every correct answer.' : 'Choose one answer.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
        ForEach(this.question()!.options, (option: AnswerOption) => {
          Button(`${this.progress!.selectedAnswers.includes(option.id) ? 'Selected: ' : ''}${option.label}`).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).width('100%').constraintSize({ minHeight: 54 }).padding(12).fontSize(17 * this.profile.textScale)
            .backgroundColor(this.progress!.selectedAnswers.includes(option.id) ? '#69E2C5' : '#2A4653').fontColor(this.progress!.selectedAnswers.includes(option.id) ? '#09252A' : '#F3F8FA')
            .accessibilityText(`${option.label}, ${this.progress!.selectedAnswers.includes(option.id) ? 'selected' : 'not selected'}`).onClick(() => { this.selectAnswer(option.id); })
        }, (option: AnswerOption) => option.id)
        if (this.question()!.type === 'sequence' && this.progress!.selectedAnswers.length > 0) { Text('Current order: ' + this.progress!.selectedAnswers.join(', ')).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%') }
        if (this.progress!.status === 'submitted') {
          Text((this.progress!.submissions[this.progress!.submissions.length - 1]?.correct ? 'Correct. ' : 'Explore this relationship again. ') + this.question()!.explanation).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
        } else { Button('Submit selected answer').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.action('submitAnswer'); }) }
        if (this.question()!.hint) { Button('Read hint').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.status = this.question()!.hint; }) }
        Button('Explore source objects').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('Explore'); })
        Button(this.progress!.status === 'answering' ? 'Pause with selection unsubmitted' : 'Pause and save context').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('pause'); })
      }.padding(20).backgroundColor('#142F3C').borderRadius(16).width('100%')
    }
    Text(`${this.progress!.submissions.length} submitted attempts. Hearing a label never completes a question.`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button('View attempts and bookmarks').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('History'); })
  }
  @Builder resume() {
    Column({ space: 8 }) { Text('Pick up your thread.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text(this.active!.diagram.title).fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Column({ space: 14 }) {
      Text('SAVED ON THIS DEVICE').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#69E2C5').letterSpacing(1.8).width('100%')
      Text(resumeContext(this.active!.diagram, this.progress!)).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      Text(`Material revision ${this.progress!.revision}. An unfinished selection is never treated as a submitted answer.`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    }.width('100%').padding(20).borderRadius(16).backgroundColor('#142F3C')
    Button('Resume').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.action('resume').then((saved: boolean) => { if (saved) { this.go(this.progress!.activeQuestionId ? 'Lesson' : 'Explore'); } }); })
    Button('Repeat context').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.status = resumeContext(this.active!.diagram, this.progress!); if (this.progress!.lastRegionId) { feedback.speak(this.active!, this.progress!.lastRegionId, 'description', this.profile, true); } })
    Button('Start again, keep previous attempts').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('startAgain').then((saved: boolean) => { if (saved) { this.go('Explore'); } }); })
    Button('View attempts and bookmarks').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.go('History'); })
  }
  @Builder history() {
    Column({ space: 8 }) { Text('Your learning trail.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('Only explicit submissions appear as attempts.').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    ForEach(this.progress!.submissions, (submission: Submission) => {
      Text(`${this.active!.diagram.questions.find((q: Question) => q.id === submission.questionId)?.prompt || submission.questionId}\n${submission.correct ? 'Correct' : 'Review suggested'} · ${submission.answers.join(', ')} · ${new Date(submission.timestamp).toLocaleString()}`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    }, (submission: Submission) => submission.eventId)
    ForEach(this.progress!.bookmarks, (id: string) => { Button(this.active!.diagram.regions.find((r: Region) => r.id === id)?.label || id).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.action('focusRegion', id); this.go('Explore'); }) })
    Button('Export private learning history').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.repository!.exportHistory(this.active!).then((saved: boolean) => { this.status = saved ? 'Private history exported separately.' : 'History export cancelled.'; }).catch((error: Error) => { this.fail(error); }); })
    Button('Delete learning history and bookmarks').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.repository!.clearHistory(this.active!).then(async () => { this.progress = await this.repository!.progress(this.active!); this.status = 'Learning history deleted from this device.'; }).catch((error: Error) => { this.fail(error); }); })
  }
  @Builder importSource() {
    Column({ space: 8 }) { Text('Turn a source into a lesson.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('Start with a package, SVG or image that you have permission to use.').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Button('Choose source or .touchmap package').enabled(!this.busy).type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.pick(); })
    if (this.sourcePreview) {
      if (this.sourceType === 'svg') { Text('SVG preview may omit source text or arrowheads on this device. Convert through the preparation service or computer CLI before reviewing visual details.').fontSize(16 * this.profile.textScale).fontColor('#FFCE90').width('100%') }
      Image(`file://${this.sourcePreview}`).width('100%').height(240).objectFit(ImageFit.Contain).backgroundColor('#FFFFFF').borderRadius(12).accessibilityText('Selected source preview. Add a description and review its objects in the author studio.')
      Text(`${this.importWidth} × ${this.importHeight} source pixels. ${this.sourceType === 'png' ? 'Raster metadata removed.' : 'SVG preparation reports unsupported features explicitly.'}`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
      Column({ space: 5 }) { Text('Material title').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.sourceName }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.sourceName = s; }).accessibilityText('Material title') }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 5 }) { Text('Source attribution').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.attribution }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.attribution = s; }).accessibilityText('Source attribution') }.width('100%').alignItems(HorizontalAlign.Start)
      Column({ space: 5 }) { Text('License or rights declaration').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.license }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.license = s; }).accessibilityText('License or rights declaration') }.width('100%').alignItems(HorizontalAlign.Start)
      if (this.sourceType === 'png') {
        Column({ space: 5 }) { Text('Crop left').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropX }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropX = s; }).accessibilityText('Crop left') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Crop top').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropY }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropY = s; }).accessibilityText('Crop top') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Crop width').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropW }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropW = s; }).accessibilityText('Crop width') }.width('100%').alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) { Text('Crop height').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.cropH }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.cropH = s; }).accessibilityText('Crop height') }.width('100%').alignItems(HorizontalAlign.Start)
        Button('Apply crop and update preview').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.crop(); })
      }
      Button('Create local authoring draft').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.createDraft(); })
      Text('Manual authoring stays offline. Optional cloud preparation requires a separate consent in the editor.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    }
  }
  @Builder settings() {
    Column({ space: 8 }) { Text('Make it feel right.').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('Your interaction profile stays on this device and applies to every material.').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Text(`Label delay: ${this.profile.dwell} ms`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.dwell, min: 0, max: 1500, step: 50 }).onChange((value: number) => { this.profile.dwell = value; }).accessibilityText('Label dwell delay')
    Text(`Audio level: ${Math.round(this.profile.volume * 100)} percent`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.volume, min: 0, max: 1, step: 0.1 }).onChange((value: number) => { this.profile.volume = value; }).accessibilityText('Audio volume')
    Text(`Text size: ${Math.round(this.profile.textScale * 100)} percent`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.textScale, min: 1, max: 2, step: 0.25 }).onChange((value: number) => { this.profile.textScale = value; }).accessibilityText('Text size, up to 200 percent')
    Text(`Scanning interval: ${this.profile.scanMs} ms`).fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Slider({ value: this.profile.scanMs, min: 700, max: 5000, step: 100 }).onChange((value: number) => { this.profile.scanMs = value; }).accessibilityText('Scanning speed')
    Row({ space: 10 }) { Toggle({ type: ToggleType.Switch, isOn: this.profile.vibration }).onChange((value: boolean) => { this.profile.vibration = value; }); Text('Optional vibration').fontColor('#EAF5F8').fontSize(17 * this.profile.textScale).layoutWeight(1) }.width('100%')
    Text(feedback.vibrationAvailable ? 'A supported haptic effect is reported by this device.' : 'No supported haptic effect reported. Text and audio remain complete.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button('Try vibration').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.cue(this.profile); })
    Row({ space: 10 }) { Toggle({ type: ToggleType.Switch, isOn: this.profile.contrast }).onChange((value: boolean) => { this.profile.contrast = value; }); Text('High contrast').fontColor('#EAF5F8').fontSize(17 * this.profile.textScale).layoutWeight(1) }.width('100%')
    Row({ space: 10 }) { Toggle({ type: ToggleType.Switch, isOn: this.profile.readerSpeech }).onChange((value: boolean) => { this.profile.readerSpeech = value; }); Text('Let screen reader handle automatic labels').fontColor('#EAF5F8').fontSize(17 * this.profile.textScale).layoutWeight(1) }.width('100%')
    Text(feedback.reader ? 'Screen reader accessibility is currently enabled. Explicit Replay still plays recordings.' : 'Screen reader accessibility is currently disabled. Native recordings are available.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Button('Save preferences').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontWeight(FontWeight.Medium).fontColor('#082D2D').backgroundColor('#69E2C5').borderRadius(12).width('100%').constraintSize({ minHeight: 54 }).padding(12).onClick(() => { this.saveProfile(); })
    Button('Repeat exploration tutorial').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { this.tutorialStep = 0; this.go('Tutorial'); })
    Column({ space: 8 }) { Text('About TouchMap').fontSize(30 * this.profile.textScale).fontWeight(FontWeight.Bold).fontColor('#F3F8FA').width('100%'); Text('DEFOZO SOFTWARE HOUSE').fontSize(16 * this.profile.textScale).fontColor('#B7C8D2').width('100%') }.width('100%').alignItems(HorizontalAlign.Start)
    Text('Team member: Michał Kiełtyka. Human-Centric Technology, IMAGINE WHAT’S NEXT, HackYeah 2026.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
    Text('OPTIONAL PREPARATION SERVICE').fontSize(12).letterSpacing(1.5).fontColor('#69E2C5').width('100%').margin({ top: 18 })
    Column({ space: 5 }) { Text('HTTPS service address').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.profile.service }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.profile.service = s; }).accessibilityText('HTTPS service address') }.width('100%').alignItems(HorizontalAlign.Start)
    Column({ space: 5 }) { Text('One-use pairing code from the service operator').fontSize(14 * this.profile.textScale).fontColor('#C3D3DC').width('100%'); TextInput({ text: this.pairingCode }).fontSize(16 * this.profile.textScale).fontColor('#12313C').backgroundColor('#EEF4F6').height(52 * this.profile.textScale).borderRadius(9).onChange((s: string) => { this.pairingCode = s; }).accessibilityText('One-use pairing code from the service operator') }.width('100%').alignItems(HorizontalAlign.Start)
    Button('Pair this authoring session').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => {
      this.preparation.base = this.profile.service;
      this.preparation.pair(this.pairingCode).then(async () => { this.pairingCode = ''; await this.saveProfile(); this.status = 'Authoring session paired. Image and speech uploads still require separate consent.'; }).catch((error: Error) => { this.fail(error); });
    })
    Text('Provider keys stay on the preparation server. Learner activity is never sent. Pairing expires and is kept only in this running app session.').fontSize(16 * this.profile.textScale).fontColor('#C3D3DC').width('100%')
  }
  build() {
    Column() {
      Row({ space: 10 }) {
        Text('◉').fontSize(30).fontColor('#69E2C5')
        Column({ space: 1 }) { Text('TouchMap').fontSize(23).fontWeight(FontWeight.Bold).fontColor('#F3F8FA'); Text('UNDERSTAND THROUGH EXPLORATION').fontSize(8).letterSpacing(1.3).fontColor('#A6BBC8') }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('Stop audio').id('stop-audio').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(13 * this.profile.textScale).constraintSize({ minHeight: 46 }).padding(10).backgroundColor('#29434E').fontColor('#F3F8FA').borderRadius(9).onClick(() => { feedback.stop(); this.status = 'Audio stopped.'; }).accessibilityText('Stop all audio immediately')
      }.padding({ left: 22, right: 22, top: 18, bottom: 14 }).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Button('Library').id('nav-library').fontSize(14 * this.profile.textScale).constraintSize({ minHeight: 46 }).width(this.profile.textScale > 1.5 ? '50%' : '33.333%').padding(8).backgroundColor(this.page === 'Library' ? '#69E2C5' : '#203A46').fontColor(this.page === 'Library' ? '#09252A' : '#F3F8FA').onClick(() => { this.go('Library'); this.repository?.list().then((items: Material[]) => { this.items = items; }); })
        Button('Import').fontSize(14 * this.profile.textScale).constraintSize({ minHeight: 46 }).width(this.profile.textScale > 1.5 ? '50%' : '33.333%').padding(8).backgroundColor('#203A46').onClick(() => { this.go('Import'); })
        Button('Settings').id('nav-settings').fontSize(14 * this.profile.textScale).constraintSize({ minHeight: 46 }).width(this.profile.textScale > 1.5 ? '50%' : '33.333%').padding(8).backgroundColor('#203A46').onClick(() => { this.go('Settings'); })
      }.padding({ left: 20, right: 20, bottom: 10 }).width('100%')
      if (this.busy) { Row({ space: 10 }) { LoadingProgress().width(28).height(28); Text(this.busyOperation).fontSize(16 * this.profile.textScale).fontColor('#FFCE90').layoutWeight(1) }.padding(12).width('100%').accessibilityText(this.busyOperation + '. Please wait.') }
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
              EditorPanel({ material: this.active, repository: this.repository!, onSaved: (material: Material) => { this.active = material; this.repository!.list().then((items: Material[]) => { this.items = items; }); } })
            }
          }
          Text(this.status).fontSize(14 * this.profile.textScale).fontColor('#FFCE90').width('100%').padding(14).backgroundColor('#213541').borderRadius(10)
          if (this.active && this.page !== 'Library' && this.page !== 'Accept') {
            Button('Exit to library').type(ButtonType.Normal).labelStyle({ maxLines: 1000, minFontSize: 0 }).fontSize(16 * this.profile.textScale).fontColor('#EAF5F8').backgroundColor('#25424F').borderRadius(12).width('100%').constraintSize({ minHeight: 50 }).padding(10).onClick(() => { feedback.stop(); this.stopScan(); this.go('Library'); })
          }
          Text('Built for curiosity. Your pace, your path.').fontSize(12).fontColor('#A6BBC8').padding({ top: 6, bottom: 24 })
        }.padding({ left: 22, right: 22, top: 12 }).width('100%').alignItems(HorizontalAlign.Start)
      }.id('main-scroll').layoutWeight(1).width('100%').scrollBar(BarState.Auto).enableScrollInteraction(!this.exploringTouch)
    }.height('100%').width('100%').backgroundColor(this.palette())
  }
}
