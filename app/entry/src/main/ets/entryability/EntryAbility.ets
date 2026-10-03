import { UIAbility, Want, AbilityConstant, Configuration } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { feedback } from '../platform/Feedback';
import { openedFileUri } from '../platform/WantReceiver';
import { initializeI18n } from '../platform/I18n';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    initializeI18n(this.context.resourceManager);
    AppStorage.setOrCreate('openedUri', openedFileUri(want));
    AppStorage.setOrCreate('appActive', true);
  }
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const uri = openedFileUri(want); if (uri) { AppStorage.setOrCreate('openedUri', uri); }
  }
  onConfigurationUpdate(_configuration: Configuration): void { initializeI18n(this.context.resourceManager); }
  onWindowStageCreate(windowStage: window.WindowStage): void { windowStage.loadContent('pages/Index'); }
  onBackground(): void { feedback.release(); AppStorage.setOrCreate('appActive', false); }
  onForeground(): void { AppStorage.setOrCreate('appActive', true); }
  onDestroy(): void { feedback.release(); }
}
