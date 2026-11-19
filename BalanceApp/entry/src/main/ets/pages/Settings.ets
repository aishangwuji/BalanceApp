/*
 * Settings.ets —— 设置页
 *
 * 以温润静奢为全局视觉基调：留白分组、柔和表面与克制的墨金强调。
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
import { UpdateService, UpdateInfo } from '../services/UpdateService';
import {
  SettingsService, AppearanceMode, KEY_APP_APPEARANCE, KEY_FONT_SIZE_LEVEL, KEY_AUTO_COLLAPSE_THINKING,
  KEY_APP_LOCK_ENABLED,
  KEY_TTS_VOICE, DEFAULT_TTS_VOICE
} from '../services/SettingsService';

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

/** 朗读音色：只有 DeepSeek TTS 的两种音色，值与服务端 voice_id 一致。 */
interface VoiceOption {
  key: string;
  nameKey: string;
  descKey: string;
}

const VOICE_OPTIONS: VoiceOption[] = [
  { key: 'stella', nameKey: 'settings_voice_stella', descKey: 'settings_voice_stella_desc' },
  { key: 'tide', nameKey: 'settings_voice_tide', descKey: 'settings_voice_tide_desc' }
];

@Entry
@Component
struct Settings {
  @StorageProp('app_language') currentLang: string = 'zh-CN';
  @StorageProp(KEY_APP_APPEARANCE) currentAppearance: string = 'system';
  @StorageProp(KEY_FONT_SIZE_LEVEL) currentFontLevel: number = 3;
  @StorageProp(KEY_AUTO_COLLAPSE_THINKING) autoCollapseThinking: boolean = true;
  @StorageProp(KEY_TTS_VOICE) ttsVoice: string = DEFAULT_TTS_VOICE;
  @StorageProp(KEY_APP_LOCK_ENABLED) appLockEnabled: boolean = false;
  /** 当前版本（运行时读 BundleInfo，和 AppScope 同源）。 */
  @State currentVersion: string = UpdateService.currentVersion();
  @State checkingUpdate: boolean = false;

  // 底部弹框控制
  @State showLanguageSheet: boolean = false;
  @State showAppearanceSheet: boolean = false;
  @State showFontSizeSheet: boolean = false;
  @State showPersonalizeSheet: boolean = false;
  @State showVoiceSheet: boolean = false;
  @State showAppLockSheet: boolean = false;

  // 字体大小滑块临时滑动值 (1 ~ 7)
  @State tempFontLevel: number = 3;

