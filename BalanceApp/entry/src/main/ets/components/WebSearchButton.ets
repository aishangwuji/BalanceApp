/*
 * WebSearchButton.ets
 *
 * 联网搜索开关组件 —— 与 ThinkingButton 同一视觉语言（温润中性色 + 墨金强调）：
 * 1. 纯文本胶囊，无 Emoji、无 ON 标记；
 * 2. 只在支持服务端联网工具的服务商下显示（当前仅 DeepSeek，见 WebSearchService.isSupported）；
 * 3. 开关只控制「是否在请求里声明 deepseek_web_search」，是否真的搜索由模型判断。
 *
 * 遵循 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

import { WebSearchService } from '../services/WebSearchService';

@Component
export struct WebSearchButton {
  @Prop isEnabled: boolean = false;
  @Prop providerId: string = 'deepseek';
  onToggle: (enabled: boolean) => void = () => {};

  build() {
    if (WebSearchService.isSupported(this.providerId)) {
      Row() {
        Text('联网搜索')
          .fontSize(13)
          .fontColor(this.isEnabled ? $r('app.color.accent') : $r('app.color.text_secondary'))
          .fontWeight(this.isEnabled ? FontWeight.Medium : FontWeight.Normal)
      }
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.isEnabled ? $r('app.color.accent_soft') : $r('app.color.fill'))
      .borderRadius(16)
      .borderWidth(1)
      .borderColor(this.isEnabled ? $r('app.color.accent_outline') : '#00000000')
      .margin({ top: 8, left: 8 })
      .animation({ duration: 200, curve: Curve.FastOutSlowIn })
      .onClick(() => {
        const nextState: boolean = !this.isEnabled;
        this.onToggle(nextState);
      })
    }
  }
}
