import 'dart:io';

import 'package:chatgpt/src/domain/runtime_log_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'app_controller_support.dart';

/// Builds and manages the in-memory runtime diagnostics surface.
class CodexRuntimeDiagnostics {
  CodexRuntimeDiagnostics({
    required List<RuntimeLogEntry> Function() logs,
    required void Function() clearLogs,
    required bool Function() isDisposed,
    required void Function() notify,
    required CodexRuntimeProbe? Function() probe,
    required RuntimeStatus Function() status,
    required bool Function() serverRunning,
    required String Function() executable,
    required String? Function() workspace,
    required String Function() providerLabel,
    required String Function() authLabel,
    required String? Function() lastError,
  }) : _logs = logs,
       _clearLogs = clearLogs,
       _isDisposed = isDisposed,
       _notify = notify,
       _probe = probe,
       _status = status,
       _serverRunning = serverRunning,
       _executable = executable,
       _workspace = workspace,
       _providerLabel = providerLabel,
       _authLabel = authLabel,
       _lastError = lastError;

  static const maximumLogEntries = 200;

  final List<RuntimeLogEntry> Function() _logs;
  final void Function() _clearLogs;
  final bool Function() _isDisposed;
  final void Function() _notify;
  final CodexRuntimeProbe? Function() _probe;
  final RuntimeStatus Function() _status;
  final bool Function() _serverRunning;
  final String Function() _executable;
  final String? Function() _workspace;
  final String Function() _providerLabel;
  final String Function() _authLabel;
  final String? Function() _lastError;

  void clear() {
    if (_logs().isEmpty) return;
    _clearLogs();
    if (!_isDisposed()) _notify();
  }

  String buildReport() {
    final probe = _probe();
    final logs = _logs();
    final lines = <String>[
      'Codex Desk runtime diagnostics',
      'Generated: ${DateTime.now().toIso8601String()}',
      'Runtime status: ${_status().name}',
      'App Server running: ${_serverRunning() ? 'yes' : 'no'}',
      'Workspace selected: ${_workspace() == null ? 'no' : 'yes'}',
      'Configured CLI: ${CodexAppServer.redactDiagnosticText(_executable())}',
      'CLI available: ${probe?.isAvailable == true ? 'yes' : 'no'}',
      if (probe?.discovery?.isNotEmpty == true)
        'CLI discovery: ${probe!.discovery}',
      if (probe?.executablePath?.isNotEmpty == true)
        'Resolved CLI: ${CodexAppServer.redactDiagnosticText(probe!.executablePath!)}',
      if (probe?.version?.isNotEmpty == true)
        'CLI version: ${CodexAppServer.redactDiagnosticText(probe!.version!)}',
      if (probe?.error?.isNotEmpty == true)
        'CLI error: ${CodexAppServer.redactDiagnosticText(probe!.error!)}',
      'CODEX_HOME configured: ${Platform.environment['CODEX_HOME']?.isNotEmpty == true ? 'yes' : 'no'}',
      'Provider: ${_providerLabel()}',
      'Authentication: ${_authLabel()}',
      if (_lastError()?.isNotEmpty == true)
        'Last error: ${CodexAppServer.redactDiagnosticText(_lastError()!)}',
      '',
      'Recent runtime logs (${logs.length}/$maximumLogEntries):',
      if (logs.isEmpty) '(none)',
      ...logs.map((entry) => entry.toDiagnosticLine()),
    ];
    return lines.join('\n');
  }
}
