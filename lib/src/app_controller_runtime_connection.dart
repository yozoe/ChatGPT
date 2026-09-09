import 'package:chatgpt/src/services/codex_app_server.dart';

/// 将运行时探测与控制器状态转换隔离，避免探测过程直接修改界面状态。
/// Isolates runtime probing from controller state transitions.
class CodexRuntimeConnection {
  CodexRuntimeConnection(this._server);

  final CodexAppServer _server;

  Future<CodexRuntimeProbe> probe() => _server.probe();
}
