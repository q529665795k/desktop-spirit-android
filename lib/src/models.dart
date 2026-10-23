import 'package:flutter/material.dart';

/// 灵宠阶段：蛋 / 小精灵
enum SpiritPhase { egg, spirit }

/// 表情定义。
///
/// 一套「表情」= 一组序列帧 + 一个情绪徽标 + 一句台词。
/// 全部复用既有 12 组动作帧，因此新增表情不需要新素材，
/// 但每种表情在视觉上都能被清楚区分（帧不同 / 徽标不同 / 色偏不同）。
class Expression {
  const Expression(
    this.id,
    this.name,
    this.dir,
    this.badge, {
    this.tint,
    this.line,
    this.badgeAsset,
  });

  /// 内部 id
  final String id;

  /// 中文名（设置页展示）
  final String name;

  /// 复用的序列帧目录（assets/<dir>/<dir>_NN.png）
  final String dir;

  /// 情绪徽标 emoji
  final String badge;

  /// 可选色偏（叠加在帧上的颜色，用于区分共用同一组帧的表情）
  final Color? tint;

  /// 可选台词（自动切换表情时可能一起说）
  final String? line;

  /// 可选徽标贴片（assets/items 下的 PNG）；非空时徽标用图片而不是 emoji。
  final String? badgeAsset;
}

/// 14 种表情状态：9 种动作帧的原生表情 + 5 种派生情绪（同帧不同徽标/色偏）。
const List<Expression> kExpressions = [
  Expression('idle', '发呆', 'idle', '😊'),
  Expression('happy', '开心', 'happy', '🥰'),
  Expression('hungry', '饿了', 'hungry', '🍽️',
      badgeAsset: 'assets/items/item_hungry.png'),
  Expression('sleep', '困了', 'sleep', '💤',
      badgeAsset: 'assets/items/item_zzz.png'),
  Expression('angry', '生气', 'angry', '💢'),
  Expression('dance', '起舞', 'dance', '🎵'),
  Expression('roll', '打滚', 'roll', '🌀'),
  Expression('talk', '说话', 'talk', '💬'),
  Expression('eat', '干饭', 'eat', '🍎'),
  Expression('evolve', '进化', 'evolve', '✨'),
  Expression('final', '完全体', 'final', '👑'),
  Expression(
    'curious',
    '好奇',
    'idle',
    '🔍',
    tint: Color(0xFF7FB4FF),
    line: '诶？那是什么呀',
  ),
  Expression(
    'miss',
    '撒娇',
    'talk',
    '🥺',
    tint: Color(0xFFFFA6C9),
    line: '主人…抱抱我嘛',
  ),
  Expression(
    'excited',
    '兴奋',
    'dance',
    '🎉',
    tint: Color(0xFFFFC46B),
    line: '耶！好开心呀！',
  ),
];

/// 按 id 取表情；找不到时回落到发呆。
Expression expressionById(String id) {
  for (final e in kExpressions) {
    if (e.id == id) return e;
  }
  return kExpressions.first;
}

/// 无人搭理时随机轮换的情绪池（不含交互动作类表情）
const List<String> kMoodRotationIds = [
  'curious',
  'miss',
  'excited',
  'happy',
  'roll',
  'dance',
];

/// 皮肤定义。
///
/// 第二套皮肤用颜色矩阵对同一批素材换色得到，不需要额外素材。
class Skin {
  const Skin(this.id, this.name, {this.matrix, this.badge = ''});

  final String id;
  final String name;

  /// 4x5 颜色矩阵；null = 原色
  final List<double>? matrix;

  final String badge;
}

const List<Skin> kSkins = [
  Skin('origin', '原色', badge: '🌙'),
  Skin(
    'moon',
    '月影',
    badge: '🌌',
    matrix: <double>[
      0.82, 0.12, 0.16, 0, 8, //
      0.06, 0.80, 0.14, 0, 6, //
      0.14, 0.10, 1.06, 0, 26, //
      0, 0, 0, 1, 0, //
    ],
  ),
];

Skin skinById(String id) {
  for (final s in kSkins) {
    if (s.id == id) return s;
  }
  return kSkins.first;
}