import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { feedback } from '../platform/Feedback';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('openedUri', want.uri || '');
    AppStorage.setOrCreate('appActive', true);
  }
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    if (want.uri) { AppStorage.setOrCreate('openedUri', want.uri); }
  }
  onWindowStageCreate(windowStage: window.WindowStage): void { windowStage.loadContent('pages/Index'); }
  onBackground(): void { feedback.release(); AppStorage.setOrCreate('appActive', false); }
  onForeground(): void { AppStorage.setOrCreate('appActive', true); }
  onDestroy(): void { feedback.release(); }
}
