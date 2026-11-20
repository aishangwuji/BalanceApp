/*
 * SkinService.ets —— 主题（皮肤）注册表与调色板解析
 *
 * 背景：鸿蒙端的配色原先全部写死在 `resources/base/element/color.json` 里，经 `$r('app.color.x')`
 * 引用。资源是编译期常量，运行时无法整体替换，所以「用户可选主题」必须先把颜色从资源层切到
 * 运行时可变的调色板层。
 *
 * 切割方式（Business Rule）：
 *   1. 组件不再直接引 `$r('app.color.x')`，改调 `skinColor('x')`；
 *   2. `skinColor` 从当前皮肤 + 当前明暗（跟随系统/浅色/深色，由 SettingsService 解析）里取值；
 *   3. 皮肤或明暗一变，`bumpVersion()` 自增 AppStorage 的 `skin_version`，所有声明了
 *      `@StorageProp(KEY_SKIN_VERSION)` 的组件重绘 —— 这是刷新链路，别绕过它直接改模块变量。
 *   4. 未知 token / 未知皮肤一律回退到 `official` 的浅色调色板，绝不返回空值（否则组件透明）。
 *
 * 只存本机偏好（不联网、不进日志）。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KEY_APP_DARK } from './SettingsService';

const DOMAIN: number = 0x0000;
const TAG: string = 'SkinService';
const PREFS_NAME: string = 'balance_skin_prefs';

/** 当前皮肤 id（持久化键）。 */
export const KEY_SKIN_ID: string = 'skin_id';
/** 皮肤版本号：任何配色变化都自增，驱动 @StorageProp 组件重绘。 */
export const KEY_SKIN_VERSION: string = 'skin_version';

/**
 * 一套配色。键是语义 token（与 color.json 同名），值是 `#RRGGBB` / `#AARRGGBB`。
 *
 * Reason: ArkTS 严格模式禁止「无类型对象字面量」，50 个字段写成类又会让新增 token 变成体力活，
 * 所以这里用紧凑的 `token=#hex,token=#hex` 串在构造时展开成 Map：数据仍然一屏能扫完，
 * 取色走 get()，新增 token 只改数据不改结构。
 */
export class SkinPalette {
  private entries: Map<string, string> = new Map<string, string>();

  constructor(source: string) {
    const parts: string[] = source.split(',');
    for (let i = 0; i < parts.length; i++) {
      const pair: string = parts[i].trim();
      if (pair.length === 0) {
        continue;
      }
      const sep: number = pair.indexOf('=');
      if (sep <= 0) {
        continue;
      }
      this.entries.set(pair.substring(0, sep), pair.substring(sep + 1));
    }
  }

  /** 取色；未登记的 token 返回空串，由调用方兜底。 */
  get(token: string): string {
    const value: string | undefined = this.entries.get(token);
    return value !== undefined ? value : '';
  }
}

export interface SkinDefinition {
  id: string;
  name: string;
  /** 英文名（英文界面用）。 */
  nameEn: string;
  /** 一句话风格说明，设置页副标题用。 */
  note: string;
  /** 英文一句话说明。 */
  noteEn: string;
  light: SkinPalette;
  dark: SkinPalette;
}

