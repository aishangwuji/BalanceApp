/*
 * AppLockGate.ets
 *
 * 应用锁覆盖层：应用锁开启后，从后台回到前台（或冷启动）时全屏遮挡内容，
 * 必须通过锁屏密码 / 指纹 / 人脸识别后才恢复访问。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { AuthService } from '../services/AuthService';
import { KEY_APP_LOCKED } from '../services/SettingsService';
import { skinColor } from '../services/SkinService';

const DOMAIN = 0x0000;
const TAG = 'AppLockGate';

@Component
export struct AppLockGate {
  /** 皮肤版本号：皮肤或明暗切换时自增（SkinService），驱动本组件按新调色板重绘。 */
  @StorageProp('skin_version') skinVersion: number = 0;
  @StorageProp(KEY_APP_LOCKED) @Watch('onLockedChanged') locked: boolean = false;
  @State authenticating: boolean = false;
  private autoStarted: boolean = false;
  private pendingTimer: number = -1;
  private authSession: number = 0;

  aboutToAppear(): void {
    if (this.locked) {
      this.scheduleUnlock();
    }
  }

  aboutToDisappear(): void {
    this.authSession += 1;
    if (this.pendingTimer >= 0) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
    }
  }

  onLockedChanged(): void {
    if (this.locked) {
      this.scheduleUnlock();
    } else {
      this.authSession += 1;
      this.authenticating = false;
    }
  }

  /** 等首帧渲染后再拉起系统认证，避免页面尚未挂载时弹窗被系统回收。 */
  private scheduleUnlock(): void {
    if (this.autoStarted) {
      return;
    }
    this.autoStarted = true;
    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = -1;
      this.autoStarted = false;
      this.requestUnlock();
    }, 300);
  }

  private async requestUnlock(): Promise<void> {
    if (!this.locked || this.authenticating) {
      return;
    }
    const session: number = ++this.authSession;
    this.authenticating = true;
    const ok: boolean = await AuthService.authenticate('解锁 openchat');
    if (session !== this.authSession) {
      return;
    }
    this.authenticating = false;
    if (ok) {
      AppStorage.setOrCreate<boolean>(KEY_APP_LOCKED, false);
    } else if (this.locked) {
      this.toast('身份验证未通过，请重试');
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'showToast failed: %{public}s', String(err));
    }
  }

  build() {
    if (this.locked) {
      Column() {
        Blank()
        Column() {
          Row() {
            Image($r('app.media.ic_lock'))
              .width(30)
              .height(30)
          }
          .width(72)
          .height(72)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(skinColor('icon_tile'))
          .borderRadius(36)
          .border({ width: 1, color: skinColor('accent_outline') })

          Text('应用已锁定')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(skinColor('text_title'))
            .margin({ top: 20 })

          Text('验证锁屏密码、指纹或人脸识别后继续')
            .fontSize(13)
            .fontColor(skinColor('text_muted'))
            .lineHeight(20)
            .margin({ top: 8 })

          Button(this.authenticating ? '正在验证…' : '解锁')
            .width('72%')
            .height(44)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(skinColor('accent_solid'))
            .fontColor(skinColor('accent_contrast'))
            .borderRadius(16)
            .enabled(!this.authenticating)
            .margin({ top: 28 })
            .onClick(() => {
              this.requestUnlock();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(skinColor('page_bg'))
    }
  }
}

