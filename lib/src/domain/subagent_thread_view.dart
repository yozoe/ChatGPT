import 'timeline_entry.dart';

/// 子智能体线程在检查器中的只读加载状态。
/// Read-only loading state for a subagent thread shown in the inspector.
class SubagentThreadView {
  const SubagentThreadView({
    required this.threadId,
    required this.title,
    required this.status,
    required this.entries,
    this.prompt = '',
    this.loading = false,
    this.error,
  });

  final String threadId;
  final String title;
  final String prompt;
  final String status;
  final List<TimelineEntry> entries;
  final bool loading;
  final String? error;

  SubagentThreadView copyWith({
    String? title,
    String? prompt,
    String? status,
    List<TimelineEntry>? entries,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => SubagentThreadView(
    threadId: threadId,
    title: title ?? this.title,
    prompt: prompt ?? this.prompt,
    status: status ?? this.status,
    entries: entries ?? this.entries,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
  );
}
