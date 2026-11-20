/*
 * ConfirmDialog.ets —— 通用二次确认弹窗（可复用组件）
 *
 * Business Rule: 所有删除类不可逆操作统一经此组件二次确认。
 * 调用方用 `if` 控制是否挂载，本组件只负责内容与回调：
 *   ConfirmDialog({ show, title, message, confirmText, danger, onConfirm, onCancel })
 */

import { skinColor } from '../services/SkinService';

@Component
export struct ConfirmDialog {
  /** 皮肤版本号：皮肤或明暗切换时自增（SkinService），驱动本组件按新调色板重绘。 */
  @StorageProp('skin_version') skinVersion: number = 0;
  @Prop show: boolean = false;
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop confirmText: string = '删除';
  @Prop danger: boolean = true;
  // Reason: 函数类型不允许 @Prop，用普通成员经构造传参（回调创建后不变，无需同步）。
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  build() {
    if (this.show) {
      Column() {
        Blank()
        Column() {
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(skinColor('text_title'))
            .margin({ top: 24, bottom: 4 })
          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(14)
              .fontColor(skinColor('text_muted'))
              .lineHeight(21)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ bottom: 16 })
          } else {
            Blank().height(12)
          }
          Row() {
            Button('取消')
              .layoutWeight(1)
              .backgroundColor(skinColor('fill'))
              .fontColor(skinColor('text_primary'))
              .borderRadius(14)
              .margin({ right: 8 })
              .onClick(() => {
                this.onCancel();
              })
            Button(this.confirmText)
              .layoutWeight(1)
              .backgroundColor(this.danger ? '#A34F44' : skinColor('accent_solid'))
              .fontColor(skinColor('accent_contrast'))
              .borderRadius(14)
              .onClick(() => {
                this.onConfirm();
              })
          }
          .width('88%')
          .margin({ bottom: 24 })
        }
        .width('88%')
        .backgroundColor(skinColor('surface'))
        .borderRadius(24)
        .border({ width: 1, color: skinColor('border_soft') })
        .shadow({ radius: 28, color: 'rgba(20,18,14,0.18)', offsetX: 0, offsetY: 10 })
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(skinColor('overlay_scrim'))
    }
  }
}
