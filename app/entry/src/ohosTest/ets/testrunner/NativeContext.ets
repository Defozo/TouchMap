import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
let activeContext: common.UIAbilityContext | undefined = undefined;
export async function nativeContext(): Promise<common.UIAbilityContext> {
  if (activeContext) { return activeContext; }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
  await delegator.addAbilityMonitor(monitor);
  try {
    await delegator.startAbility({ bundleName: 'org.touchmap.app', moduleName: 'entry', abilityName: 'EntryAbility' });
    const ability = await delegator.waitAbilityMonitor(monitor, 15000);
    activeContext = ability.context; return activeContext;
  } finally { await delegator.removeAbilityMonitor(monitor); }
}
