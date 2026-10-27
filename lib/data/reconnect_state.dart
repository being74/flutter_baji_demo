/// 自动重连进度。
///
/// [attempt] 当前（或即将进行）的重试序号，从 1 开始；0 表示未在重连。
/// [total] 盲重试总次数。
/// [watching] 盲重试用尽后是否已转入扫描监听，等待设备重新广播。
class ReconnectState {
  const ReconnectState({
    this.attempt = 0,
    this.total = 0,
    this.watching = false,
  });

  final int attempt;
  final int total;
  final bool watching;

  bool get active => attempt > 0;

  ReconnectState copyWith({int? attempt, int? total, bool? watching}) => ReconnectState(
        attempt: attempt ?? this.attempt,
        total: total ?? this.total,
        watching: watching ?? this.watching,
      );
}
