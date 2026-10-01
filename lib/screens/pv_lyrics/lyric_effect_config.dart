import 'dart:convert';
import 'dart:math' as math;

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
/// 保持动效。当前只保留抖动。
///
/// 旧版本还有波浪/呼吸/漂移/静止，现已移除；
/// 枚举值保留一个成员是为了让已保存的旧配置（旧值为 wave/breathe/…）
/// 能通过 pick() 平滑回落到 jitter，而不是变成 null。
enum LyricHold {
  jitter('抖动', '低频位置抖动');

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

/// 句与句之间的转场。
///
/// 关键设计（参考 folia-major 的 temperaTransitions / lumiereTransitions）：
/// **出场与进场走同一条向量**，所以交接在屏幕上的运动方向始终不变，
/// 读起来是一段连续的移动，而不是「退回去再推进去」。
enum LyricTransition {
  none('沿用入场/出场', '不使用转场'),
  lightsOut('熄灯', '透明度收光后换句'),
  flareCut('闪白', '轻微放大 + 模糊峰值落在边界'),
  focusPull('拉焦', '模糊出场、清晰进场'),
  cameraPan('推移', '整句沿同一向量平移交接'),
  shapeCarry('溶入', '漂移中放大并虚化，像被抽出焦点'),
  blockWipe('擦除', '整句横穿画面完成交接');

  const LyricTransition(this.label, this.desc);
  final String label;
  final String desc;
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

  /// 扫字高亮（卡拉OK）：已唱部分用强调色逐字扫过
  final bool sweep;

  /// 随机特效：每首歌自动随机一套版式/动画/文本
  final bool random;

  /// 镜头追踪（Z 轴穿越）：当前句从纵深逼近焦点再掠过镜头，
  /// 上一句上浮消失、下一句从深处浮现。
  final bool fly;

  /// 句与句之间的转场。选中后会接管入场/出场的位移。
  final LyricTransition transition;

  const LyricEffectConfig({
    this.layout = LyricLayout.huge,
    this.entrance = LyricEntrance.pop,
    this.hold = LyricHold.jitter,
    this.exit = LyricExit.shrink,
    this.treat = LyricTreat.glow,
    this.palette = LyricPalette.noir,
    this.motion = 1.0,
    this.sweep = true,
    this.random = false,
    this.fly = false,
    this.transition = LyricTransition.none,
  });

  LyricEffectConfig copyWith({
    LyricLayout? layout,
    LyricEntrance? entrance,
    LyricHold? hold,
    LyricExit? exit,
    LyricTreat? treat,
    LyricPalette? palette,
    double? motion,
    bool? sweep,
    bool? random,
    bool? fly,
    LyricTransition? transition,
  }) {
    return LyricEffectConfig(
      layout: layout ?? this.layout,
      entrance: entrance ?? this.entrance,
      hold: hold ?? this.hold,
      exit: exit ?? this.exit,
      treat: treat ?? this.treat,
      palette: palette ?? this.palette,
      motion: motion ?? this.motion,
      sweep: sweep ?? this.sweep,
      random: random ?? this.random,
      fly: fly ?? this.fly,
      transition: transition ?? this.transition,
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
        'sweep': sweep,
        'random': random,
        'fly': fly,
        'transition': transition.name,
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
      hold: pick(LyricHold.values, json['hold'] as String?, LyricHold.jitter),
      exit: pick(LyricExit.values, json['exit'] as String?, LyricExit.shrink),
      treat: pick(LyricTreat.values, json['treat'] as String?, LyricTreat.glow),
      palette: pick(LyricPalette.values, json['palette'] as String?, LyricPalette.noir),
      motion: (json['motion'] as num?)?.toDouble() ?? 1.0,
      sweep: json['sweep'] as bool? ?? true,
      random: json['random'] as bool? ?? false,
      fly: json['fly'] as bool? ?? false,
      transition: pick(LyricTransition.values, json['transition'] as String?, LyricTransition.none),
    );
  }

