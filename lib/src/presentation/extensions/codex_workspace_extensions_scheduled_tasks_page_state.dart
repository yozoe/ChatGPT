// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_page.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_task_suggestion.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_suggestion_row.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_task_row.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_library_top_bar.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_library_section_header.dart';

class ScheduledTasksPageState extends State<ScheduledTasksPage> {
  final TextEditingController _search = TextEditingController();

  static const _suggestions = [
    ScheduledTaskSuggestion(
      icon: Icons.notifications_none_outlined,
      color: Color(0xFF42A5F5),
      title: '每日简报',
      schedule: '工作日 8:00',
      prompt: '整理今天的日历、未读邮件和优先事项，给我一份每日简报。',
    ),
    ScheduledTaskSuggestion(
      icon: Icons.article_outlined,
      color: Color(0xFFB779FF),
      title: '每周回顾',
      schedule: '星期五 16:00',
      prompt: '每周五整理我最近的工作，生成一份清晰的状态更新。',
    ),
    ScheduledTaskSuggestion(
      icon: Icons.manage_search_outlined,
      color: Color(0xFF32C887),
      title: '跟进监控',
      schedule: '工作日 9:00',
      prompt: '检查待跟进事项，整理需要我注意的更新和下一步。',
    ),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String value) =>
      value.toLowerCase().contains(_search.text.trim().toLowerCase());

  String _timeLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final tasks = widget.controller.scheduledTasks
        .where((task) => _matches(task.prompt))
        .toList(growable: false);
    final suggestions = _suggestions
        .where((item) => _matches('${item.title} ${item.prompt}'))
        .toList(growable: false);
    return Column(
      children: [
        LibraryTopBar(createLabel: '创建', onCreate: () => widget.onCreate()),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            key: const Key('scheduled-tasks-page'),
            padding: const EdgeInsets.fromLTRB(72, 42, 72, 64),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1036),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已安排的任务',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontSize: 38,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -1,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '让 ChatGPT 安排任务、设置提醒或监测更新',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      key: const Key('scheduled-tasks-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '搜索已安排任务',
                        prefixIcon: const Icon(Icons.search_outlined),
                        filled: true,
                        fillColor: palette.field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                    if (tasks.isNotEmpty) ...[
                      const SizedBox(height: 42),
                      LibrarySectionHeader(label: '待执行'),
                      for (final task in tasks)
                        ScheduledTaskRow(
                          task: task,
                          timeLabel: _timeLabel(task.runAt),
                          onCancel: () =>
                              widget.controller.cancelScheduledTask(task.id),
                        ),
                    ],
                    const SizedBox(height: 42),
                    LibrarySectionHeader(label: '建议'),
                    const SizedBox(height: 10),
                    for (final suggestion in suggestions)
                      ScheduledSuggestionRow(
                        suggestion: suggestion,
                        onTap: () => widget.onCreate(suggestion.prompt),
                      ),
                    if (tasks.isEmpty && suggestions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Text(
                          '没有匹配的已安排任务。',
                          style: TextStyle(color: palette.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
