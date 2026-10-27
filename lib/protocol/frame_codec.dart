import 'dart:typed_data';

import 'baji_frame.dart';
import 'baji_protocol.dart';

/// 二进制帧编解码，同时兼容两种帧头。
abstract final class FrameCodec {
  static const int headToApp = 0xA0;
  static const int headToDevice = 0xB1;

  static const int headerSizeDocumented = 8;
  static const int headerSizeCompact = 5;
  static const int checksumSize = 1;

  /// 文档示例：0xA0 03 00 01 01 5B，和 = 0xA5，补码 0x5B。
  static int checksum(Uint8List bytes, [int from = 0, int? until]) {
    final end = until ?? bytes.length;
    var sum = 0;
    for (var index = from; index < end; index++) {
      sum += bytes[index] & 0xFF;
    }
    return (0x100 - (sum & 0xFF)) & 0xFF;
  }

  static Uint8List encode({
    required int head,
    required int type,
    required int totalPackets,
    required int packetIndex,
    required Uint8List payload,
    FrameFormat format = FrameFormat.documented8,
  }) {
    final maxPayload = BajiConfig.maxDataPayload(format);
    if (payload.length > maxPayload) {
      throw ArgumentError('payload ${payload.length} exceeds $maxPayload for $format');
    }
    final headerSize = _headerSize(format);
    final frame = Uint8List(headerSize + payload.length + checksumSize);
    frame[0] = head & 0xFF;
    frame[1] = type & 0xFF;
    if (format == FrameFormat.compact5) {
      _putU16(frame, 2, totalPackets);
      frame[4] = payload.length & 0xFF;
    } else {
      _putU16(frame, 2, totalPackets);
      _putU16(frame, 4, packetIndex);
      _putU16(frame, 6, payload.length);
    }
    frame.setRange(headerSize, headerSize + payload.length, payload);
    frame[frame.length - 1] = checksum(frame, 0, frame.length - 1);
    return frame;
  }

  /// 将一段数据域拆成若干帧。单包时两个序号字段都写 0。
  static List<Uint8List> encodeMessage({
    required int head,
    required int type,
    required Uint8List payload,
    PacketIndexPolicy? policy,
    FrameFormat? format,
  }) {
    final selectedFormat = format ?? BajiConfig.frameFormat;
    final selectedPolicy = policy ?? BajiConfig.packetIndexPolicy;
    final max = BajiConfig.maxDataPayload(selectedFormat);
    if (payload.length <= max) {
      return [
        encode(
          head: head,
          type: type,
          totalPackets: 0,
          packetIndex: 0,
          payload: payload,
          format: selectedFormat,
        ),
      ];
    }
    final chunkCount = (payload.length + max - 1) ~/ max;
    return List<Uint8List>.generate(chunkCount, (index) {
      final from = index * max;
      final to = from + max < payload.length ? from + max : payload.length;
      return encode(
        head: head,
        type: type,
        totalPackets: chunkCount,
        packetIndex: packetIndexFor(selectedPolicy, index, chunkCount),
        payload: Uint8List.sublistView(payload, from, to),
        format: selectedFormat,
      );
    });
  }

  static int packetIndexFor(PacketIndexPolicy policy, int index, int total) =>
      switch (policy) {
        PacketIndexPolicy.ascending => index + 1,
        PacketIndexPolicy.countdown => total - index,
        PacketIndexPolicy.countdownToZero => total - 1 - index,
      };

  /// 先按配置格式解析，再尝试另一种格式；校验失败、长度不符、未知协议头返回 null。
  static BajiFrame? decode(Uint8List raw) => BajiConfig.frameFormat == FrameFormat.compact5
      ? _decodeCompact(raw) ?? _decodeDocumented(raw)
      : _decodeDocumented(raw) ?? _decodeCompact(raw);

  static BajiFrame? _decodeDocumented(Uint8List raw) {
    if (raw.length < headerSizeDocumented + checksumSize) return null;
    if (!_validHeader(raw, headerSizeDocumented)) return null;

    final type = raw[1] & 0xFF;
    final totalPackets = _readU16(raw, 2);
    final packetIndex = _readU16(raw, 4);
    final dataLength = _readU16(raw, 6);
    if (dataLength > BajiConfig.maxFramePayload) return null;
    if (raw.length != headerSizeDocumented + dataLength + checksumSize) return null;

    return BajiFrame(
      head: raw[0] & 0xFF,
      type: type,
      totalPackets: totalPackets,
      packetIndex: packetIndex,
      payload: Uint8List.sublistView(raw, headerSizeDocumented, headerSizeDocumented + dataLength),
      format: FrameFormat.documented8,
    );
  }

  static BajiFrame? _decodeCompact(Uint8List raw) {
    if (raw.length < headerSizeCompact + checksumSize) return null;
    final head = raw[0] & 0xFF;
    if (head != headToApp && head != headToDevice) return null;

    final type = raw[1] & 0xFF;
    final totalPackets = _readU16(raw, 2);
    final declaredLength = raw[4] & 0xFF;
    const start = headerSizeCompact;
    final checksumOk = checksum(raw) == 0;

    bool isJson(Uint8List bytes) =>
        bytes.isNotEmpty && bytes.first == 0x7B && bytes.last == 0x7D;

    BajiFrame build(Uint8List payload, bool checksumValid) => BajiFrame(
          head: head,
          type: type,
          totalPackets: totalPackets,
          packetIndex: 0,
          payload: payload,
          format: FrameFormat.compact5,
          checksumValid: checksumValid,
        );

    if (raw.length == start + declaredLength + checksumSize) {
      final payload = Uint8List.sublistView(raw, start, start + declaredLength);
      if (checksumOk) return build(payload, true);
      if (isJson(payload)) return build(payload, false);
      return null;
    }

    if (raw.length == start + declaredLength) {
      // 固件省略校验字节：HEAD TYPE TOTAL(2) LEN(1) DATA
      final payload = Uint8List.sublistView(raw, start);
      if (isJson(payload)) return build(payload, false);
      if (checksumOk && payload.isNotEmpty) {
        final withoutTrailer = Uint8List.sublistView(payload, 0, payload.length - 1);
        if (isJson(withoutTrailer)) return build(withoutTrailer, true);
      }
      return null;
    }

    return null;
  }

  static bool _validHeader(Uint8List raw, int headerSize) {
    if (raw.length < headerSize + checksumSize) return false;
    if (checksum(raw) != 0) return false;
    final head = raw[0] & 0xFF;
    return head == headToApp || head == headToDevice;
  }

  static int _headerSize(FrameFormat format) =>
      format == FrameFormat.documented8 ? headerSizeDocumented : headerSizeCompact;

  static void _putU16(Uint8List target, int offset, int value) {
    target[offset] = (value >> 8) & 0xFF;
    target[offset + 1] = value & 0xFF;
  }

  static int _readU16(Uint8List source, int offset) =>
      ((source[offset] & 0xFF) << 8) | (source[offset + 1] & 0xFF);
}
