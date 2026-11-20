import re, pathlib

src = pathlib.Path(r"D:\Projects\apps\BalanceApp\BalanceApp\entry\src\main\ets\services\SkinService.ets").read_text(encoding="utf-8")
BLOCK_RE = re.compile(r"const (\w+): SkinPalette = new SkinPalette\(\n(.*?)\);", re.S)
PAIR_RE = re.compile(r"([a-z_]+)=(#[0-9A-Fa-f]{6,8})")

palettes = {}
for m in BLOCK_RE.finditer(src):
    palettes[m.group(1)] = dict(PAIR_RE.findall(m.group(2)))
assert len(palettes) == 8, palettes.keys()

# ArkTS token -> Flutter AppColors field
FLUTTER_FIELDS = ["pageBg","surface","surfaceAlt","surfaceRow","fill","inputBg","divider","borderSoft",
  "borderCard","textPrimary","textTitle","textSecondary","textMuted","textFaint","iconMuted","accent",
  "accentSolid","accentContrast","accentSoft","accentSoftSelected","accentOutline","iconTile",
  "reasoningText","reasoningMuted","reasoningBar","userBubbleText","heroBg","heroText","heroAccent",
  "heroMuted","dangerText","dangerFill","statusGood","overlayScrim"]

def snake(field):
    out = []
    for ch in field:
        out.append("_" + ch.lower() if ch.isupper() else ch)
    return "".join(out)

def dart_color(hexv):
    h = hexv.lstrip("#")
    if len(h) == 6:
        h = "FF" + h
    return "Color(0x%s)" % h.upper()

def emit(name, pairs):
    lines = []
    for f in FLUTTER_FIELDS:
        key = snake(f)
        assert key in pairs, (name, key)
        lines.append("  %s: %s," % (f, dart_color(pairs[key])))
    body = "\n".join(lines)
    parts_name = name.split("_")
    camel = parts_name[0].lower() + "".join(p.capitalize() for p in parts_name[1:])
    return "const AppColors %s = AppColors(\n%s\n);\n" % (camel, body)

parts = []
for nm in ["OFFICIAL_LIGHT","OFFICIAL_DARK","PAPER_LIGHT","PAPER_DARK","JADE_LIGHT","JADE_DARK","INK_LIGHT","INK_DARK"]:
    parts.append(emit(nm, palettes[nm]))

header = '''import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Preset skins shared with the HarmonyOS build.
///
/// Business Rule: this file is generated from
/// `BalanceApp/entry/src/main/ets/services/SkinService.ets` so both platforms ship
/// exactly the same hex values. Regenerate with
/// `scripts/gen_flutter_skins.py` after editing the ArkTS palettes; do not hand-edit
/// the `AppColors` constants below.
class AppSkin {
  const AppSkin({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.note,
    required this.noteEn,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final String nameEn;
  final String note;
  final String noteEn;
  final AppColors light;
  final AppColors dark;
}

'''
meta = '''const List<AppSkin> appSkins = <AppSkin>[
  AppSkin(
    id: 'official',
    name: '官方蓝白',
    nameEn: 'Official Blue',
    note: '对话主色蓝，最接近官方 App 的观感',
    noteEn: 'Blue accent, closest to the official app',
    light: OfficialLight,
    dark: OfficialDark,
  ),
  AppSkin(
    id: 'paper',
    name: '暖纸墨金',
    nameEn: 'Warm Paper',
    note: '米白纸感 + 墨黑主色，长时间阅读最舒服',
    noteEn: 'Paper-white with ink black, easy on the eyes',
    light: PaperLight,
    dark: PaperDark,
  ),
  AppSkin(
    id: 'jade',
    name: '青黛',
    nameEn: 'Jade',
    note: '低饱和青绿，清爽但不刺眼',
    noteEn: 'Muted teal green, fresh without glare',
    light: JadeLight,
    dark: JadeDark,
  ),
  AppSkin(
    id: 'ink',
    name: '石墨',
    nameEn: 'Graphite',
    note: '去彩色化，只留深浅灰度',
    noteEn: 'Colorless, pure grey scale',
    light: InkLight,
    dark: InkDark,
  ),
];

const String defaultSkinId = 'official';

/// Looks a skin up by id, falling back to the default (never throws).
AppSkin skinById(String id) {
  for (final AppSkin skin in appSkins) {
    if (skin.id == id) {
      return skin;
    }
  }
  return appSkins.first;
}
'''
out = header + "\n".join(parts) + "\n" + meta
dest = pathlib.Path(r"D:\Projects\apps\BalanceApp\mobile\lib\core\theme\app_skins.dart")
dest.write_text(out, encoding="utf-8")
print("wrote", dest, len(out), "chars")
