import 'dart:convert';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// 跨引擎动作分发通道（主界面 ↔ 悬浮窗）。
///
/// 主界面与悬浮窗是两个独立 Flutter 引擎，静态状态不共享，
/// 需要同步的动作（进化、破壳）走这里广播。
class OverlayActionChannel {
  static void send(String action, {int duration = 1600}) {
    try {
      FlutterOverlayWindow.shareData(
        jsonEncode({
          'action': action,
          'duration': duration,
          'ts': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }
}

/// 孵化期（蛋形态）互动调度：里程碑倒计时台词 + 撒娇喊饿。
///
/// 主界面与悬浮窗各自持有定时器、各自调用（二者是独立引擎，
/// 静态状态不共享，互不影响）。
class HatchChatter {
  static const List<int> milestones = [180, 120, 60, 30, 10];

  /// 破壳就绪后再次提醒的最小间隔（秒）。
  ///
  /// 旧版对 `remainSeconds <= 0` 无条件返回同一句「主人，我要破壳啦，快点点我！」，
  /// 而调用方每 10 秒 tick 一次、闸门又只是「相位是否还是蛋」——
  /// 蛋没被点破时这句就每 10 秒重复一次、永不停止，这是「破壳前的话被反复朗读」
  /// 的第一个根因。现在改成：就绪时最多每 3 分钟提醒一次，其余 tick 静默。
  static const int readyRepeatSeconds = 180;

  /// 破壳就绪台词（启动时就绪的场景也复用它，保证口径一致）
  static const String readyLine = '主人，我要破壳啦，快点点我！';

  static final Set<int> _said = <int>{};
  static int _idleTicks = 0;
  static DateTime? _lastReadySay;

  static const List<String> idleLines = [
    '主人，我饿啦，蛋壳里好无聊~',
    '主人在干嘛呀，陪陪我嘛',
    '敲敲蛋壳…主人能听到我吗？',
    '我快饿成纸片啦，想吃小鱼干',
    '主人，等我出来天天陪你玩',
    '蛋壳有点痒，好想快点出来',
    '咕噜咕噜~主人抱抱蛋嘛',
    '主人，记得喂我点吃的呀',
  ];

  /// 每 10 秒调一次；返回本次应播报的台词，空串表示本次静默。
  static String tick(int remainSeconds) {
    if (remainSeconds <= 0) {
      final now = DateTime.now();
      if (_lastReadySay == null ||
          now.difference(_lastReadySay!).inSeconds >= readyRepeatSeconds) {
        _lastReadySay = now;
        return readyLine;
      }
      return '';
    }
    for (final m in milestones) {
      if (remainSeconds <= m && !_said.contains(m)) {
        _said.add(m);
        if (m >= 60) return '主人，我还有${m ~/ 60}分钟就要破壳啦~';
        return '主人，我还有$m秒就要破壳啦~';
      }
    }
    _idleTicks++;
    // 约每 30 秒随机撒娇／喊饿一句
    if (_idleTicks % 3 == 0) {
      return idleLines[DateTime.now().millisecond % idleLines.length];
    }
    return '';
  }

  /// 重新开始一轮孵化播报（里程碑台词可以再次触发）。
  ///
  /// 注意：**不**重置 [_lastReadySay] —— 破壳就绪的提醒间隔跨轮次继续生效，
  /// 否则「切到后台再回前台」会立刻又喊一次，体感上仍然是重复朗读。
  static void reset() {
    _said.clear();
    _idleTicks = 0;
  }
}

/// 时段问候／时段吐槽（时间感知）
class TimeAware {
  static String greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 9) return '主人早上好，又是元气满满的一天！';
    if (h >= 9 && h < 12) return '上午好呀，摸摸头~';
    if (h >= 12 && h < 14) return '午安~吃饱了再睡会儿？';
    if (h >= 14 && h < 18) return '下午好，陪我玩会儿嘛';
    if (h >= 18 && h < 23) return '晚上好呀，今天辛苦啦';
    return '夜深了，主人早点睡，我陪着你~';
  }

  static String taunt() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 9) return '太阳公公出来啦，该起床干活啦';
    if (h >= 9 && h < 12) return '上午效率最高，冲鸭！';
    if (h >= 12 && h < 14) return '中午啦，记得吃午饭哦';
    if (h >= 14 && h < 18) return '下午容易犯困，站起来活动下';
    if (h >= 18 && h < 23) return '晚饭吃了吗？别饿着自己';
    return '这么晚还不睡，修仙呢？';
  }

  static const List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 时钟徽章第一行：HH:mm
  static String clockText() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  /// 时钟徽章第二行：M月d日 周X
  static String dateText() {
    final n = DateTime.now();
    return '${n.month}月${n.day}日 周${weekdays[n.weekday - 1]}';
  }
}