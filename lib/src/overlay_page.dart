import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'audio.dart';
import 'brand.dart';
import 'avatar.dart';
import 'chatter.dart';
import 'models.dart';
import 'store.dart';

/// 悬浮窗主体：蛋／精灵 + 喂食 + 摸头 + 扒边缩头 + 漫游 + 时钟徽章 + 表情轮换。
///
/// 拖动由原生 `enableDrag` 接管；原生层已经实现「贴边 35% 探出」的拖动边界，
/// Flutter 层只负责大/小窗切换、漫游与互动逻辑。
class SpiritOverlay extends StatefulWidget {
  const SpiritOverlay({super.key});

  @override
  State<SpiritOverlay> createState() => _SpiritOverlayState();
}

class _SpiritOverlayState extends State<SpiritOverlay> {
  String? _bubble;
  Timer? _bubbleTimer;
  Timer? _decayTimer;
  Timer? _boredTimer;
  Timer? _autoHideTimer;
  Timer? _panelTimer;
  Timer? _sleepTimer;
  Timer? _roamTimer;
  Timer? _moodTimer;
  Timer? _hatchTimer;
  Timer? _actionTimer;
  Timer? _clockTimer;
  StreamSubscription<dynamic>? _overlaySub;

  /// 相位兜底轮询：只在蛋形态期间运行，对齐另一个引擎的破壳结果
  Timer? _phaseWatch;

  SpiritPhase _phase = SpiritPhase.egg;
  bool _loaded = false;
  bool _evolving = false;
  bool _sleeping = false;
  bool _mini = false;
  bool _panelOpen = false;
  String? _action;
  Expression _expr = expressionById('idle');

  /// 大窗尺寸（dp）：宽 200 / 高 240
  ///
  /// 必须与主界面 `showOverlay(height: 240, width: 200)` 一致，
  /// 否则漫游边界与贴边落点会按错误宽度计算。
  static const double _bigW = 200;
  static const double _bigH = 240;

  /// 缩头小人窗尺寸（dp）
  static const double _miniW = 76;
  static const double _miniH = 96;

  /// 缩头时形象的实际绘制尺寸（大于窗口，靠裁剪只露脑袋）
  static const double _peekW = 150;
  static const double _peekH = 172;

  /// 连续闲置这么久（秒）自动入睡
  static const int _sleepIdleSeconds = 300;

  /// 用户设置的灵宠大小（0.6 ~ 1.4）。窗口尺寸与形象绘制尺寸都乘它，
  /// 所以「蛋太大」可以直接把窗口一起缩小，而不是把形象硬塞进大窗口。
  double get _scale => SpiritConfig.petScale.clamp(0.6, 1.4).toDouble();

  // ===== 漫游与坐标 =====
  double _winW = _bigW;
  double _winH = _bigH;
  double _screenW = 0;
  double _screenH = 0;

  /// 漫游当前位置：窗口绝对左缘（dp）
  double _roamX = 0;
  double _roamY = 0;
  int _roamDir = 1;
  int _roamPause = 0;
  bool _roaming = false;

  /// 缩头方向：-1 贴左 / 1 贴右；0 表示当前在大窗
  int _edge = 0;

  /// 上次因主 App 改语音设置而回一句的时间（节流，避免拖语速滑杆时刷屏）
  DateTime? _lastTtsEcho;

  String _clock = '';
  String _date = '';

  int _randomInt(int max) =>
      max <= 1 ? 0 : DateTime.now().microsecondsSinceEpoch % max;

  @override
  void initState() {
    super.initState();
    _overlaySub = FlutterOverlayWindow.overlayListener.listen(_onOverlayEvent);
    _init();
  }

