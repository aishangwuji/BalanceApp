/*
 * Settings.ets —— 设置页
 *
 * 参考 DeepSeek 设置页形式：分组列表 + 行内左侧图标 + 右侧当前值/箭头。
 * 本次仅落地入口：语言、外观、字体大小、个性化（具体内容暂不实现），
 * 以及「资产监控」入口（跳转 pages/Assets.ets）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'Settings';

@Entry
@Component
struct Settings {
  private goBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'back failed: %{public}s', String(err));
    }
  }

  private openAssets(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/Assets' }).catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'push Assets failed: %{public}s', String(e));
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'push Assets error: %{public}s', String(err));
    }
  }

  private notImplemented(): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: '该功能暂未实现' });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'showToast failed: %{public}s', String(err));
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('‹')
          .fontSize(24)
          .fontColor('#333333')
          .width(44)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.goBack();
          })
        Text('设置')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('').width(44)
      }
      .width('100%')
      .height(48)

      Scroll() {
        Column() {
          // ── 应用 ──
          Text('应用')
            .fontSize(12)
            .fontColor('#999999')
            .width('92%')
            .margin({ top: 8, bottom: 6 })

          Column() {
            this.SettingRow('语', '#4D6BFE', '语言', '中文（简体中文）', false, () => {
              this.notImplemented();
            })
            this.SettingRow('观', '#F59E0B', '外观', '系统', false, () => {
              this.notImplemented();
            })
            this.SettingRow('A', '#10B981', '字体大小', '', false, () => {
              this.notImplemented();
            })
            this.SettingRow('个', '#8B5CF6', '个性化', '', true, () => {
              this.notImplemented();
            })
          }
          .width('92%')
          .backgroundColor('#FFFFFF')
          .borderRadius(14)

          // ── 数据 ──
          Text('数据')
            .fontSize(12)
            .fontColor('#999999')
            .width('92%')
            .margin({ top: 20, bottom: 6 })

          Column() {
            this.SettingRow('资', '#0EA5E9', '资产监控', '查看各服务商余额', true, () => {
              this.openAssets();
            })
          }
          .width('92%')
          .backgroundColor('#FFFFFF')
          .borderRadius(14)

          Text('版本 1.0.0')
            .fontSize(12)
            .fontColor('#BBBBBB')
            .margin({ top: 24 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
  }

  @Builder
  SettingRow(badge: string, color: string, title: string, value: string, isLast: boolean, onTap: () => void) {
    Row() {
      Text(badge)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width(28)
        .height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor(color)
        .borderRadius(8)
      Text(title)
        .fontSize(15)
        .fontColor('#222222')
        .margin({ left: 12 })
        .layoutWeight(1)
      if (value.length > 0) {
        Text(value)
          .fontSize(13)
          .fontColor('#999999')
          .margin({ right: 4 })
      }
      Text('›')
        .fontSize(20)
        .fontColor('#CCCCCC')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .border({ width: { bottom: isLast ? 0 : 1 }, color: '#F0F0F0' })
    .onClick(onTap)
  }
}