// ── official：官方蓝白（默认）。以对话主色蓝 + 纯白卡片为主，最接近 DeepSeek 官方的观感。 ──
const OFFICIAL_LIGHT: SkinPalette = new SkinPalette(
  'page_bg=#F7F8FA,surface=#FFFFFF,surface_alt=#F7F8FA,surface_row=#F4F5F7,' +
  'fill=#F2F3F5,input_bg=#F2F3F5,divider=#ECEDF0,border_soft=#ECEDF0,' +
  'border_card=#E2E4EA,text_primary=#1B1B1F,text_title=#121317,text_secondary=#5A5D66,' +
  'text_muted=#8A8D96,text_faint=#A8ABB3,icon_muted=#9A9DA6,accent=#4D6BFE,' +
  'accent_solid=#4D6BFE,accent_contrast=#FFFFFF,accent_soft=#EDF2FF,accent_soft_selected=#E2E9FF,' +
  'accent_outline=#D6E0FF,icon_tile=#F2F3F5,reasoning_text=#6B6E77,reasoning_muted=#94979F,' +
  'reasoning_bar=#C9D3F0,user_bubble_text=#1B1B1F,hero_bg=#1B1D24,hero_text=#F5F7FF,' +
  'hero_accent=#9DB0FF,hero_muted=#C3C8D4,danger_text=#C0453C,danger_fill=#FCEDEB,' +
  'status_good=#4C8C5C,overlay_scrim=#660E0D0A,pill_search_bg=#EEF3FF,pill_search_text=#4D6BFE,' +
  'pill_search_border=#D8E3FF,chat_surface=#FFFFFF,chat_surface_alt=#F7F8FA,chat_border=#ECEDF0,' +
  'chat_fill=#F2F3F5,sidebar_surface=#F1F2F4,chat_user_bubble=#E8EEFC,chat_user_text=#1B1B1F,' +
  'chat_accent=#4D6BFE,chat_accent_soft=#EDF2FF,chat_accent_soft_selected=#E2E9FF,chat_accent_solid=#4D6BFE,' +
  'chat_accent_contrast=#FFFFFF,chat_accent_outline=#D6E0FF');

const OFFICIAL_DARK: SkinPalette = new SkinPalette(
  'page_bg=#101114,surface=#17181C,surface_alt=#1D1E23,surface_row=#1E1F25,' +
  'fill=#26272E,input_bg=#1E1F24,divider=#2A2C33,border_soft=#2A2C33,' +
  'border_card=#363841,text_primary=#E7E9EF,text_title=#F4F6FA,text_secondary=#B6BAC4,' +
  'text_muted=#8A8E98,text_faint=#71757F,icon_muted=#7B7F89,accent=#8FA6FF,' +
  'accent_solid=#8FA6FF,accent_contrast=#10121A,accent_soft=#222A3F,accent_soft_selected=#28314A,' +
  'accent_outline=#3A4770,icon_tile=#26272E,reasoning_text=#BCC0CA,reasoning_muted=#8A8E98,' +
  'reasoning_bar=#3C4667,user_bubble_text=#E9ECF4,hero_bg=#0B0C0F,hero_text=#F2F4FA,' +
  'hero_accent=#A9BBFF,hero_muted=#B4B9C5,danger_text=#F08A80,danger_fill=#3A2320,' +
  'status_good=#8FBF9C,overlay_scrim=#9909090B,pill_search_bg=#222A40,pill_search_text=#9DB0FF,' +
  'pill_search_border=#35406A,chat_surface=#17181C,chat_surface_alt=#1D1E23,chat_border=#2A2C33,' +
  'chat_fill=#232429,sidebar_surface=#191A1F,chat_user_bubble=#28314A,chat_user_text=#E9ECF4,' +
  'chat_accent=#8FA6FF,chat_accent_soft=#222A40,chat_accent_soft_selected=#28314A,chat_accent_solid=#8FA6FF,' +
  'chat_accent_contrast=#10121A,chat_accent_outline=#3A4770');

