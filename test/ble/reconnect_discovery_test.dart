import 'package:flutter/services.dart';
import 'package:flutter_baji_demo/ble/baji_ble_client.dart';
import 'package:flutter_blue_plus_ohos/flutter_blue_plus_ohos.dart';
import 'package:flutter_test/flutter_test.dart';

const _address = '1A:7B:AB:C5:BC:B9';
const _serviceUuid = '000001a0-0000-1000-8000-00805f9b34fb';
const _writeUuid = '000001a1-0000-1000-8000-00805f9b34fb';
const _readUuid = '000001a2-0000-1000-8000-00805f9b34fb';
const _cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';
const _channelName = 'flutter_blue_plus/methods';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 迁移说明：Dart 侧统一走 flutter_blue_plus_ohos（1.33.5 内核），不再经过
  // flutter_blue_plus_platform_interface，因此这里直接伪造该插件的原生
  // MethodChannel 协议：Dart→原生调用由 mock handler 应答，原生→Dart 事件通过
  // handlePlatformMessage 注入。语义与旧的平台接口 fake 相同。
  test('重连后重新发现 GATT 服务，写入不再报 primary service not found', () async {
    final platform = _FakeGattPlatform();
    const channel = MethodChannel(_channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, platform.handle);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await FlutterBluePlus.isSupported;

    final client = BajiBleClient();
    try {
      await client.connect(_address);
      expect(platform.discoverCount, 1);
      await client.writeFrame(Uint8List.fromList(const [0x01]));
      expect(platform.writeCount, 1);

      await client.disconnect();
      await client.connect(_address);

      expect(
        platform.discoverCount,
        2,
        reason:
            'flutter_blue_plus 要求每次连接后重新 discoverServices，'
            '其 servicesList 是跨连接缓存',
      );
      await client.writeFrame(Uint8List.fromList(const [0x02]));
      expect(platform.writeCount, 2);
    } finally {
      await client.close();
    }
  });
}

/// 模拟 Android GATT：断开后原生服务表清空，
/// 未重新 discoverServices 时写入返回 primary service not found。
class _FakeGattPlatform {
  int discoverCount = 0;
  int writeCount = 0;
  bool _servicesReady = false;

  static const StandardMethodCodec _codec = StandardMethodCodec();

  Future<dynamic> handle(MethodCall call) async {
    switch (call.method) {
      case 'flutterRestart':
      case 'connectedCount':
        return 0;
      case 'isSupported':
        return true;
      case 'getAdapterState':
        return {'adapter_state': 4}; // BmAdapterStateEnum.on
      case 'connect':
        _servicesReady = false;
        await Future<void>.delayed(Duration.zero);
        await _emit('OnConnectionStateChanged', _connectionState(1));
        await _emit('OnMtuChanged', {
          'remote_id': _address,
          'mtu': 512,
          'success': 1,
          'error_code': 0,
          'error_string': '',
        });
        return true;
      case 'disconnect':
        _servicesReady = false;
        await Future<void>.delayed(Duration.zero);
        await _emit(
          'OnConnectionStateChanged',
          _connectionState(0, reasonCode: 19, reasonString: 'local disconnect'),
        );
        return true;
      case 'discoverServices':
        discoverCount++;
        _servicesReady = true;
        await Future<void>.delayed(Duration.zero);
        await _emit('OnDiscoveredServices', {
          'remote_id': _address,
          'success': 1,
          'error_code': 0,
          'error_string': '',
          'services': [
            {
              'remote_id': _address,
              'service_uuid': _serviceUuid,
              'is_primary': 1,
              'characteristics': [
                _characteristic(_writeUuid, write: true, writeWithoutResponse: true),
                _characteristic(_readUuid, read: true, notify: true),
              ],
              'included_services': <dynamic>[],
            },
          ],
        });
        return true;
      case 'setNotifyValue':
        await Future<void>.delayed(Duration.zero);
        await _emit('OnDescriptorWritten', {
          'remote_id': _address,
          'service_uuid': _serviceUuid,
          'secondary_service_uuid': null,
          'characteristic_uuid': _readUuid,
          'descriptor_uuid': _cccdUuid,
          'value': '0100',
          'success': 1,
          'error_code': 0,
          'error_string': '',
        });
        return true;
      case 'writeCharacteristic':
        if (!_servicesReady) {
          throw PlatformException(
            code: 'writeCharacteristic',
            message: "primary service not found '01a0'",
          );
        }
        writeCount++;
        await Future<void>.delayed(Duration.zero);
        await _emit('OnCharacteristicWritten', _characteristicData('01'));
        return true;
      default:
        return null;
    }
  }

  Future<void> _emit(String method, Map<dynamic, dynamic> arguments) {
    final data = _codec.encodeMethodCall(MethodCall(method, arguments));
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(_channelName, data, (ByteData? _) {});
  }

  static Map<String, dynamic> _connectionState(
    int state, {
    int? reasonCode,
    String? reasonString,
  }) =>
      {
        'remote_id': _address,
        'connection_state': state,
        'disconnect_reason_code': reasonCode,
        'disconnect_reason_string': reasonString,
      };

  static Map<String, dynamic> _characteristic(
    String uuid, {
    bool read = false,
    bool write = false,
    bool writeWithoutResponse = false,
    bool notify = false,
  }) =>
      {
        'remote_id': _address,
        'service_uuid': _serviceUuid,
        'secondary_service_uuid': null,
        'characteristic_uuid': uuid,
        'descriptors': <dynamic>[],
        'properties': {
          'broadcast': 0,
          'read': read ? 1 : 0,
          'write_without_response': writeWithoutResponse ? 1 : 0,
          'write': write ? 1 : 0,
          'notify': notify ? 1 : 0,
          'indicate': 0,
          'authenticated_signed_writes': 0,
          'extended_properties': 0,
          'notify_encryption_required': 0,
          'indicate_encryption_required': 0,
        },
      };

  static Map<String, dynamic> _characteristicData(String hex) => {
        'remote_id': _address,
        'service_uuid': _serviceUuid,
        'secondary_service_uuid': null,
        'characteristic_uuid': _writeUuid,
        'value': hex,
        'success': 1,
        'error_code': 0,
        'error_string': '',
      };
}
