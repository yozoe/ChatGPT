import 'package:chatgpt/src/domain/codex_mcp_runtime_status.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Shows the configured MCP servers while the Composer is in MCP mode.
class ComposerMcpStatusPanel extends StatelessWidget {
  const ComposerMcpStatusPanel({
    super.key,
    required this.servers,
    required this.loading,
    required this.error,
  });

  final List<CodexMcpRuntimeStatus> servers;
  final bool loading;
  final String? error;

  String _authLabel(CodexMcpRuntimeStatus server) {
    final rawStatus = server.authStatus.trim();
    final status = rawStatus.toLowerCase();
    return switch (status) {
      'authenticated' || 'connected' || 'bearertoken' || 'oauth' => '已验证',
      'required' ||
      'requires_auth' ||
      'needs_auth' ||
      'notloggedin' => '需要身份验证',
      'unsupported' || 'not_supported' => '不支持身份验证',
      '' || 'unknown' => '认证状态未知',
      _ => '认证状态：$rawStatus',
    };
  }

  String _runtimeLabel(CodexMcpRuntimeStatus server) =>
      switch (server.runtimeStatus?.trim().toLowerCase()) {
        'connected' => '已连接',
        'starting' => '正在连接',
        'authenticationrequired' => '等待认证',
        'failed' => '连接失败',
        'cancelled' => '已取消',
        'disabled' => '已禁用',
        'notstarted' => '尚未启动',
        null || '' => '连接状态未知',
        final value => '状态：$value',
      };

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Semantics(
      container: true,
      label: 'MCP 服务器状态',
      child: Container(
        key: const Key('composer-mcp-status-panel'),
        constraints: const BoxConstraints(maxHeight: 260),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: palette.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.controlBorder),
        ),
        child: loading && servers.isEmpty
            ? const SizedBox(
                height: 54,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : error != null && servers.isEmpty
            ? SizedBox(
                height: 54,
                child: Center(
                  child: Text(
                    '无法读取 MCP 服务器：$error',
                    style: TextStyle(color: palette.fault, fontSize: 12),
                  ),
                ),
              )
            : servers.isEmpty
            ? SizedBox(
                height: 54,
                child: Center(
                  child: Text(
                    '尚未配置 MCP 服务器。',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '刷新 MCP 服务器失败：$error；以下为上次读取的结果。',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.fault, fontSize: 12),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      key: const Key('composer-mcp-server-list'),
                      itemCount: servers.length,
                      itemBuilder: (context, index) {
                        final server = servers[index];
                        return Semantics(
                          label:
                              '${server.displayName}，${_authLabel(server)}，${_runtimeLabel(server)}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        server.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.trace,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _authLabel(server),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  _runtimeLabel(server),
                                  style: TextStyle(
                                    color: palette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
