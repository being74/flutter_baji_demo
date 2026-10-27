import 'dart:typed_data';

import 'baji_protocol.dart';

/// 一帧完整的协议数据（不含和校验字节）。
class BajiFrame {
  const BajiFrame({
    required this.head,
    required this.type,
    required this.totalPackets,
    required this.packetIndex,
    required this.payload,
    this.format = FrameFormat.documented8,
    this.checksumValid = true,
  });

  final int head;
  final int type;
  final int totalPackets;
  final int packetIndex;
  final Uint8List payload;
  final FrameFormat format;

  /// false 表示设备帧没有校验字节，或校验算法与文档不一致；仅供诊断。
  final bool checksumValid;

  bool get isSinglePacket => totalPackets == 0;
}
