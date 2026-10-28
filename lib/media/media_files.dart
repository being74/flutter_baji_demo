import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../core/baji_log.dart';

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

  static final ImagePicker _imagePicker = ImagePicker();

  static Future<PickedMedia?> pickGif() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gif'],
    );
    final file = result?.files.single;
    if (file == null) return null;
    final path = file.path;
    if (path == null) throw StateError('无法读取 GIF 路径');
    final bytes = await File(path).readAsBytes();
    _checkFileSize(file.name, bytes.length);
    return PickedMedia(name: file.name, path: path, bytes: bytes);
  }

  static Future<PickedMedia?> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'webm', 'mkv', 'avi', '3gp', 'm4v'],
    );
    final file = result?.files.single;
    if (file == null) return null;
    final path = file.path;
    if (path == null) throw StateError('无法读取视频路径');
    final length = await File(path).length();
    _checkFileSize(file.name, length);
    return PickedMedia(name: file.name, path: path);
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
