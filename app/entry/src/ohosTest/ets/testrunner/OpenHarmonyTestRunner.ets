import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';
import { runRecovery } from './RecoveryRunner';
import { runAudioBenchmark } from './AudioBenchmark';

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void { console.info('TOUCHMAP_NATIVE_TEST_PREPARE'); }
  onRun(): void {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments();
    console.info(`TOUCHMAP_TEST_ARGUMENT_KEYS ${Object.keys(args.parameters).join(',')}`);
    const audioBench = args.parameters['audioBench'] || args.parameters['-s audioBench'];
    if (audioBench !== undefined && audioBench !== '') { runAudioBenchmark(Number(audioBench)); return; }
    const recoveryCycle = args.parameters['recoveryCycle'] || args.parameters['-s recoveryCycle'];
    if (recoveryCycle !== undefined && recoveryCycle !== '') { runRecovery(Number(recoveryCycle)); return; }
    Hypium.hypiumTest(delegator, args, testsuite);
  }
}
