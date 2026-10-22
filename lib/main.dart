import 'package:flutter/material.dart';

import 'src/brand.dart';
import 'src/home_page.dart';
import 'src/overlay_page.dart';
import 'src/store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 首次打开即开始孵化倒计时（5 分钟），之后一直沿用同一个时间点
  await SpiritStore.ensureHatchTimer();
  await SpiritStore.load();
  await SpiritConfig.load();
  runApp(const DesktopSpiritApp());
}

/// 悬浮窗独立引擎入口。
///
/// 必须显式指定 `vm:entry-point`，否则 AOT（release）下入口会被裁剪，
/// 悬浮窗引擎启动时报「找不到入口点」，表现为窗口空白。
@pragma('vm:entry-point')
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SpiritStore.ensureHatchTimer();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SpiritOverlay(),
    ),
  );
}

class DesktopSpiritApp extends StatelessWidget {
  const DesktopSpiritApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF8E7CC3),
      ),
      home: const HomePage(),
    );
  }
}