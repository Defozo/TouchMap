import { describe, it, expect, beforeAll, afterAll } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, On, Component } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { nativeContext } from '../testrunner/NativeContext';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Repository, Material, decode, uid, digest, encode, safePath, writeBytes, readBytes } from '../../../main/ets/platform/Repository';
import { Diagram, Action, Progress, Polygon, Viewport } from '../../../main/ets/domain/types';
import { initialProgress, applyAction, resumeContext } from '../../../main/ets/domain/engine';
import { sourcePoint, screenPoint, pointInPolygon, hitTest, guidePath, retainRegionNearBoundary } from '../../../main/ets/domain/geometry';
import { DraftEditor } from '../../../main/ets/domain/editor';
import { validateDiagram, publicationIssues, offlineReadiness } from '../../../main/ets/domain/validate';
import { openedFileUri } from '../../../main/ets/platform/WantReceiver';
import { initializeI18n, tr } from '../../../main/ets/platform/I18n';

async function visibleAfterMarginScroll(driver: Driver, selector: On, phase: string): Promise<Component> {
  for (let attempt = 0; attempt < 16; attempt++) {
    const scroll = await driver.findComponent(ON.id('main-scroll'));
    const area = await scroll.getBounds();
    const candidate = await driver.findComponent(selector);
    if (candidate) {
      const bounds = await candidate.getBounds();
      if (bounds.bottom - bounds.top >= 24 && bounds.top >= area.top && bounds.bottom <= area.bottom) {
        console.info(`TOUCHMAP_TUTORIAL_TEST phase=${phase} scrolls=${attempt}`); return candidate;
      }
    }
    // The content margin avoids changing Slider values while looking for a control.
    await driver.swipe(area.right - 10, area.bottom - 35, area.right - 10, area.top + 35, 1600);
  }
  throw new Error(`Tutorial control was not reachable: ${phase}`);
}

