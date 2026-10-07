import 'services/codex_app_server_codex_runtime_probe.dart';

/// Coordinates executable selection, probing, and persistence for the local runtime.
///
/// The controller still owns lifecycle UI state and decides when a running
/// process must be stopped or restarted. This coordinator only owns the
/// executable mutation transaction and its rollback semantics.
class CodexRuntimeExecutableCoordinator {
  const CodexRuntimeExecutableCoordinator({
    required this.executable,
    required this.setExecutable,
    required this.inspect,
    required this.saveExecutable,
    required this.clearExecutable,
  });

  final String Function() executable;
  final void Function(String? path) setExecutable;
  final Future<CodexRuntimeProbe> Function() inspect;
  final Future<void> Function(String path) saveExecutable;
  final Future<void> Function() clearExecutable;

  /// Applies and validates a custom executable, restoring the prior value on
  /// any probe or persistence failure.
  Future<CodexRuntimeProbe> setCustomExecutable(String path) async {
    final previous = executable();
    try {
      setExecutable(path);
      final probe = await inspect();
      if (!probe.isAvailable || probe.executablePath == null) {
        throw StateError(probe.error ?? '所选文件不是可用的 Codex CLI。');
      }
      await saveExecutable(probe.executablePath!);
      return probe;
    } catch (_) {
      setExecutable(previous);
      rethrow;
    }
  }

  /// Restores automatic discovery and refreshes the current probe.
  ///
  /// This intentionally does not roll back on failure. The previous
  /// controller behavior cleared the persisted override and left the server
  /// on automatic discovery even when the follow-up probe failed.
  Future<CodexRuntimeProbe> resetExecutable() async {
    setExecutable(null);
    await clearExecutable();
    return inspect();
  }
}
