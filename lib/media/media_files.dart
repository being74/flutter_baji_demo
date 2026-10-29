import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as picker;
import 'package:file_picker_ohos/file_picker_ohos.dart' as picker_ohos;
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../core/baji_log.dart';
import '../core/platform.dart';

class PickedMedia {
  const PickedMedia({
    required this.name,
    required this.path,
    this.bytes,
  });

  final String name;
  final String path;
  final Uint8List? bytes;
}

/// 相册、GIF、视频与拍照的选材入口。
abstract final class MediaFiles {
  static const int maxFileBytes = 32 * 1024 * 1024;
  static const int maxAlbumImages = 255;
  static const int maxSlideshowImages = 30;
  static const List<String> _videoExtensions = [
    'mp4',
    'mov',
    'webm',
    'mkv',
    'avi',
    '3gp',
    'm4v',
  ];

  static final ImagePicker _imagePicker = ImagePicker();

  static Future<PickedMedia?> pickGif() async {
    final file = await _pickSingle(_MediaKind.gif);
    if (file == null) return null;
    if (!isGif(file.name)) throw StateError('${file.name} 不是 GIF 文件');
    final bytes = await File(file.path).readAsBytes();
    _checkFileSize(file.name, bytes.length);
    return PickedMedia(name: file.name, path: file.path, bytes: bytes);
  }

  static Future<PickedMedia?> pickVideo() async {
    final file = await _pickSingle(_MediaKind.video);
    if (file == null) return null;
    final length = await File(file.path).length();
    _checkFileSize(file.name, length);
    return PickedMedia(name: file.name, path: file.path);
  }

  /// 挑单个素材。鸿蒙必须走 `file_picker_ohos` 的 Dart 实现，且用图库选择器：
  /// 文件选择器默认停在「最近」页签，翻不到更早的文件。
  static Future<_PickedFile?> _pickSingle(_MediaKind kind) async {
    if (isOhos) {
      final result = await _pickOnOhos(kind);
      final files = result?.files ?? const [];
      if (files.isEmpty) return null;
      return _PickedFile(name: files.first.name, path: files.first.path);
    }
    final result = await picker.FilePicker.platform.pickFiles(
      type: picker.FileType.custom,
      allowedExtensions:
          kind == _MediaKind.gif ? const ['gif'] : _videoExtensions,
    );
    final files = result?.files ?? const [];
    if (files.isEmpty) return null;
    return _PickedFile(name: files.first.name, path: files.first.path);
  }

  static Future<picker_ohos.FilePickerResult?> _pickOnOhos(
    _MediaKind kind,
  ) async {
    try {
      return await picker_ohos.FilePicker.platform.pickFiles(
        type: kind == _MediaKind.gif
            ? picker_ohos.FileType.image
            : picker_ohos.FileType.video,
      );
    } on PlatformException catch (error) {
      // 鸿蒙实现把「用户取消」也走 finishWithError 上报，语义上等于没选文件。
      if (error.code == 'unknown_activity') return null;
      rethrow;
    }
  }

  static Future<List<XFile>> pickAlbumImages() =>
      _imagePicker.pickMultiImage(
        imageQuality: 100,
        limit: maxAlbumImages,
        requestFullMetadata: true,
      );

  static Future<XFile?> pickCameraImage() => _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

  static Future<Uint8List> readBytes(XFile file) async {
    final bytes = await file.readAsBytes();
    _checkFileSize(file.name, bytes.length);
    return bytes;
  }

  static bool isGif(String name, {String? mimeType}) =>
      mimeType == 'image/gif' || name.toLowerCase().endsWith('.gif');

  static bool isVideo(String name, {String? mimeType}) {
    if (mimeType != null && mimeType.startsWith('video/')) return true;
    final lower = name.toLowerCase();
    return const ['.mp4', '.mov', '.webm', '.mkv', '.avi', '.3gp', '.m4v']
        .any(lower.endsWith);
  }

  static void _checkFileSize(String name, int size) {
    if (size <= 0) throw StateError('$name 是空文件');
    if (size > maxFileBytes) {
      throw StateError('$name 超过 ${maxFileBytes ~/ 1024 ~/ 1024}MB 限制');
    }
    BajiLog.instance.info('文件', '$name: $size B');
  }
}

/// 选材类型。鸿蒙两端分别对应系统图库的图片/视频选择器。
enum _MediaKind { gif, video }

/// 两个 file_picker 包的 `PlatformFile` 类型不通用，这里只保留需要的字段。
class _PickedFile {
  _PickedFile({required this.name, required String? path})
      : path = _requirePath(path);

  final String name;
  final String path;

  static String _requirePath(String? path) {
    if (path == null || path.isEmpty) {
      throw StateError('选择结果里没有可读的文件路径');
    }
    return path;
  }
}