  aboutToAppear(): void {
    const uiCtx = this.getUIContext();
    const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
    I18nService.init(hostCtx);
    SettingsService.init(hostCtx);
    this.tempFontLevel = this.currentFontLevel;
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

  /** 朗读音色显示名（stella 默认）。 */
  private currentVoiceDisplay(): string {
    return this.ttsVoice === 'tide' ? this.t('settings_voice_tide') : this.t('settings_voice_stella');
  }

  private async selectVoice(key: string): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      const hostCtx = uiCtx.getHostContext() as common.UIAbilityContext;
      await SettingsService.setTtsVoice(hostCtx, key);
      this.showVoiceSheet = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'selectVoice failed: %{public}s', String(err));
    }
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

  /**
   * 手动检查更新：Gitee → GitHub 双源，发现新版本弹窗给出说明与下载入口。
   * Business Rule: 安装交由系统浏览器（HarmonyOS 不允许应用静默安装 HAP）。
   */
  private async checkUpdate(): Promise<void> {
    if (this.checkingUpdate) {
      return;
    }
    this.checkingUpdate = true;
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const info: UpdateInfo | null = await UpdateService.check(hostCtx);
      if (info === null) {
        this.getUIContext().showAlertDialog({
          title: this.t('settings_check_update'),
          message: `${this.t('settings_up_to_date')}（v${this.currentVersion}）`
        });
        return;
      }
      const message: string = info.notes.length > 0 ? info.notes : `v${info.version}`;
      this.getUIContext().showAlertDialog({
        title: `${this.t('settings_new_version_title')} v${info.version}`,
        message: message,
        primaryButton: {
          value: this.t('settings_download'),
          action: () => {
            this.openExternal(info.downloadUrl);
          }
        },
        secondaryButton: {
          value: this.t('settings_later'),
          action: () => {
          }
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'check update failed: %{public}s', String(err));
      this.getUIContext().showAlertDialog({
        title: this.t('settings_check_update'),
        message: this.t('settings_check_failed')
      });
    } finally {
      this.checkingUpdate = false;
    }
  }

  private openProjectPage(): void {
    this.openExternal('https://gitee.com/aishangwuji/openchat');
  }

  private openExternal(url: string): void {
    if (url.length === 0) {
      return;
    }
    try {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      hostCtx.startAbility({
        action: 'ohos.want.action.viewData',
        uri: url,
        entities: ['entity.system.browsable']
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'open external failed: %{public}s', String(err));
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 顶部导航栏
        Row() {
          Text('‹')
            .fontSize(28)
            .fontColor($r('app.color.text_primary'))
            .width(42)
            .height(42)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(21)
            .onClick(() => {
              this.goBack();
            })
          Text(this.t('settings_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .margin({ left: 8 })
          Blank()
        }
        .width('92%')
        .height(58)

        Scroll() {
          Column() {
            // ── 应用 ──
            Text(this.t('settings_section_app'))
              .fontSize(11)
              .letterSpacing(0.4)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 22, bottom: 10 })

            Column() {
              this.SettingRow($r('app.media.ic_language'), this.t('settings_language'), this.currentLanguageDisplay(), false, () => {
                this.showLanguageSheet = true;
              })
              this.SettingRow($r('app.media.ic_appearance'), this.t('settings_appearance'), this.currentAppearanceDisplay(), false, () => {
                this.showAppearanceSheet = true;
              })
              this.SettingRow($r('app.media.ic_font'), this.t('settings_font_size'), this.currentFontSizeDisplay(), false, () => {
                this.tempFontLevel = this.currentFontLevel;
                this.showFontSizeSheet = true;
              })
              this.SettingRow($r('app.media.ic_personalize'), this.t('settings_personalize'), '', true, () => {
                this.showPersonalizeSheet = true;
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .border({ width: 1, color: $r('app.color.border_soft') })

            // ── 语音 ──
            Text(this.t('settings_section_voice'))
              .fontSize(11)
              .letterSpacing(0.4)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 24, bottom: 10 })

            Column() {
              this.SettingRow($r('app.media.ic_voice'), this.t('settings_tts_voice'), this.currentVoiceDisplay(), true, () => {
                this.showVoiceSheet = true;
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .border({ width: 1, color: $r('app.color.border_soft') })

            // ── 安全 ──
            Text(this.t('settings_section_security'))
              .fontSize(11)
              .letterSpacing(0.4)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 24, bottom: 10 })

            Column() {
              this.SettingRow($r('app.media.ic_lock'), this.t('settings_app_lock'), this.currentAppLockDisplay(), true, () => {
                this.showAppLockSheet = true;
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .border({ width: 1, color: $r('app.color.border_soft') })

            // ── 数据 ──
            Text(this.t('settings_section_data'))
              .fontSize(11)
              .letterSpacing(0.4)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 24, bottom: 10 })

            Column() {
              this.SettingRow($r('app.media.ic_assets'), this.t('settings_assets'), this.t('settings_assets_desc'), true, () => {
                this.openAssets();
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .border({ width: 1, color: $r('app.color.border_soft') })

            // ── 关于 ──
            Text(this.t('settings_section_about'))
              .fontSize(11)
              .letterSpacing(0.4)
              .fontColor($r('app.color.text_muted'))
              .width('92%')
              .margin({ top: 24, bottom: 10 })

            Column() {
              this.SettingRow($r('app.media.ic_refresh'), this.t('settings_check_update'),
                this.checkingUpdate ? this.t('settings_checking') : `v${this.currentVersion}`, false, () => {
                  this.checkUpdate();
                })
              this.SettingRow($r('app.media.ic_character'), this.t('settings_project_page'), '', true, () => {
                this.openProjectPage();
              })
            }
            .width('92%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .border({ width: 1, color: $r('app.color.border_soft') })

            Text(this.t('settings_version'))
              .fontSize(12)
              .fontColor($r('app.color.text_faint'))
              .margin({ top: 30, bottom: 18 })
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

      // 底部弹框：朗读音色面板
      if (this.showVoiceSheet) {
        this.VoiceSheet()
      }

      // 底部弹框：应用锁面板
      if (this.showAppLockSheet) {
        this.AppLockSheet()
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
        .fill($r('app.color.overlay_scrim'))
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
                .fontColor(this.currentLang === item.code ? $r('app.color.accent') : $r('app.color.text_primary'))
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
                .fontColor($r('app.color.accent'))
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
      .borderRadius({ topLeft: 28, topRight: 28 })
      .border({ width: 1, color: $r('app.color.border_soft') })
      .shadow({ radius: 24, color: 'rgba(20,18,14,0.14)', offsetX: 0, offsetY: 8 })
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
        .fill($r('app.color.overlay_scrim'))
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
              .fontColor(this.currentAppearance === opt.key ? $r('app.color.accent') : $r('app.color.text_primary'))
              .layoutWeight(1)

            if (this.currentAppearance === opt.key) {
              Text('✓')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.accent'))
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
      .borderRadius({ topLeft: 28, topRight: 28 })
      .border({ width: 1, color: $r('app.color.border_soft') })
      .shadow({ radius: 24, color: 'rgba(20,18,14,0.14)', offsetX: 0, offsetY: 8 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── 3. 朗读音色 Sheet ──
  @Builder
  VoiceSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill($r('app.color.overlay_scrim'))
        .onClick(() => {
          this.showVoiceSheet = false;
        })

      Column() {
        Row() {
          Text(this.t('settings_voice_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.text_muted'))
            .padding(6)
            .onClick(() => {
              this.showVoiceSheet = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })

        Text(this.t('settings_voice_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_muted'))
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 8 })

        ForEach(VOICE_OPTIONS, (opt: VoiceOption) => {
          Row() {
            Column() {
              Text(this.t(opt.nameKey))
                .fontSize(15)
                .fontWeight(this.ttsVoice === opt.key ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.ttsVoice === opt.key ? $r('app.color.accent') : $r('app.color.text_primary'))
              Text(this.t(opt.descKey))
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.ttsVoice === opt.key) {
              Text('✓')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.accent'))
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .border({ width: { bottom: 1 }, color: $r('app.color.fill') })
          .onClick(() => {
            this.selectVoice(opt.key);
          })
        }, (opt: VoiceOption) => opt.key)

        Blank().height(24)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 28, topRight: 28 })
      .border({ width: 1, color: $r('app.color.border_soft') })
      .shadow({ radius: 24, color: 'rgba(20,18,14,0.14)', offsetX: 0, offsetY: 8 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  // ── 4. 字体大小调节 Sheet ──
  @Builder
  FontSizeSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill($r('app.color.overlay_scrim'))
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
            .fontColor($r('app.color.accent'))
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
          .blockColor($r('app.color.accent_solid'))
          .trackColor($r('app.color.border_card'))
          .selectedColor($r('app.color.accent_solid'))
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
      .borderRadius({ topLeft: 28, topRight: 28 })
      .border({ width: 1, color: $r('app.color.border_soft') })
      .shadow({ radius: 24, color: 'rgba(20,18,14,0.14)', offsetX: 0, offsetY: 8 })
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
        .fill($r('app.color.overlay_scrim'))
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
              .selectedColor($r('app.color.accent_solid'))
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
      .borderRadius({ topLeft: 28, topRight: 28 })
      .border({ width: 1, color: $r('app.color.border_soft') })
      .shadow({ radius: 24, color: 'rgba(20,18,14,0.14)', offsetX: 0, offsetY: 8 })
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
        .fill($r('app.color.overlay_scrim'))
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
              .selectedColor($r('app.color.accent_solid'))
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
      .borderRadius({ topLeft: 28, topRight: 28 })
      .border({ width: 1, color: $r('app.color.border_soft') })
      .shadow({ radius: 24, color: 'rgba(20,18,14,0.14)', offsetX: 0, offsetY: 8 })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.move(TransitionEdge.BOTTOM),
        TransitionEffect.move(TransitionEdge.BOTTOM)
      ))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SettingRow(icon: Resource, title: string, value: string, isLast: boolean, onTap: () => void) {
    Row() {
      Row() {
        Image(icon)
          .width(17)
          .height(17)
        }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.icon_tile'))
      .border({ width: 1, color: $r('app.color.accent_outline') })
      .borderRadius(12)
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 14 })
        .layoutWeight(1)
      if (value.length > 0) {
        Text(value)
          .fontSize(12)
          .fontColor($r('app.color.text_muted'))
          .margin({ right: 8 })
      }
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.icon_muted'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .border({ width: { bottom: isLast ? 0 : 1 }, color: $r('app.color.border_soft') })
    .onClick(onTap)
  }
}

