import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_baji_demo/protocol/baji_protocol.dart';
import 'package:flutter_baji_demo/protocol/command_codec.dart';
import 'package:flutter_baji_demo/transfer/jpg_bin_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List textBytes(String text) => Uint8List.fromList(utf8.encode(text));

int u16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void main() {
  test('header matches working vendor bin layout', () {
    final jpeg = textBytes('123456789');
    final bin = JpgBinEncoder.encode(jpeg, width: 100, height: 200);

    final expectedHeader = Uint8List.fromList([
      0x49, 0x4D, 0x42, 0x00,
      0x04, 0x00, 0x00, 0x00,
      0x29, 0x00, 0x00, 0x00,
      0x0B, 0x00, 0x00, 0x00,
      0x64, 0x00, 0xC8, 0x00,
      0x24, 0x00, 0x00, 0x00,
      0x09, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
    ]);

    expect(bin.length, 36 + jpeg.length);
    expect(bin.sublist(0, 36), expectedHeader);
    expect(bin.sublist(36), jpeg);
  });

  test('reproduces the working vendor bin byte for byte', () {
    final vendor = File('test/fixtures/vendor_album.bin').readAsBytesSync();
    final jpeg = vendor.sublist(JpgBinEncoder.headerSize);
    final encoded = JpgBinEncoder.encode(jpeg, width: 368, height: 368);
    expect(encoded, vendor);
  });

  test('field values stay consistent', () {
    final bin = JpgBinEncoder.encode(textBytes('abc'), width: 10, height: 20);
    expect(u32(bin, 4), 4);
    expect(u32(bin, 8), bin.length - 4);
    expect(bin[12], JpgBinEncoder.pixelFmtJpeg);
    expect(bin[13], 0);
    expect(u16(bin, 14), 0);
    expect(u16(bin, 16), 10);
    expect(u16(bin, 18), 20);
    expect(u32(bin, 20), 36);
    expect(u32(bin, 24), 3);
    expect(u32(bin, 28), 0);
    expect(u32(bin, 32), 0);
    expect(JpgBinEncoder.metadataSize, 24);
  });

  test('dimensions parsed from jpeg sof when not supplied', () {
    final bin = JpgBinEncoder.encode(fakeJpeg(320, 240));
    expect(u16(bin, 16), 320);
    expect(u16(bin, 18), 240);
  });

  test('supplied dimensions take precedence over jpeg', () {
    final bin = JpgBinEncoder.encode(
      fakeJpeg(320, 240),
      width: 100,
      height: 200,
    );
    expect(u16(bin, 16), 100);
    expect(u16(bin, 18), 200);
  });

  test('non jpeg without dimensions writes zero size', () {
    final bin = JpgBinEncoder.encode(textBytes('not-a-jpeg'));
    expect(u16(bin, 16), 0);
    expect(u16(bin, 18), 0);
    expect(bin.length, 36 + 'not-a-jpeg'.length);
  });

  test('bin bytes are embedded in json file chunk', () {
    final bin = JpgBinEncoder.encode(fakeJpeg(64, 64));
    final payload = CommandCodec.fileChunk(
      6,
      bin,
      encoding: DataEncoding.jsonArray,
    );
    final obj = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    expect(obj['type'], 6);
    expect((obj['data'] as List).cast<int>(), bin);
  });
}

/// 最小 JPEG 骨架：SOI + APP0 + SOF0 + SOS + 数据 + EOI。
Uint8List fakeJpeg(int width, int height) {
  final out = BytesBuilder();
  out.add([0xFF, 0xD8]);
  out.add([0xFF, 0xE0, 0x00, 0x10]);
  out.add(ascii.encode('JFIF'));
  out.add([0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  out.add([0xFF, 0xC0, 0x00, 0x11, 0x08, (height >> 8) & 0xFF, height & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF]);
  out.add([0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]);
  out.add([0xFF, 0xDA, 0x00, 0x0C]);
  out.add([0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00]);
  out.add([0x12, 0x34, 0x56, 0x78]);
  out.add([0xFF, 0xD9]);
  return out.toBytes();
}
