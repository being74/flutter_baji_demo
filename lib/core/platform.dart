import 'dart:io' show Platform;

/// 鸿蒙引擎下 dart:io 上报的平台名为 ohos（Android/iOS 保持原生判断）。
bool get isOhos => Platform.operatingSystem == 'ohos';
