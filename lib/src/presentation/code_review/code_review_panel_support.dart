// Shared declarations extracted from code_review_panel.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_file.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_row.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_stats.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

/// Data source displayed by the workbench review surface.
enum CodeReviewSource { latestTurn, gitWorkspace }

extension CodeReviewSourceLabel on CodeReviewSource {
  String get label => switch (this) {
    CodeReviewSource.latestTurn => '最新一轮',
    CodeReviewSource.gitWorkspace => 'Git 工作区',
  };
}

/// Codex-style code review surface embedded in the active workbench.

@immutable
enum ReviewRowKind {
  context,
  addition,
  deletion,
  hunk,
  collapsed,
  metadata,
  noNewline,
  error,
}

final RegExp hunkHeaderPattern = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$',
);

List<ReviewRow> parseReviewRows(ReviewFile file) {
  if (file.error case final error?) {
    return [ReviewRow(ReviewRowKind.error, '无法读取 Diff：$error')];
  }
  if (file.diff.trim().isEmpty) {
    return const [ReviewRow(ReviewRowKind.metadata, '没有可显示的 Diff。')];
  }
  final rows = <ReviewRow>[];
  var oldLine = 0;
  var newLine = 0;
  var previousOldEnd = 0;
  var previousNewEnd = 0;
  var sawHunk = false;
  for (final line in file.diff.split('\n')) {
    if (line.startsWith('diff --git ')) {
      oldLine = 0;
      newLine = 0;
      previousOldEnd = 0;
      previousNewEnd = 0;
      sawHunk = false;
      rows.add(ReviewRow(ReviewRowKind.metadata, line));
      continue;
    }
    final match = hunkHeaderPattern.firstMatch(line);
    if (match != null) {
      final oldStart = int.parse(match.group(1)!);
      final newStart = int.parse(match.group(3)!);
      final oldGap = math.max(0, oldStart - previousOldEnd - 1);
      final newGap = math.max(0, newStart - previousNewEnd - 1);
      final gap = math.max(oldGap, newGap);
      if (gap > 0) {
        rows.add(ReviewRow(ReviewRowKind.collapsed, '未修改 $gap 行'));
      }
      rows.add(ReviewRow(ReviewRowKind.hunk, line));
      oldLine = oldStart;
      newLine = newStart;
      sawHunk = true;
      continue;
    }
    if (!sawHunk) {
      if (line.startsWith('index ') ||
          line.startsWith('--- ') ||
          line.startsWith('+++ ') ||
          line.startsWith('new file mode ') ||
          line.startsWith('deleted file mode ') ||
          line.startsWith('similarity index ') ||
          line.startsWith('rename from ') ||
          line.startsWith('rename to ') ||
          line.startsWith('Binary files ') ||
          line == 'GIT binary patch') {
        rows.add(ReviewRow(ReviewRowKind.metadata, line));
      }
      continue;
    }
    if (line.startsWith('\\ No newline at end of file')) {
      rows.add(ReviewRow(ReviewRowKind.noNewline, line));
      continue;
    }
    if (line.startsWith('+') && !line.startsWith('+++')) {
      rows.add(ReviewRow(ReviewRowKind.addition, line, newLine: newLine));
      newLine++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      rows.add(ReviewRow(ReviewRowKind.deletion, line, oldLine: oldLine));
      oldLine++;
    } else {
      rows.add(
        ReviewRow(
          ReviewRowKind.context,
          line,
          oldLine: oldLine,
          newLine: newLine,
        ),
      );
      oldLine++;
      newLine++;
    }
    previousOldEnd = math.max(previousOldEnd, oldLine - 1);
    previousNewEnd = math.max(previousNewEnd, newLine - 1);
  }
  if (file.truncated) {
    rows.add(const ReviewRow(ReviewRowKind.metadata, '… Diff 已截断，当前只显示已加载内容。'));
  }
  return rows.isEmpty
      ? const [ReviewRow(ReviewRowKind.metadata, '没有可显示的 Diff。')]
      : rows;
}

ReviewStats reviewStats(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      additions++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      deletions++;
    }
  }
  return ReviewStats(additions: additions, deletions: deletions);
}

IconData reviewFileIcon(String kind) {
  final normalized = kind.toLowerCase();
  if (normalized.contains('add') || normalized.contains('新增')) {
    return Icons.note_add_outlined;
  }
  if (normalized.contains('delete') || normalized.contains('删除')) {
    return Icons.delete_outline;
  }
  if (normalized.contains('rename') || normalized.contains('重命名')) {
    return Icons.drive_file_rename_outline;
  }
  if (normalized.contains('copy') || normalized.contains('复制')) {
    return Icons.file_copy_outlined;
  }
  if (normalized.contains('binary')) return Icons.data_object_outlined;
  return Icons.description_outlined;
}
