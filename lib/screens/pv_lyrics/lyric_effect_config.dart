import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌词版式
enum LyricLayout {
  /// 巨号铺满（默认）
  huge('巨号铺满', '单句占满 98% 屏高'),
  /// 居中常规
  center('居中', '中等字号居中'),
  /// 残像堆叠
  stack('残像堆叠', '当前句下方多份递减残影'),
  /// 跑马灯
  marquee('跑马灯', '上下行横向滚动'),
  /// 满屏铺贴
  tile('满屏铺贴', '整句平铺成背景墙'),
  /// 竖排
  vertical('竖排', '单字竖排如书');

  const LyricLayout(this.label, this.desc);
  final String label;
  final String desc;
}

/// 入场动画
enum LyricEntrance {
  pop('弹跳', '缩放过冲 + 倾斜回正'),
  spin('旋转', '大角度旋入'),
  drop('落下', '重力坠落回弹'),
  type('打字', '逐字显现'),
  zoom('缩放', '由远推近 + 虚焦'),
  blur('虚化', '模糊转清晰'),
  wipe('擦除', '横向擦入');

  const LyricEntrance(this.label, this.desc);
  final String label;
  final String desc;
}

/// 保持段动效
enum LyricHold {
  wave('波浪', '逐字正弦起伏'),
  breathe('呼吸', '整句缓慢缩放'),
  jitter('抖动', '低频位置抖动'),
  drift('漂移', '缓慢横移并放大'),
  still('静止', '不做额外动效');

  const LyricHold(this.label, this.desc);
  final String label;
  final String desc;
}

/// 出场动画
enum LyricExit {
  none('无', '直接切换'),
  shrink('缩小', '缩放淡出'),
  explode('炸裂', '向四周飞散'),
  blurOut('虚化', '模糊淡出'),
  wipeOut('擦除', '横向擦出');

  const LyricExit(this.label, this.desc);
  final String label;
  final String desc;
}

/// 文本特效（同时只开一种，保持画面干净）
enum LyricTreat {
  none('素色', '纯色填充'),
  outline('描边', '空心字'),
  strokeFill('粗描边', '强调色描边 + 填充'),
  glow('辉光', '双色光晕'),
  neon('霓虹', '高亮描边 + 闪烁光管'),
  gradient('渐变', '竖向双色渐变'),
  chroma('重色差', '加强 RGB 错位'),
  marker('高亮', '演唱进度底色扫过');

  const LyricTreat(this.label, this.desc);
  final String label;
  final String desc;
}

/// 歌词配色方案（取自 JIZURA 各 style）
enum LyricPalette {
  noir('夜黑', Color(0xFF060607), Color(0xFFF5EEEA), Color(0xFFBDB6B2),
      Color(0xFFF5A50C), Color(0xFF16F4D4)),
  crimson('绯红', Color(0xFF150509), Color(0xFFFF3D6E), Color(0xFFFF9DB6),
      Color(0xFFFFFFFF), Color(0xFF39F2C8)),
  mint('薄荷', Color(0xFF0A0E0D), Color(0xFFE6FFF5), Color(0xFF7FB9A8),
      Color(0xFF9CFF3A), Color(0xFF2EE6C8)),
  caution('警示', Color(0xFF18181A), Color(0xFFF4D21F), Color(0xFFDDD6B0),
      Color(0xFFE0231C), Color(0xFFFFFFFF)),
  hud('HUD', Color(0xFF0B0B0C), Color(0xFFFFFFFF), Color(0xFF9A9796),
      Color(0xFFF25A2B), Color(0xFF7FD7FF)),
  blueprint('蓝图', Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFF9A9AFF),
      Color(0xFF1B1BE8), Color(0xFF8C8CFF));

  const LyricPalette(this.label, this.bg, this.fg, this.sub, this.accent,
      this.accent2);
  final String label;
  final Color bg, fg, sub, accent, accent2;
}

/// 特效配置
class LyricEffectConfig {
  final LyricLayout layout;
  final LyricEntrance entrance;
  final LyricHold hold;
  final LyricExit exit;
  final LyricTreat treat;
  final LyricPalette palette;
  /// 波浪/呼吸等动效强度 0~1.5
  final double motion;

  const LyricEffectConfig({
    this.layout = LyricLayout.huge,
    this.entrance = LyricEntrance.pop,
    this.hold = LyricHold.wave,
    this.exit = LyricExit.shrink,
    this.treat = LyricTreat.glow,
    this.palette = LyricPalette.noir,
    this.motion = 1.0,
  });

  LyricEffectConfig copyWith({
    LyricLayout? layout,
    LyricEntrance? entrance,
    LyricHold? hold,
    LyricExit? exit,
    LyricTreat? treat,
    LyricPalette? palette,
    double? motion,
  }) {
    return LyricEffectConfig(
      layout: layout ?? this.layout,
      entrance: entrance ?? this.entrance,
      hold: hold ?? this.hold,
      exit: exit ?? this.exit,
      treat: treat ?? this.treat,
      palette: palette ?? this.palette,
      motion: motion ?? this.motion,
    );
  }

  Map<String, dynamic> toJson() => {
        'layout': layout.name,
        'entrance': entrance.name,
        'hold': hold.name,
        'exit': exit.name,
        'treat': treat.name,
        'palette': palette.name,
        'motion': motion,
      };

