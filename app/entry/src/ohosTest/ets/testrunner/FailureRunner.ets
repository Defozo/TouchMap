import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { nativeContext } from './NativeContext';
import { Repository, Material, encode, writeBytes } from '../../../main/ets/platform/Repository';

interface FailureCheck { name: string; passed: boolean; detail: string; }
interface FailureReport { status: string; checks: FailureCheck[]; error: string; scope: string; }
class FailureRepository extends Repository {
  async saveAs(bytes: Uint8Array, _name: string): Promise<boolean> {
    writeBytes(`${this.context.cacheDir}/failure-valid.touchmap`, bytes); return true;
  }
}
function delay(milliseconds: number): Promise<void> { return new Promise<void>((resolve) => { setTimeout(resolve, milliseconds); }); }

export async function runFailureChecks(): Promise<void> {
  const context = await nativeContext(); const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const report: FailureReport = {status:'running',checks:[],error:'',scope:'Actual native Repository import against a deleted file URI and a host-mounted size-limited staging filesystem. The app performs ordinary sandbox I/O; the host mount only injects ENOSPC.'};
  const reportPath = `${context.filesDir}/failure-checks.json`;
  try {
    const repository = new FailureRepository(context); await repository.initialize();
    const materials = await repository.list();
    const material = materials.find((item: Material) => item.diagram.packageId === 'water-cycle' && item.ready && !item.draft)!;
    if (!material) { throw new Error('Water-cycle failure fixture missing.'); }
    const beforeKeys = materials.map((item: Material) => item.key).sort().join(',');
    const beforeProgress = JSON.stringify(await repository.progress(material));
    await repository.exportPackage(material);
    const stalePath = `${context.cacheDir}/failure-deleted.touchmap`;
    writeBytes(stalePath, encode('deleted file grant fixture'));
    const staleUri = fileUri.getUriFromPath(stalePath); fs.unlinkSync(stalePath);
    let staleRejected = false, staleMessage = '';
    try { await repository.importPackage(staleUri); } catch (error) { staleRejected = true; staleMessage = (error as Error).message; }
    report.checks.push({name:'deleted_file_uri_rejected',passed:staleRejected,detail:staleMessage});
    const staging = `${context.filesDir}/staging`;
    if (fs.listFileSync(staging).length !== 0) { throw new Error('Staging must be empty before the scoped fault injection.'); }
    const go = `${context.filesDir}/failure-injection-go`;
    if (fs.accessSync(go)) { fs.unlinkSync(go); }
    writeBytes(`${context.filesDir}/failure-injection-ready.json`, encode(JSON.stringify({status:'ready',staging:staging})));
    const deadline = Date.now() + 60000;
    while (!fs.accessSync(go)) { if (Date.now() > deadline) { throw new Error('Host did not acknowledge scoped ENOSPC injection.'); } await delay(100); }
    let fullRejected = false, fullMessage = '';
    try { await repository.importPackage(`${context.cacheDir}/failure-valid.touchmap`); }
    catch (error) { fullRejected = true; fullMessage = (error as Error).message; }
    report.checks.push({name:'full_staging_import_rejected',passed:fullRejected && /space|storage|write|28/i.test(fullMessage),detail:fullMessage});
    report.checks.push({name:'no_false_success_or_new_material',passed:(await repository.list()).map((item: Material) => item.key).sort().join(',') === beforeKeys,detail:'Material IDs compared before and after both rejected imports.'});
    report.checks.push({name:'existing_progress_unchanged',passed:JSON.stringify(await repository.progress(material)) === beforeProgress,detail:'Full saved checkpoint JSON compared byte for byte.'});
    report.checks.push({name:'failed_staging_removed',passed:fs.listFileSync(staging).length === 0,detail:'Native import finally cleanup left the injected staging filesystem empty.'});
    report.status = report.checks.every((check: FailureCheck) => check.passed) ? 'passed' : 'failed';
  } catch (error) { report.status = 'failed'; report.error = `${(error as Error).message}\n${(error as Error).stack || ''}`; }
  writeBytes(reportPath, encode(JSON.stringify(report)));
  console.info(`TOUCHMAP_FAILURE_CHECKS ${JSON.stringify(report)}`);
  await delegator.finishTest(`Native failure checks ${report.status}`, report.status === 'passed' ? 0 : -1);
}
