/// 为依赖当前时间的应用行为提供本地时间来源，测试时可注入稳定时钟。
/// Supplies the current local time for time-sensitive application behavior.
///
/// Production callers use the system clock. Tests can provide a stable source
/// without changing the scheduling rules themselves.
class CodexClock {
  CodexClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  DateTime now() => _now();
}
