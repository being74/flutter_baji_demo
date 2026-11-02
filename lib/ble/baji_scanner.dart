import 'dart:async';
import 'dart:io' show Platform;

// 必须与 baji_ble_client 用同一个 BLE 包，两个包共用 MethodChannel，混用会丢回调。
import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';

import '../core/baji_log.dart';
import '../protocol/baji_protocol.dart';

class BajiDevice {
  const BajiDevice({
    required this.name,
    required this.address,
    required this.rssi,
    required this.hasTargetService,
    this.serviceUuids = const [],
  });

  final String? name;
  final String address;
  final int rssi;
  final bool hasTargetService;
  final List<String> serviceUuids;
}

/// 扫描周围 BLE 设备，只保留 e-BADGE，结果按 RSSI 从强到弱排序。
class BajiScanner {
  static const Duration _emitInterval = Duration(milliseconds: 250);
  static const Duration _scanTimeout = Duration(minutes: 10);

  Stream<List<BajiDevice>> scan() async* {
    final adapterState = await FlutterBluePlus.adapterState
        .where((state) => state != BluetoothAdapterState.unknown)
        .first;
    if (adapterState != BluetoothAdapterState.on) {
      throw StateError(
        adapterState == BluetoothAdapterState.unauthorized
            ? '蓝牙权限未授予'
            : '蓝牙未开启或不支持 BLE',
      );
    }

    final found = <String, BajiDevice>{};
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

    BajiLog.instance.info('扫描', '开始扫描 BLE 设备');
    await FlutterBluePlus.startScan(
      timeout: _scanTimeout,
      androidScanMode: AndroidScanMode.lowLatency,
    );
    try {
      await for (final results in FlutterBluePlus.onScanResults) {
        for (final result in results) {
          final previous = found[result.device.remoteId.str];
          final advertisedName = result.advertisementData.advName.trim();
          final platformName = result.device.platformName.trim();
          final name = advertisedName.isNotEmpty
              ? advertisedName
              : (platformName.isNotEmpty ? platformName : previous?.name);
          if (!isBajiDeviceName(name)) continue;
          final advertisedServices =
              result.advertisementData.serviceUuids.map((uuid) => uuid.str128).toList();
          final services = <String>{
            ...?previous?.serviceUuids,
            ...advertisedServices,
          }.toList();
          found[result.device.remoteId.str] = BajiDevice(
            name: name,
            address: result.device.remoteId.str,
            rssi: result.rssi,
            hasTargetService: services.any(BajiUuids.matchesService),
            serviceUuids: services,
          );
        }

        final now = DateTime.now();
        if (now.difference(lastEmit) < _emitInterval) continue;
        lastEmit = now;
        final sorted = found.values.toList()
          ..sort((left, right) => right.rssi.compareTo(left.rssi));
        yield sorted;
      }
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      BajiLog.instance.info('扫描', '停止扫描');
    }
  }

  /// 已配对设备来自系统绑定数据库，即使设备当前不广播也能列出（仅 Android）。
  Future<List<BajiDevice>> bondedDevices() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await FlutterBluePlus.bondedDevices;
      final devices = <BajiDevice>[];
      for (final device in raw) {
        final name = device.platformName.trim();
        if (!isBajiDeviceName(name)) continue;
        devices.add(
          BajiDevice(
            name: name,
            address: device.remoteId.str,
            rssi: 0,
            hasTargetService: false,
          ),
        );
      }
      devices.sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
      return devices;
    } catch (error) {
      BajiLog.instance.warn('扫描', '读取已配对设备失败：$error');
      return const [];
    }
  }
}

/// 实测广播名，允许带后缀，大小写不敏感。
bool isBajiDeviceName(String? name) =>
    name != null && name.toLowerCase().contains('e-badge');
