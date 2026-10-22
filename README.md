# 桌面灵宠 · Android 版

> 一颗蛋，5 分钟破壳，然后赖在你的手机桌面上不走。
> 可拖拽 · 能扒在屏幕边缘只露一个脑袋 · 两套皮肤 14 个表情 · 自动溜达 · 小黄鸭音效 · **完全离线，不联网、不上传、不要账号**。

这是「桌面灵宠」的重写版：**只保留 Android 端**，用旧版的 58 张序列帧素材重写而来，去掉了旧版里「吃桌面图标」与「窗口抖动」两个功能，并按设计稿补齐了皮肤、表情、贴边、时钟徽章等新功能。

---

## 特性一览

| 分类 | 说明 |
| --- | --- |
| 养成 | 5 分钟孵化倒计时 → 破壳；饱腹度 / 心情双数值，喂食 3 种食物（🍎25 / 🐟35 / 🍬15）；亲密度与喂食次数决定成长阶段（幼年 → 少年 → 完全体） |
| 互动 | 单击 = 摸头（心情 +10 / 亲密度 +2）；双击 = 听它吐槽；长按 = 呼出喂食面板 |
| 表情 | **14 种表情**（发呆 / 开心 / 饿了 / 困了 / 生气 / 起舞 / 打滚 / 说话 / 干饭 / 进化 / 完全体 / 好奇 / 撒娇 / 兴奋），无人搭理时会自行轮换情绪 |
| 皮肤 | **2 套**：原色 🌙、月影 🌌（用颜色矩阵对同一批素材换色，不额外占体积） |
| 贴边 | 闲置 10~120 秒（默认 20 秒）自动滑到最近的屏幕边缘，**只露一个脑袋**；点一下恢复并顺手摸个头 |
| 漫游 | 破壳后随机在桌面上溜达，交互时自动停下 |
| 时钟 | 悬浮窗底部常驻时钟 + 日期徽章，**点一下给你一句关心话** |
| 语音 | 系统 TTS 播报（语速 / 音色可调）+ 4 个离线音效（点击 / 喂食 / 破壳 / 进化） |
| 时间感知 | 按时段问候与吐槽（早上 / 上午 / 午间 / 下午 / 晚上 / 深夜） |
| 置顶设置 | 透明度 0.4~1.0、自动贴边开关与延时、漫游开关、音效开关、时钟开关、自定义形象（相册选图） |
| 离线 | **不申请 INTERNET 权限**，没有账号、没有埋点、没有云端 |

### 相比旧版去掉了什么

- ❌ **吃桌面图标**：整套无障碍服务（`SpiritAccessibilityService`）、`BIND_ACCESSIBILITY_SERVICE` 权限、`eat_icon_enabled` 开关全部移除，本应用不再需要任何无障碍授权。
- ❌ **窗口抖动**：破壳时的左右震动、蛋形态的左右轻晃已去掉（保留呼吸缩放、裂纹、闪光、蹦出）。

---

## 安装

去 [Actions](../../actions/workflows/build-apk.yml) 找最近一次成功的 `build-apk` 运行，在页面底部 **Artifacts** 下载 `desktop-spirit-android-apk`，解压得到 `app-release.apk`，传到手机安装即可。

首次开启悬浮窗需要授权：

1. 点「授权并开启悬浮窗」→ 跳转系统设置；
2. 打开「显示在其他应用上层」；
3. 小米 / 红米等国产 ROM 还需额外打开「后台弹出界面」；
4. 回来再点一次即可（Android 13+ 会请求通知权限，用于前台服务提示）。

> 本仓库 **不提交 `android/` 目录**，Android 骨架由 CI 用 `flutter create` 生成，避免残缺 Gradle 工程导致的构建问题。因此不能用 `git clone && flutter build` 直接构建，请用 CI 产物。

## 自建构建

```bash
flutter create --platforms=android --org com.moyu --project-name desktop_spirit .
cp ci/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get
python3 ci/gen_assets.py      # 逐目录声明素材（pubspec 的 "- assets/" 不递归子目录！）
flutter pub get
flutter analyze
flutter build apk --release
```

产物在 `build/app/outputs/flutter-apk/app-release.apk`。

### CI 会替你做的检查

`flutter analyze` + `flutter test`（数量 / 帧目录 / 素材文件一致性），以及构建后对 bundle 与 APK 的硬校验：

- Dart 真的编译（`kernel_blob.bin`）、release 有 `libapp.so`（不是空壳）；
- **58 张 PNG + 4 个 WAV 全部入包**，`AssetManifest.json` 非空且可索引蛋帧；
- dex 里有 `flutter.overlay.window.flutter_overlay_window.OverlayService`（类名写错会被 R8 裁掉、悬浮窗起不来）；
- 合并后的 Manifest 带 Android 14 的 `specialUse` 前台服务类型（缺失会让 `startForeground` 崩溃）；
- **没有 `INTERNET` 权限**、**没有任何无障碍服务痕迹**（对应「完全离线」与「剔除吃图标」两条要求）。

---

## 目录结构

```
lib/
  main.dart              主引擎 + overlayMain 悬浮窗引擎入口（@pragma vm:entry-point）
  src/
    brand.dart           品牌、版本、全部文案（吐槽 / 撒娇 / 关心话）
    models.dart          阶段、14 表情、2 套皮肤
    store.dart           阶段与孵化倒计时 / 养成数值（含离线衰减）/ 悬浮窗设置
    avatar.dart          序列帧动画、蛋→破壳→蹦出、睡眠 ZZZ、表情徽标、皮肤换色
    audio.dart           音效（失败自动退回系统提示音）与 TTS（语速 / 音色）
    chatter.dart         跨引擎动作通道、孵化期倒计时台词、时段问候
    home_page.dart       主界面：状态、喂食、14 表情预览、2 皮肤预览、置顶设置
    overlay_page.dart    悬浮窗：喂食 / 摸头 / 扒边缩头 / 漫游 / 时钟徽章 / 情绪轮换
assets/
  egg idle eat happy roll hungry sleep angry dance talk evolve final items sfx
ci/
  AndroidManifest.xml    固化清单（CI 覆盖用）
  gen_assets.py          逐目录声明素材，同时识别 PNG 与 WAV
_old_ref/                旧项目参考（旧 main.dart、功能与素材盘点、CI 清单）
```

## 素材说明

序列帧共 58 张，全部为 512×512 PNG：`egg 3 / idle 5 / eat 5 / happy 3 / roll 5 / hungry 3 / sleep 4 / angry 3 / dance 5 / talk 3 / evolve 8 / final 5`，另有 `items/` 6 张道具图与 `sfx/` 4 个离线音效（16-bit PCM 单声道 22050Hz）。新增的 5 种派生情绪（好奇 / 撒娇 / 兴奋等）复用上面的帧，只叠加徽标与色偏，因此不需要额外素材。

## 许可

[MIT](LICENSE)