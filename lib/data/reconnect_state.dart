/// 自动重连进度：当前重试序号、盲重试总次数、是否已转入扫描监听。
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