  factory LyricEffectConfig.fromJson(Map<String, dynamic> json) {
    T pick<T extends Enum>(List<T> values, String? name, T fallback) {
      if (name == null) return fallback;
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    return LyricEffectConfig(
      layout: pick(LyricLayout.values, json['layout'] as String?, LyricLayout.huge),
      entrance: pick(LyricEntrance.values, json['entrance'] as String?, LyricEntrance.pop),
      hold: pick(LyricHold.values, json['hold'] as String?, LyricHold.wave),
      exit: pick(LyricExit.values, json['exit'] as String?, LyricExit.shrink),
      treat: pick(LyricTreat.values, json['treat'] as String?, LyricTreat.glow),
      palette: pick(LyricPalette.values, json['palette'] as String?, LyricPalette.noir),
      motion: (json['motion'] as num?)?.toDouble() ?? 1.0,
    );
  }

  // ---------------- 持久化 ----------------

  static const _key = 'lyric_effect_config';

  static Future<LyricEffectConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const LyricEffectConfig();
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return LyricEffectConfig.fromJson(json);
    } catch (_) {
      return const LyricEffectConfig();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(toJson()));
    } catch (_) {}
  }
}

/// 歌词特效选择面板（供歌词页与设置页共用）
Future<void> showLyricEffectSheet(BuildContext context) async {
  var cfg = await LyricEffectConfig.load();
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF141418),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        void apply(LyricEffectConfig c) {
          setSheetState(() => cfg = c);
          c.save();
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                  child: Row(
                    children: [
                      const Text('歌词特效',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => apply(const LyricEffectConfig()),
                        child: const Text('恢复默认',
                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF26262C)),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      _PaletteRow(cfg: cfg, apply: apply),
                      const SizedBox(height: 22),
                      _Section<LyricLayout>(
                        title: '版式',
                        values: LyricLayout.values,
                        cfg: cfg,
                        labelOf: (e) => e.label,
                        descOf: (e) => e.desc,
                        isSelected: (e) => e == cfg.layout,
                        onSelect: (v) => apply(cfg.copyWith(layout: v)),
                      ),
                      _Section<LyricEntrance>(
                        title: '入场',
                        values: LyricEntrance.values,
                        cfg: cfg,
                        labelOf: (e) => e.label,
                        descOf: (e) => e.desc,
                        isSelected: (e) => e == cfg.entrance,
                        onSelect: (v) => apply(cfg.copyWith(entrance: v)),
                      ),
                      _Section<LyricHold>(
                        title: '保持',
                        values: LyricHold.values,
                        cfg: cfg,
                        labelOf: (e) => e.label,
                        descOf: (e) => e.desc,
                        isSelected: (e) => e == cfg.hold,
                        onSelect: (v) => apply(cfg.copyWith(hold: v)),
                      ),
                      _Section<LyricExit>(
                        title: '出场',
                        values: LyricExit.values,
                        cfg: cfg,
                        labelOf: (e) => e.label,
                        descOf: (e) => e.desc,
                        isSelected: (e) => e == cfg.exit,
                        onSelect: (v) => apply(cfg.copyWith(exit: v)),
                      ),
                      _Section<LyricTreat>(
                        title: '文本特效',
                        values: LyricTreat.values,
                        cfg: cfg,
                        labelOf: (e) => e.label,
                        descOf: (e) => e.desc,
                        isSelected: (e) => e == cfg.treat,
                        onSelect: (v) => apply(cfg.copyWith(treat: v)),
                      ),
                      const SizedBox(height: 6),
                      _MotionRow(cfg: cfg, apply: apply),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _chip({
  required String label,
  required bool selected,
  required Color accent,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2A2A32) : const Color(0xFF1C1C21),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? accent : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white60,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

class _Section<T> extends StatelessWidget {
  final String title;
  final List<T> values;
  final LyricEffectConfig cfg;
  final String Function(T) labelOf;
  final String Function(T) descOf;
  final bool Function(T) isSelected;
  final ValueChanged<T> onSelect;

  const _Section({
    required this.title,
    required this.values,
    required this.cfg,
    required this.labelOf,
    required this.descOf,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in values)
                _chip(
                  label: labelOf(v),
                  selected: isSelected(v),
                  accent: cfg.palette.accent,
                  onTap: () => onSelect(v),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(descOf(values.firstWhere(isSelected, orElse: () => values.first)),
              style: const TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final LyricEffectConfig cfg;
  final ValueChanged<LyricEffectConfig> apply;
  const _PaletteRow({required this.cfg, required this.apply});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('配色',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final p in LyricPalette.values)
              GestureDetector(
                onTap: () => apply(cfg.copyWith(palette: p)),
                child: Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: p.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cfg.palette == p
                          ? p.accent
                          : Colors.white.withValues(alpha: 0.12),
                      width: cfg.palette == p ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _dot(p.fg),
                          const SizedBox(width: 4),
                          _dot(p.accent),
                          const SizedBox(width: 4),
                          _dot(p.accent2),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.label,
                          style: TextStyle(
                              color: p.fg.withValues(alpha: 0.85), fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

class _MotionRow extends StatelessWidget {
  final LyricEffectConfig cfg;
  final ValueChanged<LyricEffectConfig> apply;
  const _MotionRow({required this.cfg, required this.apply});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('动效强度',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            activeTrackColor: cfg.palette.accent,
            thumbColor: cfg.palette.accent,
            inactiveTrackColor: Colors.white12,
          ),
          child: Slider(
            value: cfg.motion.clamp(0.0, 1.5),
            max: 1.5,
            onChanged: (v) => apply(cfg.copyWith(motion: v)),
          ),
        ),
        Text('${(cfg.motion * 100).round()}%',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}