// ── paper：暖纸墨金。低饱和米白底 + 墨黑主色 + 香槟金点缀，长时间阅读最舒服。 ──
const PAPER_LIGHT: SkinPalette = new SkinPalette(
  'page_bg=#F5F3EE,surface=#FFFEFB,surface_alt=#FAF8F3,surface_row=#F4F1EA,' +
  'fill=#EEEAE1,input_bg=#F8F6F1,divider=#EAE6DD,border_soft=#EDE8DE,' +
  'border_card=#E1DBCF,text_primary=#292822,text_title=#191915,text_secondary=#68665D,' +
  'text_muted=#898579,text_faint=#A7A395,icon_muted=#AAA596,accent=#856C4E,' +
  'accent_solid=#29271F,accent_contrast=#FFFDF8,accent_soft=#F0ECE3,accent_soft_selected=#F5F0E6,' +
  'accent_outline=#D8C8A9,icon_tile=#F1EBDD,reasoning_text=#6D6B62,reasoning_muted=#918D80,' +
  'reasoning_bar=#D8C7A0,user_bubble_text=#353127,hero_bg=#29271F,hero_text=#F4EDDF,' +
  'hero_accent=#D9BC83,hero_muted=#C2BCAD,danger_text=#A34F44,danger_fill=#F7EAE6,' +
  'status_good=#667B62,overlay_scrim=#660E0D0A,pill_search_bg=#F5F0E6,pill_search_text=#856C4E,' +
  'pill_search_border=#E6D9BE,chat_surface=#FFFEFB,chat_surface_alt=#FAF8F3,chat_border=#EDE8DE,' +
  'chat_fill=#F2EEE4,sidebar_surface=#F4F1EA,chat_user_bubble=#EFE7D6,chat_user_text=#353127,' +
  'chat_accent=#856C4E,chat_accent_soft=#F5F0E6,chat_accent_soft_selected=#EFE6D2,chat_accent_solid=#29271F,' +
  'chat_accent_contrast=#FFFDF8,chat_accent_outline=#E3D5B8');

const PAPER_DARK: SkinPalette = new SkinPalette(
  'page_bg=#191815,surface=#22211D,surface_alt=#2B2A25,surface_row=#2B2A25,' +
  'fill=#33312B,input_bg=#302F29,divider=#393730,border_soft=#393730,' +
  'border_card=#48453D,text_primary=#E9E4D9,text_title=#F5F0E6,text_secondary=#C4BFB3,' +
  'text_muted=#A29D90,text_faint=#888477,icon_muted=#777267,accent=#D2B67D,' +
  'accent_solid=#D2B67D,accent_contrast=#242119,accent_soft=#343127,accent_soft_selected=#39352A,' +
  'accent_outline=#62553C,icon_tile=#33312B,reasoning_text=#C7C2B6,reasoning_muted=#999386,' +
  'reasoning_bar=#5A5140,user_bubble_text=#EAE3D4,hero_bg=#24231F,hero_text=#F4EDDF,' +
  'hero_accent=#D9BC83,hero_muted=#C2BCAD,danger_text=#E28A7F,danger_fill=#3A2523,' +
  'status_good=#A6C39A,overlay_scrim=#990A0907,pill_search_bg=#343127,pill_search_text=#D2B67D,' +
  'pill_search_border=#62553C,chat_surface=#22211D,chat_surface_alt=#2B2A25,chat_border=#393730,' +
  'chat_fill=#2E2C27,sidebar_surface=#26251F,chat_user_bubble=#39352A,chat_user_text=#EAE3D4,' +
  'chat_accent=#D2B67D,chat_accent_soft=#343127,chat_accent_soft_selected=#39352A,chat_accent_solid=#D2B67D,' +
  'chat_accent_contrast=#242119,chat_accent_outline=#62553C');

