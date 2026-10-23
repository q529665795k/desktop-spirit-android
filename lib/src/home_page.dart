import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'audio.dart';
import 'avatar.dart';
import 'brand.dart';
import 'chatter.dart';
import 'models.dart';
import 'store.dart';

/// 主界面：形象预览 + 养成 + 全部设置。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _permission = false;
  bool _overlayVisible = false;
  String _status = '检查权限中…';
  SpiritPhase _phase = SpiritPhase.egg;
  bool _loaded = false;

  double _opacity = 1.0;
  bool _autoHide = true;
  int _autoHideDelay = 20;
  double _ttsRate = 0.5;
  String _ttsVoice = 'female';
  bool _ttsEnabled = true;
  bool _roamEnabled = true;
  bool _sfxEnabled = true;
  bool _showClock = true;
  String _skinId = 'origin';
  String _customAvatarPath = '';

  // 预览用的动作与表情
  String? _action;
  Timer? _actionTimer;
  Expression _previewExpr = expressionById('idle');

  // 孵化期气泡
  Timer? _hatchTimer;
  Timer? _eggBubbleTimer;
  String? _eggBubble;

  void _playAction(String dir, [int ms = 1800]) {
    _actionTimer?.cancel();
    setState(() => _action = dir);
    _actionTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _action = null);
    });
  }

  void _showEggBubble(String text, {int seconds = 3}) {
    _eggBubbleTimer?.cancel();
    setState(() => _eggBubble = text);
    _eggBubbleTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _eggBubble = null);
    });
  }

  /// 主界面孵化期互动：里程碑倒计时 + 撒娇喊饿
  void _startHatchChatter() {
    _hatchTimer?.cancel();
    HatchChatter.reset();
    if (_phase != SpiritPhase.egg) return;
    Timer(const Duration(seconds: 2), () {
      if (mounted && _phase == SpiritPhase.egg) {
        _showEggBubble('主人，我在蛋里啦，5 分钟后破壳，记得喂我呀~', seconds: 4);
        SpiritTts.speak('主人，我在蛋里啦，记得喂我呀');
      }
    });
    _hatchTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || _phase != SpiritPhase.egg) {
        _hatchTimer?.cancel();
        return;
      }
      final line = HatchChatter.tick(SpiritStore.remainingSeconds());
      if (line.isNotEmpty) {
        _showEggBubble(line, seconds: 4);
        SpiritTts.speak(line);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _loadPhase();
    SpiritState.load().then((_) {
      if (mounted) setState(() {});
    });
    SpiritConfig.load().then((_) {
      if (!mounted) return;
      setState(() {
        _opacity = SpiritConfig.opacity;
        _autoHide = SpiritConfig.autoHide;
        _autoHideDelay = SpiritConfig.autoHideDelay;
        _ttsRate = SpiritConfig.ttsRate;
        _ttsVoice = SpiritConfig.ttsVoice;
        _ttsEnabled = SpiritConfig.ttsEnabled;
        _roamEnabled = SpiritConfig.roamEnabled;
        _sfxEnabled = SpiritConfig.sfxEnabled;
        _showClock = SpiritConfig.showClock;
        _skinId = SpiritConfig.skinId;
        _customAvatarPath = SpiritConfig.customAvatarPath;
      });
    });
    // 启动就预热语音引擎：状态行能立刻反映引擎可用性（Android 11+ 少声明
    // TTS_SERVICE 可见性时引擎会静默起不来），第一句台词也不会因冷启动被吞。
    SpiritTts.ensure().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _actionTimer?.cancel();
    _hatchTimer?.cancel();
    _eggBubbleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 主界面与悬浮窗是两个独立引擎，悬浮窗破壳只写了 SharedPreferences，
    // 主界面内存里的 phase 仍是蛋；切回前台时重新读取即可，不用重开软件。
    if (state == AppLifecycleState.resumed) {
      _loadPhase();
      SpiritState.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _loadPhase() async {
    await SpiritStore.ensureHatchTimer();
    final ph = await SpiritStore.load();
    if (!mounted) return;
    setState(() {
      _phase = ph;
      _loaded = true;
    });
    if (ph == SpiritPhase.egg && SpiritStore.remainingSeconds() > 0) {
      _startHatchChatter();
    }
  }

  Future<void> _checkPermission() async {
    final ok = await FlutterOverlayWindow.isPermissionGranted();
    if (!mounted) return;
    setState(() {
      _permission = ok;
      _status = ok ? '悬浮窗权限：已授权' : '悬浮窗权限：未授权';
    });
  }

  Future<void> _start() async {
    // MIUI 上 isPermissionGranted 在刚授权后仍可能误报 false，
    // 因此先请求权限，再无论查询结果如何都乐观尝试一次 showOverlay。
    var granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      try {
        await FlutterOverlayWindow.requestPermission();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 400));
      granted = await FlutterOverlayWindow.isPermissionGranted();
    }
    try {
      await FlutterOverlayWindow.showOverlay(
        height: 240,
        width: 200,
        overlayTitle: kAppName,
        overlayContent: '灵宠悬浮窗',
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
      );
      if (!mounted) return;
      setState(() {
        _permission = true;
        _overlayVisible = true;
        _status = '悬浮窗权限：已授权';
      });
      SpiritSfx.play('click');
      return;
    } catch (_) {
      // showOverlay 失败，落入下面的未授权引导
    }
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _permission = false;
        _status = '未授权：请到 设置 → 应用 → 桌面灵宠 → 显示在其他应用上层 → 允许；'
            '小米记得把「后台弹出界面」也打开';
      });
      _showPermissionGuide();
    }
  }

  Future<void> _stop() async {
    await FlutterOverlayWindow.closeOverlay();
    if (!mounted) return;
    setState(() => _overlayVisible = false);
  }

  void _onHatchComplete() {
    _hatchTimer?.cancel();
    setState(() => _phase = SpiritPhase.spirit);
    SpiritStore.save(SpiritPhase.spirit);
    SpiritSfx.play('hatch');
    final greeting = TimeAware.greeting();
    _showEggBubble(greeting, seconds: 4);
    SpiritTts.speak(greeting);
  }

  void _onHatchBlocked() {
    final sec = SpiritStore.remainingSeconds();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⏳ 蛋还在孵化中… ${sec ~/ 60}分${sec % 60}秒后可破壳'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ===== 设置项写入 =====
  Future<void> _updateOpacity(double v) async {
    SpiritConfig.opacity = v;
    await SpiritConfig.save();
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'opacity': v}));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _opacity = v);
  }

  Future<void> _updateAutoHide(bool v) async {
    SpiritConfig.autoHide = v;
    await SpiritConfig.save();
    if (!mounted) return;
    setState(() => _autoHide = v);
  }

  Future<void> _updateAutoHideDelay(double v) async {
    SpiritConfig.autoHideDelay = v.round();
    await SpiritConfig.save();
    if (!mounted) return;
    setState(() => _autoHideDelay = v.round());
  }

  /// 语音设置改动后同步给悬浮窗引擎，并让它在桌面直接出一次声，
  /// 这样「切换男女声」立刻能听到结果，不用猜有没有生效。
  Future<void> _pushTtsSettings() async {
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({
        'ttsEnabled': SpiritConfig.ttsEnabled,
        'ttsVoice': SpiritConfig.ttsVoice,
        'ttsRate': SpiritConfig.ttsRate,
      }));
    } catch (_) {}
  }

  Future<void> _updateTtsRate(double v) async {
    SpiritConfig.ttsRate = v;
    await SpiritConfig.save();
    await SpiritTts.refresh();
    if (!mounted) return;
    setState(() => _ttsRate = v);
  }

  Future<void> _updateTtsVoice(String v) async {
    SpiritConfig.ttsVoice = v;
    await SpiritConfig.save();
    await SpiritTts.refresh();
    await _pushTtsSettings();
    if (!mounted) return;
    setState(() => _ttsVoice = v);
    // 只有「引擎正常、也扫到了中文声线，但没有性别标记」时才提示，
    // 引擎本身没起来的情况下面那行状态说明已经写清楚了。
    if (v != 'default' &&
        SpiritTts.ready &&
        SpiritTts.zhVoiceCount > 0 &&
        !SpiritTts.hasGenderedVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '系统语音包里没有${v == 'male' ? '男声' : '女声'}，已改用音调区分；'
            '想要更自然：设置 → 语音合成 → 安装/更新中文语音数据',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _updateTtsEnabled(bool v) async {
    SpiritConfig.ttsEnabled = v;
    await SpiritConfig.save();
    await _pushTtsSettings();
    if (!mounted) return;
    setState(() => _ttsEnabled = v);
    if (v) {
      await SpiritTts.refresh();
      await SpiritTts.speak('语音播报打开啦');
      if (mounted) setState(() {});
    }
  }

  /// 试听：直接走真实的朗读路径，顺便把引擎诊断信息刷出来。
  Future<void> _previewVoice() async {
    await SpiritTts.speak('主人，我是小狐耳，这是我的新声音');
    if (!mounted) return;
    setState(() {});
  }

  /// 语音设置卡片底下那行状态：把「为什么不出声」直接摆在用户面前。
  String _ttsStatusText() {
    if (!_ttsEnabled) return '语音播报已关闭：台词只显示气泡文字，不出声';
    if (!SpiritTts.ready) return '语音引擎准备中…';
    if (SpiritTts.diagnostic.isNotEmpty) return '⚠️ ${SpiritTts.diagnostic}';
    if (SpiritTts.zhVoiceCount == 0) {
      return '⚠️ 系统里没扫到中文语音包，可能读不出声：设置 → 语音合成 → 安装中文语音数据';
    }
    final voice = SpiritTts.hasGenderedVoice
        ? '已找到性别声线'
        : '无性别声线，用音调区分男女';
    return '引擎就绪 · 中文声线 ${SpiritTts.zhVoiceCount} 个 · $voice';
  }

  Future<void> _updateRoam(bool v) async {
    SpiritConfig.roamEnabled = v;
    await SpiritConfig.save();
    if (!mounted) return;
    setState(() => _roamEnabled = v);
  }

  Future<void> _updateSfx(bool v) async {
    SpiritConfig.sfxEnabled = v;
    await SpiritConfig.save();
    if (!mounted) return;
    setState(() => _sfxEnabled = v);
    if (v) SpiritSfx.play('click');
  }

  Future<void> _updateShowClock(bool v) async {
    SpiritConfig.showClock = v;
    await SpiritConfig.save();
    if (!mounted) return;
    setState(() => _showClock = v);
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'showClock': v}));
    } catch (_) {}
  }

  Future<void> _updateSkin(String id) async {
    SpiritConfig.skinId = id;
    await SpiritConfig.save();
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'skin': id}));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _skinId = id);
  }

  Future<void> _pickCustomAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) return;
      final dir = await getApplicationSupportDirectory();
      final target =
          File('${dir.path}${Platform.pathSeparator}custom_avatar.png');
      await File(picked.path).copy(target.path);
      SpiritConfig.customAvatarPath = target.path;
      await SpiritConfig.save();
      if (!mounted) return;
      setState(() => _customAvatarPath = target.path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自定义形象已生效，回桌面看看灵宠~')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选图失败：$e')),
      );
    }
  }

  Future<void> _resetCustomAvatar() async {
    SpiritConfig.customAvatarPath = '';
    await SpiritConfig.save();
    if (!mounted) return;
    setState(() => _customAvatarPath = '');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复内置形象')),
    );
  }

  Future<void> _feed(Food food) async {
    SpiritState.touch();
    SpiritState.satiety = math.min(100, SpiritState.satiety + food.satiety);
    SpiritState.mood = math.min(100, SpiritState.mood + food.mood);
    SpiritState.feedCount++;
    SpiritState.bump(5);
    await SpiritState.save();
    if (!mounted) return;
    SpiritSfx.play('feed');
    setState(() {});
    if (_phase == SpiritPhase.egg) {
      _showEggBubble('${food.emoji} 蛋壳里都闻到香味啦~ (+${food.satiety})');
      SpiritTts.speak('谢谢主人，等我破壳出来再吃个够');
      return;
    }
    _playAction('eat', 1800);
    SpiritTts.speak('${food.name}好好吃呀，谢谢主人');
    if (!SpiritState.evo && SpiritState.feedCount >= 10) {
      setState(() => SpiritState.evo = true);
      await SpiritState.save();
      if (!mounted) return;
      SpiritSfx.play('evolve');
      _showEggBubble('✨ 进化啦！完全体形态 ✨', seconds: 4);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✨ 进化啦！完全体形态 ✨')),
      );
    } else if (!SpiritState.evo && SpiritState.feedCount == 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🌱 成长啦！进入少年形态 🌱')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('喂了${food.name}，饱腹度+${food.satiety}，亲密度+5'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  void _showPermissionGuide() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('悬浮窗权限还没开'),
        content: const Text(
          '小米/红米手机：设置 → 应用设置 → 应用管理 → 桌面灵宠 → 权限管理 → '
          '显示在其他应用上层 → 允许；同时打开「后台弹出界面」，否则悬浮窗开不起来。\n\n'
          '授权后回来再点一次「开始悬浮窗」就行。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('$kAppName · $kVersion'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text('一只吃白饭的狐耳灵宠，挂在你的 Android 桌面上。'),
            SizedBox(height: 6),
            Text(
              '可拖拽 · 能扒在屏幕边缘只露一个脑袋 · 两套皮肤 14 个表情 · '
              '自动溜达 · 小黄鸭音效 · 完全离线，不联网不上传不要账号',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 12),
            Text('纯原创 · 自用 · 不上架 · 不商用', style: TextStyle(fontSize: 12)),
            SizedBox(height: 6),
            Text('开发：Marvis 云端 + GitHub Actions',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ===== 界面片段 =====
  Widget _buildStats() {
    final stage = SpiritState.growthStage;
    final stageColor = stage == 3
        ? const Color(0xFFB8860B)
        : (stage == 2 ? const Color(0xFF7B68C8) : Colors.grey);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🍽️ 饱腹度 ${SpiritState.satiety}/100',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 10),
            Text('😊 心情 ${SpiritState.mood}/100',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌱 成长：${SpiritState.growthStageName}',
                style: TextStyle(fontSize: 12, color: stageColor)),
            const SizedBox(width: 10),
            Image.asset('assets/items/item_heart.png',
                width: 13,
                height: 13,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            const SizedBox(width: 3),
            Text('亲密度 ${SpiritState.affinity}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🍼 喂食 ${SpiritState.feedCount} 次',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 10),
            Text('💕 已互动 ${SpiritState.interactCount} 次',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        if (stage < 3)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '喂食满 10 次 或 亲密度满 80，即可进化完全体',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildFoodRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final f in kFoods)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilledButton.tonal(
              onPressed: () => _feed(f),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    f.icon,
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        Text(f.emoji, style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 4),
                  Text(f.name),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _labelRow(String label, Widget trailing) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEgg = _phase == SpiritPhase.egg;
    final remain = SpiritStore.remainingSeconds();

    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 形象预览 + 气泡
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  SpiritAvatar(
                    phase: _phase,
                    size: 150,
                    evo: SpiritState.evo,
                    action: _action,
                    expression: _previewExpr,
                    skinId: _skinId,
                    onHatchComplete: _onHatchComplete,
                    onHatchBlocked: _onHatchBlocked,
                    customImagePath:
                        _customAvatarPath.isEmpty ? null : _customAvatarPath,
                  ),
                  if (_eggBubble != null)
                    Positioned(
                      top: -18,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 250),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                        child: Text(
                          _eggBubble!,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isEgg ? '一颗蛋正在孵化中…' : '小狐耳已经破壳啦！',
                style: theme.textTheme.bodyMedium,
              ),
              if (_loaded && isEgg && remain > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '⏳ 还有 ${remain ~/ 60}分${remain % 60}秒可破壳（点蛋壳试试）',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.copyright, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(kBrand,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 12),
              Text(_status, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              _buildStats(),
              const SizedBox(height: 10),
              _buildFoodRow(),
              const SizedBox(height: 16),

              // 悬浮窗设置
              _card(
                icon: Icons.settings,
                title: '悬浮窗设置',
                children: [
                  Row(
                    children: [
                      const Text('透明化', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: _opacity,
                          min: 0.4,
                          max: 1.0,
                          divisions: 12,
                          label: '${(_opacity * 100).round()}%',
                          onChanged: _updateOpacity,
                        ),
                      ),
                      Text('${(_opacity * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  _labelRow(
                    '闲置自动扒边缩头',
                    Switch(value: _autoHide, onChanged: _updateAutoHide),
                  ),
                  if (_autoHide)
                    Row(
                      children: [
                        const Text('延时', style: TextStyle(fontSize: 13)),
                        Expanded(
                          child: Slider(
                            value: _autoHideDelay.toDouble(),
                            min: 10,
                            max: 120,
                            divisions: 22,
                            label: '$_autoHideDelay 秒',
                            onChanged: _updateAutoHideDelay,
                          ),
                        ),
                        Text('$_autoHideDelay 秒',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 语音设置
              _card(
                icon: Icons.record_voice_over,
                title: '语音设置',
                children: [
                  _labelRow(
                    '语音播报（说台词时读出来）',
                    Switch(value: _ttsEnabled, onChanged: _updateTtsEnabled),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Text('语速', style: TextStyle(fontSize: 13)),
                      Expanded(
                        child: Slider(
                          value: _ttsRate,
                          min: 0.3,
                          max: 1.0,
                          divisions: 7,
                          label: _ttsRate < 0.45
                              ? '慢'
                              : (_ttsRate < 0.8 ? '标准' : '快'),
                          onChanged: _updateTtsRate,
                          onChangeEnd: (_) => _pushTtsSettings(),
                        ),
                      ),
                      Text(_ttsRate < 0.45 ? '慢' : (_ttsRate < 0.8 ? '标准' : '快'),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const Text('声音', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'female', label: Text('女声')),
                      ButtonSegment(value: 'male', label: Text('男声')),
                      ButtonSegment(value: 'default', label: Text('默认')),
                    ],
                    selected: {_ttsVoice},
                    onSelectionChanged: (s) => _updateTtsVoice(s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _ttsEnabled ? _previewVoice : null,
                      icon: const Icon(Icons.volume_up, size: 16),
                      label: const Text('试听一下'),
                    ),
                  ),
                  Text(
                    _ttsStatusText(),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 形象与皮肤
              _card(
                icon: Icons.palette,
                title: '形象与皮肤',
                children: [
                  _labelRow(
                    '皮肤',
                    SegmentedButton<String>(
                      segments: [
                        for (final s in kSkins)
                          ButtonSegment(
                            value: s.id,
                            label: Text(s.name),
                          ),
                      ],
                      selected: {_skinId},
                      onSelectionChanged: (s) => _updateSkin(s.first),
                      showSelectedIcon: false,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final s in kSkins)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              AvatarThumb(dir: 'idle', skinId: s.id, size: 54),
                              Text('${s.badge} ${s.name}',
                                  style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('表情（14 种，点一下预览）',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in kExpressions)
                        ChoiceChip(
                          label: Text('${e.badge} ${e.name}',
                              style: const TextStyle(fontSize: 11)),
                          selected: _previewExpr.id == e.id,
                          onSelected: (_) {
                            setState(() => _previewExpr = e);
                            _playAction(e.dir, 1600);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _labelRow(
                    '自定义形象',
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _pickCustomAvatar,
                          icon: const Icon(Icons.photo_library_outlined, size: 16),
                          label: const Text('选图片换皮'),
                        ),
                        if (_customAvatarPath.isNotEmpty)
                          TextButton.icon(
                            onPressed: _resetCustomAvatar,
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('恢复默认'),
                          ),
                      ],
                    ),
                  ),
                  if (_customAvatarPath.isNotEmpty)
                    const Text(
                      '当前使用自定义形象（静态图，建议透明底 PNG）',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 音效
              _card(
                icon: Icons.music_note,
                title: '音效',
                children: [
                  _labelRow(
                    '小黄鸭音效（离线）',
                    Switch(value: _sfxEnabled, onChanged: _updateSfx),
                  ),
                  if (_sfxEnabled)
                    Wrap(
                      spacing: 4,
                      runSpacing: 0,
                      alignment: WrapAlignment.end,
                      children: [
                        for (final s in const [
                          ['hatch', '破壳'],
                          ['evolve', '进化'],
                          ['pet', '摸头'],
                          ['feed', '干饭'],
                          ['hungry', '喊饿'],
                          ['sleep', '入睡'],
                        ])
                          TextButton.icon(
                            onPressed: () => SpiritSfx.play(s[0]),
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: Text('试听${s[1]}音',
                                style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 桌面行为
              _card(
                icon: Icons.auto_awesome,
                title: '桌面行为',
                children: [
                  _labelRow(
                    '满屏自由漫游',
                    Switch(value: _roamEnabled, onChanged: _updateRoam),
                  ),
                  _labelRow(
                    '显示时钟日期徽章',
                    Switch(value: _showClock, onChanged: _updateShowClock),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '点徽章会有一句关心话；右下角小黄鸭音效只在互动时响。',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.pets),
                label: Text(
                  _overlayVisible
                      ? '悬浮窗已开启，再次点击'
                      : (_permission ? '开始悬浮窗' : '授权并开启悬浮窗'),
                ),
              ),
              if (_overlayVisible) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: _stop, child: const Text('关闭悬浮窗')),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _showAbout,
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('关于 · 摸鱼基地出品'),
              ),
              const SizedBox(height: 12),
              Text(
                '小提示：悬浮窗开启后回桌面就能看到灵宠，可拖动；闲置会自动扒到屏幕边缘只露个脑袋，点一下恢复。\n'
                '交互：单击=摸头，双击=吐槽，长按=呼出喂食/收起面板。',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}