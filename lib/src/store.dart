import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'models.dart';

/// 阶段与孵化倒计时（蛋 → 精灵）
class SpiritStore {
  static const String _kPhase = 'spirit_phase';
  static const String _kHatchReadyAt = 'hatch_ready_at';

  static DateTime? hatchReadyAt;

  static Future<SpiritPhase> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPhase) == 'spirit' ? SpiritPhase.spirit : SpiritPhase.egg;
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
  static const String kLastDecayAt = 'last_decay_at';

  static int satiety = 80;
  static int mood = 80;
  static int feedCount = 0;
  static bool evo = false;
  static int affinity = 0;
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

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    satiety = p.getInt(kSatiety) ?? 80;
    mood = p.getInt(kMood) ?? 80;
    feedCount = p.getInt(kFeedCount) ?? 0;
    evo = p.getBool(kEvo) ?? false;
    affinity = p.getInt(kAffinity) ?? 0;
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
    await p.setInt(kLastInteract, lastInteract.millisecondsSinceEpoch);
    await p.setInt(kLastDecayAt, DateTime.now().millisecondsSinceEpoch);
  }

  static void touch() => lastInteract = DateTime.now();

  /// 真实互动（摸头 / 喂食）才加亲密度
  static void bump(int amount) {
    affinity = math.min(999, affinity + amount);
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
  static const String kRoamEnabled = 'roam_enabled';
  static const String kCustomAvatar = 'custom_avatar_path';
  static const String kSkin = 'skin_id';
  static const String kSfxEnabled = 'sfx_enabled';
  static const String kShowClock = 'show_clock';

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
    roamEnabled = p.getBool(kRoamEnabled) ?? true;
    customAvatarPath = p.getString(kCustomAvatar) ?? '';
    skinId = p.getString(kSkin) ?? 'origin';
    sfxEnabled = p.getBool(kSfxEnabled) ?? true;
    showClock = p.getBool(kShowClock) ?? true;
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(kOpacity, opacity);
    await p.setBool(kAutoHide, autoHide);
    await p.setInt(kAutoHideDelay, autoHideDelay);
    await p.setDouble(kTtsRate, ttsRate);
    await p.setString(kTtsVoice, ttsVoice);
    await p.setBool(kRoamEnabled, roamEnabled);
    await p.setString(kCustomAvatar, customAvatarPath);
    await p.setString(kSkin, skinId);
    await p.setBool(kSfxEnabled, sfxEnabled);
    await p.setBool(kShowClock, showClock);
  }
}