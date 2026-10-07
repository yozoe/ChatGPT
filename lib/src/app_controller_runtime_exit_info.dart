/// Parsed information from an unexpected `runtime/exited` notification.
///
/// The controller owns the cleanup and reconnect side effects. This value
/// object only preserves the protocol's exit code and user-facing diagnostic
/// wording in one independently testable boundary.
class CodexRuntimeExitInfo {
  const CodexRuntimeExitInfo({required this.code});

  factory CodexRuntimeExitInfo.fromParams(Map<String, dynamic> params) =>
      CodexRuntimeExitInfo(code: params['code']);

  final Object? code;

  String get message => 'Codex runtime 已退出（code $code）。';
}
