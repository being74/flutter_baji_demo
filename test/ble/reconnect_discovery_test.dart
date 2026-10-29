import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_baji_demo/ble/baji_ble_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _address = '1A:7B:AB:C5:BC:B9';
const _serviceUuid = '000001a0-0000-1000-8000-00805f9b34fb';
const _writeUuid = '000001a1-0000-1000-8000-00805f9b34fb';
const _readUuid = '000001a2-0000-1000-8000-00805f9b34fb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('重连后重新发现 GATT 服务，写入不再报 primary service not found', () async {
    final platform = _FakeBlePlatform();
    FlutterBluePlusPlatform.instance = platform;
    final client = BajiBleClient();
    addTearDown(client.close);

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
  });
}

/// 模拟 Android GATT：断开后原生服务表清空，
/// 未重新 discoverServices 时写入返回 primary service not found。
base class _FakeBlePlatform extends FlutterBluePlusPlatform {
  final StreamController<BmConnectionStateResponse> _connection =
      StreamController<BmConnectionStateResponse>.broadcast();
  final StreamController<BmMtuChangedResponse> _mtu =
      StreamController<BmMtuChangedResponse>.broadcast();
  final StreamController<BmDiscoverServicesResult> _discovered =
      StreamController<BmDiscoverServicesResult>.broadcast();
  final StreamController<BmCharacteristicData> _written =
      StreamController<BmCharacteristicData>.broadcast();
  final StreamController<BmDescriptorData> _descriptorWritten =
      StreamController<BmDescriptorData>.broadcast();

  final DeviceIdentifier _remoteId = DeviceIdentifier(_address);

  int discoverCount = 0;
  int writeCount = 0;
  bool _servicesReady = false;

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged =>
      _connection.stream;

  @override
  Stream<BmMtuChangedResponse> get onMtuChanged => _mtu.stream;

  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices =>
      _discovered.stream;

  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten => _written.stream;

  @override
  Stream<BmDescriptorData> get onDescriptorWritten => _descriptorWritten.stream;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async {
    return BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
  }

  @override
  Future<bool> connect(BmConnectRequest request) async {
    _servicesReady = false;
    _connection.add(
      BmConnectionStateResponse(
        remoteId: _remoteId,
        connectionState: BmConnectionStateEnum.connected,
        disconnectReasonCode: null,
        disconnectReasonString: null,
      ),
    );
    _mtu.add(BmMtuChangedResponse(remoteId: _remoteId, mtu: 512));
    return true;
  }

  @override
  Future<bool> disconnect(BmDisconnectRequest request) async {
    _servicesReady = false;
    _connection.add(
      BmConnectionStateResponse(
        remoteId: _remoteId,
        connectionState: BmConnectionStateEnum.disconnected,
        disconnectReasonCode: 19,
        disconnectReasonString: 'local disconnect',
      ),
    );
    return true;
  }

  @override
  Future<bool> discoverServices(BmDiscoverServicesRequest request) async {
    discoverCount++;
    _servicesReady = true;
    _discovered.add(
      BmDiscoverServicesResult(
        remoteId: _remoteId,
        services: [_service],
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    return true;
  }

  @override
  Future<bool> setNotifyValue(BmSetNotifyValueRequest request) async => false;

  @override
  Future<bool> writeCharacteristic(BmWriteCharacteristicRequest request) async {
    if (!_servicesReady) {
      throw PlatformException(
        code: 'writeCharacteristic',
        message: "primary service not found '01a0'",
      );
    }
    writeCount++;
    _written.add(
      BmCharacteristicData(
        remoteId: _remoteId,
        primaryServiceUuid: request.primaryServiceUuid,
        serviceUuid: request.serviceUuid,
        characteristicUuid: request.characteristicUuid,
        instanceId: request.instanceId,
        value: request.value,
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    return true;
  }

  BmBluetoothService get _service => BmBluetoothService(
    remoteId: _remoteId,
    primaryServiceUuid: null,
    serviceUuid: Guid(_serviceUuid),
    characteristics: [
      BmBluetoothCharacteristic(
        remoteId: _remoteId,
        primaryServiceUuid: null,
        serviceUuid: Guid(_serviceUuid),
        characteristicUuid: Guid(_writeUuid),
        instanceId: 0,
        descriptors: const [],
        properties: _properties(write: true, writeWithoutResponse: true),
      ),
      BmBluetoothCharacteristic(
        remoteId: _remoteId,
        primaryServiceUuid: null,
        serviceUuid: Guid(_serviceUuid),
        characteristicUuid: Guid(_readUuid),
        instanceId: 1,
        descriptors: const [],
        properties: _properties(read: true, notify: true),
      ),
    ],
  );

  static BmCharacteristicProperties _properties({
    bool read = false,
    bool write = false,
    bool writeWithoutResponse = false,
    bool notify = false,
  }) {
    return BmCharacteristicProperties(
      broadcast: false,
      read: read,
      writeWithoutResponse: writeWithoutResponse,
      write: write,
      notify: notify,
      indicate: false,
      authenticatedSignedWrites: false,
      extendedProperties: false,
      notifyEncryptionRequired: false,
      indicateEncryptionRequired: false,
    );
  }
}
