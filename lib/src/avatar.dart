import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

/// 通用序列帧播放组件：从 `assets/<dir>/<dir>_NN.png` 循环播放。
///
/// 关键点：`dir` 或 `fps` 切换时必须重算帧数与整轮时长，否则会取到不存在的帧
/// （例如 sleep 只有 4 帧、idle 有 5 帧），表现为闪烁或形象显示不全。
class SpriteAnim extends StatefulWidget {
  const SpriteAnim({
    super.key,
    required this.dir,
    this.fps = 6,
    this.fit = BoxFit.contain,
  });

  final String dir;
  final double fps;
  final BoxFit fit;

  @override
  State<SpriteAnim> createState() => _SpriteAnimState();
}

class _SpriteAnimState extends State<SpriteAnim>
    with SingleTickerProviderStateMixin {
  /// 每组动作素材的帧数（与 assets/ 下的 png 数量严格一致）
  static const Map<String, int> kFrameCounts = {
    'egg': 3,
    'idle': 5,
    'eat': 5,
    'happy': 3,
    'roll': 5,
    'hungry': 3,
    'sleep': 4,
    'angry': 3,
    'dance': 5,
    'talk': 3,
    'evolve': 8,
    'final': 5,
  };

  late final AnimationController _c;
  int _idx = 0;
  late int _frames;

  @override
  void initState() {
    super.initState();
    _frames = kFrameCounts[widget.dir] ?? 1;
    _c = AnimationController(vsync: this, duration: _durationFor());
    _c.addListener(() {
      final idx = (_c.value * _frames).floor() % _frames;
      if (idx != _idx) setState(() => _idx = idx);
    });
    _c.repeat();
  }

  /// 整轮时长 = 帧数 × 每帧间隔，避免 N 帧在 1000/fps 内跑完导致疯狂闪烁
  Duration _durationFor() {
    final perFrame = (1000 / widget.fps).round();
    return Duration(milliseconds: (perFrame * _frames).clamp(200, 8000));
  }

  @override
  void didUpdateWidget(covariant SpriteAnim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dir != widget.dir || oldWidget.fps != widget.fps) {
      _frames = kFrameCounts[widget.dir] ?? 1;
      _c.duration = _durationFor();
      _c.value = 0;
      setState(() => _idx = 0);
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.dir}_${(_idx + 1).toString().padLeft(2, '0')}.png';
    return Image.asset(
      'assets/${widget.dir}/$name',
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// 灵宠形象：蛋（点击破壳）／精灵（待机呼吸 + 表情徽标 + 皮肤换色）。
///
/// 相比旧版：
/// - 去掉了破壳时的左右震动与蛋形态的左右轻晃（保留呼吸缩放／裂纹／闪光／蹦出）；
/// - 新增皮肤（颜色矩阵换色）与表情徽标；
/// - 睡眠态改用静态团球帧 + ZZZ 呼吸动画。
class SpiritAvatar extends StatefulWidget {
  const SpiritAvatar({
    super.key,
    required this.phase,
    this.size = 150,
    this.onHatchComplete,
    this.onHatchBlocked,
    this.evo = false,
    this.sleep = false,
    this.action,
    this.expression,
    this.skinId = 'origin',
    this.customImagePath,
    this.showBadge = true,
    this.showStats = false,
  });

  final SpiritPhase phase;
  final double size;
  final VoidCallback? onHatchComplete;

  /// 点击破壳但孵化倒计时未到
  final VoidCallback? onHatchBlocked;
  final bool evo;
  final bool sleep;

  /// 互动动作序列目录：eat / happy / talk / angry / dance / roll / hungry / evolve
  final String? action;

  /// 当前表情（决定徽标与色偏）
  final Expression? expression;

  /// 皮肤 id（origin / moon）
  final String skinId;

  /// 自定义形象：本地图片绝对路径，非空时精灵形态用这张图换皮（静态）
  final String? customImagePath;

  /// 是否显示表情徽标
  final bool showBadge;

  /// 是否在形象下方叠加饱腹度／心情细条
  final bool showStats;

  @override
  State<SpiritAvatar> createState() => _SpiritAvatarState();
}

class _SpiritAvatarState extends State<SpiritAvatar>
    with TickerProviderStateMixin {
  bool _hatching = false;
  bool _justHatched = false;

  /// 待机呼吸（上下浮动 + 轻微缩放）
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// 破壳进度：裂纹 → 闪光 → 蹦出
  late final AnimationController _hatch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  /// 睡眠 ZZZ：一个 Z → 两个 Z → 三个 Z → 抹掉，慢帧率
  late final AnimationController _zzz = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didUpdateWidget(covariant SpiritAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sleepingNow = widget.sleep && widget.phase == SpiritPhase.spirit;
    final sleepingBefore =
        oldWidget.sleep && oldWidget.phase == SpiritPhase.spirit;
    if (sleepingNow != sleepingBefore) {
      if (sleepingNow) {
        _zzz.repeat();
      } else {
        _zzz.stop();
        _zzz.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _hatch.dispose();
    _zzz.dispose();
    super.dispose();
  }

  void _startHatch() {
    if (_hatching) return;
    final remain = SpiritStore.remainingSeconds();
    if (remain > 0) {
      widget.onHatchBlocked?.call();
      return;
    }
    setState(() => _hatching = true);
    _hatch.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _hatching = false;
        _justHatched = true;
      });
      widget.onHatchComplete?.call();
    });
  }

  /// 皮肤换色：原色直接返回，其余套一层颜色矩阵
  Widget _applySkin(Widget child, Skin skin) {
    final m = skin.matrix;
    if (m == null) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(m),
      child: child,
    );
  }

  Widget _badge(Expression expr, double s, {String? override}) {
    final emoji = override ?? expr.badge;
    if (emoji.isEmpty) return const SizedBox.shrink();
    final d = s * 0.24;
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Text(
        emoji,
        style: TextStyle(fontSize: d * 0.58),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final isSpirit = widget.phase == SpiritPhase.spirit;
    final skin = skinById(widget.skinId);
    final expr = widget.expression ?? expressionById('idle');

    if (isSpirit || _justHatched) {
      final action = widget.action;
      final isSleeping = widget.sleep && isSpirit && action == null;
      final custom =
          widget.customImagePath != null && widget.customImagePath!.isNotEmpty;

      Widget body;
      if (isSleeping) {
        // 睡眠：静态团球帧 + 极轻微呼吸 + 动态 ZZZ
        final frame = widget.evo
            ? 'assets/final/final_01.png'
            : 'assets/sleep/sleep_02.png';
        body = Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _idle,
              builder: (context, child) => Transform.scale(
                scale: 1 + _idle.value * 0.015,
                child: child,
              ),
              child: Image.asset(
                frame,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            _ZzzOverlay(controller: _zzz, size: s),
          ],
        );
      } else {
        final dir = action ?? (widget.evo ? 'final' : 'idle');
        final fps = (dir == 'talk' || dir == 'angry') ? 5.0 : 6.0;
        body = AnimatedBuilder(
          animation: _idle,
          builder: (context, child) {
            final t = _idle.value;
            final isAction = action != null || widget.evo;
            return Transform.translate(
              offset: Offset(0, isAction ? 0 : -t * 6),
              child: Transform.scale(
                scale: isAction ? 1.0 : 1 + t * 0.02,
                child: child,
              ),
            );
          },
          child: custom
              ? Image.file(
                  File(widget.customImagePath!),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                )
              : SpriteAnim(dir: dir, fps: fps),
        );
      }

      Widget content = _applySkin(
        SizedBox(width: s, height: s * 1.15, child: body),
        skin,
      );

      if (widget.showStats) {
        content = Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            content,
            Positioned(
              left: -8,
              right: -8,
              bottom: -6,
              child: _MiniStatBars(),
            ),
          ],
        );
      }

      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          content,
          if (widget.showBadge && isSpirit)
            Positioned(
              right: -s * 0.03,
              top: -s * 0.06,
              child: _badge(expr, s, override: isSleeping ? '💤' : null),
            ),
        ],
      );
    }

    if (_hatching) {
      // 破壳：裂纹 → 闪光 → 蹦出（已去掉左右震动）
      return AnimatedBuilder(
        animation: _hatch,
        builder: (context, child) {
          final t = _hatch.value;
          final flash = t >= 0.45 && t <= 0.7
              ? (1 - (t - 0.45) / 0.25).clamp(0.0, 1.0)
              : 0.0;
          final pop = t >= 0.75 ? ((t - 0.75) / 0.25).clamp(0.0, 1.0) : 0.0;
          final eggIdx = t < 0.45 ? 1 : (t < 0.75 ? 2 : 3);

          return Stack(
            alignment: Alignment.center,
            children: [
              if (flash > 0)
                Container(
                  width: s * 1.6,
                  height: s * 1.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(flash * 0.9),
                  ),
                ),
              SizedBox(
                width: s,
                height: s * 1.15,
                child: Image.asset(
                  'assets/egg/egg_${eggIdx.toString().padLeft(2, '0')}.png',
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              if (pop > 0)
                _applySkin(
                  Transform.translate(
                    offset: Offset(0, s * 0.5 * (1 - pop)),
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * pop,
                      child: SizedBox(
                        width: s,
                        height: s * 1.15,
                        child: const SpriteAnim(dir: 'idle', fps: 6),
                      ),
                    ),
                  ),
                  skin,
                ),
            ],
          );
        },
      );
    }

    // 蛋形态：呼吸浮动（已去掉左右轻晃）+ 点击破壳
    return GestureDetector(
      onTap: _startHatch,
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, child) {
          final t = _idle.value;
          return Transform.translate(
            offset: Offset(0, -t * 10),
            child: Transform.scale(scale: 1 + t * 0.04, child: child),
          );
        },
        child: SizedBox(
          width: s,
          height: s * 1.15,
          child: Image.asset(
            'assets/egg/egg_01.png',
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// 形象下方的饱腹度／心情细条（悬浮窗用）
class _MiniStatBars extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _bar('🍽️', SpiritState.satiety, const Color(0xFFFF9800)),
        const SizedBox(width: 6),
        _bar('😊', SpiritState.mood, const Color(0xFFE91E63)),
      ],
    );
  }

  Widget _bar(String icon, int value, Color color) {
    return Expanded(
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 9)),
          const SizedBox(width: 2),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (value / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Colors.white70,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 睡眠 ZZZ 呼吸动画：一个 Z → 两个 Z → 三个 Z → 抹掉，约 3.6s 一轮
class _ZzzOverlay extends StatelessWidget {
  const _ZzzOverlay({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final phase = (t * 4).floor().clamp(0, 3);
        final within = (t * 4) - phase;
        final zCount = phase + 1;
        final opacity = phase == 3 ? 1.0 - within : 0.3 + within * 0.7;
        final base = size * 0.05;
        return IgnorePointer(
          child: Stack(
            children: [
              for (var i = 0; i < zCount; i++)
                Positioned(
                  right: size * (0.02 + i * 0.06),
                  top: -size * (0.04 + i * 0.10) - 4,
                  child: Opacity(
                    opacity: (opacity * (i == 0 ? 1.0 : 0.72))
                        .clamp(0.0, 1.0),
                    child: Text(
                      'Z',
                      style: TextStyle(
                        fontSize: base * (2 + i),
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF8E7CC3),
                        shadows: const [
                          Shadow(color: Colors.black26, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 把形象渲染成一个小缩略图（设置页预览用，静态不播动画）
class AvatarThumb extends StatelessWidget {
  const AvatarThumb({
    super.key,
    required this.dir,
    this.skinId = 'origin',
    this.size = 64,
  });

  final String dir;
  final String skinId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = skinById(skinId);
    final frame = SpriteAnim.kFrameCounts[dir] ?? 1;
    final name = '${dir}_01.png';
    Widget img = Image.asset(
      'assets/$dir/$name',
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    final m = skin.matrix;
    if (m != null) {
      img = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: img);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          img,
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(
              '$frame帧',
              style: const TextStyle(fontSize: 8, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

/// 蛋的静态缩略图
class EggThumb extends StatelessWidget {
  const EggThumb({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/egg/egg_01.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// 供外部计算：动作目录 → 帧数
int framesOf(String dir) => SpriteAnim.kFrameCounts[dir] ?? 1;

/// 供外部计算：随机数（避免引入额外依赖）
int randomInt(int max) {
  if (max <= 1) return 0;
  return math.Random().nextInt(max);
}