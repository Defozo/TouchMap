import { abilityDelegatorRegistry, Driver, ON, On, Component } from '@kit.TestKit';
import { nativeContext } from './NativeContext';
import { Repository, Material, encode, writeBytes } from '../../../main/ets/platform/Repository';
import { RestorationObservation } from '../../../main/ets/platform/RestorationFrame';
import { Progress } from '../../../main/ets/domain/types';
import { tr } from '../../../main/ets/domain/i18n';

interface RestoreReport { status: string; count: number; p95Ms: number; maxMs: number; samples: RestorationObservation[]; error: string; scope: string; }
function delay(milliseconds: number): Promise<void> { return new Promise<void>((resolve) => { setTimeout(resolve, milliseconds); }); }
async function visible(driver: Driver, selector: On): Promise<Component> {
  for (let index = 0; index < 24; index++) {
    const scroll = await driver.findComponent(ON.id('main-scroll'));
    const area = await scroll.getBounds(); const candidate = await driver.findComponent(selector);
    if (candidate) { const bounds = await candidate.getBounds(); if (bounds.bottom - bounds.top >= 24 && bounds.top >= area.top && bounds.bottom <= area.bottom) { return candidate; } }
    await driver.swipe(area.right - 10, area.bottom - 35, area.right - 10, area.top + 35, 1600);
  }
  throw new Error('Restore benchmark control was not reachable.');
}

export async function runRestoreBenchmark(count: number): Promise<void> {
  const context = await nativeContext(); const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const report: RestoreReport = {status:'running',count:count,p95Ms:0,maxMs:0,samples:[],error:'',scope:'Actual active-app Library open intent through committed checkpoint load, Resume state assignment and end of next ArkUI frame. Each rendered full Progress snapshot must equal the saved checkpoint, and the Resume heading is checked through native UI automation. Excludes human selection time and cold process launch.'};
  try {
    if (!Number.isInteger(count) || count < 1 || count > 1000) { throw new Error('Invalid restoration sample count.'); }
    const repository = new Repository(context); await repository.initialize();
    let selected: Material | undefined = undefined; let expected: Progress | undefined = undefined;
    for (const material of await repository.list()) {
      if (!material.accepted || material.draft || !material.ready) { continue; }
      const progress = await repository.progress(material);
      if (progress.stateRevision > 0 && progress.submissions.length > 0 && progress.lastRegionId) { selected = material; expected = progress; break; }
    }
    if (!selected || !expected) { throw new Error('An accepted ready material with saved object and submission context is required.'); }
    const driver = Driver.create();
    for (let index = 0; index < 100; index++) { if (await driver.findComponent(ON.id('nav-library'))) { break; } await delay(50); }
    AppStorage.setOrCreate('measureRestoration', true);
    for (let index = 0; index < count; index++) {
      await (await driver.findComponent(ON.id('nav-library'))).click();
      const search = await visible(driver, ON.id('library-search')); await search.inputText(selected.diagram.title);
      const open = await visible(driver, ON.id(`open-material-${selected.key}`));
      AppStorage.setOrCreate('restorationObservation', '');
      await open.click();
      let raw = ''; const deadline = Date.now() + 5000;
      while (!raw) { raw = AppStorage.get<string>('restorationObservation') || ''; if (Date.now() > deadline) { throw new Error('Restore frame observation timed out.'); } if (!raw) { await delay(10); } }
      const observation = JSON.parse(raw) as RestorationObservation;
      if (observation.page !== 'Resume' || observation.packageId !== selected.diagram.packageId || JSON.stringify(observation.progress) !== JSON.stringify(expected)) { throw new Error('Rendered restoration state differs from the committed full checkpoint.'); }
      if (!(await driver.findComponent(ON.text(tr('tm_50e3bb39718a'))))) { throw new Error('Resume heading did not render.'); }
      report.samples.push(observation);
      writeBytes(`${context.filesDir}/restore-benchmark-progress.json`, encode(JSON.stringify({completed:index+1,total:count,durationMs:observation.durationMs})));
    }
    const sorted = report.samples.map((item: RestorationObservation) => item.durationMs).sort((a: number, b: number) => a-b);
    report.p95Ms = sorted[Math.ceil(count * .95) - 1]; report.maxMs = sorted[sorted.length - 1];
    report.status = report.p95Ms < 1000 ? 'passed' : 'failed';
  } catch (error) { report.status = 'failed'; report.error = `${(error as Error).message}\n${(error as Error).stack || ''}`; }
  finally { AppStorage.setOrCreate('measureRestoration', false); }
  writeBytes(`${context.filesDir}/restore-benchmark.json`, encode(JSON.stringify(report)));
  await delegator.finishTest(`Native restore benchmark ${report.status}`, report.status === 'passed' ? 0 : -1);
}
