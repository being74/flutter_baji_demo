import 'dart:typed_data';

/// JPEG → 设备 IMB bin 容器。
///
/// 布局：`'IMB\0'(4) | 偏移(4) | 总长(4) | 元数据(24) | JPEG`，元数据依次为
/// format(1)、compress(1)、data_crc(2)、width(2)、height(2)、offset(4)、
/// len(4)、unzipOffset(4)、unzipLen(4)。
abstract final class JpgBinEncoder {
  static const int magicSize = 4;
  static const int metadataSize = 24;
  static const int headerSize = magicSize + 4 + 4 + metadataSize;
  static const int pixelFmtJpeg = 11;
  static const int compressNone = 0;

  static Uint8List encode(Uint8List jpeg, {int? width, int? height}) {
    final parsed = (width != null && width > 0 && height != null && height > 0)
        ? null
        : jpegSize(jpeg);
    final imageWidth = (width != null && width > 0) ? width : (parsed?.$1 ?? 0);
    final imageHeight = (height != null && height > 0) ? height : (parsed?.$2 ?? 0);

    final bin = Uint8List(headerSize + jpeg.length);
    final data = ByteData.sublistView(bin);
    bin[0] = 0x49; // I
    bin[1] = 0x4D; // M
    bin[2] = 0x42; // B
    bin[3] = 0;
    data.setUint32(4, magicSize, Endian.little);
    data.setUint32(8, bin.length - magicSize, Endian.little);
    bin[12] = pixelFmtJpeg;
    bin[13] = compressNone;
    // data_crc（0x0E..0x0F）保持 0：厂商可用样本即 0，算法未知。
    data.setUint16(16, imageWidth, Endian.little);
    data.setUint16(18, imageHeight, Endian.little);
    data.setUint32(20, headerSize, Endian.little);
    data.setUint32(24, jpeg.length, Endian.little);
    data.setUint32(28, 0, Endian.little);
    data.setUint32(32, 0, Endian.little);
    bin.setRange(headerSize, bin.length, jpeg);
    return bin;
  }

  /// 从 JPEG 的 SOF 段读取宽高；非 JPEG 或结构异常返回 null。
  static (int, int)? jpegSize(Uint8List jpeg) {
    if (jpeg.length < 4) return null;
    if (_u8(jpeg, 0) != 0xFF || _u8(jpeg, 1) != 0xD8) return null;
    var index = 2;
    while (index + 3 < jpeg.length) {
      if (_u8(jpeg, index) != 0xFF) return null;
      final marker = _u8(jpeg, index + 1);
      if (marker == 0xFF) {
        index++;
      } else if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        index += 2;
      } else if (marker == 0xD9 || marker == 0xDA) {
        return null;
      } else {
        final length = _readU16(jpeg, index + 2);
        if (length < 2) return null;
        final isSof = marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC;
        if (isSof) {
          if (index + 8 >= jpeg.length) return null;
          final height = _readU16(jpeg, index + 5);
          final width = _readU16(jpeg, index + 7);
          return (width, height);
        }
        index += 2 + length;
      }
    }
    return null;
  }

  static int _readU16(Uint8List source, int offset) =>
      (_u8(source, offset) << 8) | _u8(source, offset + 1);

  static int _u8(Uint8List source, int offset) => source[offset] & 0xFF;
}
