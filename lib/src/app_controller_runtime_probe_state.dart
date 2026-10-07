import 'package:chatgpt/src/services/codex_app_server.dart';

/// Owns the small mutable state produced by a Codex CLI probe.
///
/// The controller remains responsible for notifying listeners and deciding
/// when a probe should trigger reconnect. This object only groups the probe,
/// loading marker, and error value that belong to that operation.
class CodexRuntimeProbeState {
  CodexRuntimeProbe? probe;
  String? error;
  bool checking = false;

  void begin() {
    checking = true;
    error = null;
  }

  void apply(CodexRuntimeProbe value) {
    probe = value;
    error = value.isAvailable ? null : value.error;
    checking = false;
  }

  void fail(String message) {
    error = message;
    checking = false;
  }

  void finish() {
    checking = false;
  }

  void clear() {
    probe = null;
    error = null;
    checking = false;
  }
}
