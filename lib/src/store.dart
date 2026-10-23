import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'models.dart';

/// 阶段与孵化倒计时（蛋 → 精灵）
class SpiritStore {
  static const String _kPhase = 'spirit_phase';
  static const String _kHatchReadyAt = 'hatch_ready_at';
  static const String _kOverlayAliveAt = 'overlay_alive_at';
  static const String _kVoiceLastLine = 'voice_last_line';
  static const String _kVoiceLastAt = 'voice_last_at';

  /// 同一句台词在两个引擎之间的去重窗口（秒）。
  ///
  /// 主界面与悬浮窗跑的是**同一套**孵化脚本：开场白「主人，我在蛋里啦…」、
  /// 以及倒计时里程碑（「我还有1分钟就要破壳啦~」）两边的文案一字不差。
  /// 用户先开 App、随后又点开悬浮窗，就会在几秒内听到同一句被念两遍——
  /// 也就是「两个语音读文」。谁先念谁写时间戳，窗口期内另一个引擎同一句静默。
  static const int lineDedupeWindowSeconds = 25;

  /// 悬浮窗心跳有效窗口（秒）。超过这么久没刷新，就认为悬浮窗已经关了/被杀掉。
  static const int overlayAliveWindowSeconds = 90;

  static DateTime? hatchReadyAt;

  /// 悬浮窗（另一个引擎）最近是否还活着。主界面用它决定「灵宠的台词由谁来说」。
  static bool overlayAlive = false;

  static Future<SpiritPhase> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPhase) == 'spirit' ? SpiritPhase.spirit : SpiritPhase.egg;
  }

  /// 跨引擎读相位：`reload()` 先丢掉 Dart 侧缓存再从平台重读。
  ///
  /// shared_preferences 的 Dart 实例是**按引擎各自缓存**的：悬浮窗引擎破壳时写进
  /// SharedPreferences，主界面引擎的 `_preferenceCache` 里还是「蛋」，
  /// 直接 `load()` 读出来永远是旧值 —— 这正是「悬浮窗破壳了、主界面还在按蛋说话」
  /// 的根因。跨引擎读取一律走这个方法。
  static Future<SpiritPhase> loadFresh() async {
    final p = await SharedPreferences.getInstance();
    try {
      await p.reload();
    } catch (_) {}
    return p.getString(_kPhase) == 'spirit' ? SpiritPhase.spirit : SpiritPhase.egg;
  }

  /// 悬浮窗引擎心跳（每 30 秒一次）：主界面据此判断桌面上的灵宠还在不在。
  static Future<void> markOverlayAlive() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kOverlayAliveAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// 悬浮窗关窗/销毁时清掉心跳，主界面立刻恢复「由我来说话」。
  static Future<void> markOverlayDead() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kOverlayAliveAt);
    overlayAlive = false;
  }

  /// 重新判定悬浮窗是否存活（心跳在 90 秒内算活）
  static Future<bool> refreshOverlayAlive() async {
    final p = await SharedPreferences.getInstance();
    try {
      await p.reload();
    } catch (_) {}
    final ts = p.getInt(_kOverlayAliveAt);
    overlayAlive = ts != null &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(ts))
                .inSeconds <=
            overlayAliveWindowSeconds;
    return overlayAlive;
  }

  /// 申请「这句台词由我这台引擎来说」；返回 false 表示另一个引擎刚念过同一句。
  ///
  /// 两个引擎的 SharedPreferences 缓存各自独立，读写前一律 `reload()`，
  /// 否则去重表读到的永远是本引擎最后一次写的值，跨引擎就失效了。
  static Future<bool> claimLine(String line,
      {int windowSeconds = lineDedupeWindowSeconds}) async {
    if (line.isEmpty) return false;
    final p = await SharedPreferences.getInstance();
    try {
      await p.reload();
    } catch (_) {}
    final last = p.getString(_kVoiceLastLine);
    final at = p.getInt(_kVoiceLastAt);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last == line &&
        at != null &&
        now - at <= windowSeconds * 1000) {
      return false;
    }
    await p.setString(_kVoiceLastLine, line);
    await p.setInt(_kVoiceLastAt, now);
    return true;
  }

  static Future<void> save(SpiritPhase phase) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPhase, phase == SpiritPhase.spirit ? 'spirit' : 'egg');
  }

  /// 首次打开时记录 now + 5 分钟，之后一直沿用同一个时间点。
  static Future<void> ensureHatchTimer() async {
    if (hatchReadyAt != null) return;
    final p = await SharedPreferences.getInstance();
    final ts = p.getInt(_kHatchReadyAt);
    if (ts != null) {
      hatchReadyAt = DateTime.fromMillisecondsSinceEpoch(ts);
    } else {
      hatchReadyAt = DateTime.now().add(kHatchDuration);
      await p.setInt(_kHatchReadyAt, hatchReadyAt!.millisecondsSinceEpoch);
    }
  }

  /// 距可破壳还剩多少秒（0 = 随时可破壳）
  static int remainingSeconds() {
    if (hatchReadyAt == null) return 0;
    final diff = hatchReadyAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// 用于把倒计时格式化成「x分y秒」
  static String remainingText() {
    final s = remainingSeconds();
    return '${s ~/ 60}分${s % 60}秒';
  }
}

