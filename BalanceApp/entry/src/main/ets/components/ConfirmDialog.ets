/*
 * ConfirmDialog.ets —— 通用二次确认弹窗（可复用组件）
 *
 * Business Rule: 所有删除类不可逆操作统一经此组件二次确认。
 * 调用方用 `if` 控制是否挂载，本组件只负责内容与回调：
 *   ConfirmDialog({ show, title, message, confirmText, danger, onConfirm, onCancel })
 */

@Component
export struct ConfirmDialog {
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
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 20, bottom: 4 })
          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(14)
              .fontColor($r('app.color.text_muted'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ bottom: 16 })
          } else {
            Blank().height(12)
          }
          Row() {
            Button('取消')
              .layoutWeight(1)
              .backgroundColor($r('app.color.fill'))
              .fontColor($r('app.color.text_primary'))
              .margin({ right: 8 })
              .onClick(() => {
                this.onCancel();
              })
            Button(this.confirmText)
              .layoutWeight(1)
              .backgroundColor(this.danger ? '#EF4444' : '#4D6BFE')
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.onConfirm();
              })
          }
          .width('90%')
          .margin({ bottom: 20 })
        }
        .width('88%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(16)
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.4)')
    }
  }
}
