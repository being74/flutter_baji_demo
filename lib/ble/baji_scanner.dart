import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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

/// 扫描周围 BLE 设备，只保留 e-BADGE。
///
/// 实测广播名为 `e-BADGE`，名称可能带后缀，因此使用不区分大小写的包含匹配；
/// 结果按 RSSI 从强到弱排序。
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
            hasTargetService: services.any(
              (uuid) => uuid == BajiUuids.service || _shortId(uuid) == 0x0150,
            ),
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

  static int? _shortId(String uuid) {
    if (uuid.length != 36) return null;
    const suffix = '-0000-1000-8000-00805f9b34fb';
    if (!uuid.startsWith('0000') || !uuid.endsWith(suffix)) return null;
    return int.tryParse(uuid.substring(4, 8), radix: 16);
  }
}

/// 实测广播名，允许带后缀，大小写不敏感。
bool isBajiDeviceName(String? name) =>
    name != null && name.toLowerCase().contains('e-badge');
