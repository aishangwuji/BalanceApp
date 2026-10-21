/*
 * ThinkingButton.ets
 *
 * 深度思考开关组件 —— 采用全局温润中性色与墨金强调。
 * 1. 严格禁用所有 Emoji 表情符与额外修饰文本（无表情、无 ON 标签）；
 * 2. 纯粹「深度思考」胶囊切换：开启时淡蓝紫背景加细边框，关闭时素灰背景；
 * 3. 自动感应当前服务商与模型（DeepSeek、小米 MiMo、Kimi 等）支持性。
 *
 * 遵循 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

import { isThinkingSupported } from '../services/ProviderRegistry';

@Component
export struct ThinkingButton {
  @Prop isEnabled: boolean = false;
  @Prop providerId: string = 'deepseek';
  @Prop modelId: string = '';
  onToggle: (enabled: boolean) => void = () => {};

  private isVisible(): boolean {
    return isThinkingSupported(this.providerId, this.modelId);
  }

  build() {
    if (this.isVisible()) {
      Row() {
        Row() {
          Text('深度思考')
            .fontSize(13)
            .fontColor(this.isEnabled ? $r('app.color.accent') : $r('app.color.text_secondary'))
            .fontWeight(this.isEnabled ? FontWeight.Medium : FontWeight.Normal)
        }
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .backgroundColor(this.isEnabled ? $r('app.color.accent_soft') : $r('app.color.fill'))
        .borderRadius(16)
        .borderWidth(1)
        .borderColor(this.isEnabled ? $r('app.color.accent_outline') : '#00000000')
        .animation({ duration: 200, curve: Curve.FastOutSlowIn })
        .onClick(() => {
          const nextState: boolean = !this.isEnabled;
          this.onToggle(nextState);
        })
      }
      .width('96%')
      .justifyContent(FlexAlign.Start)
      .margin({ top: 8 })
    }
  }
}
