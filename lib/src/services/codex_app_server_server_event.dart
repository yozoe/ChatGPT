// Extracted class from codex_app_server.dart.
import 'codex_app_server_support.dart';

class ServerEvent {
  const ServerEvent({
    required this.method,
    required this.params,
    this.requestId,
  });

  final String method;
  final JsonMap params;

  /// 非空值表示 App Server 发起了需要客户端答复的 JSON-RPC 请求；通知永远没有 id。
  /// A non-null value means App Server initiated a JSON-RPC request that the client must answer; notifications never carry an id.
  final Object? requestId;

  /// 判断事件是否为需要客户端回复的服务器请求。
  /// Determines whether this event is a server request requiring a client reply.
  bool get isServerRequest => requestId != null;
}
