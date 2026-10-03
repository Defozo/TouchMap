import { abilityDelegatorRegistry } from '@kit.TestKit';
import { http } from '@kit.NetworkKit';
import { nativeContext } from './NativeContext';
import { DraftEditor } from '../../../main/ets/domain/editor';
import { Diagram } from '../../../main/ets/domain/types';
import { Preparation, DraftEnvelope } from '../../../main/ets/platform/Preparation';
import { Repository, Material, encode, writeBytes, readBytes, uid } from '../../../main/ets/platform/Repository';

interface FixtureStatus { received: number; completed: number; cancelled: number; }
interface PreparationOutcome { result?: DraftEnvelope; error: string; }
interface PreparationCheck { name: string; passed: boolean; detail: string; }
interface PreparationReport { status: string; checks: PreparationCheck[]; error: string; scope: string; }
const endpoint: string = 'http://127.0.0.1:8089';
function delay(ms: number): Promise<void> { return new Promise<void>((resolve) => { setTimeout(resolve, ms); }); }
async function complete(pending: Promise<void>): Promise<void> {
  await Promise.race([pending, delay(10000).then(() => { throw new Error('Native preparation did not settle after release or cancellation.'); })]);
}
async function fixture(path: string, post: boolean = false): Promise<FixtureStatus> {
  const connection = http.createHttp();
  try {
    const response = await connection.request(`${endpoint}/test/${path}`, { method: post ? http.RequestMethod.POST : http.RequestMethod.GET, connectTimeout: 5000, readTimeout: 5000, expectDataType: http.HttpDataType.STRING });
    if (response.responseCode !== 200 || typeof response.result !== 'string') { throw new Error('Controlled preparation fixture is unavailable.'); }
    return JSON.parse(response.result) as FixtureStatus;
  } finally { connection.destroy(); }
}
async function received(): Promise<void> {
  const deadline = Date.now() + 10000;
  while ((await fixture('status')).received === 0) { if (Date.now() > deadline) { throw new Error('No native request reached the controlled fixture.'); } await delay(40); }
}

export async function runPreparationChecks(): Promise<void> {
  const context = await nativeContext();
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const report: PreparationReport = { status: 'running', checks: [], error: '', scope: 'Actual native HTTP transport, native revision guard and durable repository readback against a deliberately delayed loopback response. No provider inference; separate from full Editor UI testing.' };
  let repository: Repository | undefined;
  let current: Material | undefined;
  try {
    repository = new Repository(context); await repository.initialize();
    const sample = (await repository.list()).find((item: Material) => item.diagram.packageId === 'water-cycle' && !item.draft)!;
    if (!sample) { throw new Error('The owned SVG preparation fixture is missing.'); }
    const original = JSON.parse(JSON.stringify(sample.diagram)) as Diagram;
    original.packageId = `preparation-check-${uid()}`; original.audio = []; original.questions = [];
    const source = readBytes(`${sample.directory}/${original.source.path}`);
    const preview = original.source.previewPath ? readBytes(`${sample.directory}/${original.source.previewPath}`) : undefined;
    current = await repository.createSource(original, source, preview);
    const editor = new DraftEditor(current.diagram);
    const preparation = new Preparation(); preparation.base = endpoint;
    await fixture('reset', true);
    const late: PreparationOutcome = { error: '' };
    const pending = preparation.draft(source, editor.diagram, true, true).then((value: DraftEnvelope) => { late.result = value; }).catch((error: Error) => { late.error = error.message; });
    await received();
    editor.setTitle('Native edit committed while preparation was pending');
    current = await repository.saveDraft(editor.diagram, current);
    const before = JSON.stringify(editor.diagram);
    const committedTitle = current.diagram.title;
    await fixture('release', true); await complete(pending);
    if (!late.result || late.error) { throw new Error(`Delayed native result failed: ${late.error}`); }
    const applied = editor.replaceFromJob(late.result.result.diagram, original.source.sha256, original.revision);
    const reloaded = (await repository.list()).find((item: Material) => item.key === current!.key)!;
    report.checks.push({ name: 'late_response_cannot_replace_new_revision', passed: !applied && JSON.stringify(editor.diagram) === before && reloaded.diagram.title === committedTitle, detail: `Original revision ${original.revision}; committed revision ${reloaded.diagram.revision}; late response adopted=${applied}.` });

    await fixture('reset', true);
    const cancelled: PreparationOutcome = { error: '' };
    const cancelPending = preparation.draft(source, editor.diagram, true, true).then((value: DraftEnvelope) => { cancelled.result = value; }).catch((error: Error) => { cancelled.error = error.message; });
    await received(); preparation.cancel();
    editor.setTitle('Later edit survives cancelled preparation');
    current = await repository.saveDraft(editor.diagram, current);
    const afterCancel = JSON.stringify(editor.diagram);
    await delay(150); await fixture('release', true); await complete(cancelPending);
    const cancelledReload = (await repository.list()).find((item: Material) => item.key === current!.key)!;
    const observed = await fixture('status');
    report.checks.push({ name: 'cancelled_native_request_does_not_deliver_adoptable_result', passed: !cancelled.result && cancelled.error.length > 0 && JSON.stringify(editor.diagram) === afterCancel && cancelledReload.diagram.title === editor.diagram.title, detail: `Native request rejected=${cancelled.error.length > 0}; fixture completed=${observed.completed}; remote cancellation observed=${observed.cancelled}.` });
    report.status = report.checks.every((item: PreparationCheck) => item.passed) ? 'passed' : 'failed';
  } catch (error) { report.status = 'failed'; report.error = (error as Error).message; }
  finally {
    if (repository && current) { try { await repository.deleteMaterial(current); } catch (_) {} }
    writeBytes(`${context.filesDir}/preparation-checks.json`, encode(JSON.stringify(report)));
    console.info(`TOUCHMAP_PREPARATION_CHECKS ${JSON.stringify(report)}`);
    delegator.finishTest(JSON.stringify(report), report.status === 'passed' ? 0 : 1);
  }
}
