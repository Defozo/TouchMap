import { describe, it, expect, beforeAll, afterAll } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { nativeContext } from '../testrunner/NativeContext';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Repository, Material, decode, uid, digest, encode, safePath } from '../../../main/ets/platform/Repository';
import { Diagram, Action, Progress, Polygon, Viewport } from '../../../main/ets/domain/types';
import { initialProgress, applyAction, resumeContext } from '../../../main/ets/domain/engine';
import { sourcePoint, screenPoint, pointInPolygon, hitTest, guidePath } from '../../../main/ets/domain/geometry';
import { DraftEditor } from '../../../main/ets/domain/editor';
import { validateDiagram, publicationIssues, offlineReadiness } from '../../../main/ets/domain/validate';

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
    it('portable_paths_reject_traversal_and_reserved_names', 0, () => {
      expect(safePath('../secret')).assertFalse(); expect(safePath('/absolute')).assertFalse();
      expect(safePath('audio/CON.wav')).assertFalse(); expect(safePath('audio/label.wav')).assertTrue();
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
      const scroll = await driver.findComponent(ON.id('main-scroll'));
      const repeat = await scroll.scrollSearch(ON.text('Repeat exploration tutorial')); await repeat.click(); await driver.delayMs(200);
      let next = await driver.findComponent(ON.id('tutorial-next')); await next.click(); await driver.delayMs(200);
      next = await driver.findComponent(ON.id('tutorial-next')); await next.click(); await driver.delayMs(200);
      expect(await driver.findComponent(ON.text('Start exploring')) !== null).assertTrue();
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
