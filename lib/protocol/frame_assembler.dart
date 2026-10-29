import 'dart:typed_data';

import 'baji_frame.dart';
import 'baji_protocol.dart';

/// 设备上报分包重组：documented8 按包号排序，compact5 按到达顺序追加。
class FrameAssembler {
  FrameAssembler({PacketIndexPolicy? policy})
      : policy = policy ?? BajiConfig.packetIndexPolicy;

  final PacketIndexPolicy policy;
  final Map<int, _Session> _sessions = {};

  /// 返回重组完成的数据域；尚未收齐返回 null。
  Uint8List? offer(BajiFrame frame) {
    if (frame.isSinglePacket) {
      _sessions.remove(frame.type);
      return frame.payload;
    }

    final total = frame.totalPackets;
    final current = _sessions[frame.type];
    final session = current == null || current.total != total
        ? _Session(total)
        : current;
    _sessions[frame.type] = session;

    if (frame.format == FrameFormat.compact5) {
      session.ordered.add(frame.payload);
      if (session.ordered.length < total) return null;
      _sessions.remove(frame.type);
      return _concatenate(session.ordered);
    }

    session.parts[frame.packetIndex] = frame.payload;
    if (session.parts.length < total) return null;

    _sessions.remove(frame.type);
    final indices = switch (policy) {
      PacketIndexPolicy.ascending => List.generate(total, (index) => index + 1),
      PacketIndexPolicy.countdown => List.generate(total, (index) => total - index),
      PacketIndexPolicy.countdownToZero =>
        List.generate(total, (index) => total - 1 - index),
    };
    final ordered = <Uint8List>[];
    for (final index in indices) {
      final part = session.parts[index];
      if (part != null) ordered.add(part);
    }
    if (ordered.length != total) return null;
    return _concatenate(ordered);
  }

  void reset() => _sessions.clear();

  Uint8List _concatenate(List<Uint8List> chunks) {
    final size = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Uint8List(size);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }
}

class _Session {
  _Session(this.total);

  final int total;
  final Map<int, Uint8List> parts = {};
  final List<Uint8List> ordered = [];
}
