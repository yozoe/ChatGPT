import 'package:chatgpt/src/services/codex_app_server.dart';

/// Isolates runtime probing from controller state transitions.
class CodexRuntimeConnection {
  CodexRuntimeConnection(this._server);

  final CodexAppServer _server;

  Future<CodexRuntimeProbe> probe() => _server.probe();
}