/// 养成状态：饱腹度 / 心情 / 喂食次数 / 进化 / 亲密度 / 最后互动时间
class SpiritState {
  static const String kSatiety = 'satiety';
  static const String kMood = 'mood';
  static const String kFeedCount = 'feed_count';
  static const String kEvo = 'evo';
  static const String kLastInteract = 'last_interact';
  static const String kAffinity = 'affinity';
  static const String kInteractCount = 'interact_count';
  static const String kLastDecayAt = 'last_decay_at';

  static int satiety = 80;
  static int mood = 80;
  static int feedCount = 0;
  static bool evo = false;
  static int affinity = 0;

  /// 真实互动次数（摸头 / 喂食），持久化后在主页计数器里显示
  static int interactCount = 0;
  static DateTime lastInteract = DateTime.now();

  /// 成长阶段：1 幼年 / 2 少年 / 3 完全体
  static int get growthStage {
    if (evo || feedCount >= 10 || affinity >= 80) return 3;
    if (feedCount >= 5 || affinity >= 30) return 2;
    return 1;
  }

  static String get growthStageName {
    switch (growthStage) {
      case 3:
        return '完全体';
      case 2:
        return '少年';
      default:
        return '幼年';
    }
  }

  /// 读取养成数值。
  ///
  /// [refresh] = true 时先 `reload()` 再读：主界面切回前台、或悬浮窗在桌面上喂过食
  /// 之后，Dart 侧缓存里还是旧数值，不 reload 就会显示过期的饱腹度/心情。
  static Future<void> load({bool refresh = false}) async {
    final p = await SharedPreferences.getInstance();
    if (refresh) {
      try {
        await p.reload();
      } catch (_) {}
    }
    satiety = p.getInt(kSatiety) ?? 80;
    mood = p.getInt(kMood) ?? 80;
    feedCount = p.getInt(kFeedCount) ?? 0;
    evo = p.getBool(kEvo) ?? false;
    affinity = p.getInt(kAffinity) ?? 0;
    interactCount = p.getInt(kInteractCount) ?? 0;
    final ti = p.getInt(kLastInteract);
    lastInteract =
        ti != null ? DateTime.fromMillisecondsSinceEpoch(ti) : DateTime.now();
    // 离线衰减：按离开的时长补算，每 30 秒 1 点（与运行时同一速率）
    final ld = p.getInt(kLastDecayAt);
    if (ld != null) {
      final steps = DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(ld))
              .inSeconds ~/
          30;
      if (steps > 0) _decayBy(steps);
    }
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kSatiety, satiety);
    await p.setInt(kMood, mood);
    await p.setInt(kFeedCount, feedCount);
    await p.setBool(kEvo, evo);
    await p.setInt(kAffinity, affinity);
    await p.setInt(kInteractCount, interactCount);
    await p.setInt(kLastInteract, lastInteract.millisecondsSinceEpoch);
    await p.setInt(kLastDecayAt, DateTime.now().millisecondsSinceEpoch);
  }

  static void touch() => lastInteract = DateTime.now();

  /// 真实互动（摸头 / 喂食）才加亲密度，并累计互动次数
  static void bump(int amount) {
    affinity = math.min(999, affinity + amount);
    interactCount++;
    touch();
  }

  /// 运行时衰减：每 30 秒调用一次，扣 1 点
  static void decay() => _decayBy(1);

  static void _decayBy(int steps) {
    satiety = math.max(5, satiety - steps);
    mood = math.max(10, mood - steps);
  }

  static void reset() {
    satiety = 80;
    mood = 80;
    feedCount = 0;
    evo = false;
    affinity = 0;
    interactCount = 0;
    lastInteract = DateTime.now();
  }
}

