import { tr } from '../domain/i18n';
import { common, Want } from '@kit.AbilityKit';

/** OpenHarmony's full-page system picker, with its normal temporary URI grants.
 * The Oniro 6.1 image does not compose the modal FilePicker UIExtension correctly.
 * MainAbility exposes the same OPEN_FILE/CREATE_FILE contract without an overlay.
 * Contract: openharmony/applications_filepicker, FilePickerUtil and AbilityCommonUtil.
 */
export class SystemPicker {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  private async request(want: Want): Promise<string> {
    const result = await this.context.startAbilityForResult(want);
    if (result.resultCode !== 0) { return ''; }
    const streams = result.want?.parameters?.['ability.params.stream'] as string[] | undefined;
    if (!streams || streams.length === 0) { return ''; }
    if (streams.length !== 1 || typeof streams[0] !== 'string' ||
      !streams[0].startsWith('file://') || streams[0].includes('\u0000')) {
      throw new Error(tr('tm_dee8317a6682'));
    }
    return streams[0];
  }

  async select(): Promise<string> {
    return this.request({
      bundleName: 'com.ohos.filepicker', abilityName: 'MainAbility',
      action: 'ohos.want.action.OPEN_FILE',
      parameters: { startMode: 'choose', pickerType: 'select', extType: 'filePicker',
        key_pick_num: 1, key_select_mode: 0 }
    });
  }

  async save(name: string): Promise<string> {
    if (!name || /[/\\\u0000]/.test(name) || name.length > 180) {
      throw new Error(tr('tm_4aace0fa58f1'));
    }
    return this.request({
      bundleName: 'com.ohos.filepicker', abilityName: 'MainAbility',
      action: 'ohos.want.action.CREATE_FILE',
      parameters: { startMode: 'save', pickerType: 'save', extType: 'filePicker',
        pickerMode: 0, autoCreateEmptyFile: true, key_pick_file_name: [name], saveFile: name }
    });
  }
}
