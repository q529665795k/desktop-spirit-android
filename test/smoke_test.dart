import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:desktop_spirit/src/avatar.dart';
import 'package:desktop_spirit/src/brand.dart';
import 'package:desktop_spirit/src/models.dart';

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
    for (final f in ['sfx_click', 'sfx_feed', 'sfx_hatch', 'sfx_evolve']) {
      expect(File('assets/sfx/$f.wav').existsSync(), isTrue, reason: '缺少音效 $f');
    }
  });

  test('文案与孵化时长', () {
    expect(kTaunts, isNotEmpty);
    expect(kSpiritTaunts, isNotEmpty);
    expect(kCareLines, isNotEmpty);
    expect(kHatchIdleLines, isNotEmpty);
    expect(kHatchDuration.inMinutes, 5);
  });
}