/*
 * Index.ets —— 应用入口壳
 *
 * 主界面为智能对话（ChatView）。历史抽屉底部的「设置」入口进入设置页，
 * 资产监控已迁至「设置 > 资产监控」（pages/Assets.ets）。
 */

import { ChatView } from './ChatView';

@Entry
@Component
struct Index {
  build() {
    Column() {
      ChatView()
    }
    .width('100%')
    .height('100%')
  }
}
