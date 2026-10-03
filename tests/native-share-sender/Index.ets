import { common, Want, wantConstant } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';

@Entry
@Component
struct Index {
  @State status: string = 'This separate normal-permission app sends its own private package with a temporary read grant.';
  @State busy: boolean = false;

  private async send(stream: boolean): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const bytes = await context.resourceManager.getRawFileContent('payload.touchmap');
      const path = `${context.filesDir}/shared.touchmap`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        let offset = 0;
        while (offset < bytes.length) {
          const part = bytes.slice(offset);
          const written = fs.writeSync(file.fd, part.buffer);
          if (written <= 0) { throw new Error('Package write did not complete.'); }
          offset += written;
        }
        fs.fsyncSync(file.fd);
      } finally { fs.closeSync(file); }
      const uri = fileUri.getUriFromPath(path);
      let want: Want = {
        bundleName: 'org.touchmap.app', abilityName: 'EntryAbility',
        action: stream ? 'ohos.want.action.sendData' : 'ohos.want.action.viewData',
        type: 'application/vnd.touchmap+zip',
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      if (stream) { want.parameters = { 'ability.params.stream': [uri] }; }
      else { want.uri = uri; }
      console.info(`TOUCHMAP_SHARE_TEST action=${want.action} uri=${uri} readGrant=true`);
      await context.startAbility(want);
      this.status = `${stream ? 'sendData stream' : 'viewData URI'} sent with normal read-URI grant.`;
    } catch (error) {
      this.status = `Share failed: ${(error as Error).message}`;
      console.error(`TOUCHMAP_SHARE_TEST_FAILURE ${this.status}`);
    } finally { this.busy = false; }
  }

  build() {
    Column({ space: 22 }) {
      Text('TouchMap share test').fontSize(30).fontWeight(FontWeight.Bold)
      Text(this.status).fontSize(20).width('100%')
      Button('Open package with viewData').id('share-open-uri').width('100%').height(64).enabled(!this.busy).onClick(() => { this.send(false); })
      Button('Share package with stream').id('share-send-stream').width('100%').height(64).enabled(!this.busy).onClick(() => { this.send(true); })
    }.padding(28).width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}
