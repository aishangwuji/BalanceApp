/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { I18nService } from '../services/I18nService';
import { initSkin } from '../services/SkinService';
import {
  SettingsService, KEY_APP_APPEARANCE, KEY_APP_DARK, KEY_APP_LOCK_ENABLED, KEY_APP_LOCKED
} from '../services/SettingsService';
import { AuthService } from '../services/AuthService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    I18nService.init(this.context);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // Business Rule: 仅当用户选择「跟随系统」时，系统深色变化才更新解析深色态。
    const mode: string | undefined = AppStorage.get<string>(KEY_APP_APPEARANCE);
    if (mode === undefined || mode === 'system') {
      const dark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate<boolean>(KEY_APP_DARK, dark);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // Business Rule: 必须等设置加载完成（决定冷启动是否处于锁定态）再渲染首页，避免短暂露出内容。
    await SettingsService.init(this.context);
    // 主题（皮肤）：在首帧之前把用户选的调色板装载好，避免先闪一帧默认色。
    await initSkin(this.context);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // Business Rule: 开启应用锁后，离开前台即进入锁定态；认证弹窗自身引起的切后台不重复锁定。
    const lockEnabled: boolean = AppStorage.get<boolean>(KEY_APP_LOCK_ENABLED) === true;
    if (lockEnabled && !AuthService.isInProgress()) {
      AppStorage.setOrCreate<boolean>(KEY_APP_LOCKED, true);
    }
  }
}