// ── jade：青黛。近白底 + 低饱和青绿主色，冷但不刺眼，适合白天长聊。 ──
const JADE_LIGHT: SkinPalette = new SkinPalette(
  'page_bg=#F4F7F5,surface=#FFFFFF,surface_alt=#F6F9F7,surface_row=#F2F6F3,' +
  'fill=#EAF0EB,input_bg=#F1F5F2,divider=#E2E9E4,border_soft=#E4EBE6,' +
  'border_card=#D6E0D9,text_primary=#1E2723,text_title=#131A16,text_secondary=#4F5B54,' +
  'text_muted=#7B8780,text_faint=#9BA69F,icon_muted=#87938C,accent=#2E7D62,' +
  'accent_solid=#2E7D62,accent_contrast=#FFFFFF,accent_soft=#E6F1EC,accent_soft_selected=#DCEDE5,' +
  'accent_outline=#C6DED3,icon_tile=#EAF0EB,reasoning_text=#5D6A62,reasoning_muted=#8A968E,' +
  'reasoning_bar=#BFD6C9,user_bubble_text=#1E2723,hero_bg=#17231D,hero_text=#EFF6F1,' +
  'hero_accent=#8FC9AC,hero_muted=#BFCCC4,danger_text=#B04A3D,danger_fill=#FAEDEA,' +
  'status_good=#3F7D5C,overlay_scrim=#660B120E,pill_search_bg=#E6F1EC,pill_search_text=#2E7D62,' +
  'pill_search_border=#C6DED3,chat_surface=#FFFFFF,chat_surface_alt=#F6F9F7,chat_border=#E2E9E4,' +
  'chat_fill=#EDF2EE,sidebar_surface=#F1F6F3,chat_user_bubble=#DCEDE5,chat_user_text=#1E2723,' +
  'chat_accent=#2E7D62,chat_accent_soft=#E6F1EC,chat_accent_soft_selected=#DCEDE5,chat_accent_solid=#2E7D62,' +
  'chat_accent_contrast=#FFFFFF,chat_accent_outline=#C6DED3');

const JADE_DARK: SkinPalette = new SkinPalette(
  'page_bg=#0E1412,surface=#151B18,surface_alt=#1A211D,surface_row=#1B221E,' +
  'fill=#232C27,input_bg=#1A211D,divider=#28332D,border_soft=#28332D,' +
  'border_card=#35423B,text_primary=#E3EAE5,text_title=#F1F7F3,text_secondary=#B3BEB7,' +
  'text_muted=#86928B,text_faint=#6E7A73,icon_muted=#78847D,accent=#6FB394,' +
  'accent_solid=#6FB394,accent_contrast=#0C1512,accent_soft=#1D2C26,accent_soft_selected=#22352D,' +
  'accent_outline=#34513F,icon_tile=#232C27,reasoning_text=#BAC5BE,reasoning_muted=#87938C,' +
  'reasoning_bar=#335043,user_bubble_text=#E3EAE5,hero_bg=#091009,hero_text=#EFF6F1,' +
  'hero_accent=#8FC9AC,hero_muted=#B7C4BD,danger_text=#E68F84,danger_fill=#33211E,' +
  'status_good=#8FBF9C,overlay_scrim=#99070C0A,pill_search_bg=#1D2C26,pill_search_text=#7DC3A4,' +
  'pill_search_border=#34513F,chat_surface=#151B18,chat_surface_alt=#1A211D,chat_border=#28332D,' +
  'chat_fill=#1F2723,sidebar_surface=#171E1A,chat_user_bubble=#22352D,chat_user_text=#E3EAE5,' +
  'chat_accent=#6FB394,chat_accent_soft=#1D2C26,chat_accent_soft_selected=#22352D,chat_accent_solid=#6FB394,' +
  'chat_accent_contrast=#0C1512,chat_accent_outline=#34513F');

