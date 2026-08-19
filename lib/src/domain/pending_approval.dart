import '../services/codex_app_server.dart';

enum ApprovalKind { command, fileChange, permissions }

class PendingApproval {
  const PendingApproval({
    required this.requestId,
    required this.method,
    required this.params,
    required this.kind,
  });

  final Object requestId;
  final String method;
  final JsonMap params;
  final ApprovalKind kind;

  String get title => switch (kind) {
    ApprovalKind.command => '命令执行请求',
    ApprovalKind.fileChange => '文件变更请求',
    ApprovalKind.permissions => '额外权限请求',
  };

  String get detail {
    final reason = params['reason']?.toString();
    final command = params['command']?.toString();
    final root = params['grantRoot']?.toString();
    final network = params['networkApprovalContext'];
    return [
      if (reason != null && reason.isNotEmpty) reason,
      if (command != null && command.isNotEmpty) command,
      if (root != null && root.isNotEmpty) '授权目录：$root',
      if (network != null) '网络访问：$network',
    ].join('\n');
  }

  static PendingApproval? fromEvent(ServerEvent event) {
    final requestId = event.requestId;
    if (requestId == null) return null;
    final kind = switch (event.method) {
      'item/commandExecution/requestApproval' => ApprovalKind.command,
      'item/fileChange/requestApproval' => ApprovalKind.fileChange,
      'item/permissions/requestApproval' => ApprovalKind.permissions,
      _ => null,
    };
    if (kind == null) return null;
    return PendingApproval(
      requestId: requestId,
      method: event.method,
      params: event.params,
      kind: kind,
    );
  }
}
