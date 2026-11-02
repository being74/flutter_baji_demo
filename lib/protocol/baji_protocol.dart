import 'dart:typed_data';

/// 协议联调开关集中在这里。
abstract final class BajiConfig {
  /// 单帧数据域上限（文档 2.1 节）。
  static const int maxFramePayload = 496;

  /// 分包序号策略。
  static PacketIndexPolicy packetIndexPolicy = PacketIndexPolicy.countdownToZero;

  /// 文件分片编码：保持 JSON 结构，data 内放图片字节。
  static DataEncoding dataEncoding = DataEncoding.jsonArray;

  /// 文件分片之间的发送间隔，避免 write without response 打爆设备缓冲。
  static Duration interChunkDelay = const Duration(milliseconds: 8);

  /// 帧头格式（仅影响 APP → Device 编码）。
  static FrameFormat frameFormat = FrameFormat.documented8;

  /// 是否逐帧输出文件传输的完整报文（只写日志）。
  static bool logFileFrames = true;

  /// 单帧文件写入失败后的重试次数。
  static int chunkWriteRetries = 3;

  /// 设备主动断开后是否自动重连。
  static bool autoReconnect = true;

  /// 鸿蒙专用：用指定地址代替扫描到的地址建链，现场兜底用。
  /// 通过 `--dart-define=OHOS_BLE_ADDRESS=XX:XX:XX:XX:XX:XX` 指定，为空不替换。
  static const String _addressOverrideEnv =
      String.fromEnvironment('OHOS_BLE_ADDRESS');

  static String? ohosAddressOverride =
      _addressOverrideEnv.isEmpty ? null : _addressOverrideEnv;

  /// 自动重连的退避间隔；列表长度即最大尝试次数。
  static List<Duration> autoReconnectDelays = const [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  /// 盲重试耗尽后，是否通过 BLE 扫描等待设备重新广播。
  static bool autoReconnectScan = true;

  /// 扫描等待自动重连的最长时间，默认 10 分钟。
  static Duration autoReconnectScanTimeout = const Duration(minutes: 10);

  /// 当前帧格式允许的最大数据域长度：5 字节头只有 1 字节长度字段。
  static int maxDataPayload([FrameFormat? format]) =>
      (format ?? frameFormat) == FrameFormat.compact5 ? 255 : maxFramePayload;

  /// 文件分片原始字节数，按编码方式反推，保证编码后不超过帧上限。
  static int rawChunkSize({DataEncoding? encoding, int headerBudget = 64}) {
    final selected = encoding ?? dataEncoding;
    if (selected == DataEncoding.rawBinary) return maxDataPayload();
    final budget = maxDataPayload() - headerBudget;
    final size = switch (selected) {
      DataEncoding.rawBinary => maxDataPayload(),
      DataEncoding.jsonArray => budget ~/ 4,
      DataEncoding.hexString => budget ~/ 2,
      DataEncoding.base64 => budget * 3 ~/ 4,
    };
    return size < 16 ? 16 : size;
  }
}

enum PacketIndexPolicy {
  /// 1, 2, ..., N
  ascending,

  /// N, N-1, ..., 1
  countdown,

  /// N-1, N-2, ..., 0（文档：首包号最大、尾包 0x0000）
  countdownToZero,
}

enum FrameFormat {
  /// 文档格式：HEAD TYPE TOTAL(2) CUR(2) LEN(2) DATA
  documented8,

  /// e-BADGE 实测格式：HEAD TYPE TOTAL(2) LEN(1) DATA DCHK
  compact5,
}

enum DataEncoding {
  /// 直接把图片/文件分片作为 DATA，type 由帧头携带，不再包 JSON。
  rawBinary,

  /// {"type":X,"data":[1,2,3]}
  jsonArray,

  /// {"type":X,"data":"010203"}
  hexString,

  /// {"type":X,"data":"AQID"}
  base64,
}

abstract final class BajiUuids {
  /// 设备服务与特征值：服务 `0x01A0`、写 `0x01A1`（write without response）、
  /// 读/通知 `0x01A2`（notify）。
  static const String service = '000001a0-0000-1000-8000-00805f9b34fb';
  static const String write = '000001a1-0000-1000-8000-00805f9b34fb';
  static const String read = '000001a2-0000-1000-8000-00805f9b34fb';
  static const String cccd = '00002902-0000-1000-8000-00805f9b34fb';

  /// 兼容组 `0x0150/0151/0152`，供仍使用该组 UUID 的固件。
  static const String legacyService = '00000150-0000-1000-8000-00805f9b34fb';
  static const String legacyWrite = '00000151-0000-1000-8000-00805f9b34fb';
  static const String legacyRead = '00000152-0000-1000-8000-00805f9b34fb';

  /// 建链时按优先级逐组精确匹配，整组命中即采用。
  static const List<({String service, String write, String read})> sets = [
    (service: service, write: write, read: read),
    (service: legacyService, write: legacyWrite, read: legacyRead),
  ];

  /// UUID 是否属于任一已知服务组。
  static bool matchesService(String uuid) => sets.any(
        (set) =>
            uuid == set.service || _shortOf(uuid) == _shortOf(set.service),
      );

  static int? _shortOf(String uuid) {
    if (uuid.length != 36) return null;
    const suffix = '-0000-1000-8000-00805f9b34fb';
    if (!uuid.startsWith('0000') || !uuid.toLowerCase().endsWith(suffix)) {
      return null;
    }
    return int.tryParse(uuid.substring(4, 8), radix: 16);
  }

  /// 回退匹配时排除的通用 GATT 服务，避免误选电池/设备信息等特征值。
  static const Set<int> standardServiceIds = {
    0x1800, 0x1801, 0x1805, 0x1809, 0x180A, 0x180D, 0x180F,
    0x1810, 0x1811, 0x1812, 0x1816, 0x1818, 0x181A, 0x181C,
    0x181E, 0x1826, 0x1844, 0x1846,
  };
}

abstract final class BajiCommands {
  static const int activation = 0x01;
  static const int ota = 0x02;
  static const int bootAnimation = 0x03;
  static const int watchFace = 0x04;
  static const int ambience = 0x05;
  static const int album = 0x06;
  static const int version = 0x07;
  static const int activationTime = 0x08;
  static const int lyricBackground = 0x09;
  static const int marquee = 0x0C;
  static const int deviceSettings = 0x0D;
  static const int identity = 0x0E;
}

/// 大写空格分隔的十六进制，可限制长度。
String toHex(Uint8List bytes, {int maxBytes = 1 << 30}) {
  final count = bytes.length <= maxBytes ? bytes.length : maxBytes;
  final buffer = StringBuffer();
  for (var index = 0; index < count; index++) {
    if (index > 0) buffer.write(' ');
    buffer.write(bytes[index].toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  if (bytes.length > maxBytes) buffer.write(' …');
  return buffer.toString();
}