// ── ink：石墨。去彩色化，靠深浅灰度分区，主色是浅灰白，最不抢内容。 ──
const INK_LIGHT: SkinPalette = new SkinPalette(
  'page_bg=#F5F6F7,surface=#FFFFFF,surface_alt=#F7F8F9,surface_row=#F3F4F6,' +
  'fill=#ECEEF0,input_bg=#F3F4F6,divider=#E4E6E9,border_soft=#E6E8EB,' +
  'border_card=#D8DBDF,text_primary=#1F2126,text_title=#15171B,text_secondary=#55585E,' +
  'text_muted=#7F838A,text_faint=#9EA2A8,icon_muted=#8A8E95,accent=#3A3F4B,' +
  'accent_solid=#1F2126,accent_contrast=#FFFFFF,accent_soft=#EBEDF0,accent_soft_selected=#E1E4E9,' +
  'accent_outline=#C9CDD4,icon_tile=#ECEEF0,reasoning_text=#5D6067,reasoning_muted=#8B8F96,' +
  'reasoning_bar=#C5C9D0,user_bubble_text=#1F2126,hero_bg=#15171B,hero_text=#F5F6F8,' +
  'hero_accent=#B9BFCB,hero_muted=#C0C4CB,danger_text=#B0443A,danger_fill=#F8EDEB,' +
  'status_good=#4F7A5E,overlay_scrim=#66090A0C,pill_search_bg=#EBEDF0,pill_search_text=#3A3F4B,' +
  'pill_search_border=#D3D7DD,chat_surface=#FFFFFF,chat_surface_alt=#F7F8F9,chat_border=#E4E6E9,' +
  'chat_fill=#EEF0F2,sidebar_surface=#F2F3F5,chat_user_bubble=#E8EAEE,chat_user_text=#1F2126,' +
  'chat_accent=#3A3F4B,chat_accent_soft=#EBEDF0,chat_accent_soft_selected=#E1E4E9,chat_accent_solid=#1F2126,' +
  'chat_accent_contrast=#FFFFFF,chat_accent_outline=#C9CDD4');

const INK_DARK: SkinPalette = new SkinPalette(
  'page_bg=#0B0C0E,surface=#131417,surface_alt=#18191D,surface_row=#191A1E,' +
  'fill=#212327,input_bg=#18191D,divider=#24262B,border_soft=#24262B,' +
  'border_card=#32353B,text_primary=#E6E8EC,text_title=#F3F5F8,text_secondary=#B4B8BF,' +
  'text_muted=#878B93,text_faint=#6E727A,icon_muted=#787C84,accent=#C9CFD8,' +
  'accent_solid=#C9CFD8,accent_contrast=#0B0C0E,accent_soft=#212427,accent_soft_selected=#262A2F,' +
  'accent_outline=#3A3E45,icon_tile=#212327,reasoning_text=#BBBFC6,reasoning_muted=#878B93,' +
  'reasoning_bar=#3B3F47,user_bubble_text=#E6E8EC,hero_bg=#07080A,hero_text=#F3F5F8,' +
  'hero_accent=#AEB4BE,hero_muted=#B2B6BE,danger_text=#F08A80,danger_fill=#36211E,' +
  'status_good=#8CBC98,overlay_scrim=#9907080A,pill_search_bg=#212427,pill_search_text=#C9CFD8,' +
  'pill_search_border=#3A3E45,chat_surface=#131417,chat_surface_alt=#18191D,chat_border=#24262B,' +
  'chat_fill=#1E2024,sidebar_surface=#16171B,chat_user_bubble=#262A2F,chat_user_text=#E6E8EC,' +
  'chat_accent=#C9CFD8,chat_accent_soft=#212427,chat_accent_soft_selected=#262A2F,chat_accent_solid=#C9CFD8,' +
  'chat_accent_contrast=#0B0C0E,chat_accent_outline=#3A3E45');

export const SKINS: SkinDefinition[] = [
  { id: 'official', name: '官方蓝白', nameEn: 'Official Blue', note: '对话主色蓝，最接近官方 App 的观感', noteEn: 'Blue accent, closest to the official app', light: OFFICIAL_LIGHT, dark: OFFICIAL_DARK },
  { id: 'paper', name: '暖纸墨金', nameEn: 'Warm Paper', note: '米白纸感 + 墨黑主色，长时间阅读最舒服', noteEn: 'Paper-white with ink black, easy on the eyes', light: PAPER_LIGHT, dark: PAPER_DARK },
  { id: 'jade', name: '青黛', nameEn: 'Jade', note: '低饱和青绿，清爽但不刺眼', noteEn: 'Muted teal green, fresh without glare', light: JADE_LIGHT, dark: JADE_DARK },
  { id: 'ink', name: '石墨', nameEn: 'Graphite', note: '去彩色化，只留深浅灰度', noteEn: 'Colorless, pure grey scale', light: INK_LIGHT, dark: INK_DARK }
];

