import 'dart:convert';
import 'dart:typed_data';

/// JPEG 帧 → 动图 bin 容器，严格按厂商 docx 生成。
///
/// 布局：
/// ```
/// 文件头(32B)
///   0x12345678            固定
///   firstOffset - 8       首帧地址减 8（= 32 + 16N - 8）
///   frameCount            帧数
///   intervalMs            帧间隔
///   "output/<duration>ms\0" 12B，始终 NUL 结尾；100ms 放不下时退回 output/50ms\0
///   totalSize             bin 文件总大小
/// 地址表(N × 16B)
///   "frame_%05d."(12B) + 帧绝对偏移(4B)
/// 每帧
///   current(4B) + next(4B) + 24B 元数据 + JPEG
/// ```
abstract final class AnimBinEncoder {
  static const int magic = 0x12345678;
  static const int fileHeaderSize = 32;
  static const int tableEntrySize = 16;
  static const int frameHeaderSize = 32;
  static const int metadataSize = 24;
  static const int pixelFmtJpeg = 0x0B;

  static const int _maxFrames = 99999;
  static const int _durationLabelSize = 12;

  static Uint8List encode({
    required List<Uint8List> frames,
    required int width,
    required int height,
    required int intervalMs,
  }) {
    if (frames.isEmpty) throw ArgumentError('frames must not be empty');
    if (frames.length > _maxFrames) {
      throw ArgumentError('frames ${frames.length} exceeds $_maxFrames');
    }
    if (width < 0 || width > 0xFFFF) throw ArgumentError('width $width out of range');
    if (height < 0 || height > 0xFFFF) throw ArgumentError('height $height out of range');
    if (intervalMs < 0 || intervalMs > 999) {
      throw ArgumentError('intervalMs $intervalMs out of range');
    }

    final frameCount = frames.length;
    final firstOffset = fileHeaderSize + tableEntrySize * frameCount;
    final offsets = List<int>.filled(frameCount, 0);
    var cursor = firstOffset;
    for (var index = 0; index < frameCount; index++) {
      final jpeg = frames[index];
      if (jpeg.isEmpty) throw ArgumentError('frame $index is empty');
      offsets[index] = cursor;
      cursor += frameHeaderSize + jpeg.length;
    }
    final totalSize = cursor;

    final bin = Uint8List(totalSize);
    final data = ByteData.sublistView(bin);
    data.setUint32(0, magic, Endian.little);
    data.setUint32(4, firstOffset - 8, Endian.little);
    data.setUint32(8, frameCount, Endian.little);
    data.setUint32(12, intervalMs, Endian.little);
    bin.setRange(16, 16 + _durationLabelSize, _durationLabel(intervalMs));
    data.setUint32(28, totalSize, Endian.little);

    for (var index = 0; index < frameCount; index++) {
      final jpeg = frames[index];
      final tableOffset = fileHeaderSize + index * tableEntrySize;
      final tableLabel = ascii.encode('frame_${(index + 1).toString().padLeft(5, '0')}.');
      bin.setRange(tableOffset, tableOffset + 12, tableLabel);
      data.setUint32(tableOffset + 12, offsets[index], Endian.little);

      final base = offsets[index];
      final next = offsets[(index + 1) % frameCount];
      data.setUint32(base, offsets[index], Endian.little);
      data.setUint32(base + 4, next, Endian.little);
      bin[base + 8] = pixelFmtJpeg;
      bin[base + 9] = 0;
      data.setUint16(base + 10, 0, Endian.little);
      data.setUint16(base + 12, width, Endian.little);
      data.setUint16(base + 14, height, Endian.little);
      data.setUint32(base + 16, base + frameHeaderSize, Endian.little);
      data.setUint32(base + 20, jpeg.length, Endian.little);
      data.setUint32(base + 24, 0, Endian.little);
      data.setUint32(base + 28, 0, Endian.little);
      bin.setRange(base + frameHeaderSize, base + frameHeaderSize + jpeg.length, jpeg);
    }
    return bin;
  }

  /// docx 的 12B 字段以固定 `ms\0` 结尾。实测两份样本在 interval=100/50 时都写
  /// `output/50ms\0`；100ms 的 `output/100ms` 恰好 12B 且无 NUL，若设备按 C 字符串
  /// 读取会越界到 @28（文件大小）。因此：≤99ms 写实际时长并保留结尾 NUL，
  /// 放不下时退回样本一致的 `output/50ms\0`。
  static Uint8List _durationLabel(int intervalMs) {
    final label = Uint8List(_durationLabelSize);
    final preferred = 'output/${intervalMs}ms';
    final text = preferred.length <= _durationLabelSize - 1 ? preferred : 'output/50ms';
    label.setRange(0, text.length, ascii.encode(text));
    return label;
  }
}
