import 'dart:convert';
import 'dart:typed_data';

import 'baji_protocol.dart';
import 'device_message.dart';

/// JSON 数据域的构造与解析。文档里的 0x0d 只是书写习惯，JSON 中必须写十进制。
abstract final class CommandCodec {
  static const String _hexChars = '0123456789abcdef';

  // ---------------------------------------------------------------- APP -> Device

  static Uint8List activationQuery() => _json({'type': BajiCommands.activation});

  static Uint8List versionQuery() => _json({'type': BajiCommands.version});

  static Uint8List identityReply(bool valid) => _json({
        'type': BajiCommands.identity,
        'Ret': valid ? 1 : 0,
      });

  static Uint8List updateActivationTime([DateTime? time]) {
    final now = time ?? DateTime.now();
    return _json({
      'type': BajiCommands.activationTime,
      'year': now.year,
      'mon': now.month,
      'day': now.day,
      'hour': now.hour,
      'min': now.minute,
      // 文档字段名为 mes，按「秒」处理。
      'mes': now.second,
    });
  }

  static Uint8List setDeviceSettings(int bgLight, int breather, String devName) =>
      _json({
        'type': BajiCommands.deviceSettings,
        'bglight': bgLight,
        'breather': breather,
        'devname': devName,
      });

  /// 表盘：先发文件名，再发该文件的数据分片。
  static Uint8List watchFaceFile(String fileName) => _json({
        'type': BajiCommands.watchFace,
        'filename': fileName,
      });

  /// 相册：先发本次传输的图片数量。
  static Uint8List albumCount(int count) => _json({
        'type': BajiCommands.album,
        'number': count,
      });

  /// 动态氛围信息包：先发 `{"type":5,"number":N}`，等待后再发图像数据。
  static Uint8List ambienceInfo(int number) => _json({
        'type': BajiCommands.ambience,
        'number': number,
      });

  /// 跑马灯信息包：分辨率 + 滚动方向 + 图片数量。size 为 2 字节宽 + 2 字节高。
  static Uint8List marqueeInfo(int width, int height, int display, int number) =>
      _json({
        'type': BajiCommands.marquee,
        'size': [
          (width >> 8) & 0xFF,
          width & 0xFF,
          (height >> 8) & 0xFF,
          height & 0xFF,
        ],
        'display': display,
        'number': number,
      });

