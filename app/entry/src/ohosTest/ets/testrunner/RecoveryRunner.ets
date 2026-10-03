import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { nativeContext } from './NativeContext';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Repository, Material, decode, encode, readBytes, writeBytes } from '../../../main/ets/platform/Repository';
import { hitTest } from '../../../main/ets/domain/geometry';
import { Diagram, Progress, Action } from '../../../main/ets/domain/types';

interface RecoveryMetrics { events: number; clock: string; hitTestP95Ms: number; hitTestMaxMs: number; progressReadP95Ms: number; progressReadMaxMs: number; scope: string; }
interface RecoveryMarker {
  status: string; cycle: number; phase: string; verifiedPrevious: boolean; stateRevision: number;
  submissions: number; selected: string[]; lastRegion: string; importedKey: string; error: string;
}
class RecoveryRepository extends Repository {
  async saveAs(bytes: Uint8Array, _name: string): Promise<boolean> {
    writeBytes(`${this.context.filesDir}/recovery-transfer.touchmap`, bytes); return true;
  }
}
export async function runRecovery(cycle: number): Promise<void> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const context = await nativeContext();
  const markerPath = `${context.filesDir}/recovery-observed.json`;
  let marker: RecoveryMarker = {status:'failed',cycle:cycle,phase:'initializing',verifiedPrevious:false,stateRevision:0,submissions:0,selected:[],lastRegion:'',importedKey:'',error:''};
  try {
    if (!Number.isInteger(cycle) || cycle < 0 || cycle > 10000) { throw new Error('Invalid recoveryCycle'); }
    const repository = new RecoveryRepository(context); await repository.initialize();
    let materials = await repository.list(); let material = materials.find((entry: Material) => entry.diagram.packageId === 'native-recovery');
    if (cycle === 0) {
      if (material) { await repository.deleteMaterial(material); }
      for (const old of materials.filter((entry: Material) => entry.diagram.packageId.startsWith('native-recovery-import-'))) { await repository.deleteMaterial(old); }
      const diagram = JSON.parse(decode(await context.resourceManager.getRawFileContent('samples/water-cycle/diagram.json'))) as Diagram;
      diagram.packageId = 'native-recovery'; diagram.title = 'Forced restart recovery test'; diagram.audio = [];
      material = await repository.createSource(diagram, await context.resourceManager.getRawFileContent('samples/water-cycle/source.svg'), diagram.source.previewPath ? await context.resourceManager.getRawFileContent(`samples/water-cycle/${diagram.source.previewPath}`) : undefined);
    }
    if (!material) { throw new Error('Recovery material missing after process restart'); }
    let progress = await repository.progress(material);
    if (cycle === 0) {
      const hits: number[] = []; const restores: number[] = [];
      for (let index = 0; index < 100; index++) {
        const x = (index * 73) % material.diagram.source.width; const y = (index * 47) % material.diagram.source.height;
        let started = Date.now(); hitTest(material.diagram, {x:x,y:y}); hits.push(Date.now() - started);
        started = Date.now(); await repository.progress(material); restores.push(Date.now() - started);
      }
      hits.sort((a: number, b: number) => a - b); restores.sort((a: number, b: number) => a - b);
      const metrics: RecoveryMetrics = {events:100,clock:'Date.now milliseconds',hitTestP95Ms:hits[94],hitTestMaxMs:hits[99],progressReadP95Ms:restores[94],progressReadMaxMs:restores[99],scope:'Warm native hit tests and committed checkpoint reads; excludes cold launch, UI rendering and human tasks'};
      writeBytes(`${context.filesDir}/recovery-metrics.json`, encode(JSON.stringify(metrics))); console.info(`TOUCHMAP_NATIVE_METRICS ${JSON.stringify(metrics)}`);
    }

    if (cycle > 0) {
      const previous = JSON.parse(decode(readBytes(markerPath))) as RecoveryMarker;
      if (previous.status !== 'committed' || previous.cycle !== cycle - 1 || previous.stateRevision !== progress.stateRevision || previous.submissions !== progress.submissions.length || previous.selected.join(',') !== progress.selectedAnswers.join(',') || previous.lastRegion !== progress.lastRegionId) { throw new Error('Acknowledged progress differs after forced restart'); }
      if (previous.importedKey) {
        const imported = materials.find((entry: Material) => entry.key === previous.importedKey);
        if (!imported || !fs.accessSync(`${imported.directory}/${imported.diagram.source.path}`)) { throw new Error('Acknowledged imported material missing after restart'); }
        await repository.deleteMaterial(imported);
      }
      marker.verifiedPrevious = true;
    }
    const dispatch = async (type: string, targetId: string = '', answers?: string[]): Promise<void> => {
      progress = await repository.dispatch(material!, {eventId:`recovery-${cycle}-${type}`,expectedRevision:progress.stateRevision,type:type,targetId:targetId,answerIds:answers});
    };
    const question = material.diagram.questions[0];
    if (cycle % 4 === 0) {
      marker.phase = 'save'; await dispatch('focusRegion', material.diagram.regions[(cycle / 4) % material.diagram.regions.length].id);
      await dispatch('bookmark', progress.lastRegionId);
    } else if (cycle % 4 === 1) {
      marker.phase = 'unfinished-selection'; const submissions = progress.submissions.length;
      await dispatch('openQuestion', question.id); await dispatch('selectAnswer', '', question.acceptedAnswers); await dispatch('pause');
      if (progress.submissions.length !== submissions || progress.status !== 'answering') { throw new Error('Unfinished answer was incorrectly submitted'); }
    } else if (cycle % 4 === 2) {
      marker.phase = 'submit-duplicate'; await dispatch('resume'); const count = progress.submissions.length;
      const submit: Action = {eventId:`recovery-${cycle}-submit`,expectedRevision:progress.stateRevision,type:'submitAnswer'};
      progress = await repository.dispatch(material, submit); const duplicate = await repository.dispatch(material, submit);
      if (progress.submissions.length !== count + 1 || duplicate.submissions.length !== progress.submissions.length || duplicate.stateRevision !== progress.stateRevision) { throw new Error('Duplicate submission was not idempotent'); }
    } else {
      marker.phase = 'package-import';
      const diagram = JSON.parse(JSON.stringify(material.diagram)) as Diagram; diagram.packageId = `native-recovery-import-${cycle}`; diagram.title = 'Recovery package transfer';
      marker.phase = 'package-create';
      let transfer = await repository.createSource(diagram, readBytes(`${material.directory}/${diagram.source.path}`), diagram.source.previewPath ? readBytes(`${material.directory}/${diagram.source.previewPath}`) : undefined);
      transfer.manifest.author = {name:'TouchMap native test',declaration:'Deterministic test fixture. Not a learner-authored package.'};
      marker.phase = 'package-export'; await repository.exportPackage(transfer);
      marker.phase = 'package-delete-original'; await repository.deleteMaterial(transfer);
      marker.phase = 'package-import';
      transfer = await repository.importPackage(`${context.filesDir}/recovery-transfer.touchmap`);
      if (transfer.accepted) { throw new Error('Imported declaration was automatically trusted'); }
      marker.importedKey = transfer.key;
    }
    marker.status = 'committed'; marker.stateRevision = progress.stateRevision; marker.submissions = progress.submissions.length;
    marker.selected = progress.selectedAnswers; marker.lastRegion = progress.lastRegionId;
    writeBytes(markerPath, encode(JSON.stringify(marker)));
    console.info(`TOUCHMAP_RECOVERY_COMMITTED ${JSON.stringify(marker)}`);
  } catch (error) {
    console.error(`TOUCHMAP_RECOVERY_ERROR_STACK ${(error as Error).stack}`);
    marker.error = (error as Error).message; writeBytes(markerPath, encode(JSON.stringify(marker)));
    console.error(`TOUCHMAP_RECOVERY_FAILED ${JSON.stringify(marker)}`);
  }
  // Keep this test process alive. The host controller must force-stop it after the fsynced marker.
  setInterval(() => { console.info('TOUCHMAP_RECOVERY_WAITING_FOR_FORCE_STOP'); }, 60000);
}
