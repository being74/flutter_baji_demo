# 鸿蒙（HarmonyOS / ohos）适配说明

本分支在 `main`（Android/iOS/Web）基础上完成鸿蒙化适配，基于本地鸿蒙版 Flutter
**3.22.1-ohos-1.0.4**（Dart 3.4.0，[openharmony-tpc/flutter_flutter](https://gitcode.com/openharmony-tpc/flutter_flutter)）。

## 一、依赖版本（3.22 配套 TAG）

版本选择依据 [CPF-Flutter 三方库适配列表](https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.md)
及各仓库 README 的「TAG 版本对应表」，**必须与框架版本配套**，不能混用：

| 插件 | 原 pin（3.47.5） | 本分支 | ohos 实现 | 来源 |
|---|---|---|---|---|
| flutter_blue_plus | ^2.3.14 | **1.33.5**（精确锁版） | flutter_blue_plus_ohos @ `1.33.5-ohos-1.0.0` | CPF-Flutter/fluttertpc_flutter_blue_plus (path: ohos) |
| permission_handler | ^12.0.3 | ^11.3.1 | 主包整体 override @ `11.3.1-ohos-1.0.0-beta.1` | CPF-Flutter/flutter_permission_handler |
| image_picker | ^1.2.4 | ^1.1.2 | 主包整体 override @ `image_picker-v1.1.2-ohos-1.0.1` | CPF-Flutter/flutter_packages |
| file_picker | ^13.3.0 | ^8.0.6 | 主包整体 override @ `10.2.0-ohos-1.0.0-beta.1` | CPF-Flutter/fluttertpc_file_picker |
| video_player | ^2.14.1 | ^2.9.2 | 主包整体 override @ `video_player-v2.9.2-ohos-1.0.1` | CPF-Flutter/flutter_packages |
| path_provider | ^2.1.6 | ^2.1.4 | 主包整体 override @ `provider-v2.1.4_ohos-1.0.1` | CPF-Flutter/flutter_packages |
| device_info_plus | ^13.3.0 | ^9.0.0 | 无需 ohos 实现（仅 Android 分支调用） | pub.dev |
| image / path | 纯 Dart | 放宽下限由 pub 解析 | — | pub.dev |

注意事项（踩过的坑）：

- `permission_handler` 的 `12.0.1-ohos-1.0.0` 虽然映射表标了 3.22，但其 pubspec
  要求 `sdk: ^3.5.0`，Dart 3.4 解析不过，实际用 `11.3.1-ohos-1.0.0-beta.1`。
- `flutter_blue_plus` 3.22 配套版本是 **1.x API**；`2.1.0-ohos-1.0.0` 只配套 3.27/3.35。
  主包精确锁 1.33.5 保证 pub.dev 的 Android/iOS 原生与 fork 的 Dart 层 channel 协议一致。
- `file_picker` 3.22 配套 TAG 是基于上游 8.0.6 的整体 ohos 化包（根包名 `file_picker`），
  与 10.3.8 起的 `file_picker_ohos` 分包结构不同。
- 环境要求：Dart SDK 约束已降为 `^3.4.0`；`flutter_lints` 降为 ^4。

## 二、代码适配点

- `lib/core/platform.dart`（新增）：`isOhos`（`Platform.operatingSystem == 'ohos'`）。
- `lib/ble/ble_permissions.dart`：ohos 走 `Permission.bluetoothConnect`
  （permission_handler_ohos 映射到 `ohos.permission.ACCESS_BLUETOOTH`）；
  `requestEnable()` 仅 Android（ohos 无应用内开蓝牙接口，关着时 UI 引导去系统设置）。
- `lib/ble/baji_ble_client.dart`：import 换为 `flutter_blue_plus_ohos`；
  去掉 2.x 的 `connect(license:)`；MTU 协商分支加入 ohos（fork 的 requestMtu 为 android/ohos-only）。
- `lib/ble/baji_scanner.dart`：无需改动（bondedDevices 非 Android 返回空）。
- `lib/data/baji_repository.dart`：自动重连对 ohos 视为「状态码不可依赖」（同 iOS 策略）。
- `lib/ui/baji_app.dart`：`onPopInvokedWithResult`（3.24+）→ `onPopInvoked`。
- 全局：`Color.withValues/toARGB32`（3.27+）→ `withOpacity/value`。
- `lib/media/media_files.dart`：file_picker 13.x 静态 API → `FilePicker.platform.pickFiles`。
- `lib/media/video_frames.dart`：通道契约不变，ohos 原生实现在
  `ohos/entry/src/main/ets/plugins/BajiVideoPlugin.ets`（AVImageGenerator + AVMetadataExtractor
  + PixelMap crop/scale + ImagePacker，语义对齐 Android MainActivity.kt）。

## 三、ohos 工程配置

- `ohos/entry/src/main/module.json5`：声明 `ohos.permission.ACCESS_BLUETOOTH`
  （user_grant，附 reason）与 `INTERNET`。
- `compatibleSdkVersion: 5.1.0(18)`。

## 四、构建与运行

```bash
flutter pub get
flutter build hap --debug              # 需要签名配置
flutter build hap --debug --no-codesign # 仅编译验证（本分支当前验证方式）
flutter run                             # 真机运行
```

首次真机运行前需要调试签名：用 DevEco Studio 打开 `ohos/` 工程，
`File -> Project Structure -> Signing Configs` 勾选
*Automatically generate signature*（需登录华为账号，会生成与本工程
bundleName `com.example.flutter_baji_demo` 绑定的调试 profile）。
`~/.ohos/config` 下历史工程的 profile 与本工程 bundleName 不匹配，不能直接复用。

## 五、已知平台差异

- **抽帧精度**：ohos `AVImageGenerator` 只支持按关键帧取帧（无 Android
  `OPTION_CLOSEST` 逐帧模式），interval 小于视频 GOP 时相邻帧会重复。
- **已配对设备列表**（`bondedDevices`）与**应用内打开蓝牙**（`turnOn`）为
  Android 专属，ohos 上自动跳过。
- MTU 协商在 ohos 上与 Android 同路径（requestMtu 517，失败回退 23/20 字节分片）。
- Dart 层测试 `flutter test` 92 项全部通过；ohos 构建产物为未签名 hap，
  安装需先完成上述签名配置。
