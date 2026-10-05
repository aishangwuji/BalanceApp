/*
 * SettingsService.ets
 *
 * 全局设置项管理服务 —— 外观模式、字体大小缩放、思考折叠等个性化配置。
 * 遵循 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SettingsService';
const PREFS_NAME = 'balance_prefs';

// 偏好键常量
export const KEY_APP_APPEARANCE = 'app_appearance'; // 'system' | 'light' | 'dark'
export const KEY_FONT_SIZE_LEVEL = 'app_font_size_level'; // 1 ~ 7，默认 3
export const KEY_AUTO_COLLAPSE_THINKING = 'auto_collapse_thinking'; // boolean，默认 true
/**
 * 解析后的实际深色态（system 时跟随系统），供非资源侧（Markdown 主题）读取。
 * Business Rule: 资源颜色由 setColorMode 自动切换，但 Markdown 库主题需显式布尔，
 *   故此处统一落一个已解析值，避免 system+系统深色时正文配色与背景不一致（隐形）。
 */
export const KEY_APP_DARK = 'app_dark'; // boolean

// 7 档字体缩放系数，第 3 档为标准大小 (1.0)
export const FONT_SCALE_LEVELS: number[] = [0.85, 0.92, 1.0, 1.08, 1.16, 1.25, 1.35];

export type AppearanceMode = 'system' | 'light' | 'dark';

export class SettingsService {
  private static prefsInstance: preferences.Preferences | undefined = undefined;

  /**
   * 初始化设置，从 Preferences 读取持久化设置并同步到 AppStorage
   */
  public static async init(context: common.UIAbilityContext): Promise<void> {
    try {
      SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });

      // 1. 外观模式
      const appModeVal: preferences.ValueType = await SettingsService.prefsInstance.get(KEY_APP_APPEARANCE, 'system');
      let appearance: AppearanceMode = 'system';
      if (typeof appModeVal === 'string' && (appModeVal === 'system' || appModeVal === 'light' || appModeVal === 'dark')) {
        appearance = appModeVal as AppearanceMode;
      }
      AppStorage.setOrCreate<string>(KEY_APP_APPEARANCE, appearance);
      SettingsService.applyColorMode(context, appearance);
      SettingsService.storeResolvedDark(context, appearance);

      // 2. 字体大小档位 (1 ~ 7，第 3 档为标准)
      const fontLevelVal: preferences.ValueType = await SettingsService.prefsInstance.get(KEY_FONT_SIZE_LEVEL, 3);
      let fontLevel: number = 3;
      if (typeof fontLevelVal === 'number' && fontLevelVal >= 1 && fontLevelVal <= 7) {
        fontLevel = Math.round(fontLevelVal);
      }
      AppStorage.setOrCreate<number>(KEY_FONT_SIZE_LEVEL, fontLevel);
      const fontScale: number = SettingsService.getScaleByLevel(fontLevel);
      AppStorage.setOrCreate<number>('app_font_scale', fontScale);

      // 3. 思考内容自动折叠 (默认 true)
      const collapseVal: preferences.ValueType = await SettingsService.prefsInstance.get(KEY_AUTO_COLLAPSE_THINKING, true);
      let autoCollapse: boolean = true;
      if (typeof collapseVal === 'boolean') {
        autoCollapse = collapseVal;
      }
      AppStorage.setOrCreate<boolean>(KEY_AUTO_COLLAPSE_THINKING, autoCollapse);

      hilog.info(DOMAIN, TAG, 'SettingsService initialized successfully: appearance=%{public}s, fontLevel=%{public}d, autoCollapse=%{public}s',
        appearance, fontLevel, String(autoCollapse));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'SettingsService init failed: %{public}s', String(err));
    }
  }

  /**
   * 根据档位获取对应文字倍率
   */
  public static getScaleByLevel(level: number): number {
    const idx: number = Math.max(1, Math.min(7, level)) - 1;
    return FONT_SCALE_LEVELS[idx];
  }

  /**
   * 应用系统/浅色/深色外观
   */
  public static applyColorMode(context: common.UIAbilityContext, mode: AppearanceMode): void {
    try {
      let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === 'light') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (mode === 'dark') {
        colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      context.getApplicationContext().setColorMode(colorMode);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'applyColorMode failed: %{public}s', String(err));
    }
  }

  /** 解析并落存实际深色态，供 Markdown 等非资源侧读取。 */
  private static storeResolvedDark(context: common.UIAbilityContext, mode: AppearanceMode): void {
    AppStorage.setOrCreate<boolean>(KEY_APP_DARK, SettingsService.resolveDark(context, mode));
  }

  /**
   * 解析实际深色态：显式 light/dark 直接决定；system 读系统配置。
   * Reason: setColorMode 只切换资源解析，Markdown 库主题需显式布尔，故统一收口于此。
   */
  public static resolveDark(context: common.UIAbilityContext, mode: AppearanceMode): boolean {
    if (mode === 'dark') {
      return true;
    }
    if (mode === 'light') {
      return false;
    }
    try {
      return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } catch (err) {
      return false;
    }
  }

  /**
   * 设置外观模式并持久化
   */
  public static async setAppearance(context: common.UIAbilityContext, mode: AppearanceMode): Promise<void> {
    AppStorage.setOrCreate<string>(KEY_APP_APPEARANCE, mode);
    SettingsService.applyColorMode(context, mode);
    SettingsService.storeResolvedDark(context, mode);

    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await SettingsService.prefsInstance.put(KEY_APP_APPEARANCE, mode);
      await SettingsService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setAppearance save failed: %{public}s', String(err));
    }
  }

  /**
   * 设置字体大小档位 (1 ~ 7)
   */
  public static async setFontSizeLevel(context: common.UIAbilityContext, level: number): Promise<void> {
    const validLevel: number = Math.max(1, Math.min(7, level));
    AppStorage.setOrCreate<number>(KEY_FONT_SIZE_LEVEL, validLevel);
    AppStorage.setOrCreate<number>('app_font_scale', SettingsService.getScaleByLevel(validLevel));

    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await SettingsService.prefsInstance.put(KEY_FONT_SIZE_LEVEL, validLevel);
      await SettingsService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setFontSizeLevel save failed: %{public}s', String(err));
    }
  }

  /**
   * 设置思考内容自动折叠
   */
  public static async setAutoCollapseThinking(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate<boolean>(KEY_AUTO_COLLAPSE_THINKING, enabled);

    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await SettingsService.prefsInstance.put(KEY_AUTO_COLLAPSE_THINKING, enabled);
      await SettingsService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setAutoCollapseThinking save failed: %{public}s', String(err));
    }
  }
}
