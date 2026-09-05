// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_dialog.dart';

class ScheduledTasksDialogState extends State<ScheduledTasksDialog> {
  final TextEditingController _prompt = TextEditingController();
  late DateTime _runAt;
  bool _saving = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _prompt.text = widget.initialPrompt ?? '';
    _runAt = DateTime.now().add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pickRunAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _runAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: '选择执行日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_runAt),
      helpText: '选择执行时间',
    );
    if (time == null || !mounted) return;
    setState(() {
      _runAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _schedule() async {
    if (_prompt.text.trim().isEmpty || !_runAt.isAfter(DateTime.now())) {
      setState(() => _validationError = '请填写提示词，并选择未来的执行时间。');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    final saved = await widget.controller.schedulePrompt(
      prompt: _prompt.text,
      runAt: _runAt,
    );
    if (!mounted) return;
    if (saved) {
      _prompt.clear();
      setState(() {
        _runAt = DateTime.now().add(const Duration(hours: 1));
        _saving = false;
        _validationError = null;
      });
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写提示词，并选择未来的执行时间。')));
    }
  }

  String _timeLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final tasks = widget.controller.scheduledTasks;
    return AlertDialog(
      key: const Key('scheduled-tasks-dialog'),
      title: const Text('已安排'),
      content: SizedBox(
        width: 600,
        height: 510,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '任务会在设定时间创建一条新对话并发送提示词。仅在 Codex Desk 保持打开时执行。',
              style: TextStyle(color: palette.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('scheduled-task-prompt-field'),
              controller: _prompt,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '到点后发送的提示词',
                hintText: '例如：检查当前分支的测试结果并汇总风险',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const Key('scheduled-task-time-picker'),
                  onPressed: _saving ? null : _pickRunAt,
                  icon: const Icon(Icons.schedule_outlined, size: 18),
                  label: Text(_timeLabel(_runAt)),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('schedule-task-confirm'),
                  onPressed: _saving ? null : _schedule,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_saving ? '安排中…' : '安排任务'),
                ),
              ],
            ),
            if (_validationError case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                key: const Key('scheduled-task-validation-error'),
                style: TextStyle(color: palette.fault, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              '待执行',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                        '没有已安排的任务。',
                        style: TextStyle(color: palette.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final dispatching = widget.controller
                            .isScheduledTaskDispatching(task.id);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule_outlined),
                          title: Text(
                            task.prompt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_timeLabel(task.runAt)),
                          trailing: IconButton(
                            tooltip: dispatching ? '正在发送' : '取消安排',
                            onPressed: dispatching
                                ? null
                                : () => widget.controller.cancelScheduledTask(
                                    task.id,
                                  ),
                            icon: dispatching
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                    ),
                                  )
                                : const Icon(Icons.close, size: 19),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
