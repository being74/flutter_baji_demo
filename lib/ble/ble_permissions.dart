import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/platform.dart';

/// Android 12+ 用 BLUETOOTH_SCAN/CONNECT；更低版本扫描需要定位权限。
/// ohos 用 ohos.permission.ACCESS_BLUETOOTH（permission_handler_ohos 将
/// Permission.bluetoothConnect 映射到该权限）；iOS 由 CoreBluetooth 自动弹窗。
abstract final class BlePermissions {
  static Future<bool> granted() async {
    final permissions = await _required();
    for (final permission in permissions) {
      if (!await permission.isGranted) return false;
    }
    return true;
  }

  static Future<bool> request() async {
    final permissions = await _required();
    final statuses = await permissions.request();
    return statuses.isNotEmpty && statuses.values.every((status) => status.isGranted);
  }

  static Future<bool> isBluetoothEnabled() async {
    try {
      final state = await FlutterBluePlus.adapterState
          .where((state) => state != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 2));
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// Android 上无法通过 Intent 强制打开蓝牙时，使用系统的开启弹窗。
  /// ohos 无应用侧开启接口，只能引导用户去系统设置。
  static Future<void> requestEnable() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {}
  }

  static Future<List<Permission>> _required() async {
    if (isOhos) return [Permission.bluetoothConnect];
    if (!Platform.isAndroid) return const [];
    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt >= 31) {
      return [Permission.bluetoothScan, Permission.bluetoothConnect];
    }
    return [Permission.locationWhenInUse];
  }
}
