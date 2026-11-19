/*
 * WebSearchButton.ets
 *
 * 联网搜索开关组件 —— 与 ThinkingButton 同一视觉语言（官方输入框内的淡蓝能力胶囊）：
 * 1. 纯文本 + 图标胶囊，无 Emoji、无 ON 标记；
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
        Image($r('app.media.ic_globe'))
          .width(13)
          .height(13)
          .margin({ right: 5 })
        Text('智能搜索')
          .fontSize(13)
          .fontColor(this.isEnabled ? $r('app.color.pill_search_text') : $r('app.color.text_secondary'))
          .fontWeight(this.isEnabled ? FontWeight.Medium : FontWeight.Normal)
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.isEnabled ? $r('app.color.pill_search_bg') : $r('app.color.fill'))
      .borderRadius(16)
      .borderWidth(1)
      .borderColor(this.isEnabled ? $r('app.color.pill_search_border') : '#00000000')
      .animation({ duration: 200, curve: Curve.FastOutSlowIn })
      .onClick(() => {
        const nextState: boolean = !this.isEnabled;
        this.onToggle(nextState);
      })
    }
  }
}
