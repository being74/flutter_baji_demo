import 'dart:typed_data';

import 'package:flutter_baji_demo/protocol/baji_frame.dart';
import 'package:flutter_baji_demo/protocol/baji_protocol.dart';
import 'package:flutter_baji_demo/protocol/command_codec.dart';
import 'package:flutter_baji_demo/protocol/device_message.dart';
import 'package:flutter_baji_demo/protocol/frame_assembler.dart';
import 'package:flutter_baji_demo/protocol/frame_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

Uint8List payloadOf(String text) => Uint8List.fromList(text.codeUnits);

int sumOf(Uint8List data) =>
    data.fold<int>(0, (sum, byte) => (sum + byte) & 0xFF);

void main() {
  setUp(() {
    BajiConfig.frameFormat = FrameFormat.documented8;
    BajiConfig.packetIndexPolicy = PacketIndexPolicy.countdownToZero;
  });

  test('checksum matches document example', () {
    expect(FrameCodec.checksum(bytes([0xA0, 0x03, 0x00, 0x01, 0x01])), 0x5B);
  });

  test('single packet round trip', () {
    final payload = payloadOf('{"type":1}');
    final raw = FrameCodec.encode(
      head: FrameCodec.headToDevice,
      type: BajiCommands.activation,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
    );

    expect(raw.length, 9 + payload.length);
    expect(sumOf(raw) & 0xFF, 0);

    final frame = FrameCodec.decode(raw)!;
    expect(frame.head, FrameCodec.headToDevice);
    expect(frame.type, BajiCommands.activation);
    expect(frame.totalPackets, 0);
    expect(frame.packetIndex, 0);
    expect(frame.payload, payload);
  });

  test('496 byte payload stays single packet', () {
    final payload = Uint8List(496)..[0] = 1;
    final frames = FrameCodec.encodeMessage(
      head: FrameCodec.headToDevice,
      type: 6,
      payload: payload,
      policy: PacketIndexPolicy.ascending,
      format: FrameFormat.documented8,
    );
    expect(frames.length, 1);
    expect(FrameCodec.decode(frames.single)!.payload, payload);
  });

  test('497 byte payload splits into two packets', () {
    final payload = Uint8List(497);
    final frames = FrameCodec.encodeMessage(
      head: FrameCodec.headToDevice,
      type: 6,
      payload: payload,
      policy: PacketIndexPolicy.ascending,
      format: FrameFormat.documented8,
    );
    expect(frames.length, 2);
    expect(FrameCodec.decode(frames[0])!.totalPackets, 2);
    expect(FrameCodec.decode(frames[0])!.packetIndex, 1);
    expect(FrameCodec.decode(frames[1])!.packetIndex, 2);
    expect(FrameCodec.decode(frames[1])!.payload.length, 1);
  });

  test('countdown policy numbers packets from total down to one', () {
    final frames = FrameCodec.encodeMessage(
      head: FrameCodec.headToDevice,
      type: 6,
      payload: Uint8List(1000),
      policy: PacketIndexPolicy.countdown,
      format: FrameFormat.documented8,
    );
    expect(frames.length, 3);
    expect(FrameCodec.decode(frames[0])!.packetIndex, 3);
    expect(FrameCodec.decode(frames[1])!.packetIndex, 2);
    expect(FrameCodec.decode(frames[2])!.packetIndex, 1);
  });

  test('empty payload still produces one valid frame', () {
    final raw = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: 7,
      totalPackets: 0,
      packetIndex: 0,
      payload: Uint8List(0),
    );
    final frame = FrameCodec.decode(raw)!;
    expect(frame.payload.length, 0);
  });

  test('compact frame round trip', () {
    final payload = payloadOf('{"type":13,"allspace":16384,"freespace":4356}');
    final raw = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: BajiCommands.deviceSettings,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
      format: FrameFormat.compact5,
    );
    expect(raw.length, 5 + payload.length + 1);
    expect(raw[4], payload.length);

    final frame = FrameCodec.decode(raw)!;
    expect(frame.format, FrameFormat.compact5);
    expect(frame.type, BajiCommands.deviceSettings);
    expect(frame.totalPackets, 0);
    expect(frame.payload, payload);
  });

  test('compact frames split and reassemble in arrival order', () {
    final payload = Uint8List(1000);
    final frames = FrameCodec.encodeMessage(
      head: FrameCodec.headToDevice,
      type: 6,
      payload: payload,
      policy: PacketIndexPolicy.ascending,
      format: FrameFormat.compact5,
    );
    expect(frames.length, 4);

    final assembler = FrameAssembler();
    for (final raw in frames.take(3)) {
      expect(assembler.offer(FrameCodec.decode(raw)!), isNull);
    }
    expect(assembler.offer(FrameCodec.decode(frames.last)!), payload);
  });

  test('decode prefers configured format but accepts the other', () {
    final payload = payloadOf('{"type":7,"version":"1.0"}');
    final documented = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: BajiCommands.version,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
      format: FrameFormat.documented8,
    );
    final compact = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: BajiCommands.version,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
      format: FrameFormat.compact5,
    );
    expect(FrameCodec.decode(documented)!.format, FrameFormat.documented8);
    expect(FrameCodec.decode(compact)!.format, FrameFormat.compact5);
  });

  test('compact frame without checksum byte is accepted for diagnostics', () {
    final payload = payloadOf('{"type":13,"allspace":16384}');
    final full = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: BajiCommands.deviceSettings,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
      format: FrameFormat.compact5,
    );
    final frame = FrameCodec.decode(Uint8List.sublistView(full, 0, full.length - 1))!;
    expect(frame.format, FrameFormat.compact5);
    expect(frame.checksumValid, false);
    expect(frame.payload, payload);
  });

  test('compact frame with mismatched checksum is accepted when payload looks like json', () {
    final payload = payloadOf('{"type":13,"freespace":4356}');
    final full = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: BajiCommands.deviceSettings,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
      format: FrameFormat.compact5,
    );
    full[full.length - 1] = full.last ^ 0xFF;
    final frame = FrameCodec.decode(full)!;
    expect(frame.checksumValid, false);
    expect(frame.payload, payload);
  });

  test('compact frame with bad checksum and binary payload is rejected', () {
    final payload = Uint8List.fromList(List<int>.generate(10, (index) => index));
    final full = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: 6,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
      format: FrameFormat.compact5,
    );
    full[full.length - 1] = full.last ^ 0xFF;
    expect(FrameCodec.decode(full), isNull);
  });

  test('reproduces e-BADGE 0x0d frame layout', () {
    final payload = payloadOf(
      '{"type":13,"allspace":16384,"freespace":4300,"devname":"Baji12345",'
      '"size":[1,104,1,104],"brand":0}',
    );
    expect(payload.length, 98);

    final raw = FrameCodec.encode(
      head: FrameCodec.headToApp,
      type: BajiCommands.deviceSettings,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
      format: FrameFormat.compact5,
    );
    expect(raw.length, 104);
    expect(raw[4], 0x62);
    expect(sumOf(raw) & 0xFF, 0);

    final frame = FrameCodec.decode(raw)!;
    expect(frame.format, FrameFormat.compact5);
    expect(frame.checksumValid, true);
    expect(frame.payload, payload);

    final message = CommandCodec.parse(frame.payload)! as DeviceInfoMessage;
    expect(message.totalSpace, 16384);
    expect(message.freeSpace, 4300);
    expect(message.devName, 'Baji12345');
  });

  test('documented activation query uses eight byte header', () {
    final payload = payloadOf('{"type":1}');
    final raw = FrameCodec.encodeMessage(
      head: FrameCodec.headToDevice,
      type: BajiCommands.activation,
      payload: payload,
      policy: PacketIndexPolicy.ascending,
      format: FrameFormat.documented8,
    ).single;

    expect(raw.length, 19);
    expect(raw.sublist(0, 8), [0xB1, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A]);
    expect(raw.sublist(8, 18), payload);
    expect(sumOf(raw) & 0xFF, 0);
  });

  test('multi packet frames follow documented table', () {
    final frames = FrameCodec.encodeMessage(
      head: FrameCodec.headToDevice,
      type: 6,
      payload: Uint8List(1000),
      policy: PacketIndexPolicy.countdownToZero,
      format: FrameFormat.documented8,
    );
    expect(frames.length, 3);
    for (var index = 0; index < frames.length; index++) {
      final frame = FrameCodec.decode(frames[index])!;
      expect(frame.head, FrameCodec.headToDevice);
      expect(frame.type, 6);
      expect(frame.totalPackets, 3);
      expect(frame.packetIndex, 2 - index);
      expect(frame.payload.length <= 496, isTrue);
      expect(sumOf(frames[index]) & 0xFF, 0);
    }
  });

  test('countdown to zero numbers packets from total minus one down to zero', () {
    final frames = FrameCodec.encodeMessage(
      head: FrameCodec.headToDevice,
      type: 6,
      payload: Uint8List(1000),
      policy: PacketIndexPolicy.countdownToZero,
      format: FrameFormat.documented8,
    );
    expect(FrameCodec.decode(frames[0])!.packetIndex, 2);
    expect(FrameCodec.decode(frames[1])!.packetIndex, 1);
    expect(FrameCodec.decode(frames[2])!.packetIndex, 0);
  });

  test('corrupted checksum is rejected', () {
    final raw = FrameCodec.encode(
      head: FrameCodec.headToDevice,
      type: 1,
      totalPackets: 0,
      packetIndex: 0,
      payload: payloadOf('{"type":1}'),
    );
    raw[raw.length - 1] = raw.last + 1;
    expect(FrameCodec.decode(raw), isNull);
  });

  test('compact payload exceeding 255 bytes is rejected by encoder', () {
    expect(
      () => FrameCodec.encode(
        head: FrameCodec.headToDevice,
        type: 6,
        totalPackets: 0,
        packetIndex: 0,
        payload: Uint8List(256),
        format: FrameFormat.compact5,
      ),
      throwsArgumentError,
    );
  });

  test('baji frame equality is value based', () {
    final frame = BajiFrame(
      head: 0xA0,
      type: 1,
      totalPackets: 0,
      packetIndex: 0,
      payload: Uint8List.fromList([1, 2]),
    );
    expect(frame.isSinglePacket, isTrue);
  });
}
