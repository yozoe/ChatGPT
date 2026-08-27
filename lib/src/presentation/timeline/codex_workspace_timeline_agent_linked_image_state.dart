// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_linked_image.dart';

class AgentLinkedImageState extends State<AgentLinkedImage> {
  WorkspaceFileReference? _localReference;

  @visibleForTesting
  Future<void> resolveForTesting() => _resolveLocalReference();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolveLocalReference());
    });
  }

  @override
  void didUpdateWidget(covariant AgentLinkedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.workspacePath != widget.workspacePath) {
      _localReference = null;
      unawaited(_resolveLocalReference());
    }
  }

  Future<void> _resolveLocalReference() async {
    final source = widget.source;
    final workspacePath = widget.workspacePath;
    final uri = Uri.tryParse(source);
    final isWindowsPath = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source);
    final isLocal =
        uri != null &&
        (uri.scheme.isEmpty || uri.scheme == 'file' || isWindowsPath);
    final reference = isLocal && workspacePath != null
        ? await resolveWorkspaceFileReference(
            href: source,
            workspacePath: workspacePath,
          )
        : null;
    if (!mounted ||
        source != widget.source ||
        workspacePath != widget.workspacePath) {
      return;
    }
    setState(() => _localReference = reference);
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.source);
    if (uri == null) return _fallback();
    Widget errorBuilder(BuildContext _, Object _, StackTrace? _) => _fallback();
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return Image.network(widget.source, errorBuilder: errorBuilder);
    }
    if (uri.scheme == 'data') {
      final data = uri.data;
      if (data != null) {
        return Image.memory(data.contentAsBytes(), errorBuilder: errorBuilder);
      }
      return _fallback();
    }
    if (uri.scheme == 'resource') {
      return Image.asset(uri.path, errorBuilder: errorBuilder);
    }
    final reference = _localReference;
    if (reference != null) {
      return Image.file(File(reference.path), errorBuilder: errorBuilder);
    }
    return _fallback();
  }

  Widget _fallback() => Text(
    widget.alt.isEmpty ? '无法显示图片' : widget.alt,
    style: widget.fallbackStyle,
  );
}
