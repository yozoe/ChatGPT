import 'package:chatgpt/src/domain/codex_mcp_server.dart';
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

  final List<CodexMcpServer> servers;
  final bool loading;
  final String? error;

  String _authLabel(CodexMcpServer server) {
    final rawStatus = server.authStatus?.trim();
    final status = rawStatus?.toLowerCase();
    return switch (status) {
      'authenticated' || 'connected' => '已验证',
      'required' || 'requires_auth' || 'needs_auth' => '需要身份验证',
      'unsupported' || 'not_supported' => '不支持身份验证',
      null || '' || 'unknown' => '认证状态未知',
      _ => '认证状态：$rawStatus',
    };
  }

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
                              '${server.name}，${_authLabel(server)}，${server.enabled ? '已启用' : '已禁用'}',
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
                                        server.name,
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
                                  server.enabled ? '已启用' : '已禁用',
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
