/// 全局品牌与文案常量。
///
/// 汇总所有静态数据（名字、版本、台词、食物、关心话），
/// 让 UI 与逻辑层只引用这里，避免散落魔法字符串。
library;

/// 出品署名
const String kBrand = '摸鱼基地出品';

/// 应用名（与 AndroidManifest 的 android:label 一致）
const String kAppName = '桌面灵宠';

/// 版本号（与 pubspec version 保持一致，仅用于展示）
const String kVersion = 'v1.0.0';

/// 孵化倒计时：首次打开后多久可以破壳
const Duration kHatchDuration = Duration(minutes: 5);

/// 孵化期（蛋形态）的吐槽与撒娇
const List<String> kTaunts = [
  '咕噜咕噜~',
  '主人理理我嘛',
  '好无聊啊…',
  '我快饿成纸片啦',
  '戳我干嘛！',
  '哼，不理你了',
  '再摸要秃了！',
  '今天也要元气满满！',
  '蛋壳有点痒…',
  '什么时候破壳呀',
  '你又在玩手机',
  '陪我玩会儿呗',
  '困了…ZZZ',
  '这颗蛋很贵哒',
  '小心点，别摔着我',
  '求求给点吃的',
  '在吗在吗在吗',
  '主人辛苦啦',
  '摸摸头~',
  '我要看外面的世界！',
];

/// 破壳后（小精灵形态）的吐槽
const List<String> kSpiritTaunts = [
  '嘿嘿，我出来啦！',
  '主人，摸摸耳朵~',
  '银发狐耳，天下第一！',
  '今天想吃小鱼干！',
  '破壳的感觉真不错！',
  '外面世界好亮呀！',
  '别戳啦，痒！',
  '尾巴可软啦~',
  '我闻到了好吃的！',
  '陪我看会儿天空呗',
];

/// 孵化期的撒娇/喊饿（每约 30 秒随机一句）
const List<String> kHatchIdleLines = [
  '主人，我饿啦，蛋壳里好无聊~',
  '主人在干嘛呀，陪陪我嘛',
  '敲敲蛋壳…主人能听到我吗？',
  '我快饿成纸片啦，想吃小鱼干',
  '主人，等我出来天天陪你玩',
  '蛋壳有点痒，好想快点出来',
  '咕噜咕噜~主人抱抱蛋嘛',
  '主人，记得喂我点吃的呀',
];

/// 点时钟徽章时出现的「一句关心话」
const List<String> kCareLines = [
  '记得喝口水呀~',
  '坐久了站起来动一动',
  '眼睛累了就看看窗外',
  '今天也要好好吃饭哦',
  '别熬夜啦，早点休息',
  '深呼吸三次，会舒服很多',
  '做不完的事，明天再说',
  '你已经很棒啦，真的',
  '肩膀放松一点嘛',
  '笑一笑，我最喜欢你笑',
];

/// 食物定义（喂食面板与主页共用）
class Food {
  const Food(this.emoji, this.name, this.satiety, this.mood);

  final String emoji;
  final String name;

  /// 提升的饱腹度
  final int satiety;

  /// 提升的心情
  final int mood;
}

const List<Food> kFoods = [
  Food('🍎', '苹果', 25, 5),
  Food('🐟', '小鱼干', 35, 8),
  Food('🍬', '糖果', 15, 3),
];