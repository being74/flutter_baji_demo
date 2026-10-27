import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_baji_demo/transfer/anim_bin_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

int readU16(Uint8List source, int offset) =>
    source[offset] | (source[offset + 1] << 8);

int readU32(Uint8List source, int offset) =>
    source[offset] |
    (source[offset + 1] << 8) |
    (source[offset + 2] << 16) |
    (source[offset + 3] << 24);

void main() {
  test('three frame bin matches docx formulas', () {
    final jpeg = Uint8List.fromList(
      List<int>.generate(255, (index) => index % 251),
    );
    final bin = AnimBinEncoder.encode(
      frames: List<Uint8List>.filled(3, jpeg),
      width: 256,
      height: 256,
      intervalMs: 50,
    );

    expect(bin.length, 941);
    expect(readU32(bin, 0), 0x12345678);
    expect(readU32(bin, 4), 72);
    expect(readU32(bin, 8), 3);
    expect(readU32(bin, 12), 50);
    expect(
      bin.sublist(16, 28),
      ascii.encode('output/50ms\u0000'),
    );
    expect(readU32(bin, 28), 941);

    expect(utf8.decode(bin.sublist(32, 44)), 'frame_00001.');
    expect(readU32(bin, 44), 80);
    expect(utf8.decode(bin.sublist(48, 60)), 'frame_00002.');
    expect(readU32(bin, 60), 367);
    expect(utf8.decode(bin.sublist(64, 76)), 'frame_00003.');
    expect(readU32(bin, 76), 654);

    assertFrame(bin, frameOffset: 80, nextOffset: 367, jpeg: jpeg);
    assertFrame(bin, frameOffset: 367, nextOffset: 654, jpeg: jpeg);
    assertFrame(bin, frameOffset: 654, nextOffset: 80, jpeg: jpeg);
  });

  test('single frame loops to itself and 100ms label is NUL terminated', () {
    final jpeg = Uint8List.fromList(List<int>.generate(10, (index) => index));
    final bin = AnimBinEncoder.encode(
      frames: [jpeg],
      width: 368,
      height: 368,
      intervalMs: 100,
    );

    expect(bin.length, 32 + 16 + 32 + jpeg.length);
    expect(readU32(bin, 4), 40);
    expect(readU32(bin, 8), 1);
    expect(readU32(bin, 12), 100);
    expect(utf8.decode(bin.sublist(16, 27)), 'output/50ms');
    expect(bin[27], 0);
    expect(readU32(bin, 28), bin.length);
    expect(readU32(bin, 44), 48);
    assertFrame(bin, frameOffset: 48, nextOffset: 48, jpeg: jpeg);
    expect(bin.sublist(48 + 8, 48 + 12), [0x0B, 0, 0, 0]);
    expect(readU16(bin, 48 + 12), 0x0170);
    expect(readU16(bin, 48 + 14), 0x0170);
    expect(readU32(bin, 48 + 16), 80);
  });

  test('duration label keeps trailing NUL and falls back for 100ms', () {
    Uint8List label(int intervalMs) => AnimBinEncoder.encode(
          frames: [Uint8List.fromList([1])],
          width: 1,
          height: 1,
          intervalMs: intervalMs,
        ).sublist(16, 28);

    expect(utf8.decode(label(5)), 'output/5ms\u0000\u0000');
    expect(utf8.decode(label(50)), 'output/50ms\u0000');
    expect(utf8.decode(label(99)), 'output/99ms\u0000');
    expect(utf8.decode(label(100)), 'output/50ms\u0000');
    for (var interval = 0; interval <= 999; interval++) {
      expect(label(interval)[11], 0, reason: 'interval=$interval');
    }
  });

  test('empty frames are rejected', () {
    expect(
      () => AnimBinEncoder.encode(
        frames: const [],
        width: 1,
        height: 1,
        intervalMs: 50,
      ),
      throwsArgumentError,
    );
  });

  test('interval above 999 is rejected', () {
    expect(
      () => AnimBinEncoder.encode(
        frames: [Uint8List.fromList([1])],
        width: 1,
        height: 1,
        intervalMs: 1000,
      ),
      throwsArgumentError,
    );
  });
}

void assertFrame(
  Uint8List bin, {
  required int frameOffset,
  required int nextOffset,
  required Uint8List jpeg,
}) {
  expect(readU32(bin, frameOffset), frameOffset);
  expect(readU32(bin, frameOffset + 4), nextOffset);
  expect(bin[frameOffset + 8], 0x0B);
  expect(readU32(bin, frameOffset + 16), frameOffset + 32);
  expect(readU32(bin, frameOffset + 20), jpeg.length);
  expect(
    bin.sublist(frameOffset + 32, frameOffset + 32 + jpeg.length),
    jpeg,
  );
}
