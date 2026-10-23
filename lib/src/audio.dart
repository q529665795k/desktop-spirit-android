import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'store.dart';

/// 音效（小黄鸭风格，4 个离线 wav，随包分发，不联网）。
///
/// 悬浮窗跑在独立 Flutter 引擎里，插件由引擎自动注册（FlutterEngineGroup 默认
/// automaticallyRegisterPlugins=true），「插件没注册上」不是外放失败的原因；真正会踩的
/// 是引擎冷启动尚未就绪、音频焦点被别人占用这类时序问题。因此所有调用都必须容错：
/// 失败就退回系统提示音，绝不能让音效把功能带崩。
class SpiritSfx {
  /// 事件名 → 音频资源。7 个离线 wav 随包分发，不联网。
  ///
  /// 1.0.1 补充 pet / sleep / hungry 三枚，替掉这些事件此前一律复用 click
  /// 的偷懒做法，让「摸头 / 入睡 / 喊饿」各有辨识度。
  static const Map<String, String> _assets = {
    'click': 'sfx/sfx_click.wav',
    'feed': 'sfx/sfx_feed.wav',
    'hatch': 'sfx/sfx_hatch.wav',
    'evolve': 'sfx/sfx_evolve.wav',
    'pet': 'sfx/sfx_pet.wav',
    'sleep': 'sfx/sfx_sleep.wav',
    'hungry': 'sfx/sfx_hungry.wav',
  };

  /// 全部音效事件名（供测试/诊断核对，避免「声明了却没素材」）。
  static List<String> get events => _assets.keys.toList(growable: false);

  /// 事件名 → 资源相对路径（不含 assets/ 前缀）。
  static String? assetOf(String name) => _assets[name];

  static AudioPlayer? _player;
  static bool _degraded = false;

  /// 是否已退化为系统提示音
  static bool get degraded => _degraded;

  static Future<void> play(String name) async {
    if (!SpiritConfig.sfxEnabled) return;
    final asset = _assets[name];
    if (asset == null) return;
    try {
      final p = _player ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume(0.9);
      await p.stop();
      await p.play(AssetSource(asset));
      _degraded = false;
    } catch (_) {
      _degraded = true;
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }
}

/// 文字转语音播报（角色说出台词时同步朗读书面文字）。
///
/// 1.0.1 按真机反馈重做，几个关键点：
/// - **引擎可见性**：Android 11+（targetSdk ≥ 30）必须在清单里声明
///   `android.intent.action.TTS_SERVICE` 的 `<queries>`，否则系统解析不到默认语音引擎，
///   `TextToSpeech` 初始化直接失败 —— 症状就是「设置能点、选择能存、一点声音都没有，还不报错」。
/// - **不阻塞界面**：引擎起不来时 flutter_tts 会把调用挂进内部待办队列，Future 永不完成。
///   这里每个原生调用都带超时，保证 `ensure/applySettings/refresh` 一定会返回，
///   界面上的男女声切换不会因为等引擎而卡住。
/// - **离线声线优先**：本应用没有 INTERNET 权限，选到 `network_required=1` 的云端声线
///   只会静默失败，所以挑声线时强制过滤。
/// - **男女声**：优先用系统里真实存在的中文（离线）性别声线；找不到就退回音调区分，
///   保证「男声/女声」至少在听感上有差别。
/// - **可诊断**：任何一步失败都写进 [diagnostic]，设置页直接展示；朗读彻底失败时
///   用系统提示音做一次节流降级反馈，让用户知道「程序在试，是引擎的问题」。
class SpiritTts {
  /// 最近一次失败原因，空字符串表示没出过问题。设置页直接展示，用户可自查。
  static String diagnostic = '';

  static FlutterTts? _tts;
  static Future<void>? _init;
  static bool _ready = false;
  static bool _voicesScanned = false;
  static bool _settingsApplied = false;
  static List<Map<String, String>> _voices = const [];
  static Map<String, String>? _maleVoice;
  static Map<String, String>? _femaleVoice;
  static DateTime? _lastBeep;

  /// 引擎已完成初始化（或已确认起不来并记录了原因）
  static bool get ready => _ready;

  /// 系统里是否找到了带性别标记的中文离线声线
  static bool get hasGenderedVoice => _maleVoice != null || _femaleVoice != null;

  /// 已扫到的中文声线数量（诊断用）
  static int get zhVoiceCount => _voices.length;

  /// 初始化（幂等）：多次调用共用同一个 Future，避免重复创建引擎。
  static Future<void> ensure() => _init ??= _doInit();

  static Future<void> _doInit() async {
    final t = FlutterTts();
    _tts = t;
    try {
      await _warmUp(t).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      diagnostic = '语音引擎初始化超时，系统可能未安装/未启用 TTS 引擎';
    } catch (e) {
      diagnostic = '语音引擎初始化失败：$e';
    }
    _ready = true;
  }

  static Future<void> _warmUp(FlutterTts t) async {
    await t.setVolume(1.0);
    await t.awaitSpeakCompletion(false);
    await _scanVoices(t);
  }

  // ===== 声线挑选（纯函数，便于单测断言）=====

  static Map<String, String> _asMap(Map v) =>
      v.map((k, val) => MapEntry(k.toString(), val.toString()));

  static String _localeOf(Map v) =>
      '${v['locale'] ?? v['Locale'] ?? v['language'] ?? ''}'.toLowerCase();

