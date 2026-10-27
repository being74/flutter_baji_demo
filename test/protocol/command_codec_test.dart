import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_baji_demo/protocol/baji_protocol.dart';
import 'package:flutter_baji_demo/protocol/command_codec.dart';
import 'package:flutter_baji_demo/protocol/device_message.dart';
import 'package:flutter_baji_demo/protocol/frame_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List textBytes(String text) => Uint8List.fromList(utf8.encode(text));

Map<String, dynamic> parseJson(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

Uint8List concat(List<Uint8List> chunks) {
  final size = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  final result = Uint8List(size);
  var offset = 0;
  for (final chunk in chunks) {
    result.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return result;
}

void main() {
  test('activation query uses decimal type', () {
    final obj = parseJson(CommandCodec.activationQuery());
    expect(obj['type'], 1);
    expect(obj.length, 1);
  });

  test('version query', () {
    expect(parseJson(CommandCodec.versionQuery())['type'], 7);
  });

  test('identity reply', () {
    expect(parseJson(CommandCodec.identityReply(true))['Ret'], 1);
    expect(parseJson(CommandCodec.identityReply(false))['Ret'], 0);
  });

  test('device settings', () {
    final obj = parseJson(CommandCodec.setDeviceSettings(60, 2, 'Baji01'));
    expect(obj['type'], 13);
    expect(obj['bglight'], 60);
    expect(obj['breather'], 2);
    expect(obj['devname'], 'Baji01');
  });

  test('activation time fields', () {
    final obj = parseJson(
      CommandCodec.updateActivationTime(DateTime(2026, 10, 21, 13, 45, 30)),
    );
    expect(obj['type'], 8);
    expect(obj['year'], 2026);
    expect(obj['mon'], 10);
    expect(obj['day'], 21);
    expect(obj['hour'], 13);
    expect(obj['min'], 45);
    expect(obj['mes'], 30);
  });

  test('watch face file name', () {
    final obj = parseJson(CommandCodec.watchFaceFile('hour.bin'));
    expect(obj['type'], 4);
    expect(obj['filename'], 'hour.bin');
  });

  test('album count', () {
    final obj = parseJson(CommandCodec.albumCount(3));
    expect(obj['type'], 6);
    expect(obj['number'], 3);
  });

  test('ambience info matches protocol frame sample', () {
    final payload = CommandCodec.ambienceInfo(1);
    expect(utf8.decode(payload), '{"type":5,"number":1}');

    final frame = FrameCodec.encode(
      head: FrameCodec.headToDevice,
      type: 5,
      totalPackets: 0,
      packetIndex: 0,
      payload: payload,
    );
    expect(
      frame,
      [
        0xB1, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x15,
        0x7B, 0x22, 0x74, 0x79, 0x70, 0x65, 0x22, 0x3A, 0x35, 0x2C,
        0x22, 0x6E, 0x75, 0x6D, 0x62, 0x65, 0x72, 0x22, 0x3A, 0x31, 0x7D,
        0x64,
      ],
    );
  });

  test('marquee info has four byte size', () {
    final obj = parseJson(CommandCodec.marqueeInfo(360, 360, 2, 2));
    expect(obj['type'], 12);
    expect(obj['size'], [1, 104, 1, 104]);
    expect(obj['display'], 2);
    expect(obj['number'], 2);
  });

  test('raw binary chunk returns original image bytes', () {
    final source = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02, 0x7D]);
    expect(
      CommandCodec.fileChunk(
        BajiCommands.album,
        source,
        encoding: DataEncoding.rawBinary,
      ),
      source,
    );
  });

  test('file chunk json array round trip', () {
    final source = Uint8List.fromList([0, 1, 2, 3, 127, 255, 128]);
    final obj = parseJson(
      CommandCodec.fileChunk(6, source, encoding: DataEncoding.jsonArray),
    );
    expect(obj['type'], 6);
    expect((obj['data'] as List).cast<int>(), source);
  });

  test('file chunk hex string', () {
    final obj = parseJson(
      CommandCodec.fileChunk(
        6,
        Uint8List.fromList([0x0A, 0x1B, 0xFF]),
        encoding: DataEncoding.hexString,
      ),
    );
    expect(obj['data'], '0a1bff');
  });

  test('file chunk base64', () {
    final obj = parseJson(
      CommandCodec.fileChunk(
        6,
        textBytes('hello'),
        encoding: DataEncoding.base64,
      ),
    );
    expect(obj['data'], 'aGVsbG8=');
  });

  test('parse activation state', () {
    final on = CommandCodec.parse(textBytes('{"type":1,"state":1}'))!;
    expect((on as ActivationMessage).activated, isTrue);
    final off = CommandCodec.parse(textBytes('{"type":1,"state":0}'))!;
    expect((off as ActivationMessage).activated, isFalse);
  });

  test('parse version', () {
    final message = CommandCodec.parse(
      textBytes('{"type":7,"version":"2024.01"}'),
    )! as VersionMessage;
    expect(message.version, '2024.01');
  });

  test('parse device info', () {
    final message = CommandCodec.parse(
      textBytes(
        '{"type":13,"allspace":1048576,"freespace":524288,'
        '"devname":"baji","size":[1,0,0,104],"brand":5}',
      ),
    )! as DeviceInfoMessage;
    expect(message.totalSpace, 1048576);
    expect(message.freeSpace, 524288);
    expect(message.devName, 'baji');
    expect(message.width, 256);
    expect(message.height, 104);
    expect(message.roundScreen, isTrue);
    expect(message.brand, 5);
  });

  test('parse device info with integer size', () {
    final message = CommandCodec.parse(
      textBytes('{"type":13,"size":-2147483648,"brand":5}'),
    )! as DeviceInfoMessage;
    expect(message.roundScreen, isFalse);
  });

  test('parse device info with comma string size', () {
    final message = CommandCodec.parse(
      textBytes(
        '{"type":13,"allspace":16384,"freespace":4364,"devname":"kop",'
        '"size":"368,368","screen":"0","brand":0}',
      ),
    )! as DeviceInfoMessage;
    expect(message.width, 368);
    expect(message.height, 368);
    expect(message.roundScreen, isTrue);
    expect(message.devName, 'kop');
    expect(message.totalSpace, 16384);
    expect(message.freeSpace, 4364);
  });

  test('parse identity check', () {
    final message = CommandCodec.parse(
      textBytes('{"type":14,"IdCheck":"123456789012"}'),
    )! as IdentityCheckMessage;
    expect(message.code, '123456789012');
  });

  test('parse identity result', () {
    final message = CommandCodec.parse(
      textBytes('{"type":14,"Ret":1}'),
    )! as IdentityResultMessage;
    expect(message.valid, isTrue);
  });

  test('parse tolerates trailing zero padding', () {
    final payload = Uint8List.fromList([
      ...textBytes('{"type":7,"version":"1.0"}'),
      ...List<int>.filled(10, 0),
    ]);
    final message = CommandCodec.parse(payload)! as VersionMessage;
    expect(message.version, '1.0');
  });

  test('invalid payload returns null', () {
    expect(CommandCodec.parse(textBytes('not json')), isNull);
    expect(CommandCodec.parse(Uint8List(0)), isNull);
    expect(CommandCodec.parse(textBytes('{"foo":1}')), isNull);
  });

  test('album payload is one json split across frames', () {
    final bytes = Uint8List.fromList(
      List<int>.generate(900, (index) => index % 251),
    );
    final whole = CommandCodec.fileChunk(
      6,
      bytes,
      encoding: DataEncoding.jsonArray,
    );
    final chunks = CommandCodec.filePayloadChunks(
      6,
      bytes,
      encoding: DataEncoding.jsonArray,
      maxChunk: 496,
    );
    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => chunk.length <= 496), isTrue);
    expect(utf8.decode(chunks.first), startsWith('{"type":6,"data":['));
    expect(utf8.decode(chunks.last), endsWith(']}'));
    expect(utf8.decode(chunks.first), isNot(endsWith(']}')));
    expect(concat(chunks), whole);
  });

  test('single frame carries complete json', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final whole = CommandCodec.fileChunk(
      6,
      bytes,
      encoding: DataEncoding.jsonArray,
    );
    final chunks = CommandCodec.filePayloadChunks(
      6,
      bytes,
      encoding: DataEncoding.jsonArray,
      maxChunk: 496,
    );
    expect(chunks.length, 1);
    expect(chunks.single, whole);
  });

  test('raw binary payload splits exactly', () {
    final bytes = Uint8List.fromList(List<int>.generate(700, (index) => index));
    final chunks = CommandCodec.filePayloadChunks(
      6,
      bytes,
      encoding: DataEncoding.rawBinary,
      maxChunk: 255,
    );
    expect(chunks.map((chunk) => chunk.length), [255, 255, 190]);
    expect(concat(chunks), bytes);
  });

  test('raw bin split keeps jpeg eoi in last chunk', () {
    final bin = Uint8List(1000)
      ..[998] = 0xFF
      ..[999] = 0xD9;
    final chunks = CommandCodec.filePayloadChunks(
      6,
      bin,
      encoding: DataEncoding.rawBinary,
      maxChunk: 496,
    );
    expect(chunks.length, 3);
    final last = chunks.last;
    expect(last[last.length - 2], 0xFF);
    expect(last.last, 0xD9);
    expect(concat(chunks), bin);
  });

  test('raw envelope wraps bin and keeps jpeg eoi before closing brace', () {
    final bin = Uint8List(1000)
      ..[998] = 0xFF
      ..[999] = 0xD9;
    final chunks = CommandCodec.rawFileEnvelopeChunks(6, bin, maxChunk: 496);
    final prefix = ascii.encode('{"type":6,"data":');
    final whole = concat(chunks);
    final last = chunks.last;

    expect(whole.sublist(0, prefix.length), prefix);
    expect(whole.last, 0x7D);
    expect(
      whole.sublist(prefix.length, whole.length - 1),
      bin,
    );
    expect(
      last.sublist(last.length - 3),
      [0xFF, 0xD9, 0x7D],
    );
  });

  test('empty payload returns no chunks', () {
    expect(CommandCodec.splitPayload(Uint8List(0), 496), isEmpty);
  });
}
