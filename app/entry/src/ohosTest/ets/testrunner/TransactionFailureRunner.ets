import { abilityDelegatorRegistry } from '@kit.TestKit';
import { nativeContext } from './NativeContext';
import { Repository, Material, decode, encode, readBytes, writeBytes } from '../../../main/ets/platform/Repository';
import { Action, Diagram, Progress } from '../../../main/ets/domain/types';
import { applyAction } from '../../../main/ets/domain/engine';

interface TransactionMarker { status: string; mode: string; key: string; before: Progress; pending: Action; error: string; }
interface TransactionCheck { name: string; passed: boolean; }
interface TransactionReport { status: string; mode: string; checks: TransactionCheck[]; error: string; scope: string; }

// A test-only barrier deliberately leaves real RDB writes uncommitted. The host
// kills this process; a separate process checks the actual store's recovery.
// This does not inject a hook into production dispatch or change its behavior.
export async function runTransactionFailure(phase: string): Promise<void> {
  const context = await nativeContext();
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const repository = new Repository(context); await repository.initialize();
  const markerPath = `${context.filesDir}/transaction-ready.json`;
  const preparing = phase.startsWith('prepare-');
  const mode = phase.replace(/^(prepare|verify)-/, '');
  const report: TransactionReport = {status:'failed',mode:mode,checks:[],error:'',scope:'Real native RDB transaction interrupted after partial event/progress writes or partial deletion. A test-only SQL barrier uses the production tables; production dispatch is separately exercised before and after process death.'};
  try {
    if (!['event-only', 'progress-written', 'delete-partial'].includes(mode)) { throw new Error('Unknown transaction interruption phase.'); }
    if (preparing) {
      for (const old of (await repository.list()).filter((item: Material) => item.diagram.packageId === 'native-uncommitted-check')) { await repository.deleteMaterial(old); }
      const diagram = JSON.parse(decode(await context.resourceManager.getRawFileContent('samples/water-cycle/diagram.json'))) as Diagram;
      diagram.packageId = 'native-uncommitted-check'; diagram.title = 'Native uncommitted transaction fixture'; diagram.audio = [];
      const material = await repository.createSource(diagram,
        await context.resourceManager.getRawFileContent('samples/water-cycle/source.svg'),
        diagram.source.previewPath ? await context.resourceManager.getRawFileContent(`samples/water-cycle/${diagram.source.previewPath}`) : undefined);
      let progress = await repository.progress(material);
      progress = await repository.dispatch(material, {eventId:`${mode}-open`,expectedRevision:progress.stateRevision,type:'openQuestion',targetId:diagram.questions[0].id});
      progress = await repository.dispatch(material, {eventId:`${mode}-select`,expectedRevision:progress.stateRevision,type:'selectAnswer',answerIds:diagram.questions[0].acceptedAnswers});
      const pending: Action = {eventId:`${mode}-submit`,expectedRevision:progress.stateRevision,type:'submitAnswer'};
      const next = applyAction(diagram, progress, pending).state;
      repository.db!.beginTransaction();
      if (mode === 'delete-partial') {
        await repository.db!.executeSql('DELETE FROM events WHERE material=?', [material.key]);
        await repository.db!.executeSql('DELETE FROM progress WHERE id=?', [material.key]);
      } else {
        await repository.db!.executeSql('INSERT INTO events(id,material,body) VALUES(?,?,?)', [pending.eventId,material.key,JSON.stringify(pending)]);
        if (mode === 'progress-written') { await repository.db!.executeSql('INSERT OR REPLACE INTO progress(id,revision,body) VALUES(?,?,?)', [material.key,next.stateRevision,JSON.stringify(next)]); }
      }
      const marker: TransactionMarker = {status:'uncommitted-writes-complete',mode:mode,key:material.key,before:progress,pending:pending,error:''};
      writeBytes(markerPath, encode(JSON.stringify(marker)));
      console.info(`TOUCHMAP_TRANSACTION_WAITING ${mode}`);
      setInterval(() => {}, 60000);
      return;
    }
    const marker = JSON.parse(decode(readBytes(markerPath))) as TransactionMarker;
    if (marker.status !== 'uncommitted-writes-complete' || marker.mode !== mode) { throw new Error('Missing matching pre-commit barrier.'); }
    const material = (await repository.list()).find((item: Material) => item.key === marker.key);
    if (!material) { throw new Error('Material disappeared after uncommitted transaction.'); }
    const restored = await repository.progress(material);
    report.checks.push({name:'complete_checkpoint_restored',passed:JSON.stringify(restored) === JSON.stringify(marker.before)});
    report.checks.push({name:'unfinished_selection_not_submitted',passed:restored.submissions.length === 0 && restored.selectedAnswers.join(',') === marker.before.selectedAnswers.join(',')});
    const rows = await repository.db!.querySql('SELECT id FROM events WHERE id=?', [marker.pending.eventId]);
    report.checks.push({name:'uncommitted_event_absent',passed:!rows.goToFirstRow()}); rows.close();
    const submitted = await repository.dispatch(material, marker.pending);
    const duplicate = await repository.dispatch(material, marker.pending);
    report.checks.push({name:'explicit_retry_commits_once',passed:submitted.submissions.length === 1 && duplicate.submissions.length === 1 && submitted.stateRevision === duplicate.stateRevision});
    report.status = report.checks.every((check: TransactionCheck) => check.passed) ? 'passed' : 'failed';
    await repository.deleteMaterial(material);
  } catch (error) { report.error = `${(error as Error).message}\n${(error as Error).stack || ''}`; }
  writeBytes(`${context.filesDir}/transaction-report.json`, encode(JSON.stringify(report)));
  await delegator.finishTest(`Native transaction interruption ${report.status}`, report.status === 'passed' ? 0 : -1);
}
