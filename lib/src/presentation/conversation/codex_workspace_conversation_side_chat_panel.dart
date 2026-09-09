import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Presents an ephemeral fork while leaving the parent conversation visible.
class SideChatPanel extends StatefulWidget {
  const SideChatPanel({
    super.key,
    required this.session,
    required this.onClose,
  });

  final CodexSideChatSession session;
  final VoidCallback onClose;

  @override
  State<SideChatPanel> createState() => SideChatPanelState();
}

class SideChatPanelState extends State<SideChatPanel> {
  final TextEditingController _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text;
    if (!await widget.session.send(text) || !mounted) return;
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) => ColoredBox(
        color: palette.module,
        child: Column(
          children: [
            ListTile(
              key: const Key('side-chat-panel-header'),
              title: const Text('侧边聊天'),
              subtitle: const Text('临时聊天，不会切换主任务'),
              trailing: IconButton(
                key: const Key('side-chat-close'),
                tooltip: '关闭侧边聊天',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(height: 1),
            if (widget.session.lastError case final error?)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error, style: TextStyle(color: palette.fault)),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.session.entries.length,
                itemBuilder: (context, index) {
                  final entry = widget.session.entries[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('${entry.title}\n${entry.detail}'),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('side-chat-field'),
                      controller: _composer,
                      enabled: widget.session.canSend,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '询问 Codex…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('side-chat-send'),
                    onPressed: widget.session.canSend ? _send : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
