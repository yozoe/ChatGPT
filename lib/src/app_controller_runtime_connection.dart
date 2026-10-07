import 'package:chatgpt/src/services/codex_app_server.dart';

/// 将运行时探测与控制器状态转换隔离，避免探测过程直接修改界面状态。
/// Isolates runtime probing from controller state transitions.
class CodexRuntimeConnection {
  CodexRuntimeConnection(this._server);

  final CodexAppServer _server;

  Future<CodexRuntimeProbe> probe() => _server.probe();

  /// 启动指定工作区的 App Server 进程。
  /// Starts the App Server process for the requested workspace.
  Future<void> start({required String workingDirectory}) async {
    await _server.start(workingDirectory: workingDirectory);
  }

  /// 完成当前 App Server 的协议初始化握手。
  /// Completes the protocol initialization handshake for the current App Server.
  Future<void> initialize() => _server.initialize();

  /// 停止此连接拥有的 App Server 进程。
  /// Stops the App Server process owned by this connection.
  Future<void> stop() => _server.stop();
}
