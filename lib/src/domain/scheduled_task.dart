import 'package:flutter/foundation.dart';

/// A locally persisted prompt that Codex Desk dispatches at a chosen time.
///
/// Scheduled prompts only execute while Codex Desk is open. The schedule is
/// stored outside the project directory and contains the project path needed
/// to reconnect before dispatching the prompt.
@immutable
class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.workspacePath,
    required this.prompt,
    required this.runAt,
  });

  final String id;
  final String workspacePath;
  final String prompt;
  final DateTime runAt;

  factory ScheduledTask.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid scheduled task.');
    final id = value['id']?.toString().trim() ?? '';
    final workspacePath = value['workspacePath']?.toString().trim() ?? '';
    final prompt = value['prompt']?.toString().trim() ?? '';
    final runAt = DateTime.tryParse(value['runAt']?.toString() ?? '');
    if (id.isEmpty ||
        workspacePath.isEmpty ||
        prompt.isEmpty ||
        runAt == null) {
      throw const FormatException('Invalid scheduled task fields.');
    }
    return ScheduledTask(
      id: id,
      workspacePath: workspacePath,
      prompt: prompt,
      runAt: runAt.toLocal(),
    );
  }

  Map<String, String> toJson() => {
    'id': id,
    'workspacePath': workspacePath,
    'prompt': prompt,
    'runAt': runAt.toUtc().toIso8601String(),
  };
}
