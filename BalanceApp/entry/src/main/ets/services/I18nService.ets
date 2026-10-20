/*
 * I18nService.ets
 *
 * 应用国际化多语言服务 —— 支持中文（简体）与英文（English）。
 * 提供基于 AppStorage 的全局响应式语言切换与 Preferences 持久化存储。
 *
 * 遵循 ArkTS 严格模式规范：禁止解构、强类型定义、无 any/unknown。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { i18n } from '@kit.LocalizationKit';

const DOMAIN = 0x0000;
const TAG = 'I18nService';
const PREFS_NAME = 'balance_prefs';
const KEY_APP_LANGUAGE = 'app_language';

export type AppLanguage = 'zh-CN' | 'en-US';

export interface LanguageItem {
  code: AppLanguage;
  name: string;
  nativeName: string;
}

export const SUPPORTED_LANGUAGES: LanguageItem[] = [
  { code: 'zh-CN', name: '中文（简体）', nativeName: '中文（简体中文）' },
  { code: 'en-US', name: 'English', nativeName: 'English' }
];

const DICTIONARY: Record<AppLanguage, Record<string, string>> = {
  'zh-CN': {
    'settings_title': '设置',
    'settings_section_app': '应用',
    'settings_language': '语言',
    'settings_language_current': '中文（简体中文）',
    'settings_appearance': '外观',
    'settings_appearance_system': '系统',
    'settings_appearance_light': '浅色',
    'settings_appearance_dark': '深色',
    'settings_appearance_select': '选择外观模式',
    'settings_font_size': '字体大小',
    'settings_font_size_title': '设置字体大小',
    'settings_font_size_preview_title': '预览效果',
    'settings_font_size_preview_sample': '这是一段用于预览字体大小的文字样例。拖动下方滑块调整整体界面字号。',
    'settings_font_size_standard': '标准',
    'settings_personalize': '个性化',
    'settings_auto_collapse_thinking': '思考内容自动折叠',
    'settings_auto_collapse_thinking_desc': '开启后，思考结束后将自动折叠思考内容。',
    'settings_section_security': '安全',
    'settings_app_lock': '应用锁',
    'settings_app_lock_title': '应用锁',
    'settings_app_lock_desc': '开启后，离开应用再进入时需验证锁屏密码、指纹或人脸识别。',
    'settings_app_lock_on': '已开启',
    'settings_app_lock_off': '未开启',
    'settings_section_data': '数据',
    'settings_assets': '资产监控',
    'settings_assets_desc': '查看各服务商余额',
    'settings_section_chat': '对话',
    'settings_topic_gate': '上下文净化',
    'settings_topic_gate_desc': '按句判定回复是否切题，离题内容留在界面但不参与后续上下文。',
    'settings_topic_gate_on': '已开启',
    'settings_topic_gate_off': '未开启',
    'settings_topic_gate_title': '上下文净化（Jev）',
    'settings_topic_gate_key': 'Jev Key',
    'settings_topic_gate_key_placeholder': '粘贴 Jev Key',
    'settings_topic_gate_key_saved': '已配置，留空则保持不变',
    'settings_topic_gate_threshold': '切题阈值',
    'settings_topic_gate_threshold_hint': '低于该概率的句子不参与后续上下文；数值越高越严格。',
    'settings_topic_gate_save': '保存',
    'settings_topic_gate_clear_key': '清除 Key',
    'settings_topic_gate_need_key': '请先填写 Jev Key',
    'settings_version': '版本 1.0.0',
    'settings_select_language': '选择语言',
    'common_cancel': '取消',
    'common_confirm': '确定',
    'common_not_implemented': '该功能暂未实现',
  },
  'en-US': {
    'settings_title': 'Settings',
    'settings_section_app': 'Application',
    'settings_language': 'Language',
    'settings_language_current': 'English',
    'settings_appearance': 'Appearance',
    'settings_appearance_system': 'System',
    'settings_appearance_light': 'Light',
    'settings_appearance_dark': 'Dark',
    'settings_appearance_select': 'Select Appearance',
    'settings_font_size': 'Font Size',
    'settings_font_size_title': 'Font Size',
    'settings_font_size_preview_title': 'Preview',
    'settings_font_size_preview_sample': 'This is a sample text for previewing font size. Drag the slider below to adjust text size across the app.',
    'settings_font_size_standard': 'Standard',
    'settings_personalize': 'Personalization',
    'settings_auto_collapse_thinking': 'Auto-collapse Thinking Process',
    'settings_auto_collapse_thinking_desc': 'When enabled, the thinking process will collapse automatically after generation ends.',
    'settings_section_security': 'Security',
    'settings_app_lock': 'App Lock',
    'settings_app_lock_title': 'App Lock',
    'settings_app_lock_desc': 'When enabled, entering the app after leaving requires your lock-screen password, fingerprint, or face.',
    'settings_app_lock_on': 'On',
    'settings_app_lock_off': 'Off',
    'settings_section_data': 'Data',
    'settings_assets': 'Assets & Balance',
    'settings_assets_desc': 'View provider balances',
    'settings_section_chat': 'Conversation',
    'settings_topic_gate': 'Context Cleanup',
    'settings_topic_gate_desc': 'Scores each sentence for topicality; off-topic text stays visible but is dropped from later context.',
    'settings_topic_gate_on': 'On',
    'settings_topic_gate_off': 'Off',
    'settings_topic_gate_title': 'Context Cleanup (Jev)',
    'settings_topic_gate_key': 'Jev Key',
    'settings_topic_gate_key_placeholder': 'Paste your Jev key',
    'settings_topic_gate_key_saved': 'Configured; leave blank to keep it',
    'settings_topic_gate_threshold': 'On-topic threshold',
    'settings_topic_gate_threshold_hint': 'Sentences below this probability are left out of later context. Higher is stricter.',
    'settings_topic_gate_save': 'Save',
    'settings_topic_gate_clear_key': 'Clear key',
    'settings_topic_gate_need_key': 'Enter a Jev key first',
    'settings_version': 'Version 1.0.0',
    'settings_select_language': 'Select Language',
    'common_cancel': 'Cancel',
    'common_confirm': 'Confirm',
    'common_not_implemented': 'Feature not implemented yet',
  }
};

export class I18nService {
  private static currentLang: AppLanguage = 'zh-CN';
  private static prefsInstance: preferences.Preferences | undefined = undefined;

  /**
   * 初始化语言服务，从 Preferences 读取持久化设置
   */
  public static async init(context: common.UIAbilityContext): Promise<void> {
    try {
      I18nService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      const val: preferences.ValueType = await I18nService.prefsInstance.get(KEY_APP_LANGUAGE, 'zh-CN');
      let lang: AppLanguage = 'zh-CN';
      if (typeof val === 'string' && (val === 'zh-CN' || val === 'en-US')) {
        lang = val as AppLanguage;
      }
      I18nService.currentLang = lang;
      AppStorage.setOrCreate<string>('app_language', lang);
      hilog.info(DOMAIN, TAG, 'I18nService initialized with language: %{public}s', lang);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'I18nService init failed: %{public}s', String(err));
    }
  }

  /**
   * 获取当前语言
   */
  public static getLanguage(): AppLanguage {
    return I18nService.currentLang;
  }

  /**
   * 切换语言并持久化
   */
  public static async setLanguage(context: common.UIAbilityContext, lang: AppLanguage): Promise<void> {
    I18nService.currentLang = lang;
    AppStorage.setOrCreate<string>('app_language', lang);

    try {
      if (I18nService.prefsInstance === undefined) {
        I18nService.prefsInstance = await preferences.getPreferences(context, { name: PREFS_NAME });
      }
      await I18nService.prefsInstance.put(KEY_APP_LANGUAGE, lang);
      await I18nService.prefsInstance.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'save language failed: %{public}s', String(err));
    }

    // 尝试同步系统偏好语言
    try {
      if (lang === 'zh-CN') {
        i18n.System.setAppPreferredLanguage('zh-Hans');
      } else {
        i18n.System.setAppPreferredLanguage('en');
      }
    } catch (e) {
      // 某些真机权限可能不允许，静默忽略
    }
  }

  /**
   * 获取指定 key 的国际化文本
   */
  public static t(key: string, langOverride?: AppLanguage): string {
    const lang: AppLanguage = langOverride || I18nService.currentLang;
    const dict: Record<string, string> = DICTIONARY[lang] || DICTIONARY['zh-CN'];
    const val: string | undefined = dict[key];
    if (val !== undefined) {
      return val;
    }
    const fallback: string | undefined = DICTIONARY['zh-CN'][key];
    return fallback !== undefined ? fallback : key;
  }
}