const DEFAULT_SKIN_ID: string = 'official';

let activeId: string = DEFAULT_SKIN_ID;
let activeDark: boolean = false;

/** 皮肤列表（设置页渲染选择器用）。 */
export function skinList(): SkinDefinition[] {
  return SKINS;
}

/** 当前皮肤 id。 */
export function currentSkinId(): string {
  return activeId;
}

/** 按 id 找皮肤；找不到回退默认皮肤（防止脏偏好把界面打空）。 */
export function findSkin(id: string): SkinDefinition {
  for (let i = 0; i < SKINS.length; i++) {
    if (SKINS[i].id === id) {
      return SKINS[i];
    }
  }
  return SKINS[0];
}

/**
 * 取色：当前皮肤 × 当前明暗。
 * Reason: 组件里直接写这个函数（不是 `this.xxx`），全局 @Builder 也能用；刷新靠 @StorageProp 重绘。
 */
export function skinColor(token: string): string {
  const skin: SkinDefinition = findSkin(activeId);
  const palette: SkinPalette = activeDark ? skin.dark : skin.light;
  const value: string = palette.get(token);
  if (value.length > 0) {
    return value;
  }
  // 未登记 token：回退默认浅色皮肤，绝不返回空串（空色 = 透明组件）。
  const fallback: string = SKINS[0].light.get(token);
  return fallback.length > 0 ? fallback : '#000000';
}

/** 自增版本号：让所有 @StorageProp(KEY_SKIN_VERSION) 的组件重绘。 */
function bumpVersion(): void {
  const current: number = AppStorage.get<number>(KEY_SKIN_VERSION) ?? 0;
  AppStorage.setOrCreate<number>(KEY_SKIN_VERSION, current + 1);
}

/** 应用皮肤（内存态 + AppStorage + 重绘）。持久化由调用方决定是否落盘。 */
export function applySkin(id: string): void {
  activeId = findSkin(id).id;
  AppStorage.setOrCreate<string>(KEY_SKIN_ID, activeId);
  bumpVersion();
}

/**
 * 同步明暗：SettingsService 解析出「当前是否深色」后调它。
 * Reason: 明暗与皮肤是两个独立维度（用户可以「暖纸 + 深色」），所以皮肤侧只认一个布尔。
 */
export function syncDarkMode(dark: boolean): void {
  if (activeDark === dark) {
    return;
  }
  activeDark = dark;
  bumpVersion();
}

/** 冷启动/切换皮肤后强制重绘（不改皮肤本身）。 */
export function refreshSkin(): void {
  bumpVersion();
}

/**
 * 冷启动加载：读偏好 → 应用皮肤 → 同步明暗 → 重绘。
 * 失败只记日志并停在默认皮肤，绝不让启动流程卡住。
 */
export async function initSkin(context: common.UIAbilityContext): Promise<string> {
  activeDark = AppStorage.get<boolean>(KEY_APP_DARK) ?? false;
  try {
    const prefs: preferences.Preferences = await preferences.getPreferences(context, { name: PREFS_NAME });
    const stored: preferences.ValueType = await prefs.get(KEY_SKIN_ID, DEFAULT_SKIN_ID);
    const id: string = typeof stored === 'string' ? stored : DEFAULT_SKIN_ID;
    activeId = findSkin(id).id;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'load skin failed, fallback to default: %{public}s', String(err));
    activeId = DEFAULT_SKIN_ID;
  }
  AppStorage.setOrCreate<string>(KEY_SKIN_ID, activeId);
  bumpVersion();
  return activeId;
}

/** 持久化皮肤选择（先就地生效，再落盘；落盘失败不影响本次切换）。 */
export async function persistSkin(context: common.UIAbilityContext, id: string): Promise<void> {
  try {
    const prefs: preferences.Preferences = await preferences.getPreferences(context, { name: PREFS_NAME });
    await prefs.put(KEY_SKIN_ID, id);
    await prefs.flush();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'persist skin failed: %{public}s', String(err));
  }
}
