import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'store.dart';

/// 音效（小黄鸭风格，4 个离线 wav，随包分发，不联网）。
///
/// 悬浮窗是独立 Flutter 引擎，插件在部分机型上可能注册失败，
/// 因此所有调用都必须容错：失败就退回系统提示音，绝不能让音效把功能带崩。
class SpiritSfx {
  static const Map<String, String> _assets = {
    'click': 'sfx/sfx_click.wav',
    'feed': 'sfx/sfx_feed.wav',
    'hatch': 'sfx/sfx_hatch.wav',
    'evolve': 'sfx/sfx_evolve.wav',
  };

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

/// 文字转语音播报。
///
/// 要点（沿用旧版踩坑经验）：
/// - 语言设置失败不把引擎标记为不可用，否则一次异常会永久静默；
/// - 男女声优先用系统枚举到的真实中文声线，没有再用音调兜底；
/// - 语速/音色只在设置变化时应用一次，避免每次播报都做昂贵调用导致丢声。
class SpiritTts {
  static FlutterTts? _tts;
  static bool _ready = false;
  static bool _voicesScanned = false;
  static bool _settingsApplied = false;
  static Map<String, String>? _maleVoice;
  static Map<String, String>? _femaleVoice;

  static Future<void> ensure() async {
    if (_tts != null) return;
    final t = FlutterTts();
    _tts = t;
    try {
      await t.setVolume(1.0);
      await t.setPitch(1.0);
      await t.awaitSpeakCompletion(false);
      try {
        if (await t.isLanguageAvailable('zh-CN') == true) {
          await t.setLanguage('zh-CN');
        } else if (await t.isLanguageAvailable('zh') == true) {
          await t.setLanguage('zh');
        }
      } catch (_) {}
      await _scanVoices(t);
    } catch (_) {
      // 引擎首次调用可能才真正就绪，这里不阻断后续播报
    }
    _ready = true;
  }

  static bool _isMale(String n) {
    final s = n.toLowerCase();
    return (s.contains('male') && !s.contains('female')) ||
        s.contains('男') ||
        s.contains('-male') ||
        s.contains('#male');
  }

  static bool _isFemale(String n) {
    final s = n.toLowerCase();
    return s.contains('female') || s.contains('女') || s.contains('#female');
  }

  static Future<void> _scanVoices(FlutterTts t) async {
    if (_voicesScanned) return;
    _voicesScanned = true;
    try {
      final dynamic raw = await t.getVoices;
      if (raw is! List) return;
      for (final v in raw) {
        if (v is! Map) continue;
        final loc = '${v['locale'] ?? v['Locale'] ?? v['language'] ?? ''}'
            .toLowerCase();
        if (!loc.startsWith('zh')) continue;
        final m = Map<String, String>.from(
          v.map((k, val) => MapEntry(k.toString(), val.toString())),
        );
        final name = m['name'] ?? m['Name'] ?? '';
        _maleVoice ??= _isMale(name) ? m : null;
        _femaleVoice ??= _isFemale(name) ? m : null;
      }
    } catch (_) {}
  }

  static Future<void> applySettings() async {
    await ensure();
    final t = _tts;
    if (t == null) return;
    try {
      await t.setSpeechRate(SpiritConfig.ttsRate.clamp(0.3, 1.0));
      switch (SpiritConfig.ttsVoice) {
        case 'male':
          if (_maleVoice != null) await t.setVoice(_maleVoice!);
          await t.setPitch(0.55);
          break;
        case 'female':
          if (_femaleVoice != null) await t.setVoice(_femaleVoice!);
          await t.setPitch(1.35);
          break;
        default:
          await t.setPitch(1.0);
      }
      _settingsApplied = true;
    } catch (_) {}
  }

  static Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await ensure();
    final t = _tts;
    if (t == null || !_ready) return;
    try {
      if (!_settingsApplied) await applySettings();
      await t.stop();
      // 部分引擎 stop 后立刻 speak 会吞掉第一句
      await Future.delayed(const Duration(milliseconds: 80));
      await t.speak(text);
    } catch (_) {}
  }

  /// 设置页改动后强制重新应用
  static Future<void> refresh() async {
    _settingsApplied = false;
    await applySettings();
  }
}