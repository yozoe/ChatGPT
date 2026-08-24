/// 已脱敏运行时诊断的严重程度。
/// Severity of a redacted runtime diagnostic entry.
enum RuntimeLogLevel { info, warning, error }

/// 将诊断等级映射为界面和复制报告都可复用的文字。
/// Maps diagnostic severities to text reusable by UI and copied reports.
extension RuntimeLogLevelLabel on RuntimeLogLevel {
  /// 返回运行时日志等级的简短展示文本。
  /// Returns a short display label for the runtime log level.
  String get label => switch (this) {
    RuntimeLogLevel.info => '信息',
    RuntimeLogLevel.warning => '警告',
    RuntimeLogLevel.error => '错误',
  };
}

/// 已脱敏的本机 Codex 运行时诊断日志条目；只在内存中保留最近记录。
/// A redacted local Codex runtime diagnostic log entry; only recent entries remain in memory.
class RuntimeLogEntry {
  const RuntimeLogEntry({
    required this.message,
    required this.level,
    required this.createdAt,
  });

  final String message;
  final RuntimeLogLevel level;
  final DateTime createdAt;

  /// 根据 stderr 或协议异常文本推断日志等级并创建条目。
  /// Infers a log level from stderr or protocol-error text and creates an entry.
  factory RuntimeLogEntry.fromMessage({
    required String message,
    DateTime? createdAt,
  }) {
    final value = message.toLowerCase();
    final level =
        value.contains('fatal') ||
            value.contains('error') ||
            value.contains('failed') ||
            value.contains('exception')
        ? RuntimeLogLevel.error
        : value.contains('warn')
        ? RuntimeLogLevel.warning
        : RuntimeLogLevel.info;
    return RuntimeLogEntry(
      message: message,
      level: level,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  /// 将日志格式化为适合复制到诊断报告的一行文本。
  /// Formats the log as one line suitable for a copied diagnostic report.
  String toDiagnosticLine() {
    final timestamp = createdAt.toIso8601String();
    return '[$timestamp] ${level.label}: $message';
  }
}