  /// 随机模式：按种子生成一套特效组合。
  /// 同一首歌内稳定（换歌会换一套），避免每帧乱跳。
  ///
  /// 注意：**配色不参与随机**（用 [keepPalette]），
  /// 否则每句都换整屏底色会疯狂闪屏。
  factory LyricEffectConfig.randomized(int seed, {LyricPalette? keepPalette}) {
    double h(int salt) {
      final x = math.sin((seed + salt) * 127.1 + 311.7) * 43758.5453;
      return x - x.floor();
    }

    final layouts = LyricLayout.values;
    final entrances = LyricEntrance.values;
    final exits = LyricExit.values;
    final treats = LyricTreat.values;
    final palettes = LyricPalette.values;
    // 转场不参与随机：它描述的是「上一句→这一句」的交接，
    // 而随机是按当前句种子算的，同一句的转场必须稳定。
    final transitions = LyricTransition.values;

    return LyricEffectConfig(
      layout: layouts[(h(1) * layouts.length).floor().clamp(0, layouts.length - 1)],
      entrance: entrances[(h(2) * entrances.length).floor().clamp(0, entrances.length - 1)],
      hold: LyricHold.jitter, // 保持只剩抖动，不参与随机
      exit: exits[(h(4) * exits.length).floor().clamp(0, exits.length - 1)],
      treat: treats[(h(5) * treats.length).floor().clamp(0, treats.length - 1)],
      palette: keepPalette ??
          palettes[(h(6) * palettes.length).floor().clamp(0, palettes.length - 1)],
      motion: 0.75 + h(7) * 0.6,
      sweep: h(8) > 0.25,
      random: true,
      fly: h(9) > 0.5,
      transition: transitions[(h(10) * transitions.length).floor().clamp(0, transitions.length - 1)],
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
///
/// [onChanged] 每次改动立即回调，面板还开着就已经把新配置推给调用方。
/// 不传则只落盘（设置页只需持久化，不需要实时预览）。
Future<void> showLyricEffectSheet(BuildContext context,
    {ValueChanged<LyricEffectConfig>? onChanged}) async {
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
          // 立即生效：不等面板关闭，调用方当场就能重建
          onChanged?.call(c);
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
                      _ToggleRow(
                        title: '扫字高亮',
                        desc: '已唱部分用强调色逐字扫过（卡拉OK）',
                        value: cfg.sweep,
                        accent: cfg.palette.accent,
                        onChanged: (v) => apply(cfg.copyWith(sweep: v)),
                      ),
                      const SizedBox(height: 6),
                      _ToggleRow(
                        title: '镜头追踪',
                        desc: 'Z 轴穿越：当前句从纵深逼近再掠过镜头，'
                            '上下句在景深中进出（会接管入场/出场位移）',
                        value: cfg.fly,
                        accent: cfg.palette.accent,
                        onChanged: (v) => apply(cfg.copyWith(fly: v)),
                      ),
                      const SizedBox(height: 6),
                      _ToggleRow(
                        title: '随机特效',
                        desc: '每一句歌词随机一套版式 / 动画 / 文本（配色不变）',
                        value: cfg.random,
                        accent: cfg.palette.accent,
                        onChanged: (v) => apply(cfg.copyWith(random: v)),
                      ),
                      const SizedBox(height: 22),
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
                      _Section<LyricTransition>(
                        title: '转场',
                        values: LyricTransition.values,
                        cfg: cfg,
                        labelOf: (e) => e.label,
                        descOf: (e) => e.desc,
                        isSelected: (e) => e == cfg.transition,
                        onSelect: (v) => apply(cfg.copyWith(transition: v)),
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

class _ToggleRow extends StatelessWidget {
  final String title;
  final String desc;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.title,
    required this.desc,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C21),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: value ? accent : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        color: value ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: accent,
            onChanged: onChanged,
          ),
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
