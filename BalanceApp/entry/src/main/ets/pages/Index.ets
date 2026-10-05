/*
 * Index.ets —— 应用入口壳
 *
 * 主界面为智能对话（ChatView）。历史抽屉底部的「设置」入口进入设置页，
 * 资产监控已迁至「设置 > 资产监控」（pages/Assets.ets）。
 */

import { KeyboardAvoidMode } from '@kit.ArkUI';
import { ChatView } from './ChatView';

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    // UX 修复：默认 KeyboardAvoidMode.OFFSET 会整页上移、顶栏被顶出屏幕；
    // 改为 RESIZE，窗口内容区压缩，顶部固定、聊天区收缩，输入框保持在键盘之上。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  build() {
    Column() {
      ChatView()
    }
    .width('100%')
    .height('100%')
  }
}
