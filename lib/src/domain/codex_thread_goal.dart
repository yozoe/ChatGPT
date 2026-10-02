import 'package:flutter/foundation.dart';

/// Persisted long-running objective reported by Codex App Server.
@immutable
class CodexThreadGoal {
  const CodexThreadGoal({
    required this.threadId,
    required this.objective,
    required this.status,
    this.tokenBudget,
    this.tokensUsed = 0,
    this.timeUsedSeconds = 0,
  });

  factory CodexThreadGoal.fromJson(Map<dynamic, dynamic> value) {
    int? integer(Object? raw) => switch (raw) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };

    return CodexThreadGoal(
      threadId: value['threadId']?.toString() ?? '',
      objective: value['objective']?.toString().trim() ?? '',
      status: value['status']?.toString().trim() ?? 'active',
      tokenBudget: integer(value['tokenBudget']),
      tokensUsed: integer(value['tokensUsed']) ?? 0,
      timeUsedSeconds: integer(value['timeUsedSeconds']) ?? 0,
    );
  }

  final String threadId;
  final String objective;
  final String status;
  final int? tokenBudget;
  final int tokensUsed;
  final int timeUsedSeconds;

  bool get isPaused => status == 'paused';
  bool get isBlocked => status == 'blocked';
  bool get canResume => isPaused || isBlocked;
  bool get isActive => status == 'active';
  bool get isBudgetExhausted =>
      tokenBudget != null && tokenBudget! > 0 && tokensUsed >= tokenBudget!;
  bool get isTerminal =>
      status == 'complete' ||
      status == 'completed' ||
      status == 'usageLimited' ||
      status == 'budgetLimited' ||
      isBudgetExhausted;

  double? get progress {
    final budget = tokenBudget;
    if (budget == null || budget <= 0) return null;
    return (tokensUsed / budget).clamp(0, 1).toDouble();
  }

  CodexThreadGoal copyWith({
    String? objective,
    String? status,
    int? tokenBudget,
    int? tokensUsed,
    int? timeUsedSeconds,
    bool clearTokenBudget = false,
  }) => CodexThreadGoal(
    threadId: threadId,
    objective: objective ?? this.objective,
    status: status ?? this.status,
    tokenBudget: clearTokenBudget ? null : tokenBudget ?? this.tokenBudget,
    tokensUsed: tokensUsed ?? this.tokensUsed,
    timeUsedSeconds: timeUsedSeconds ?? this.timeUsedSeconds,
  );
}