  /// 从声线名/特性里判断性别：`zh-cn-x-ccc#male_1-local`、`中文男声` 这类都能识别。
  /// 注意必须先判 female，否则 `female` 里的 `male` 会误命中。
  static String? genderOf(Map voice) {
    final hay =
        '${voice['name'] ?? voice['Name'] ?? ''} ${voice['features'] ?? ''}'
            .toLowerCase();
    if (hay.contains('female') || hay.contains('女') || hay.contains('#female')) {
      return 'female';
    }
    if (hay.contains('male') || hay.contains('男') || hay.contains('#male')) {
      return 'male';
    }
    return null;
  }

  /// 挑一个「中文 + 指定性别 + 本地（离线）」的声线，没有则返回 null。
  ///
  /// 必须过滤 `network_required = 1`：本应用声明为完全离线、无 INTERNET 权限，
  /// 选到云端声线只会静默失败，比退回音调区分更糟。
  static Map<String, String>? pickVoice(List<dynamic> voices, String want) {
    if (want != 'male' && want != 'female') return null;
    for (final v in voices) {
      if (v is! Map) continue;
      if (!_localeOf(v).startsWith('zh')) continue;
      final net = '${v['network_required'] ?? ''}';
      if (net == '1' || net.toLowerCase() == 'true') continue;
      if (genderOf(v) == want) return _asMap(v);
    }
    return null;
  }

  /// 音色 -> 音调。真实性别声线到手时用温和差值（不破坏自然度），
  /// 只能靠音调区分时差值放大，保证听得出男女。
  static double pitchFor(String voice, {bool matched = false}) {
    switch (voice) {
      case 'male':
        return matched ? 0.80 : 0.62;
      case 'female':
        return matched ? 1.15 : 1.40;
      default:
        return 1.0;
    }
  }

  static Future<void> _scanVoices(FlutterTts t) async {
    if (_voicesScanned) return;
    try {
      final dynamic raw = await t.getVoices;
      // 引擎尚未就绪时可能返回 null / 空表，保持 _voicesScanned=false 下次重试
      if (raw is! List || raw.isEmpty) return;
      final list = <Map<String, String>>[];
      for (final v in raw) {
        if (v is! Map) continue;
        if (_localeOf(v).startsWith('zh')) list.add(_asMap(v));
      }
      if (list.isEmpty) return;
      _voices = list;
      _maleVoice = pickVoice(raw, 'male');
      _femaleVoice = pickVoice(raw, 'female');
      _voicesScanned = true;
    } catch (_) {
      // 引擎未就绪，保留 _voicesScanned=false，下次再扫
    }
  }

  /// 把当前设置（语速 / 音色）下发到引擎。失败只记诊断，不影响界面。
  static Future<void> applySettings() async {
    await ensure();
    final t = _tts;
    if (t == null) return;
    try {
      if (!_voicesScanned) await _scanVoices(t);
      await t.setVolume(1.0);
      for (final lang in const ['zh-CN', 'zh']) {
        if (await t.isLanguageAvailable(lang) == true) {
          await t.setLanguage(lang);
          break;
        }
      }
      await t.setSpeechRate(SpiritConfig.ttsRate.clamp(0.3, 1.0).toDouble());
      final matched = SpiritConfig.ttsVoice == 'male'
          ? _maleVoice != null
          : (SpiritConfig.ttsVoice == 'female' ? _femaleVoice != null : false);
      await t.setPitch(pitchFor(SpiritConfig.ttsVoice, matched: matched));
      final voice =
          SpiritConfig.ttsVoice == 'male' ? _maleVoice : _femaleVoice;
      if (matched && voice != null) {
        await t.setVoice(voice);
      } else if (SpiritConfig.ttsVoice != 'default') {
        // 没有对应性别的中文离线声线：退回默认声线，靠音调区分男女。
        // flutter_tts 3.8.5 没有 clearVoice()，只能用 getDefaultVoice 复位。
        final def = await t.getDefaultVoice;
        if (def is Map && def.isNotEmpty) await t.setVoice(_asMap(def));
      }
      _settingsApplied = true;
    } on TimeoutException {
      diagnostic = '语音参数下发超时（引擎可能未就绪）';
    } catch (e) {
      diagnostic = '语音参数下发失败：$e';
    }
  }

  /// 朗读一段文字（失败有节流降级反馈，绝不抛给调用方）。
  static Future<void> speak(String text) async {
    if (text.isEmpty || !SpiritConfig.ttsEnabled) return;
    await ensure();
    final t = _tts;
    if (t == null || !_ready) return;
    try {
      if (!_settingsApplied) {
        await applySettings().timeout(const Duration(seconds: 6));
      }
      await t.stop().timeout(const Duration(seconds: 3));
      // 部分引擎 stop 后立刻 speak 会吞掉第一句
      await Future.delayed(const Duration(milliseconds: 80));
      await t.speak(text).timeout(const Duration(seconds: 3));
      diagnostic = '';
    } on TimeoutException {
      _settingsApplied = false;
      diagnostic = '朗读超时：引擎未就绪（Android 11+ 需在清单声明 TTS_SERVICE 可见性）';
      await _fallbackBeep();
    } catch (e) {
      _settingsApplied = false;
      diagnostic = '朗读失败：$e';
      await _fallbackBeep();
    }
  }

  /// 降级反馈：彻底发不出声时用系统提示音顶一下，并做 10 秒节流，
  /// 避免引擎不可用时每句台词都「哒」一声。
  static Future<void> _fallbackBeep() async {
    final now = DateTime.now();
    if (_lastBeep != null && now.difference(_lastBeep!).inSeconds < 10) return;
    _lastBeep = now;
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  /// 设置页改动后强制重新下发参数（有超时兜底，调用方可以直接 await）。
  static Future<void> refresh() async {
    _settingsApplied = false;
    if (!SpiritConfig.ttsEnabled) return;
    await applySettings().timeout(const Duration(seconds: 8), onTimeout: () {});
  }
}