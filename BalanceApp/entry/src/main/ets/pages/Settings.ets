/*
 * Settings.ets —— 设置页
 *
 * 参考 DeepSeek 设置页形式：分组列表 + 行内左侧图标 + 右侧当前值/箭头。
 * 支持：
 * 1. 语言：中文（简体）/ English 动态切换与持久化；
 * 2. 外观：系统 / 浅色 / 深色 动态切换与持久化；
 * 3. 字体大小：7 档文字大小调节，第 3 档为标准大小，配实时预览；
 * 4. 个性化：思考内容自动折叠 Switch（提示：开启后，思考结束后将自动折叠思考内容）。
 *
 * 遵循 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { I18nService, AppLanguage, SUPPORTED_LANGUAGES, LanguageItem } from '../services/I18nService';
import {
  SettingsService, AppearanceMode, KEY_APP_APPEARANCE, KEY_FONT_SIZE_LEVEL, KEY_AUTO_COLLAPSE_THINKING,
  KEY_APP_LOCK_ENABLED, KEY_TOPIC_GATE_ENABLED, KEY_TOPIC_GATE_THRESHOLD, DEFAULT_TOPIC_GATE_THRESHOLD,
  SYSTEM_ONE_CHANNEL_TYPESAFE, SYSTEM_ONE_CHANNEL_OPENROUTER
} from '../services/SettingsService';
import { findSystemOneChannel, SystemOneChannel } from '../services/JevService';
import { PROVIDERS, ProviderDefinition } from '../services/ProviderRegistry';

const DOMAIN = 0x0000;
const TAG = 'Settings';

interface AppearanceOption {
  key: AppearanceMode;
  nameKey: string;
}

const APPEARANCE_OPTIONS: AppearanceOption[] = [
  { key: 'system', nameKey: 'settings_appearance_system' },
  { key: 'light', nameKey: 'settings_appearance_light' },
  { key: 'dark', nameKey: 'settings_appearance_dark' }
];

@Entry
@Component
struct Settings {
  @StorageProp('app_language') currentLang: string = 'zh-CN';
  @StorageProp(KEY_APP_APPEARANCE) currentAppearance: string = 'system';
  @StorageProp(KEY_FONT_SIZE_LEVEL) currentFontLevel: number = 3;
  @StorageProp(KEY_AUTO_COLLAPSE_THINKING) autoCollapseThinking: boolean = true;
  @StorageProp(KEY_APP_LOCK_ENABLED) appLockEnabled: boolean = false;
  @StorageProp(KEY_TOPIC_GATE_ENABLED) topicGateEnabled: boolean = false;
  @StorageProp(KEY_TOPIC_GATE_THRESHOLD) topicGateThreshold: number = DEFAULT_TOPIC_GATE_THRESHOLD;

  // 底部弹框控制
  @State showLanguageSheet: boolean = false;
  @State showAppearanceSheet: boolean = false;
  @State showFontSizeSheet: boolean = false;
  @State showPersonalizeSheet: boolean = false;
  @State showAppLockSheet: boolean = false;
  @State showTopicGateSheet: boolean = false;

  // 上下文净化：两个 tab 分别配置 System One（判定）与 System Two（生成）渠道。
  @State topicTab: number = 0;
  @State systemOneChannel: string = SYSTEM_ONE_CHANNEL_TYPESAFE;
  @State systemOneKeyInput: string = '';
  @State systemOneHasKey: boolean = false;
  @State systemTwoProviderId: string = 'deepseek';
  @State systemTwoKeyInput: string = '';
  @State systemTwoHasKey: boolean = false;
  @State topicGateError: string = '';
  @State tempTopicThreshold: number = DEFAULT_TOPIC_GATE_THRESHOLD;

  // 字体大小滑块临时滑动值 (1 ~ 7)
  @State tempFontLevel: number = 3;

  aboutToAppear(): void {
    const uiCtx = this.getUIContext();
    const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
    I18nService.init(hostCtx);
    SettingsService.init(hostCtx);
    this.tempFontLevel = this.currentFontLevel;
    this.tempTopicThreshold = this.topicGateThreshold;
    this.loadTopicGateState();
  }

  private async loadTopicGateState(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.systemOneChannel = await SettingsService.getTopicGateChannel(hostCtx);
      const oneKey: string = await SettingsService.getSystemOneKey(hostCtx, this.systemOneChannel);
      this.systemOneHasKey = oneKey.length > 0;
      const twoKey: string = await SettingsService.getProviderKey(hostCtx, this.systemTwoProviderId);
      this.systemTwoHasKey = twoKey.length > 0;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadTopicGateState failed: %{public}s', String(err));
    }
  }

  private async selectSystemOneChannel(channel: string): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await SettingsService.setTopicGateChannel(hostCtx, channel);
      this.systemOneChannel = channel;
      this.systemOneKeyInput = '';
      this.topicGateError = '';
      const key: string = await SettingsService.getSystemOneKey(hostCtx, channel);
      this.systemOneHasKey = key.length > 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'selectSystemOneChannel failed: %{public}s', String(err));
    }
  }

  private async selectSystemTwoProvider(providerId: string): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.systemTwoProviderId = providerId;
      this.systemTwoKeyInput = '';
      this.topicGateError = '';
      const key: string = await SettingsService.getProviderKey(hostCtx, providerId);
      this.systemTwoHasKey = key.length > 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'selectSystemTwoProvider failed: %{public}s', String(err));
    }
  }

  private t(key: string): string {
    const lang: AppLanguage = this.currentLang === 'en-US' ? 'en-US' : 'zh-CN';
    return I18nService.t(key, lang);
  }

  private currentLanguageDisplay(): string {
    let i: number = 0;
    while (i < SUPPORTED_LANGUAGES.length) {
      if (SUPPORTED_LANGUAGES[i].code === this.currentLang) {
        return SUPPORTED_LANGUAGES[i].nativeName;
      }
      i += 1;
    }
    return '中文（简体中文）';
  }

  private currentAppearanceDisplay(): string {
    if (this.currentAppearance === 'light') {
      return this.t('settings_appearance_light');
    }
    if (this.currentAppearance === 'dark') {
      return this.t('settings_appearance_dark');
    }
    return this.t('settings_appearance_system');
  }

  private currentFontSizeDisplay(): string {
    if (this.currentFontLevel === 3) {
      return this.t('settings_font_size_standard');
    }
    return `${this.currentFontLevel} / 7`;
  }

  private async selectLanguage(code: AppLanguage): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
      await I18nService.setLanguage(hostCtx, code);
      this.showLanguageSheet = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'selectLanguage failed: %{public}s', String(err));
    }
  }

  private async selectAppearance(mode: AppearanceMode): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
      await SettingsService.setAppearance(hostCtx, mode);
      this.showAppearanceSheet = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'selectAppearance failed: %{public}s', String(err));
    }
  }

  private async applyFontLevel(level: number): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
      await SettingsService.setFontSizeLevel(hostCtx, level);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'applyFontLevel failed: %{public}s', String(err));
    }
  }

  private async toggleAutoCollapse(enabled: boolean): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
      await SettingsService.setAutoCollapseThinking(hostCtx, enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'toggleAutoCollapse failed: %{public}s', String(err));
    }
  }

  private async toggleAppLock(enabled: boolean): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
      await SettingsService.setAppLockEnabled(hostCtx, enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'toggleAppLock failed: %{public}s', String(err));
    }
  }

  private currentAppLockDisplay(): string {
    return this.appLockEnabled ? this.t('settings_app_lock_on') : this.t('settings_app_lock_off');
  }

  private topicGateDisplay(): string {
    return this.topicGateEnabled ? this.t('settings_topic_gate_on') : this.t('settings_topic_gate_off');
  }

  /** 当前 System One 渠道实际下发的模型 id（端点与模型由官方文档固定）。 */
  private systemOneModelLabel(): string {
    const channel: SystemOneChannel | undefined = findSystemOneChannel(this.systemOneChannel);
    return channel === undefined ? '' : channel.model;
  }

  private async toggleTopicGate(enabled: boolean): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await SettingsService.setTopicGateEnabled(hostCtx, enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'toggleTopicGate failed: %{public}s', String(err));
    }
  }

  private async applyTopicGateThreshold(value: number): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await SettingsService.setTopicGateThreshold(hostCtx, value);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'applyTopicGateThreshold failed: %{public}s', String(err));
    }
  }

  /** System One：留空表示保持不变（清除走单独的「清除 Key」入口）。 */
  private async saveSystemOneKey(): Promise<void> {
    const text: string = this.systemOneKeyInput.trim();
    if (text.length === 0 && !this.systemOneHasKey) {
      this.topicGateError = this.t('settings_topic_gate_need_key');
      return;
    }
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (text.length > 0) {
        await SettingsService.setSystemOneKey(hostCtx, this.systemOneChannel, text);
        this.systemOneHasKey = true;
      }
      this.systemOneKeyInput = '';
      this.topicGateError = '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveSystemOneKey failed: %{public}s', String(err));
    }
  }

  private async clearSystemOneKey(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await SettingsService.setSystemOneKey(hostCtx, this.systemOneChannel, '');
      // 当前渠道没有 Key 时判定必然失败，顺带关闭开关，避免留下永远空转的启用态。
      await SettingsService.setTopicGateEnabled(hostCtx, false);
      this.systemOneHasKey = false;
      this.systemOneKeyInput = '';
      this.topicGateError = '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'clearSystemOneKey failed: %{public}s', String(err));
    }
  }

  /** System Two：写入与资产监控共用的 `key_<providerId>`。 */
  private async saveSystemTwoKey(): Promise<void> {
    const text: string = this.systemTwoKeyInput.trim();
    if (text.length === 0) {
      this.topicGateError = this.t('settings_topic_gate_need_key');
      return;
    }
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await SettingsService.setProviderKey(hostCtx, this.systemTwoProviderId, text);
      this.systemTwoHasKey = true;
      this.systemTwoKeyInput = '';
      this.topicGateError = '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveSystemTwoKey failed: %{public}s', String(err));
    }
  }

  private async clearSystemTwoKey(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await SettingsService.setProviderKey(hostCtx, this.systemTwoProviderId, '');
      this.systemTwoHasKey = false;
      this.systemTwoKeyInput = '';
      this.topicGateError = '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'clearSystemTwoKey failed: %{public}s', String(err));
    }
  }

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

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 顶部导航栏
        Row() {
          Text('‹')
            .fontSize(24)
            .fontColor($r('app.color.text_primary'))
            .width(44)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.goBack();
            })
          Text(this.t('settings_title'))
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
            Text(this.t('settings_section_app'))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 8, bottom: 6 })

            Column() {
              this.SettingRow($r('app.media.ic_language'), '#4D6BFE', this.t('settings_language'), this.currentLanguageDisplay(), false, () => {
                this.showLanguageSheet = true;
              })
              this.SettingRow($r('app.media.ic_appearance'), '#F59E0B', this.t('settings_appearance'), this.currentAppearanceDisplay(), false, () => {
                this.showAppearanceSheet = true;
              })
              this.SettingRow($r('app.media.ic_font'), '#10B981', this.t('settings_font_size'), this.currentFontSizeDisplay(), false, () => {
                this.tempFontLevel = this.currentFontLevel;
                this.showFontSizeSheet = true;
              })
              this.SettingRow($r('app.media.ic_personalize'), '#8B5CF6', this.t('settings_personalize'), '', true, () => {
                this.showPersonalizeSheet = true;
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(14)

            // ── 对话 ──
            Text(this.t('settings_section_chat'))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 20, bottom: 6 })

            Column() {
              this.SettingRow($r('app.media.ic_character'), '#6366F1', this.t('settings_topic_gate'), this.topicGateDisplay(), true, () => {
                this.showTopicGateSheet = true;
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(14)

            // ── 安全 ──
            Text(this.t('settings_section_security'))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 20, bottom: 6 })

            Column() {
              this.SettingRow($r('app.media.ic_lock'), '#EF4444', this.t('settings_app_lock'), this.currentAppLockDisplay(), true, () => {
                this.showAppLockSheet = true;
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(14)

            // ── 数据 ──
            Text(this.t('settings_section_data'))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 20, bottom: 6 })

            Column() {
              this.SettingRow($r('app.media.ic_assets'), '#0EA5E9', this.t('settings_assets'), this.t('settings_assets_desc'), true, () => {
                this.openAssets();
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(14)

            Text(this.t('settings_version'))
              .fontSize(12)
              .fontColor($r('app.color.text_faint'))
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
      .backgroundColor($r('app.color.page_bg'))

      // 底部弹框：多语言切换面板
      if (this.showLanguageSheet) {
        this.LanguageSheet()
      }

      // 底部弹框：外观切换面板
      if (this.showAppearanceSheet) {
        this.AppearanceSheet()
      }

      // 底部弹框：字体大小调节面板
      if (this.showFontSizeSheet) {
        this.FontSizeSheet()
      }

      // 底部弹框：个性化面板
      if (this.showPersonalizeSheet) {
        this.PersonalizeSheet()
      }

      // 底部弹框：应用锁面板
      if (this.showAppLockSheet) {
        this.AppLockSheet()
      }

      // 底部弹框：上下文净化面板
      if (this.showTopicGateSheet) {
        this.TopicGateSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  // ── 1. 语言切换 Sheet ──
  @Builder
  LanguageSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill('#66000000')
        .onClick(() => {
          this.showLanguageSheet = false;
        })

      Column() {
        Row() {
          Text(this.t('settings_select_language'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_muted'))
            .padding(6)
            .onClick(() => {
              this.showLanguageSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        ForEach(SUPPORTED_LANGUAGES, (item: LanguageItem) => {
          Row() {
            Column() {
              Text(item.nativeName)
                .fontSize(15)
                .fontWeight(this.currentLang === item.code ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.currentLang === item.code ? '#4D6BFE' : $r('app.color.text_primary'))
              if (item.code !== 'en-US') {
                Text(item.name)
                  .fontSize(12)
                  .fontColor($r('app.color.text_muted'))
                  .margin({ top: 2 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.currentLang === item.code) {
              Text('✓')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#4D6BFE')
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .border({ width: { bottom: 1 }, color: $r('app.color.fill') })
          .onClick(() => {
            this.selectLanguage(item.code);
          })
        }, (item: LanguageItem) => item.code)

        Blank().height(24)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── 2. 外观切换 Sheet ──
  @Builder
  AppearanceSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill('#66000000')
        .onClick(() => {
          this.showAppearanceSheet = false;
        })

      Column() {
        Row() {
          Text(this.t('settings_appearance_select'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_muted'))
            .padding(6)
            .onClick(() => {
              this.showAppearanceSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        ForEach(APPEARANCE_OPTIONS, (opt: AppearanceOption) => {
          Row() {
            Text(this.t(opt.nameKey))
              .fontSize(15)
              .fontWeight(this.currentAppearance === opt.key ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.currentAppearance === opt.key ? '#4D6BFE' : $r('app.color.text_primary'))
              .layoutWeight(1)

            if (this.currentAppearance === opt.key) {
              Text('✓')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#4D6BFE')
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .border({ width: { bottom: 1 }, color: $r('app.color.fill') })
          .onClick(() => {
            this.selectAppearance(opt.key);
          })
        }, (opt: AppearanceOption) => opt.key)

        Blank().height(24)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── 3. 字体大小调节 Sheet ──
  @Builder
  FontSizeSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill('#66000000')
        .onClick(() => {
          this.showFontSizeSheet = false;
        })

      Column() {
        // 顶部标题
        Row() {
          Text(this.t('settings_font_size_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_muted'))
            .padding(6)
            .onClick(() => {
              this.showFontSizeSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        // 预览卡片
        Column() {
          Text(this.t('settings_font_size_preview_title'))
            .fontSize(12)
            .fontColor($r('app.color.text_muted'))
            .margin({ bottom: 8 })

          Text(this.t('settings_font_size_preview_sample'))
            .fontSize(15 * SettingsService.getScaleByLevel(this.tempFontLevel))
            .fontColor($r('app.color.text_primary'))
            .lineHeight(22 * SettingsService.getScaleByLevel(this.tempFontLevel))
        }
        .width('90%')
        .padding(16)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .borderWidth(1)
        .borderColor($r('app.color.border_card'))
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 10, bottom: 20 })

        // 七档滑块说明与标尺
        Row() {
          Text('A')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(this.tempFontLevel === 3 ? this.t('settings_font_size_standard') : `${this.tempFontLevel} / 7`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4D6BFE')
          Blank()
          Text('A')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('88%')
        .margin({ bottom: 8 })

        // 7 档离散 Slider
        Slider({
          value: this.tempFontLevel,
          min: 1,
          max: 7,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor('#4D6BFE')
          .trackColor('#E2E8F0')
          .selectedColor('#4D6BFE')
          .showSteps(true)
          .width('90%')
          .onChange((value: number, mode: SliderChangeMode) => {
            const rounded: number = Math.round(value);
            this.tempFontLevel = rounded;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.applyFontLevel(rounded);
            }
          })

        Blank().height(30)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── 4. 个性化 Sheet ──
  @Builder
  PersonalizeSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill('#66000000')
        .onClick(() => {
          this.showPersonalizeSheet = false;
        })

      Column() {
        Row() {
          Text(this.t('settings_personalize'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_muted'))
            .padding(6)
            .onClick(() => {
              this.showPersonalizeSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        // 思考内容自动折叠卡片
        Column() {
          Row() {
            Column() {
              Text(this.t('settings_auto_collapse_thinking'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .fontWeight(FontWeight.Medium)
              Text(this.t('settings_auto_collapse_thinking_desc'))
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.autoCollapseThinking })
              .selectedColor('#4D6BFE')
              .switchPointColor('#FFFFFF')
              .onChange((isOn: boolean) => {
                this.toggleAutoCollapse(isOn);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('92%')
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .borderWidth(1)
        .borderColor($r('app.color.border_card'))
        .margin({ top: 10, bottom: 24 })

        Blank().height(20)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── 5. 应用锁 Sheet ──
  @Builder
  AppLockSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill('#66000000')
        .onClick(() => {
          this.showAppLockSheet = false;
        })

      Column() {
        Row() {
          Text(this.t('settings_app_lock_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_muted'))
            .padding(6)
            .onClick(() => {
              this.showAppLockSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        // 应用锁卡片
        Column() {
          Row() {
            Column() {
              Text(this.t('settings_app_lock'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .fontWeight(FontWeight.Medium)
              Text(this.t('settings_app_lock_desc'))
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.appLockEnabled })
              .selectedColor('#4D6BFE')
              .switchPointColor('#FFFFFF')
              .onChange((isOn: boolean) => {
                this.toggleAppLock(isOn);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('92%')
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .borderWidth(1)
        .borderColor($r('app.color.border_card'))
        .margin({ top: 10, bottom: 24 })

        Blank().height(20)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── 6. 上下文净化（Jev）Sheet ──
  @Builder
  TopicGateSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill('#66000000')
        .onClick(() => {
          this.showTopicGateSheet = false;
        })

      Column() {
        Row() {
          Text(this.t('settings_topic_gate_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_muted'))
            .padding(6)
            .onClick(() => {
              this.showTopicGateSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

        // 两个 tab：System One（判定）与 System Two（生成）分开配置，Key 互不复用。
        Row() {
          Button(this.t('settings_system_one'))
            .fontSize(13)
            .layoutWeight(1)
            .backgroundColor(this.topicTab === 0 ? '#4D6BFE' : '#E2E8F0')
            .fontColor(this.topicTab === 0 ? '#FFFFFF' : '#475569')
            .onClick(() => {
              this.topicTab = 0;
              this.topicGateError = '';
            })
          Button(this.t('settings_system_two'))
            .fontSize(13)
            .layoutWeight(1)
            .margin({ left: 8 })
            .backgroundColor(this.topicTab === 1 ? '#4D6BFE' : '#E2E8F0')
            .fontColor(this.topicTab === 1 ? '#FFFFFF' : '#475569')
            .onClick(() => {
              this.topicTab = 1;
              this.topicGateError = '';
            })
        }
        .width('92%')
        .margin({ bottom: 14 })

        if (this.topicTab === 0) {
        // 开关
        Column() {
          Row() {
            Column() {
              Text(this.t('settings_topic_gate'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .fontWeight(FontWeight.Medium)
              Text(this.t('settings_topic_gate_desc'))
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.topicGateEnabled })
              .selectedColor('#4D6BFE')
              .switchPointColor('#FFFFFF')
              .onChange((isOn: boolean) => {
                this.toggleTopicGate(isOn);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('92%')
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .borderWidth(1)
        .borderColor($r('app.color.border_card'))
        .margin({ top: 4, bottom: 16 })

        // 渠道：官方 / OpenRouter（端点与模型按官方文档固定）
        Column() {
          Text(this.t('settings_channel'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 8 })

          Row() {
            Button(this.t('settings_channel_typesafe'))
              .fontSize(12)
              .layoutWeight(1)
              .backgroundColor(this.systemOneChannel === SYSTEM_ONE_CHANNEL_TYPESAFE ? '#4D6BFE' : '#E2E8F0')
              .fontColor(this.systemOneChannel === SYSTEM_ONE_CHANNEL_TYPESAFE ? '#FFFFFF' : '#475569')
              .onClick(() => {
                this.selectSystemOneChannel(SYSTEM_ONE_CHANNEL_TYPESAFE);
              })
            Button('OpenRouter')
              .fontSize(12)
              .layoutWeight(1)
              .margin({ left: 8 })
              .backgroundColor(this.systemOneChannel === SYSTEM_ONE_CHANNEL_OPENROUTER ? '#4D6BFE' : '#E2E8F0')
              .fontColor(this.systemOneChannel === SYSTEM_ONE_CHANNEL_OPENROUTER ? '#FFFFFF' : '#475569')
              .onClick(() => {
                this.selectSystemOneChannel(SYSTEM_ONE_CHANNEL_OPENROUTER);
              })
          }
          .width('100%')

          Text(this.systemOneModelLabel())
            .fontSize(11)
            .fontColor($r('app.color.text_muted'))
            .width('100%')
            .margin({ top: 6 })

          this.KeyEditor(
            this.systemOneKeyInput,
            this.systemOneHasKey,
            (v: string) => {
              this.systemOneKeyInput = v;
              this.topicGateError = '';
            },
            () => {
              this.saveSystemOneKey();
            },
            () => {
              this.clearSystemOneKey();
            }
          )
        }
        .width('92%')
        .padding(16)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .borderWidth(1)
        .borderColor($r('app.color.border_card'))
        .margin({ bottom: 16 })

        // 阈值
        Column() {
          Row() {
            Text(this.t('settings_topic_gate_threshold'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(this.tempTopicThreshold.toFixed(2))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#4D6BFE')
          }
          .width('100%')

          Slider({
            value: this.tempTopicThreshold,
            min: 0.1,
            max: 0.9,
            step: 0.05,
            style: SliderStyle.InSet
          })
            .blockColor('#4D6BFE')
            .trackColor('#E2E8F0')
            .selectedColor('#4D6BFE')
            .width('100%')
            .margin({ top: 4 })
            .onChange((value: number, mode: SliderChangeMode) => {
              this.tempTopicThreshold = value;
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.applyTopicGateThreshold(value);
              }
            })

          Text(this.t('settings_topic_gate_threshold_hint'))
            .fontSize(11)
            .fontColor($r('app.color.text_muted'))
            .width('100%')
            .margin({ top: 4 })
        }
        .width('92%')
        .padding(16)
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .borderWidth(1)
        .borderColor($r('app.color.border_card'))

        }

        if (this.topicTab === 1) {
          this.SystemTwoPane()
        }

        Blank().height(24)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── System One / System Two 共用的 Key 编辑器 ──
  @Builder
  KeyEditor(value: string, hasKey: boolean, onChange: (v: string) => void, onSave: () => void, onClear: () => void) {
    Text(this.t('settings_topic_gate_key'))
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ top: 12, bottom: 8 })

    TextInput({ placeholder: this.t('settings_topic_gate_key_placeholder'), text: value })
      .type(InputType.Password)
      .width('100%')
      .height(42)
      .onChange((v: string) => {
        onChange(v);
      })

    if (hasKey) {
      Text(this.t('settings_topic_gate_key_saved'))
        .fontSize(11)
        .fontColor($r('app.color.text_muted'))
        .width('100%')
        .margin({ top: 6 })
    }
    if (this.topicGateError.length > 0) {
      Text(this.topicGateError)
        .fontSize(11)
        .fontColor($r('app.color.danger_text'))
        .width('100%')
        .margin({ top: 6 })
    }

    Row() {
      if (hasKey) {
        Button(this.t('settings_topic_gate_clear_key'))
          .fontSize(13)
          .layoutWeight(1)
          .backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            onClear();
          })
      }
      Button(this.t('settings_topic_gate_save'))
        .fontSize(13)
        .layoutWeight(1)
        .margin({ left: hasKey ? 8 : 0 })
        .onClick(() => {
          onSave();
        })
    }
    .width('100%')
    .margin({ top: 12 })
  }

  // ── System Two：生成模型渠道（复用资产监控的服务商 Key） ──
  @Builder
  SystemTwoPane() {
    Column() {
      Text(this.t('settings_system_two_desc'))
        .fontSize(12)
        .fontColor($r('app.color.text_muted'))
        .width('100%')
        .margin({ bottom: 12 })

      Text(this.t('settings_provider'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PROVIDERS, (p: ProviderDefinition) => {
          Button(p.name)
            .fontSize(12)
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(this.systemTwoProviderId === p.id ? '#4D6BFE' : '#E2E8F0')
            .fontColor(this.systemTwoProviderId === p.id ? '#FFFFFF' : '#475569')
            .onClick(() => {
              this.selectSystemTwoProvider(p.id);
            })
        }, (p: ProviderDefinition) => p.id)
      }
      .width('100%')

      this.KeyEditor(
        this.systemTwoKeyInput,
        this.systemTwoHasKey,
        (v: string) => {
          this.systemTwoKeyInput = v;
          this.topicGateError = '';
        },
        () => {
          this.saveSystemTwoKey();
        },
        () => {
          this.clearSystemTwoKey();
        }
      )

      Text(this.t('settings_system_two_shared'))
        .fontSize(11)
        .fontColor($r('app.color.text_muted'))
        .width('100%')
        .margin({ top: 10 })
    }
    .width('92%')
    .padding(16)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(12)
    .borderWidth(1)
    .borderColor($r('app.color.border_card'))
  }

  @Builder
  SettingRow(icon: Resource, color: string, title: string, value: string, isLast: boolean, onTap: () => void) {
    Row() {
      Row() {
        Image(icon)
          .width(18)
          .height(18)
      }
      .width(28)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(color)
      .borderRadius(8)
      Text(title)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
        .layoutWeight(1)
      if (value.length > 0) {
        Text(value)
          .fontSize(13)
          .fontColor($r('app.color.text_muted'))
          .margin({ right: 4 })
      }
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.icon_muted'))
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .border({ width: { bottom: isLast ? 0 : 1 }, color: $r('app.color.border_soft') })
    .onClick(onTap)
  }
}
