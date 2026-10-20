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
/** 应用锁开关（离开应用后需验证锁屏密码/指纹/人脸）。 */
export const KEY_APP_LOCK_ENABLED = 'app_lock_enabled'; // boolean
/** 当前应用是否处于锁定态；由 EntryAbility 切后台时置 true，认证通过后置 false。 */
export const KEY_APP_LOCKED = 'app_locked'; // boolean
/** 上下文净化（Jev topic gate）开关；关闭时不发起任何判定。 */
export const KEY_TOPIC_GATE_ENABLED = 'topic_gate_enabled'; // boolean
/** Jev（TypeSafe System One）Key；与生成 Key 分开存储。 */
export const KEY_TOPIC_GATE_API_KEY = 'key_jev'; // string
/** 切题概率阈值，低于该值的分段不参与回放。 */
export const KEY_TOPIC_GATE_THRESHOLD = 'topic_gate_threshold'; // number 0~1
/** 端点与模型覆盖项；缺省用 JevService 的官方默认值。 */
export const KEY_TOPIC_GATE_ENDPOINT = 'topic_gate_endpoint'; // string
export const KEY_TOPIC_GATE_MODEL = 'topic_gate_model'; // string
export const DEFAULT_TOPIC_GATE_THRESHOLD: number = 0.5;

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

      // 4. 应用锁：仅在首次初始化时决定是否直接锁定，避免页面再次 init 时把已解锁状态重置。
      const lockVal: preferences.ValueType = await SettingsService.prefsInstance.get(KEY_APP_LOCK_ENABLED, false);
      let appLockEnabled: boolean = false;
      if (typeof lockVal === 'boolean') {
        appLockEnabled = lockVal;
      }
      AppStorage.setOrCreate<boolean>(KEY_APP_LOCK_ENABLED, appLockEnabled);
      const existingLocked: boolean | undefined = AppStorage.get<boolean>(KEY_APP_LOCKED);
      if (appLockEnabled && existingLocked === undefined) {
        AppStorage.setOrCreate<boolean>(KEY_APP_LOCKED, true);
      } else if (!appLockEnabled) {
        AppStorage.setOrCreate<boolean>(KEY_APP_LOCKED, false);
      }

      // 5. 上下文净化：启用态与阈值进 AppStorage，Key/端点留 Preferences（不扩散）。
      const gateVal: preferences.ValueType = await SettingsService.prefsInstance.get(KEY_TOPIC_GATE_ENABLED, false);
      let gateEnabled: boolean = false;
      if (typeof gateVal === 'boolean') {
        gateEnabled = gateVal;
      }
      AppStorage.setOrCreate<boolean>(KEY_TOPIC_GATE_ENABLED, gateEnabled);

      const thresholdVal: preferences.ValueType =
        await SettingsService.prefsInstance.get(KEY_TOPIC_GATE_THRESHOLD, DEFAULT_TOPIC_GATE_THRESHOLD);
      let threshold: number = DEFAULT_TOPIC_GATE_THRESHOLD;
      if (typeof thresholdVal === 'number' && thresholdVal >= 0 && thresholdVal <= 1) {
        threshold = thresholdVal;
      }
      AppStorage.setOrCreate<number>(KEY_TOPIC_GATE_THRESHOLD, threshold);

      hilog.info(DOMAIN, TAG, 'SettingsService initialized successfully: appearance=%{public}s, fontLevel=%{public}d, autoCollapse=%{public}s, appLock=%{public}s',
        appearance, fontLevel, String(autoCollapse), String(appLockEnabled));
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
   * 设置应用锁开关并持久化。
   * Business Rule: 关闭时立即清除当前锁定态；开启后不立即锁定，待应用离开后台时生效。
   */
  public static async setAppLockEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate<boolean>(KEY_APP_LOCK_ENABLED, enabled);
    if (!enabled) {
      AppStorage.setOrCreate<boolean>(KEY_APP_LOCKED, false);
    }

    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await SettingsService.prefsInstance.put(KEY_APP_LOCK_ENABLED, enabled);
      await SettingsService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setAppLockEnabled save failed: %{public}s', String(err));
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

  /**
   * 上下文净化开关。
   * Business Rule: 关闭时立即停止判定与回放投影，已写入历史的掩码保留但不生效（可随时重开）。
   */
  public static async setTopicGateEnabled(context: common.UIAbilityContext, enabled: boolean): Promise<void> {
    AppStorage.setOrCreate<boolean>(KEY_TOPIC_GATE_ENABLED, enabled);

    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await SettingsService.prefsInstance.put(KEY_TOPIC_GATE_ENABLED, enabled);
      await SettingsService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setTopicGateEnabled save failed: %{public}s', String(err));
    }
  }

  /** 切题概率阈值（0~1，越严格越高）。 */
  public static async setTopicGateThreshold(context: common.UIAbilityContext, threshold: number): Promise<void> {
    const valid: number = Math.max(0, Math.min(1, threshold));
    AppStorage.setOrCreate<number>(KEY_TOPIC_GATE_THRESHOLD, valid);

    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await SettingsService.prefsInstance.put(KEY_TOPIC_GATE_THRESHOLD, valid);
      await SettingsService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setTopicGateThreshold save failed: %{public}s', String(err));
    }
  }

  /** 保存 Jev Key；传空字符串表示清除。Key 只落本机 Preferences，不进日志。 */
  public static async setTopicGateApiKey(context: common.UIAbilityContext, apiKey: string): Promise<void> {
    const trimmed: string = apiKey.trim();

    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await SettingsService.prefsInstance.put(KEY_TOPIC_GATE_API_KEY, trimmed);
      await SettingsService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setTopicGateApiKey save failed: %{public}s', String(err));
    }
  }

  /** 读取 Jev Key（设置页回显与判定服务共用）。 */
  public static async getTopicGateApiKey(context: common.UIAbilityContext): Promise<string> {
    try {
      if (SettingsService.prefsInstance === undefined) {
        SettingsService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      const val: preferences.ValueType = await SettingsService.prefsInstance.get(KEY_TOPIC_GATE_API_KEY, '');
      return typeof val === 'string' ? val as string : '';
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getTopicGateApiKey failed: %{public}s', String(err));
      return '';
    }
  }
}
