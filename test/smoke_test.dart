import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:desktop_spirit/src/audio.dart';
import 'package:desktop_spirit/src/avatar.dart';
import 'package:desktop_spirit/src/brand.dart';
import 'package:desktop_spirit/src/models.dart';
import 'package:desktop_spirit/src/store.dart';

/// 轻量回归测试：只校验确定性约束（数量、帧目录、素材文件、文案非空）。
/// 这些约束一旦被改动，立即在 CI 上红，避免「素材打不进包」这类问题再次发生。
void main() {
  test('表情 / 皮肤 / 食物数量符合设计', () {
    expect(kExpressions.length, 14);
    expect(kSkins.length, 2);
    expect(kFoods.length, 3);
  });

  test('表情复用既有动作帧，帧目录与情绪池都有效', () {
    for (final e in kExpressions) {
      expect(SpriteAnim.kFrameCounts.containsKey(e.dir), isTrue,
          reason: '表情 ${e.id} 的帧目录 ${e.dir} 不在帧数表里');
    }
    for (final id in kMoodRotationIds) {
      expect(kExpressions.any((e) => e.id == id), isTrue,
          reason: '情绪池里的 $id 没有定义');
    }
  });

  test('素材与帧数表逐帧一致，音效齐全', () {
    SpriteAnim.kFrameCounts.forEach((dir, frames) {
      for (var i = 1; i <= frames; i++) {
        final p = 'assets/$dir/${dir}_${i.toString().padLeft(2, '0')}.png';
        expect(File(p).existsSync(), isTrue, reason: '缺少素材 $p');
      }
    });
    // 音效表与磁盘必须一一对应（声明了却没素材就会静默不响）
    for (final name in SpiritSfx.events) {
      final rel = SpiritSfx.assetOf(name)!;
      expect(File('assets/$rel').existsSync(), isTrue,
          reason: '事件 $name 对应的音效缺失：assets/$rel');
    }
    expect(SpiritSfx.events.length, 7, reason: '音效数量变动需同步 CI 与本文档');
  });

  test('道具贴片存在且被真实引用（避免打包了却不接线）', () {
    final assets = <String>[
      for (final f in kFoods) f.icon,
      kHeartIconAsset,
      'assets/items/item_hungry.png',
      'assets/items/item_zzz.png',
    ];
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: '缺少道具贴片 $a');
    }
    // 表情徽标里引用的贴片也要在磁盘上
    for (final e in kExpressions) {
      final b = e.badgeAsset;
      if (b != null) {
        expect(File(b).existsSync(), isTrue, reason: '表情 ${e.id} 的徽标贴片缺失：$b');
      }
    }
  });

  test('帧率 / 轮播口径自洽：一轮每帧恰好一次、整轮=帧数×每帧时长', () {
    SpriteAnim.kFrameCounts.forEach((dir, frames) {
      final fps = SpriteAnim.fpsFor(dir);
      // 帧数与素材一致（除不尽也靠取模收敛，不会跳到不存在的帧）
      final seen = <int>{};
      const steps = 1000;
      for (var i = 0; i <= steps; i++) {
        final idx = SpriteAnim.frameIndexAt(i / steps, frames);
        expect(idx, inInclusiveRange(0, frames - 1),
            reason: '$dir 第 $i/$steps 步取到越界帧 $idx');
        seen.add(idx);
      }
      expect(seen.length, frames, reason: '$dir 一轮内应覆盖全部 $frames 帧');

      // 整轮时长 = 每帧时长 × 帧数（200~8000ms 收敛，不出现 0 或负数）
      final expected = SpriteAnim.frameMillis(fps) * frames;
      final clamped = expected.clamp(200, 8000);
      expect(SpriteAnim.cycleFor(dir, fps).inMilliseconds, clamped,
          reason: '$dir 整轮时长与「帧数×每帧时长」不符');
    });

    // talk / angry 放慢一档，其余默认 6
    expect(SpriteAnim.fpsFor('talk'), 5);
    expect(SpriteAnim.fpsFor('angry'), 5);
    expect(SpriteAnim.fpsFor('idle'), SpriteAnim.kDefaultFps);
    expect(SpriteAnim.fpsFor('sleep'), 6);
  });

  test('文案与孵化时长', () {
    expect(kTaunts, isNotEmpty);
    expect(kSpiritTaunts, isNotEmpty);
    expect(kCareLines, isNotEmpty);
    expect(kHatchIdleLines, isNotEmpty);
    expect(kHatchDuration.inMinutes, 5);
  });

  test('计数器：真实互动累计亲密度与互动次数，成长阶段随喂食推进', () {
    SpiritState.reset();
    expect(SpiritState.interactCount, 0);
    expect(SpiritState.growthStageName, '幼年');
    SpiritState.bump(5); // 喂食
    SpiritState.feedCount++;
    expect(SpiritState.affinity, 5);
    expect(SpiritState.interactCount, 1);
    SpiritState.bump(2); // 摸头
    expect(SpiritState.affinity, 7);
    expect(SpiritState.interactCount, 2);
    // 喂满 10 次进入完全体；5 次进入少年
    SpiritState.feedCount = 5;
    expect(SpiritState.growthStage, 2);
    SpiritState.feedCount = 10;
    expect(SpiritState.growthStage, 3);
    SpiritState.reset();
  });

  // ===== 语音（TTS）=====
  // 这几条覆盖「男女声切换」的真实缺陷点：声线必须中文 + 离线才有用，
  // 没有性别声线时必须退回音调区分，而不能静默什么都不做。

  test('声线性别识别：先判 female，避免 male 子串误命中', () {
    expect(SpiritTts.genderOf({'name': 'zh-cn-x-ccc#female_1-local'}), 'female');
    expect(SpiritTts.genderOf({'name': 'zh-cn-x-ccc#male_1-local'}), 'male');
    expect(SpiritTts.genderOf({'name': '中文女声', 'locale': 'zh-CN'}), 'female');
    expect(SpiritTts.genderOf({'name': 'zh-cn-x-ccc-local'}), isNull);
  });

  test('声线挑选：只要中文离线声线，跳过云端声线', () {
    final voices = <Map<String, String>>[
      {'name': 'en-us-x-tpf#male_1-local', 'locale': 'en-US', 'network_required': '0'},
      {'name': 'zh-cn-x-ccc#female_1-local', 'locale': 'zh-CN', 'network_required': '0'},
      {'name': 'zh-cn-x-ccc#male_1-local', 'locale': 'zh-CN', 'network_required': '0'},
      {'name': 'zh-cn-x-cloud#male_2-network', 'locale': 'zh-CN', 'network_required': '1'},
      {'name': 'zh-cn-x-cloud2#female_2-network', 'locale': 'zh-CN', 'network_required': '1'},
    ];
    expect(SpiritTts.pickVoice(voices, 'female')?['name'],
        'zh-cn-x-ccc#female_1-local');
    expect(SpiritTts.pickVoice(voices, 'male')?['name'],
        'zh-cn-x-ccc#male_1-local',
        reason: '不能选中 network_required=1 的云端声线（本应用无网络权限，选中只会静默失败）');
    expect(SpiritTts.pickVoice(voices, 'default'), isNull);
    expect(SpiritTts.pickVoice(const [], 'male'), isNull);
  });

  test('音调兜底：拿到真实性别声线时温和，只能靠音调时拉开男女差值', () {
    expect(SpiritTts.pitchFor('male'), lessThan(SpiritTts.pitchFor('female')));
    expect(SpiritTts.pitchFor('male', matched: true),
        greaterThan(SpiritTts.pitchFor('male')));
    expect(SpiritTts.pitchFor('female', matched: true),
        lessThan(SpiritTts.pitchFor('female')));
    expect(SpiritTts.pitchFor('default'), 1.0);
  });

  test('语音播报开关默认开启，关掉后 speak 直接返回（不碰原生通道）', () async {
    expect(SpiritConfig.ttsEnabled, isTrue);
    SpiritConfig.ttsEnabled = false;
    await SpiritTts.speak('关掉播报后这句不该出声');
    SpiritConfig.ttsEnabled = true;
    await SpiritTts.speak('');
  });
}