export default function nativeSuite(): void {
  describe('TouchMapNative', () => {
    let repository: Repository;
    let material: Material;
    let diagram: Diagram;
    let context: common.UIAbilityContext;
    beforeAll(async () => {
      context = await nativeContext();
      repository = new Repository(context); await repository.initialize();
      diagram = JSON.parse(decode(await context.resourceManager.getRawFileContent('samples/water-cycle/diagram.json'))) as Diagram;
      diagram.packageId = `native-test-${uid()}`; diagram.title = 'Native transactional test'; diagram.audio = [];
      material = await repository.createSource(diagram, await context.resourceManager.getRawFileContent('samples/water-cycle/source.svg'), diagram.source.previewPath ? await context.resourceManager.getRawFileContent(`samples/water-cycle/${diagram.source.previewPath}`) : undefined);
    });
    afterAll(async () => { if (material) { await repository.deleteMaterial(material); } });

    it('native_hash_uses_platform_SHA256', 0, async () => {
      expect(await digest(encode('abc'))).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
    it('bundled_geometry_and_questions_pass_contract', 0, () => {
      expect(validateDiagram(diagram).length).assertEqual(0);
      expect(publicationIssues(diagram).length).assertEqual(0);
      expect(offlineReadiness(diagram, [diagram.source.path]).ready).assertFalse();
    });
    it('hole_boundaries_and_viewport_roundtrip', 0, () => {
      const polygon: Polygon = { outer: [{x:0,y:0},{x:100,y:0},{x:100,y:100},{x:0,y:100}], holes: [[{x:30,y:30},{x:70,y:30},{x:70,y:70},{x:30,y:70}]] };
      expect(pointInPolygon({x:0,y:50}, polygon)).assertTrue();
      expect(pointInPolygon({x:50,y:50}, polygon)).assertFalse();
      expect(pointInPolygon({x:30,y:50}, polygon)).assertFalse();
      const viewport: Viewport = {scale:2.5,offsetX:37,offsetY:-18,rotation:90};
      const restored = sourcePoint(screenPoint({x:18,y:43}, viewport), viewport);
      expect(Math.abs(restored.x - 18) < 0.000001 && Math.abs(restored.y - 43) < 0.000001).assertTrue();
      expect(hitTest(diagram, {x:NaN,y:0}).length).assertEqual(0);
      expect(guidePath({x:0,y:0}, null, 5, 'Destination').known).assertFalse();
    });
    it('boundary_hysteresis_retains_jitter_but_releases_clear_crossing', 0, () => {
      const local = JSON.parse(JSON.stringify(diagram)) as Diagram;
      const region = local.regions[0]; local.regions = [region]; region.line = []; region.lineWidth = 0;
      region.polygons = [{ outer: [{x:0,y:0},{x:10,y:0},{x:10,y:10},{x:0,y:10}], holes: [] }];
      expect(hitTest(local, {x:10.4,y:5}).length).assertEqual(0);
      expect(retainRegionNearBoundary(local, {x:10.4,y:5}, region.id, 0.5)?.id).assertEqual(region.id);
      expect(retainRegionNearBoundary(local, {x:10.6,y:5}, region.id, 0.5) === undefined).assertTrue();
      expect(retainRegionNearBoundary(local, {x:10.4,y:5}, '', 0.5) === undefined).assertTrue();
    });
    it('native_English_resources_resolve_and_keep_dynamic_values_literal', 0, () => {
      expect(context.resourceManager.getStringByNameSync('tm_16b98aa8bc32')).assertEqual('Start exploring');
      initializeI18n(context.resourceManager);
      expect(tr('tm_03072fec9bb5', ['12 {0} $&'])).assertEqual('Continue authoring revision 12 {0} $&');
    });
    it('touch_and_pause_never_submit_and_checkpoint_reloads', 0, async () => {
      await repository.clearHistory(material);
      let progress = await repository.progress(material);
      progress = await repository.dispatch(material, {eventId:uid(),expectedRevision:progress.stateRevision,type:'focusRegion',targetId:diagram.regions[0].id});
      const question = diagram.questions[0];
      progress = await repository.dispatch(material, {eventId:uid(),expectedRevision:progress.stateRevision,type:'openQuestion',targetId:question.id});
      progress = await repository.dispatch(material, {eventId:uid(),expectedRevision:progress.stateRevision,type:'selectAnswer',answerIds:question.acceptedAnswers});
      progress = await repository.dispatch(material, {eventId:uid(),expectedRevision:progress.stateRevision,type:'pause'});
      const reloaded = new Repository(context); await reloaded.initialize();
      const committed = await reloaded.progress(material);
      expect(committed.submissions.length).assertEqual(0);
      expect(committed.selectedAnswers.join(',')).assertEqual(question.acceptedAnswers.join(','));
      expect(committed.paused).assertTrue();
      expect(resumeContext(diagram, committed).includes('not submitted')).assertTrue();
    });
    it('duplicate_submission_is_idempotent_and_stale_update_rolls_back', 0, async () => {
      await repository.clearHistory(material);
      let progress = await repository.progress(material); const question = diagram.questions[0];
      progress = await repository.dispatch(material, {eventId:uid(),expectedRevision:progress.stateRevision,type:'openQuestion',targetId:question.id});
      progress = await repository.dispatch(material, {eventId:uid(),expectedRevision:progress.stateRevision,type:'selectAnswer',answerIds:question.acceptedAnswers});
      const submit: Action = {eventId:uid(),expectedRevision:progress.stateRevision,type:'submitAnswer'};
      const first = await repository.dispatch(material, submit); const repeated = await repository.dispatch(material, submit);
      expect(first.submissions.length).assertEqual(1); expect(repeated.submissions.length).assertEqual(1);
      expect(repeated.stateRevision).assertEqual(first.stateRevision); expect(first.submissions[0].correct).assertTrue();
      let rejected = false;
      try { await repository.dispatch(material, {eventId:uid(),expectedRevision:0,type:'focusRegion',targetId:diagram.regions[0].id}); } catch (error) { rejected = true; }
      expect(rejected).assertTrue(); expect((await repository.progress(material)).stateRevision).assertEqual(first.stateRevision);
    });
    it('changed_relation_invalidates_question_and_late_result', 0, () => {
      const editor = new DraftEditor(diagram); const relation = editor.diagram.relations[0]; relation.label = 'Changed meaning';
      editor.updateRelation(relation);
      expect(editor.diagram.questions.filter((q) => q.factIds.includes(relation.id)).every((q) => q.review.status === 'needs_review')).assertTrue();
      expect(editor.replaceFromJob(diagram, diagram.source.sha256, diagram.revision)).assertFalse();
      expect(editor.undo()).assertTrue(); expect(editor.diagram.revision).assertEqual(diagram.revision);
      expect(editor.redo()).assertTrue(); expect(editor.diagram.revision).assertEqual(diagram.revision + 1);
    });
    it('undo_to_published_content_preserves_the_accepted_revision', 0, async () => {
      const sample = JSON.parse(decode(await context.resourceManager.getRawFileContent('samples/water-cycle/diagram.json'))) as Diagram;
      const overview = sample.audio.find((item) => item.kind === 'overview')!;
      overview.targetId = material.diagram.packageId;
      writeBytes(`${material.directory}/${overview.path}`, await context.resourceManager.getRawFileContent(`samples/water-cycle/${overview.path}`));
      const withAudio = JSON.parse(JSON.stringify(material.diagram)) as Diagram; withAudio.audio = [overview];
      material = await repository.saveDraft(withAudio, material);
      const published: Material = JSON.parse(JSON.stringify(material)) as Material;
      published.draft = false; published.accepted = true;
      await repository.saveMaterial(published);
      let fork: Material | undefined = undefined;
      let restored: Material | undefined = undefined;
      try {
        const editor = new DraftEditor(published.diagram);
        editor.setDescription('A temporary edit to undo.');
        fork = await repository.saveDraft(editor.diagram, published);
        expect(editor.undo()).assertTrue();
        restored = await repository.saveDraft(editor.diagram, fork);
        editor.adoptSaved(restored.diagram);
        expect(restored.key !== published.key).assertTrue();
        expect(await digest(readBytes(`${restored.directory}/${overview.path}`))).assertEqual(overview.sha256);
        expect(editor.canRedo).assertTrue(); expect(editor.redo()).assertTrue();
        expect(editor.diagram.description).assertEqual('A temporary edit to undo.');
        const original = (await repository.list()).find((item: Material) => item.key === published.key)!;
        expect(original.draft).assertFalse(); expect(original.accepted).assertTrue();
        expect(original.directory).assertEqual(published.directory);
        expect(JSON.stringify(original.diagram)).assertEqual(JSON.stringify(published.diagram));
        const overwrite: Material = JSON.parse(JSON.stringify(published)) as Material; overwrite.draft = true;
        let rejected = false;
        try { await repository.saveMaterial(overwrite); } catch (error) { rejected = true; }
        expect(rejected).assertTrue();
      } finally {
        if (fork) { await repository.deleteMaterial(fork); }
        if (restored) { await repository.deleteMaterial(restored); }
      }
    });
    it('failed_draft_asset_restore_keeps_saved_material_and_cleans_staging', 0, async () => {
      const root = `${context.filesDir}/materials`;
      const before = fs.listFileSync(root).sort().join('|');
      const allBefore = JSON.stringify(await repository.list());
      const unavailable = JSON.parse(JSON.stringify(material.diagram)) as Diagram;
      unavailable.source.sha256 = '0'.repeat(64);
      let rejected = false;
      try { await repository.saveDraft(unavailable, material); } catch (error) { rejected = true; }
      expect(rejected).assertTrue();
      expect(fs.listFileSync(root).sort().join('|')).assertEqual(before);
      expect(JSON.stringify(await repository.list())).assertEqual(allBefore);
    });
    it('portable_paths_reject_traversal_and_reserved_names', 0, () => {
      expect(safePath('../secret')).assertFalse(); expect(safePath('/absolute')).assertFalse();
      expect(safePath('audio/CON.wav')).assertFalse(); expect(safePath('audio/label.wav')).assertTrue();
    });
    it('shared_file_wants_accept_one_local_uri_and_reject_remote_or_multiple_streams', 0, () => {
      expect(openedFileUri({ uri:'file://docs/lesson.touchmap' })).assertEqual('file://docs/lesson.touchmap');
      expect(openedFileUri({ parameters:{'ability.params.stream':['file://docs/lesson.touchmap']} })).assertEqual('file://docs/lesson.touchmap');
      expect(openedFileUri({ uri:'https://example.com/lesson.touchmap' })).assertEqual('');
      expect(openedFileUri({ parameters:{'ability.params.stream':['file://docs/a','file://docs/b']} })).assertEqual('');
      expect(openedFileUri({ parameters:{'ability.params.stream':'file://docs/a'} })).assertEqual('');
      expect(openedFileUri({ uri:'file://docs/a\u0000b' })).assertEqual('');
    });
    it('native_controls_open_settings_and_return_to_library', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({bundleName:'org.touchmap.app',abilityName:'EntryAbility'});
      const driver = Driver.create(); await driver.delayMs(1500);
      const settings = await driver.findComponent(ON.id('nav-settings')); await settings.click();
      await driver.delayMs(300);
      expect(await driver.findComponent(ON.text('Make it feel right.')) !== null).assertTrue();
      const stop = await driver.findComponent(ON.id('stop-audio')); await stop.click();
      const library = await driver.findComponent(ON.id('nav-library')); await library.click();
      await driver.delayMs(300);
      expect(await driver.findComponent(ON.text('A world you can explore.')) !== null).assertTrue();
    });
    it('tutorial_labels_react_to_each_step', 0, async () => {
      const driver = Driver.create();
      const settings = await driver.findComponent(ON.id('nav-settings')); await settings.click(); await driver.delayMs(200);
      const repeat = await visibleAfterMarginScroll(driver, ON.text('Repeat exploration tutorial'), 'repeat'); await repeat.click(); await driver.delayMs(200);
      let next = await visibleAfterMarginScroll(driver, ON.id('tutorial-next'), 'step-one'); await next.click(); await driver.delayMs(200);
      next = await visibleAfterMarginScroll(driver, ON.id('tutorial-next'), 'step-two'); await next.click(); await driver.delayMs(200);
      expect(await visibleAfterMarginScroll(driver, ON.text('Start exploring'), 'step-three') !== null).assertTrue();
      const library = await driver.findComponent(ON.id('nav-library')); await library.click(); await driver.delayMs(200);
    });
    it('local_deletion_removes_assets_progress_and_events', 0, async () => {
      const directory = material.directory; await repository.deleteMaterial(material);
      expect((await repository.list()).some((entry: Material) => entry.key === material.key)).assertFalse();
      expect((await repository.progress(material)).stateRevision).assertEqual(0);
      expect(fs.accessSync(directory)).assertFalse();
    });
  });
}
