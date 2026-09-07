/// Supplies the current local time for time-sensitive application behavior.
///
/// Production callers use the system clock. Tests can provide a stable source
/// without changing the scheduling rules themselves.
class CodexClock {
  CodexClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  DateTime now() => _now();
}