  Future<void> _init() async {
    await SpiritStore.ensureHatchTimer();
    final ph = await SpiritStore.load();
    await SpiritState.load();
    await SpiritConfig.load();
    // 预热 TTS 引擎：设了 8 秒超时，起不来也不会拖住界面，失败原因留给设置页显示。
    SpiritTts.ensure();
    if (!mounted) return;
    setState(() {
      _phase = ph;
      _loaded = true;
      _clock = TimeAware.clockText();
      _date = TimeAware.dateText();
    });
    _winW = _bigW * _scale;
    _winH = _bigH * _scale;
    await _syncScreenSize();
    // 原生首次建窗时把 Dart 传来的 200/240 直接当物理像素用（插件历史行为），
    // 在 2.75 倍屏上逻辑尺寸只剩约 73×87dp：形象被压到底边、气泡没有排布空间。
    // 引擎就绪后主动 resizeOverlay 一次校正到 dp 规格（原生 resize 通道会做 dp→px）。
    await _applyWindowSize(_bigW * _scale, _bigH * _scale);
    _startSleepWatch();
    // 心跳：主界面靠它判断「桌面上的灵宠还在不在」，从而决定台词由谁来说，
    // 避免两个引擎同时读同一句（用户听到的「两个语音读文」）。
    SpiritStore.markOverlayAlive();
    _decayTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      SpiritStore.markOverlayAlive();
      _onDecay();
    });
    _boredTimer = Timer.periodic(const Duration(seconds: 60), (_) => _onBored());
    _roamTimer =
        Timer.periodic(const Duration(milliseconds: 1200), (_) => _onRoamTick());
    _moodTimer = Timer.periodic(const Duration(seconds: 15), (_) => _onMoodTick());
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _onClockTick());
    _startHatchChatter();
    _startPhaseWatch();
    _resetAutoHide();
    // 开窗先亮一句：悬浮态下文字必须能看见（蛋形态由 HatchChatter 的开场台词负责）
    if (_phase == SpiritPhase.spirit) {
      Timer(const Duration(milliseconds: 900), () {
        if (mounted) {
          _showBubble('点我摸摸头 · 双击吐槽 · 长按喂食',
              const Duration(seconds: 6));
        }
      });
    }
  }

  Future<void> _syncScreenSize() async {
    try {
      final size = await FlutterOverlayWindow.getScreenSize();
      if (size != null && size.width > 0) {
        _screenW = size.width;
        _screenH = size.height;
        _roamY = math.max(40.0, _screenH * 0.35);
        _roamX = math.max(8.0, _screenW / 2 - _winW / 2);
      }
    } catch (_) {}
  }

  /// 校正悬浮窗尺寸：原生 resize 通道按 dp→px 换算，与下方所有 dp 常量一致。
  Future<void> _applyWindowSize(double w, double h) async {
    try {
      await FlutterOverlayWindow.resizeOverlay(w.toInt(), h.toInt(), true);
    } catch (_) {}
    _winW = w;
    _winH = h;
  }

  /// 把「窗口绝对左/上缘（dp）」换算成 gravity=CENTER 下的偏移并移动
  Future<void> _moveTo(double left, double top) async {
    if (_screenW <= 0 || _screenH <= 0) return;
    final px = left - _screenW / 2 + _winW / 2;
    final py = top - _screenH / 2 + _winH / 2;
    try {
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(px, py));
    } catch (_) {}
  }

  // ===== 孵化期 =====
  void _startHatchChatter() {
    _hatchTimer?.cancel();
    HatchChatter.reset();
    if (_phase != SpiritPhase.egg) return;
    Timer(const Duration(seconds: 3), () async {
      if (!mounted || _phase != SpiritPhase.egg) return;
      // 主界面刚开过 App、用户紧接着点开悬浮窗时，这句开场白两个引擎都会念；
      // 谁先念谁占位，另一个 90 秒内不重复（否则用户听到同一句被读两遍）。
      if (!await SpiritStore.claimLine('主人，我在蛋里啦，记得喂我呀',
          windowSeconds: 90)) {
        return;
      }
      if (!mounted || _phase != SpiritPhase.egg) return;
      _showBubble('主人，我在蛋里啦，5 分钟后破壳，记得喂我呀~',
          const Duration(seconds: 4));
      SpiritTts.speak('主人，我在蛋里啦，记得喂我呀');
    });
    _hatchTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || _phase != SpiritPhase.egg) {
        _hatchTimer?.cancel();
        return;
      }
      final line = HatchChatter.tick(SpiritStore.remainingSeconds());
      if (line.isEmpty) return;
      // 里程碑文案两边一字不差，另一个引擎刚念过就静默，避免两路语音
      if (!await SpiritStore.claimLine(line)) return;
      if (!mounted) return;
      _showBubble(line, const Duration(seconds: 4));
      SpiritTts.speak(line);
    });
  }

  /// 另一个引擎（主界面）已经破壳：把相位对齐过来，并且**不出声**。
  /// 问候语由亲手破壳的那一侧播过一次了，这里再读一遍就是「两个语音读文」。
  ///
  /// 通道消息之外的兜底轮询：个别 ROM 上跨引擎消息会丢，丢了的后果就是
  /// 悬浮窗一直停在蛋、继续读孵化期台词。
  void _startPhaseWatch() {
    _phaseWatch?.cancel();
    if (_phase != SpiritPhase.egg) return;
    _phaseWatch = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _phase != SpiritPhase.egg) {
        _phaseWatch?.cancel();
        return;
      }
      final ph = await SpiritStore.loadFresh();
      if (!mounted || ph != SpiritPhase.spirit) return;
      _phaseWatch?.cancel();
      _hatchTimer?.cancel();
      setState(() {
        _phase = SpiritPhase.spirit;
        _expr = expressionById('idle');
      });
      _showBubble('破壳啦，我从蛋壳里出来咯~', const Duration(seconds: 3));
    });
  }

  /// 按当前 [_scale] 重设窗口尺寸与落点（主界面拖动「大小」后下发）。
  Future<void> _applyPetScale() async {
    if (_screenW <= 0) await _syncScreenSize();
    if (_mini) {
      final w = _miniW * _scale;
      await _applyWindowSize(w, _miniH * _scale);
      if (_screenW > 0) {
        final left = _edge < 0 ? 0.0 : math.max(0.0, _screenW - w);
        _roamX = left;
        await _moveTo(left, math.max(40.0, _roamY));
      }
    } else {
      final w = _bigW * _scale;
      await _applyWindowSize(w, _bigH * _scale);
      if (_screenW > 0) {
        final left = (_screenW / 2 - w / 2)
            .clamp(5.0, math.max(5.0, _screenW - w - 5))
            .toDouble();
        _roamX = left;
        await _moveTo(left, math.max(40.0, _roamY));
      }
    }
    if (!mounted) return;
    setState(() {});
    _showBubble('大小：${(_scale * 100).round()}%', const Duration(seconds: 2));
    _resetAutoHide();
  }

  // ===== 气泡 =====
  void _showBubble(String text, Duration dur) {
    _bubbleTimer?.cancel();
    if (mounted) setState(() => _bubble = text);
    _bubbleTimer = Timer(dur, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _playAction(String dir, [int ms = 1600]) {
    _actionTimer?.cancel();
    Expression? match;
    for (final e in kExpressions) {
      if (e.dir == dir && e.tint == null) {
        match = e;
        break;
      }
    }
    if (mounted) {
      setState(() {
        _action = dir;
        if (match != null) _expr = match;
      });
    }
    _actionTimer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(() {
        _action = null;
        _expr = expressionById('idle');
      });
    });
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _decayTimer?.cancel();
    _boredTimer?.cancel();
    _autoHideTimer?.cancel();
    _panelTimer?.cancel();
    _actionTimer?.cancel();
    _hatchTimer?.cancel();
    _sleepTimer?.cancel();
    _roamTimer?.cancel();
    _moodTimer?.cancel();
    _clockTimer?.cancel();
    _overlaySub?.cancel();
    _phaseWatch?.cancel();
    // 关窗即清心跳：主界面立刻恢复「台词由我来说」，不用等心跳过期
    SpiritStore.markOverlayDead();
    super.dispose();
  }

  // ===== 主 App 事件同步 =====
  void _onOverlayEvent(dynamic event) {
    if (event == null) return;
    double? op;
    bool petTouch = false;
    String? action;
    int duration = 1600;
    bool? hatchComplete;
    bool? showClock;
    String? skin;
    bool? ttsEnabled;
    String? ttsVoice;
    double? ttsRate;
    double? petScale;
    try {
      dynamic m = event;
      if (event is String) m = jsonDecode(event);
      if (m is Map) {
        op = (m['opacity'] as num?)?.toDouble();
        petTouch = m['petTouch'] == true;
        action = m['action'] as String?;
        duration = (m['duration'] as num?)?.toInt() ?? 1600;
        if (m['hatchComplete'] == true) hatchComplete = true;
        if (m.containsKey('showClock')) showClock = m['showClock'] == true;
        skin = m['skin'] as String?;
        if (m.containsKey('ttsEnabled')) ttsEnabled = m['ttsEnabled'] == true;
        ttsVoice = m['ttsVoice'] as String?;
        ttsRate = (m['ttsRate'] as num?)?.toDouble();
        petScale = (m['petScale'] as num?)?.toDouble();
      }
    } catch (_) {}

    if (op != null) {
      SpiritConfig.opacity = op.clamp(0.4, 1.0).toDouble();
    }
    if (showClock != null) SpiritConfig.showClock = showClock;
    if (skin != null) SpiritConfig.skinId = skin;
    // 语音设置改动：悬浮窗是独立引擎，必须本地更新后再重新下发给 TTS 引擎，
    // 否则主 App 里换了男女声，桌面上说话的还是旧声音（这就是「切了没反应」的根因之一）。
    if (ttsEnabled != null) SpiritConfig.ttsEnabled = ttsEnabled;
    if (ttsVoice != null &&
        (ttsVoice == 'female' ||
            ttsVoice == 'male' ||
            ttsVoice == 'default')) {
      SpiritConfig.ttsVoice = ttsVoice;
    }
    if (ttsRate != null) {
      SpiritConfig.ttsRate = ttsRate.clamp(0.3, 1.0).toDouble();
    }
    if (ttsEnabled != null || ttsVoice != null || ttsRate != null) {
      SpiritTts.refresh();
      final now = DateTime.now();
      if (SpiritConfig.ttsEnabled &&
          (_lastTtsEcho == null ||
              now.difference(_lastTtsEcho!).inSeconds >= 6)) {
        _lastTtsEcho = now;
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (mounted) SpiritTts.speak('主人，我换好声音啦');
        });
      }
    }
    if (petTouch) {
      _wake();
      _resetAutoHide();
    }
    if (action != null) {
      _playAction(action, duration);
    }
    if (hatchComplete == true) {
      _hatchTimer?.cancel();
      _phaseWatch?.cancel();
      _phase = SpiritPhase.spirit;
      // 注意：这里**不播**问候语与破壳音效 —— 破壳是在主界面点的，
      // 声音已经由主界面出过，跟着一起读就是用户听到的「两个语音读文」。
    }
    // 大小缩放：主界面松手后下发，这里重设窗口尺寸并回一句提示
    if (petScale != null) {
      SpiritConfig.petScale = petScale.clamp(0.6, 1.4).toDouble();
      _applyPetScale();
    }
    if (mounted) setState(() {});
  }

  // ===== 时钟徽章 =====
  void _onClockTick() {
    if (!mounted) return;
    setState(() {
      _clock = TimeAware.clockText();
      _date = TimeAware.dateText();
    });
  }

  void _onClockTap() {
    _touchAndReset();
    final line = kCareLines[_randomInt(kCareLines.length)];
    _showBubble('💗 $line', const Duration(seconds: 4));
    SpiritTts.speak(line);
    SpiritSfx.play('click');
  }

  // ===== 漫游 =====
  void _onRoamTick() {
    if (!mounted || !_loaded) return;
    if (_phase != SpiritPhase.spirit) return;
    if (!SpiritConfig.roamEnabled) return;
    if (_mini || _sleeping || _action != null || _panelOpen) return;
    if (DateTime.now().difference(SpiritState.lastInteract).inSeconds < 12) {
      return;
    }
    if (_roamPause > 0) {
      _roamPause--;
      return;
    }
    if (_randomInt(100) < 20) {
      _roamPause = 2 + _randomInt(3);
      return;
    }
    _moveRoam();
  }

  Future<void> _moveRoam() async {
    if (_roaming) return;
    if (_screenW <= 0) {
      await _syncScreenSize();
      if (_screenW <= 0) return;
    }
    _roaming = true;
    try {
      final step = 6.0 + _randomInt(9);
      var nx = _roamX + _roamDir * step;
      if (nx < 5) {
        nx = 5;
        _roamDir = 1;
      }
      if (nx > _screenW - _winW - 5) {
        nx = math.max(5.0, _screenW - _winW - 5);
        _roamDir = -1;
      }
      if (_randomInt(100) < 20) _roamDir = -_roamDir;
      _roamX = nx;
      await _moveTo(nx, _roamY);
    } catch (_) {}
    _roaming = false;
  }

  // ===== 互动 =====
  void _touchAndReset() {
    _wake();
    _resetAutoHide();
  }

  void _resetAutoHide() {
    _autoHideTimer?.cancel();
    if (!SpiritConfig.autoHide || _mini) return;
    _autoHideTimer = Timer(
      Duration(seconds: SpiritConfig.autoHideDelay),
      _goMini,
    );
  }

  /// 闲置 → 扒到最近的屏幕边缘只露一个脑袋
  Future<void> _goMini() async {
    if (!_loaded || _mini) return;
    _mini = true;
    _panelOpen = false;
    _bubbleTimer?.cancel();
    _roamPause = 0;
    if (_screenW <= 0) await _syncScreenSize();
    if (_screenW > 0) {
      final centerX = _roamX + _winW / 2;
      _edge = centerX < _screenW / 2 ? -1 : 1;
    } else {
      _edge = -1;
    }
    if (mounted) setState(() => _bubble = null);
    final mw = _miniW * _scale;
    final mh = _miniH * _scale;
    await _applyWindowSize(mw, mh);
    if (_screenW > 0) {
      final left = _edge < 0 ? 0.0 : _screenW - mw;
      _roamX = left;
      await _moveTo(left, math.max(40.0, _roamY));
    }
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    if (!_mini) return;
    _mini = false;
    _panelOpen = false;
    _bubble = null;
    _edge = 0;
    if (mounted) setState(() {});
    final bw = _bigW * _scale;
    await _applyWindowSize(bw, _bigH * _scale);
    if (_screenW > 0) {
      final left = (_screenW / 2 - bw / 2)
          .clamp(5.0, math.max(5.0, _screenW - bw - 5))
          .toDouble();
      _roamX = left;
      await _moveTo(left, math.max(40.0, _roamY));
    }
    _resetAutoHide();
  }

  Future<void> _onTapMini() async {
    _touchAndReset();
    await _restore();
    await _pet();
  }

  // ===== 睡眠 =====
  void _startSleepWatch() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(const Duration(seconds: _sleepIdleSeconds), () {
      _enterSleep();
    });
  }

  void _enterSleep() {
    if (_phase == SpiritPhase.egg || _sleeping || !mounted) return;
    setState(() {
      _sleeping = true;
      _bubble = null;
      _expr = expressionById('sleep');
    });
    SpiritSfx.play('sleep');
    SpiritTts.speak('好困，我先睡一会啦');
  }

  void _wake() {
    SpiritState.touch();
    if (_sleeping) {
      _sleeping = false;
      if (mounted) {
        setState(() {
          _expr = expressionById('idle');
          _bubble = null;
        });
      }
    }
    _startSleepWatch();
  }

  // ===== 衰减与吐槽 =====
  void _onDecay() {
    SpiritState.decay();
    SpiritState.save();
    if (!mounted) return;
    if (!_sleeping && _phase == SpiritPhase.spirit && SpiritState.satiety < 30) {
      _playAction('hungry', 1600);
      SpiritSfx.play('hungry');
      _showBubble('🍽️ 我饿啦！快喂我~', const Duration(seconds: 4));
    }
    setState(() {});
  }

  void _onBored() {
    if (!_loaded || _sleeping) return;
    if (_phase == SpiritPhase.egg) return;
    final idle = DateTime.now().difference(SpiritState.lastInteract).inSeconds;
    if (idle < 40) return;
    SpiritState.touch();
    _resetAutoHide();
    final text = _randomInt(3) == 0 ? TimeAware.taunt() : _taunt();
    _showBubble(text, const Duration(seconds: 3));
    SpiritTts.speak(text);
  }

  String _taunt() {
    final pool = _phase == SpiritPhase.spirit ? kSpiritTaunts : kTaunts;
    return pool[_randomInt(pool.length)];
  }

  /// 无人搭理时轮换情绪（成功率 1/2，避免过于频繁变化）
  void _onMoodTick() {
    if (!mounted || !_loaded) return;
    if (_phase != SpiritPhase.spirit) return;
    if (_mini || _sleeping || _panelOpen || _action != null) return;
    if (DateTime.now().difference(SpiritState.lastInteract).inSeconds < 20) {
      return;
    }
    if (_randomInt(2) == 0) return;
    final next = kMoodRotationIds[_randomInt(kMoodRotationIds.length)];
    if (next == _expr.id) return;
    final e = expressionById(next);
    setState(() => _expr = e);
    final line = e.line;
    if (line != null && _randomInt(2) == 0) {
      _showBubble(line, const Duration(seconds: 3));
      SpiritTts.speak(line);
    }
  }

  // ===== 互动动作 =====
  void _onTap() {
    _touchAndReset();
    _playAction('talk', 1400);
    final text = _taunt();
    _showBubble(text, const Duration(seconds: 3));
    SpiritTts.speak(text);
    SpiritSfx.play('click');
  }

  Future<void> _pet() async {
    _touchAndReset();
    SpiritState.mood = math.min(100, SpiritState.mood + 10);
    SpiritState.bump(2);
    await SpiritState.save();
    SpiritSfx.play('pet');
    _playAction('happy', 1400);
    _showBubble('💗 摸摸头~ 心情+10 亲密度+2', const Duration(seconds: 3));
    SpiritTts.speak('好舒服呀，再摸摸');
  }

  Future<void> _feed(Food food) async {
    _touchAndReset();
    SpiritState.satiety = math.min(100, SpiritState.satiety + food.satiety);
    SpiritState.mood = math.min(100, SpiritState.mood + food.mood);
    SpiritState.feedCount++;
    SpiritState.bump(5);
    await SpiritState.save();
    SpiritSfx.play('feed');
    if (!mounted) return;
    if (_phase == SpiritPhase.egg) {
      _showBubble('${food.emoji} 蛋壳里都闻到香味啦~ (+${food.satiety})',
          const Duration(seconds: 3));
      SpiritTts.speak('谢谢主人，等我破壳出来再吃个够');
      return;
    }
    _playAction('eat', 1800);
    _showBubble('${food.emoji} 好好吃~(+${food.satiety})', const Duration(seconds: 3));
    SpiritTts.speak('${food.name}好好吃呀，谢谢主人');
    if (!SpiritState.evo &&
        (SpiritState.feedCount >= 10 || SpiritState.affinity >= 80)) {
      await _evolve();
    }
  }

  Future<void> _evolve() async {
    SpiritState.evo = true;
    await SpiritState.save();
    SpiritSfx.play('evolve');
    if (!mounted) return;
    _playAction('evolve', 2200);
    OverlayActionChannel.send('evolve', duration: 2200);
    setState(() {
      _evolving = true;
      _expr = expressionById('final');
    });
    _showBubble('✨ 进化啦！完全体 ✨', const Duration(seconds: 4));
    SpiritTts.speak('哇，我进化啦！');
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    setState(() => _evolving = false);
  }

  void _onHatchComplete() {
    _hatchTimer?.cancel();
    setState(() {
      _phase = SpiritPhase.spirit;
      _expr = expressionById('idle');
    });
    SpiritStore.save(SpiritPhase.spirit);
    OverlayActionChannel.send('hatchComplete');
    SpiritSfx.play('hatch');
    final greeting = TimeAware.greeting();
    _showBubble(greeting, const Duration(seconds: 3));
    SpiritTts.speak(greeting);
  }

  /// 悬浮窗里点蛋：先过孵化倒计时
  void _onEggTap() {
    _touchAndReset();
    if (SpiritStore.remainingSeconds() > 0) {
      _onHatchBlocked();
      return;
    }
    _onHatchComplete();
  }

  void _onEggPoke() {
    _touchAndReset();
    const lines = HatchChatter.idleLines;
    final line = lines[_randomInt(lines.length)];
    _showBubble(line, const Duration(seconds: 3));
    SpiritTts.speak(line);
  }

  void _onHatchBlocked() {
    final sec = SpiritStore.remainingSeconds();
    _showBubble('⏳ 还在孵化… ${sec ~/ 60}分${sec % 60}秒后可破壳',
        const Duration(seconds: 3));
  }

  void _openPanel() {
    _touchAndReset();
    _panelTimer?.cancel();
    setState(() => _panelOpen = true);
    _panelTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _panelOpen = false);
    });
  }

  // ===== 复用组件 =====
  Widget _roundBtn({
    required VoidCallback onTap,
    required String emoji,
    required double s,
    String? label,
    String? iconPath,
    bool danger = false,
  }) {
    // 按钮图标优先用打包好的道具贴片（assets/items），无贴片时退回 emoji。
    // 这些贴片以前只声明不引用，等于白占包体；现在喂食/摸摸按钮实际用上。
    Widget icon(double size) {
      if (iconPath == null) return Text(emoji, style: TextStyle(fontSize: size));
      return Image.asset(
        iconPath,
        width: size * 1.15,
        height: size * 1.15,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Text(emoji, style: TextStyle(fontSize: size)),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: s,
        height: label == null ? s : s + 14,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          shape: label == null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: label == null ? null : BorderRadius.circular(10),
          border: Border.all(color: danger ? Colors.redAccent : Colors.black12),
        ),
        // emoji 在部分系统字体缺失时渲染空白，补贴片或文字标签兜底
        child: label == null
            ? icon(s * 0.62)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon(s * 0.5),
                  const SizedBox(height: 1),
                  Text(label,
                      style: const TextStyle(fontSize: 9, color: Colors.black87)),
                ],
              ),
      ),
    );
  }

  Widget _statBar(String icon, int value, Color color) {
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

  Widget _bubbleWidget({double maxWidth = 160}) {
    final text = _bubble;
    if (text == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _clockBadge() {
    final on = SpiritConfig.showClock;
    if (!on || _mini) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _onClockTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _clock,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B5AA8),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _date,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar({required double size, bool showBadge = true}) {
    return SpiritAvatar(
      phase: _phase,
      size: size,
      evo: SpiritState.evo,
      sleep: _sleeping,
      action: _action,
      expression: _expr,
      skinId: SpiritConfig.skinId,
      showBadge: showBadge,
      onHatchComplete: _onHatchComplete,
      onHatchBlocked: _onHatchBlocked,
      customImagePath:
          SpiritConfig.customAvatarPath.isEmpty ? null : SpiritConfig.customAvatarPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 缩头态：只露一个脑袋，点一下恢复 + 摸头
          if (_mini) {
            final pw = _peekW * _scale;
            final ph = _peekH * _scale;
            return Opacity(
              opacity: SpiritConfig.opacity,
              child: GestureDetector(
                onTap: _onMiniTap,
                onDoubleTap: _onTap,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: SizedBox(
                      width: pw,
                      height: ph,
                      child: _avatar(size: pw, showBadge: false),
                    ),
                  ),
                ),
              ),
            );
          }

          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final center = Offset(w / 2, h / 2);

          // 顶部留给气泡、底部留给细条与喂食面板，形象整盒（size × size*1.15）
          // 只在中段排布。旧版把形象上缘硬编码成 max(46dp, ...)，窗口一旦被系统
          // 压小就会把蛋挤到窗口底边、细条横切蛋身，看起来就是「蛋不圆」。
          const double reserveTop = 34;
          const double reserveBottom = 52;
          final availH = math.max(44.0, h - reserveTop - reserveBottom);
          final availW = math.max(44.0, w - 8);
          final size = math.min(
            math.min(availW * 0.86, availH / 1.15),
            w * 0.62,
          );
          const btnSize = 26.0;
          final boxH = size * 1.15;
          final avatarTop = reserveTop + math.max(0.0, (availH - boxH) / 2);
          final avatarBottom = avatarTop + boxH;
          final barsW = math.min(124.0, math.max(64.0, w - 16));
          final barsTop =
              math.min(avatarBottom + 2, math.max(4.0, h - reserveBottom));
          final panelTop =
              math.min(barsTop + 14, math.max(4.0, h - btnSize - 18));
          final bubbleMax = math.max(80.0, w - 16);

          return Opacity(
            opacity: SpiritConfig.opacity,
            child: Stack(
              children: [
                if (_evolving)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.85),
                          boxShadow: const [
                            BoxShadow(color: Colors.amberAccent, blurRadius: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 灵宠
                Positioned(
                  left: center.dx - size / 2,
                  top: avatarTop,
                  child: GestureDetector(
                    onTap: _phase == SpiritPhase.egg ? _onEggTap : _pet,
                    onDoubleTap: _phase == SpiritPhase.egg ? _onEggPoke : _onTap,
                    onLongPress: _openPanel,
                    child: _avatar(size: size),
                  ),
                ),
                // 气泡（排在灵宠之后，避免被身体遮挡）
                Positioned(
                  left: 4,
                  right: 4,
                  top: 4,
                  child: _bubbleWidget(maxWidth: bubbleMax),
                ),
                // 饱腹度/心情细条
                Positioned(
                  left: center.dx - barsW / 2,
                  top: barsTop,
                  child: SizedBox(
                    width: barsW,
                    child: Row(
                      children: [
                        _statBar('🍽️', SpiritState.satiety, const Color(0xFFFF9800)),
                        const SizedBox(width: 6),
                        _statBar('😊', SpiritState.mood, const Color(0xFFE91E63)),
                      ],
                    ),
                  ),
                ),
                // 操作面板（长按呼出）
                // 面板比窗口宽时整体缩放，窗口被压小也不会把按钮切掉
                if (_panelOpen)
                  Positioned(
                    left: 2,
                    right: 2,
                    top: panelTop,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        children: [
                          for (final f in kFoods)
                            _roundBtn(
                              onTap: () => _feed(f),
                              emoji: f.emoji,
                              iconPath: f.icon,
                              label: f.name,
                              s: btnSize,
                            ),
                          _roundBtn(
                            onTap: _pet,
                            emoji: '💗',
                            iconPath: kPetIconAsset,
                            label: '摸摸',
                            s: btnSize,
                          ),
                          _roundBtn(
                            onTap: _goMini,
                            emoji: '🫥',
                            label: '扒边',
                            s: btnSize,
                            danger: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                // 时钟/日期徽章（点一下给一句关心话）；面板展开时让位，避免叠字
                if (SpiritConfig.showClock && !_panelOpen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 4,
                    child: Center(child: _clockBadge()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _onMiniTap() async {
    await _onTapMini();
  }
}