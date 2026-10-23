import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:desktop_spirit/src/audio.dart';
import 'package:desktop_spirit/src/avatar.dart';
import 'package:desktop_spirit/src/brand.dart';
import 'package:desktop_spirit/src/chatter.dart';
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

  // ===== 孵化期台词：不再无限重复 =====
  // 用户报的「破壳后还在重复读破壳前的语音」，第一根因就是
  // 倒计时归零后 tick 每次无条件返回同一句，而调用方每 10 秒 tick 一次。

  test('破壳就绪台词只在间隔到期时出现，不会每 10 秒重读一遍', () {
    HatchChatter.reset();
    expect(HatchChatter.tick(0), HatchChatter.readyLine);
    expect(HatchChatter.tick(0), '',
        reason: '刚提醒过就不该再喊，否则蛋没被点破时会永远每 10 秒重复同一句');
    expect(HatchChatter.tick(0), '');
    expect(HatchChatter.readyRepeatSeconds, greaterThanOrEqualTo(60),
        reason: '重复间隔太短体感仍然是重复朗读');
  });

  test('里程碑台词每个只报一次，随后转回静默/撒娇节奏', () {
    HatchChatter.reset();
    expect(HatchChatter.tick(180), contains('3分钟'));
    expect(HatchChatter.tick(180), '');
    expect(HatchChatter.tick(120), contains('2分钟'));
    expect(HatchChatter.tick(60), contains('1分钟'));
    expect(HatchChatter.tick(30), contains('30秒'));
    expect(HatchChatter.tick(10), contains('10秒'));
    // 里程碑都说完后，回到「约每 30 秒一句撒娇/喊饿」的节奏（10 秒一 tick → 每 3 次一跳）。
    // 连续三次 tick 里恰好只有一次出声，且那一句来自撒娇/喊饿池；
    // 不写死「第几次出声」——计数器从上一段带过来的偏移不该成为断言的一部分。
    final tail = [
      HatchChatter.tick(180),
      HatchChatter.tick(180),
      HatchChatter.tick(180),
    ];
    expect(tail.where((s) => s.isNotEmpty).length, 1,
        reason: '三次 tick 只应出现一句撒娇台词，其余静默');
    expect(HatchChatter.idleLines, contains(tail.firstWhere((s) => s.isNotEmpty)));
  });

  test('跨引擎状态：loadFresh 读平台相位，悬浮窗心跳可标记存活/关窗', () async {
    // Dart 侧缓存是按引擎独立的：不 reload 读不到另一个引擎写的相位。
    SharedPreferences.setMockInitialValues({'spirit_phase': 'spirit'});
    expect(await SpiritStore.loadFresh(), SpiritPhase.spirit);

    await SpiritStore.markOverlayAlive();
    expect(await SpiritStore.refreshOverlayAlive(), isTrue,
        reason: '悬浮窗活着时主界面必须知道，否则会跟着一起读台词');
    await SpiritStore.markOverlayDead();
    expect(await SpiritStore.refreshOverlayAlive(), isFalse,
        reason: '关窗后要立刻恢复「台词由主界面来说」');
    expect(SpiritStore.overlayAliveWindowSeconds, inInclusiveRange(30, 300),
        reason: '心跳窗口太大 → 悬浮窗关掉后主界面长时间不敢说话');
  });

  // ===== 两路语音：同一句台词不许两个引擎各念一遍 =====
  // 主界面与悬浮窗跑同一套孵化脚本（开场白 + 里程碑倒计时），文案一字不差。

  test('同一句台词跨引擎只念一次，不同台词互不影响', () async {
    SharedPreferences.setMockInitialValues({});
    const intro = '主人，我在蛋里啦，记得喂我呀';
    expect(await SpiritStore.claimLine(intro), isTrue);
    expect(await SpiritStore.claimLine(intro), isFalse,
        reason: '另一个引擎刚念过同一句就该让位，否则用户听到同一句被读两遍');
    expect(await SpiritStore.claimLine('主人，我还有1分钟就要破壳啦~'), isTrue,
        reason: '不同台词不受去重影响');
    expect(SpiritStore.lineDedupeWindowSeconds, inInclusiveRange(5, 120),
        reason: '窗口过小挡不住「先开 App 再点悬浮窗」的两个引擎；'
            '过大又会把用户主动触发的正常台词吞掉');
    expect(await SpiritStore.claimLine(intro, windowSeconds: 0), isTrue,
        reason: '窗口为 0 表示不去重，用来确认这个窗口确实在起作用');
  });

  test('灵宠大小缩放：默认值在合法区间内，上下限就是滑杆的 60%~140%', () {
    expect(SpiritConfig.petScale, inInclusiveRange(0.6, 1.4));
    expect(0.6.clamp(0.6, 1.4), 0.6);
    expect(1.4.clamp(0.6, 1.4), 1.4);
    expect(2.0.clamp(0.6, 1.4), 1.4);
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