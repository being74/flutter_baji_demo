import 'package:flutter/foundation.dart';

enum BajiLogLevel { debug, info, warn, error }

class BajiLogEntry {
  const BajiLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  final int id;
  final DateTime timestamp;
  final BajiLogLevel level;
  final String tag;
  final String message;
}

/// 进程内的环形日志，供 UI 与联调排查使用。
class BajiLog extends ChangeNotifier {
  BajiLog._();

  static final BajiLog instance = BajiLog._();

  static const int maxEntries = 600;

  final List<BajiLogEntry> _entries = [];
  int _counter = 0;

  List<BajiLogEntry> get entries => List.unmodifiable(_entries);

  void debug(String tag, String message) => _append(BajiLogLevel.debug, tag, message);

  void info(String tag, String message) => _append(BajiLogLevel.info, tag, message);

  void warn(String tag, String message) => _append(BajiLogLevel.warn, tag, message);

  void error(String tag, String message) => _append(BajiLogLevel.error, tag, message);

  /// 图片/文件传输专用日志。
  void transfer(String tag, String message) => _append(BajiLogLevel.info, tag, message);

  /// 传输专用、只输出到控制台（用于逐帧大报文）。
  void transferTrace(String tag, String message) {
    debugPrint('[BajiTransfer][$tag] $message');
  }

  void transferWarn(String tag, String message) => _append(BajiLogLevel.warn, tag, message);

  void transferError(String tag, String message) => _append(BajiLogLevel.error, tag, message);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  static String formatTime(DateTime timestamp) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  void _append(BajiLogLevel level, String tag, String message) {
    _entries.add(
      BajiLogEntry(
        id: ++_counter,
        timestamp: DateTime.now(),
        level: level,
        tag: tag,
        message: message,
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    debugPrint('[Baji][$tag] $message');
    notifyListeners();
  }
}