  /// 单帧文件数据编码。
  static Uint8List fileChunk(
    int type,
    Uint8List chunk, {
    DataEncoding? encoding,
  }) {
    final selected = encoding ?? BajiConfig.dataEncoding;
    if (selected == DataEncoding.rawBinary) return chunk;
    final buffer = StringBuffer()
      ..write('{"type":')
      ..write(type)
      ..write(',"data":');
    switch (selected) {
      case DataEncoding.rawBinary:
        break;
      case DataEncoding.jsonArray:
        buffer.write('[');
        for (var index = 0; index < chunk.length; index++) {
          if (index > 0) buffer.write(',');
          buffer.write(chunk[index]);
        }
        buffer.write(']');
      case DataEncoding.hexString:
        buffer.write('"');
        for (final byte in chunk) {
          buffer
            ..write(_hexChars[(byte >> 4) & 0x0F])
            ..write(_hexChars[byte & 0x0F]);
        }
        buffer.write('"');
      case DataEncoding.base64:
        buffer
          ..write('"')
          ..write(base64Encode(chunk))
          ..write('"');
    }
    buffer.write('}');
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  /// 把整份文件编码成一个数据域，再按帧上限切片。
  static List<Uint8List> filePayloadChunks(
    int type,
    Uint8List bytes, {
    DataEncoding? encoding,
    int? maxChunk,
  }) =>
      splitPayload(
        fileChunk(type, bytes, encoding: encoding),
        maxChunk ?? BajiConfig.maxDataPayload(),
      );

  /// 相册整包：`{"type":6,"data":<raw bin>}`，data 后直接拼二进制，不是合法 JSON。
  static Uint8List rawFileEnvelope(int type, Uint8List bytes) {
    final prefix = ascii.encode('{"type":$type,"data":');
    final suffix = ascii.encode('}');
    final out = Uint8List(prefix.length + bytes.length + suffix.length);
    out.setRange(0, prefix.length, prefix);
    out.setRange(prefix.length, prefix.length + bytes.length, bytes);
    out.setRange(prefix.length + bytes.length, out.length, suffix);
    return out;
  }

  static List<Uint8List> rawFileEnvelopeChunks(
    int type,
    Uint8List bytes, {
    int? maxChunk,
  }) =>
      splitPayload(
        rawFileEnvelope(type, bytes),
        maxChunk ?? BajiConfig.maxDataPayload(),
      );

  /// 按 [maxChunk] 切片，返回的片段按原顺序拼接后与原数组完全一致。
  static List<Uint8List> splitPayload(Uint8List payload, int maxChunk) {
    if (maxChunk <= 0) throw ArgumentError.value(maxChunk, 'maxChunk');
    if (payload.isEmpty) return const [];
    final chunks = <Uint8List>[];
    for (var start = 0; start < payload.length; start += maxChunk) {
      final end = start + maxChunk < payload.length ? start + maxChunk : payload.length;
      chunks.add(Uint8List.sublistView(payload, start, end));
    }
    return chunks;
  }

  // ---------------------------------------------------------------- Device -> APP

  static DeviceMessage? parse(Uint8List payload) {
    var text = utf8.decode(payload, allowMalformed: true);
    text = text.replaceAll(RegExp(r'^[\s\u0000]+|[\s\u0000]+$'), '');
    if (text.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final type = _asInt(decoded['type']);
    if (type == null) return null;
    return switch (type) {
      BajiCommands.activation => ActivationMessage(_asInt(decoded['state']) == 1),
      BajiCommands.version => VersionMessage(_asString(decoded['version']) ?? ''),
      BajiCommands.deviceSettings => _parseDeviceInfo(decoded, text),
      BajiCommands.identity => _parseIdentity(decoded, type, text),
      _ => UnknownMessage(type, text),
    };
  }

  static DeviceMessage _parseIdentity(
    Map<String, dynamic> obj,
    int type,
    String raw,
  ) {
    if (obj.containsKey('IdCheck')) {
      return IdentityCheckMessage(_asString(obj['IdCheck']) ?? '');
    }
    if (obj.containsKey('Ret')) {
      return IdentityResultMessage(_asInt(obj['Ret']) == 1);
    }
    return UnknownMessage(type, raw);
  }

  static DeviceMessage _parseDeviceInfo(Map<String, dynamic> obj, String raw) {
    // 0x0d 双向：APP 下发的设置包不应被当成设备信息。
    if (!obj.containsKey('allspace') &&
        !obj.containsKey('freespace') &&
        !obj.containsKey('size') &&
        !obj.containsKey('brand')) {
      return UnknownMessage(BajiCommands.deviceSettings, raw);
    }
    final resolution = _parseResolution(obj['size']);
    final screen = _asInt(obj['screen']);
    return DeviceInfoMessage(
      totalSpace: _asInt(obj['allspace']),
      freeSpace: _asInt(obj['freespace']),
      devName: _asString(obj['devname']),
      width: resolution.$1,
      height: resolution.$2,
      // e-BADGE 上报 size 为 "368,368" 字符串时没有圆/方标志位，
      // 此时使用同帧的 screen 字段（0=圆屏，1=方屏）。
      roundScreen: resolution.$3 ?? (screen == null ? null : screen == 0),
      brand: _asInt(obj['brand']),
    );
  }

  /// 返回 (宽, 高, 是否圆屏)。
  static (int?, int?, bool?) _parseResolution(Object? element) {
    if (element == null) return (null, null, null);

    if (element is List && element.length >= 4) {
      final values = element.map((value) => _asInt(value) ?? 0).toList();
      final round = (values[0] & 0x80) == 0;
      final width = ((values[0] & 0x7F) << 8) | values[1];
      final height = (values[2] << 8) | values[3];
      return (width, height, round);
    }

    // 实测 e-BADGE 上报：{"size":"368,368"}；无圆/方标志位。
    if (element is String) {
      final parts = element
          .split(',')
          .map((part) => int.tryParse(part.trim()))
          .whereType<int>()
          .toList();
      if (parts.length >= 2) return (parts[0], parts[1], null);
    }

    final raw = element is num ? element.toInt() : int.tryParse(element.toString());
    if (raw == null) return (null, null, null);
    final round = (raw >> 31) == 0;
    final resolution = raw & 0x7FFFFFFF;
    return ((resolution >> 16) & 0x7FFF, resolution & 0xFFFF, round);
  }

  // ---------------------------------------------------------------- helpers

  static Uint8List _json(Map<String, Object?> value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _asString(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }
}
