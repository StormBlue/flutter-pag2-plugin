# flutter_pag2_plugin

腾讯 PAG 的 Flutter 插件，基于 `Texture` 渲染，支持 Android 与 iOS。

## 功能特性

- 支持三种数据源：`asset`、`network`、`bytes`
- 支持播放控制：`start / pause / stop / setProgress`
- 支持动画事件回调：`start / repeat / end / cancel`
- 支持实例级高级参数：`videoEnabled`、`useDiskCache`、`cacheScale`、`maxFrameRate`
- 支持全局开关：缓存池、多线程、复用、Android 首帧可用性检查
- 支持 `GlobalKey<PAGViewState>` 主动控制

## 兼容性

- Flutter: `>=3.41.0`
- Dart: `>=3.11.0 <4.0.0`
- Android: `minSdk 24`（插件当前构建配置 `compileSdk/targetSdk = 35`）
- iOS: `13.0+`
- libpag: `4.5.27`

## 安装

建议以主仓 `path` 依赖方式接入。

```yaml
dependencies:
  flutter_pag2_plugin:
    path: third_party/flutter_pag2_plugin
```

如果你的 `pubspec.yaml` 不在主仓根目录，按相对路径调整：

```yaml
dependencies:
  flutter_pag2_plugin:
    path: ../../third_party/flutter_pag2_plugin
```

代码导入：

```dart
import 'package:flutter_pag2_plugin/pag.dart';
```

## 快速开始

### 1) Asset

```dart
PAGView.asset(
  'assets/anim.pag',
  width: 200,
  height: 200,
  autoPlay: true,
  repeatCount: PAGView.REPEAT_COUNT_LOOP,
);
```

### 2) Network

```dart
PAGView.network(
  'https://example.com/anim.pag',
  width: 200,
  height: 200,
  autoPlay: true,
);
```

### 3) Bytes

```dart
PAGView.bytes(
  bytesData,
  width: 200,
  height: 200,
  autoPlay: true,
);
```

### 4) 事件回调

```dart
PAGView.asset(
  'assets/anim.pag',
  onInit: () {},
  onAnimationStart: () {},
  onAnimationRepeat: () {},
  onAnimationEnd: () {},
  onAnimationCancel: () {},
);
```

### 5) 通过 GlobalKey 控制播放

```dart
final pagKey = GlobalKey<PAGViewState>();

PAGView.network(
  'https://example.com/anim.pag',
  key: pagKey,
);

pagKey.currentState?.start();
pagKey.currentState?.pause();
pagKey.currentState?.stop();
pagKey.currentState?.setProgress(0.5);
final layers = await pagKey.currentState?.getLayersUnderPoint(10, 10);
```

## 构造参数

`PAGView.network / PAGView.asset / PAGView.bytes` 共有参数：

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `width` | `double?` | `null` | 控件宽度，建议显式传入以减少布局跳变 |
| `height` | `double?` | `null` | 控件高度 |
| `repeatCount` | `int` | `PAGView.REPEAT_COUNT_DEFAULT` | 循环次数；`PAGView.REPEAT_COUNT_LOOP` 为无限循环 |
| `initProgress` | `double` | `0` | 初始进度 |
| `autoPlay` | `bool` | `false` | 初始化完成后自动播放 |
| `videoEnabled` | `bool?` | `null` | 是否启用视频图层解码 |
| `useDiskCache` | `bool?` | `null` | 是否启用 PAG 磁盘缓存 |
| `cacheScale` | `double?` | `null` | 渲染缓存缩放，建议范围 `[0, 1]` |
| `maxFrameRate` | `double?` | `null` | 最大帧率 |
| `onInit` | `PAGCallback?` | `null` | 初始化完成回调 |
| `onAnimationStart` | `PAGCallback?` | `null` | 动画开始回调 |
| `onAnimationEnd` | `PAGCallback?` | `null` | 动画结束回调 |
| `onAnimationCancel` | `PAGCallback?` | `null` | 动画取消回调 |
| `onAnimationRepeat` | `PAGCallback?` | `null` | 动画循环回调 |
| `defaultBuilder` | `Widget Function(BuildContext)?` | `null` | 加载中/不可用时占位 UI |
| `reuse` | `bool` | `false` | 是否启用复用 |
| `reuseKey` | `String?` | `null` | 复用键（`network` 默认 URL，`asset` 默认 package+assetName） |
| `key` | `Key?` | `null` | Flutter Widget key |

数据源专有参数：

- `PAGView.network(String? url, ...)`
- `PAGView.asset(String? assetName, {String? package, ...})`
- `PAGView.bytes(Uint8List? bytesData, ...)`

## 运行时控制 API（PAGViewState）

| 方法 | 说明 |
|---|---|
| `start()` | 开始播放 |
| `pause()` | 暂停播放 |
| `stop()` | 停止并回到初始进度 |
| `setProgress(double progress)` | 设置进度 |
| `setVideoEnabled(bool enabled)` | 动态开启/关闭视频图层 |
| `setUseDiskCache(bool enabled)` | 动态开启/关闭磁盘缓存 |
| `setCacheScale(double scale)` | 动态设置缓存缩放 |
| `setMaxFrameRate(double frameRate)` | 动态设置最大帧率 |
| `getLayersUnderPoint(double x, double y)` | 获取坐标点下的图层名列表 |

## 全局设置 API（PAG）

```dart
PAG.enableCache(true);          // 渲染实例缓存，默认 true
PAG.setCacheSize(10);           // 缓存池上限，默认 10
PAG.enableMultiThread(true);    // 多线程加载/释放，默认 true
PAG.enableReuse(false);         // 复用开关，默认 false
PAG.enableCheckAvailable(true); // Android 首帧可用性检查，默认 true
```

## 平台说明

### Android

- 插件已声明网络权限：`android.permission.INTERNET`（用于 `PAGView.network`）
- 当前构建参数：`minSdk 24`、`targetSdk 35`、`Java 17`
- 混淆建议：

```proguard
-keep class org.libpag.** { *; }
```

### iOS

- `platform :ios, '13.0'`
- 依赖 `libpag (~> 4.5.27)`
- 如果使用 `http`（非 `https`）网络资源，请在主工程按需配置 ATS

## 合规提醒

- Apple 官方要求：自 **2026-04-28** 起，提交到 App Store 的 iOS App 需使用 **iOS 26 SDK（Xcode 26+）** 构建。接入本插件的主项目请同步升级构建链路。

## 建议目录结构

```text
<your-main-project>/
  third_party/
    flutter_pag2/
  pubspec.yaml
```

## 开发与验证

```bash
./.fvm/flutter_sdk/bin/flutter pub get
./.fvm/flutter_sdk/bin/flutter analyze
```

## 常见问题

### 1) 为什么 Android 首帧前看不到纹理？

默认开启了 `PAG.enableCheckAvailable(true)`。在首帧可用前会显示占位区域。你可以传 `defaultBuilder` 自定义占位 UI，或按业务需求关闭该检查。

### 2) 为什么建议显式设置 `width/height`？

显式尺寸可以减少加载完成前后的布局跳变，提升首屏稳定性。

### 3) 复用什么时候开启？

默认关闭（`PAG.enableReuse(false)`）。只有在你明确有大量同源 PAG 实例并且已验证业务一致性时再开启。

## License

见 [LICENSE](LICENSE)。
