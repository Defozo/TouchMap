import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';
import { runRecovery } from './RecoveryRunner';
import { runAudioBenchmark } from './AudioBenchmark';
import { runAudioControls } from './AudioControls';
import { runFailureChecks } from './FailureRunner';
import { runRestoreBenchmark } from './RestoreBenchmark';
import { runPreparationChecks } from './PreparationRunner';
import { runTransactionFailure } from './TransactionFailureRunner';

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void { console.info('TOUCHMAP_NATIVE_TEST_PREPARE'); }
  onRun(): void {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments();
    console.info(`TOUCHMAP_TEST_ARGUMENT_KEYS ${Object.keys(args.parameters).join(',')}`);
    const transaction = args.parameters['transactionFailure'] || args.parameters['-s transactionFailure'];
    if (transaction !== undefined && transaction !== '') { runTransactionFailure(`${transaction}`); return; }
    const restoration = args.parameters['restoreBenchmark'] || args.parameters['-s restoreBenchmark'];
    if (restoration !== undefined && restoration !== '') { runRestoreBenchmark(Number(restoration)); return; }
    const preparation = args.parameters['preparationChecks'] || args.parameters['-s preparationChecks'];
    if (preparation !== undefined && preparation !== '') { runPreparationChecks(); return; }
    const failureChecks = args.parameters['failureChecks'] || args.parameters['-s failureChecks'];
    if (failureChecks !== undefined && failureChecks !== '') { runFailureChecks(); return; }
    const audioControls = args.parameters['audioControls'] || args.parameters['-s audioControls'];
    if (audioControls !== undefined && audioControls !== '') { runAudioControls(`${audioControls}`); return; }
    const audioBench = args.parameters['audioBench'] || args.parameters['-s audioBench'];
    if (audioBench !== undefined && audioBench !== '') { runAudioBenchmark(Number(audioBench)); return; }
    const recoveryCycle = args.parameters['recoveryCycle'] || args.parameters['-s recoveryCycle'];
    if (recoveryCycle !== undefined && recoveryCycle !== '') { runRecovery(Number(recoveryCycle)); return; }
    Hypium.hypiumTest(delegator, args, testsuite);
  }
}