/// 悬浮窗设置（主 App 与悬浮窗共用，SharedPreferences 持久化）
class SpiritConfig {
  static const String kOpacity = 'overlay_opacity';
  static const String kAutoHide = 'auto_hide_enabled';
  static const String kAutoHideDelay = 'auto_hide_delay';
  static const String kTtsRate = 'tts_rate';
  static const String kTtsVoice = 'tts_voice';
  static const String kTtsEnabled = 'tts_enabled';
  static const String kRoamEnabled = 'roam_enabled';
  static const String kCustomAvatar = 'custom_avatar_path';
  static const String kSkin = 'skin_id';
  static const String kSfxEnabled = 'sfx_enabled';
  static const String kShowClock = 'show_clock';
  static const String kPetScale = 'pet_scale';

  /// 灵宠大小缩放 0.6 ~ 1.4（1.0 = 最初的尺寸）。
  ///
  /// 悬浮窗窗口高度与形象绘制尺寸一起按它缩放，蛋和精灵同步生效。
  /// 默认 0.85：不少机型上 200×240dp 的蛋偏大，留出一点余量。
  static double petScale = 0.85;

  /// 悬浮窗透明度 0.4 ~ 1.0
  static double opacity = 1.0;

  /// 闲置自动贴边缩头（扒边只露一个脑袋）
  static bool autoHide = true;

  /// 闲置多少秒后自动缩到边缘（10~120）
  static int autoHideDelay = 20;

  /// 语音语速 0.3 ~ 1.0
  static double ttsRate = 0.5;

  /// 音色 female / male / default
  static String ttsVoice = 'female';

  /// 语音播报开关（关掉后只出气泡不出声）
  static bool ttsEnabled = true;

  /// 满屏自由漫游
  static bool roamEnabled = true;

  /// 自定义形象图片路径（空 = 用内置素材）
  static String customAvatarPath = '';

  /// 当前皮肤 id
  static String skinId = 'origin';

  /// 音效开关
  static bool sfxEnabled = true;

  /// 悬浮窗里是否显示时钟/日期徽章
  static bool showClock = true;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    opacity = (p.getDouble(kOpacity) ?? 1.0).clamp(0.4, 1.0);
    autoHide = p.getBool(kAutoHide) ?? true;
    autoHideDelay = (p.getInt(kAutoHideDelay) ?? 20).clamp(10, 120);
    ttsRate = (p.getDouble(kTtsRate) ?? 0.5).clamp(0.3, 1.0);
    final v = p.getString(kTtsVoice) ?? 'female';
    ttsVoice = (v == 'female' || v == 'male' || v == 'default') ? v : 'female';
    ttsEnabled = p.getBool(kTtsEnabled) ?? true;
    roamEnabled = p.getBool(kRoamEnabled) ?? true;
    customAvatarPath = p.getString(kCustomAvatar) ?? '';
    skinId = p.getString(kSkin) ?? 'origin';
    sfxEnabled = p.getBool(kSfxEnabled) ?? true;
    showClock = p.getBool(kShowClock) ?? true;
    petScale = (p.getDouble(kPetScale) ?? 0.85).clamp(0.6, 1.4).toDouble();
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(kOpacity, opacity);
    await p.setBool(kAutoHide, autoHide);
    await p.setInt(kAutoHideDelay, autoHideDelay);
    await p.setDouble(kTtsRate, ttsRate);
    await p.setString(kTtsVoice, ttsVoice);
    await p.setBool(kTtsEnabled, ttsEnabled);
    await p.setBool(kRoamEnabled, roamEnabled);
    await p.setString(kCustomAvatar, customAvatarPath);
    await p.setString(kSkin, skinId);
    await p.setBool(kSfxEnabled, sfxEnabled);
    await p.setBool(kShowClock, showClock);
    await p.setDouble(kPetScale, petScale);
  }
}