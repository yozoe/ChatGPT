// Shared declarations extracted from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
// ignore_for_file: use_key_in_widget_constructors

import 'dart:math' as math;

import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';

/// Matches Codex's compact source form while keeping the one supported input
/// contract explicit: the local CLI resolves the marketplace's default ref.

enum ExtensionSettingsTab { plugins, mcp, skills }

/// Codex-style extension settings shared by the workbench and plugin page.

/// Plugin library keeps CLI-backed plugin actions in a full workspace instead
/// of obscuring the current project with a modal.

enum PluginAddAction { createPlugin, addMarketplace, recordSkill }

/// Manages prompts that Codex Desk will send later while the app is running.

/// 展示可搜索、可按状态筛选并支持显式 Git 操作的项目对话框。
/// Displays a searchable, status-filterable project dialog with explicit Git actions.

/// 展示只读 Git Diff 的详情面板，不包含暂存、恢复或写入仓库的操作。
/// Displays a read-only Git diff detail panel without staging, restoring, or repository write actions.

/// Collapses consecutive low-level tool records into one Codex-style activity
/// disclosure while retaining their order in the conversation timeline.
List<ConversationTimelineItem> conversationTimelineItems(
  List<TimelineEntry> entries,
) {
  final timelineEntries = orderAgentMessagePhases(entries);
  final items = <ConversationTimelineItem>[];
  final pendingTurnEntries = <IndexedTimelineEntry>[];

  void flushPendingTurnEntries() {
    if (pendingTurnEntries.isEmpty) return;
    appendStandardTimelineItems(items, pendingTurnEntries);
    pendingTurnEntries.clear();
  }

  for (var index = 0; index < timelineEntries.length; index++) {
    final entry = timelineEntries[index];
    // 旧版缓存可能仍含逐文件的协议记录。文件变更会由专用摘要卡片
    // 和审查入口呈现，不应占据会话流。
    // Older caches may retain per-file protocol records. File changes are
    // presented by the dedicated summary card and review entry instead.
    if (entry.title == '文件变更') {
      continue;
    }
    if (entry.kind == TimelineKind.user) {
      flushPendingTurnEntries();
      items.add(ConversationTimelineItem.entry(entry, index));
      continue;
    }
    if (entry.kind == TimelineKind.elapsed) {
      final processEntries = pendingTurnEntries
          .where((item) {
            final itemEntry = item.entry;
            return itemEntry.kind != TimelineKind.agent &&
                itemEntry.kind != TimelineKind.approval &&
                itemEntry.kind != TimelineKind.error;
          })
          .toList(growable: false);
      if (processEntries.isEmpty) {
        appendStandardTimelineItems(items, pendingTurnEntries);
        items.add(ConversationTimelineItem.entry(entry, index));
      } else {
        // Keep the complete turn in one stable widget. The disclosure renders
        // expanded process entries in their original position, followed by the
        // final answer and then this duration footer. Splitting the final answer
        // out before the disclosure made command output appear underneath it.
        items.add(
          ConversationTimelineItem.completedTurn(
            entry,
            pendingTurnEntries
                .map((item) => item.entry)
                .toList(growable: false),
            index,
          ),
        );
      }
      pendingTurnEntries.clear();
      continue;
    }
    pendingTurnEntries.add(IndexedTimelineEntry(entry, index));
  }
  flushPendingTurnEntries();
  return items;
}

/// Uses the App Server's authoritative agent-message phase to keep commentary
/// inline with work while placing `final_answer` after tools and before the
/// duration/terminal status, regardless of notification arrival order.
List<TimelineEntry> orderAgentMessagePhases(List<TimelineEntry> entries) {
  final ordered = <TimelineEntry>[];
  var turnStart = 0;
  while (turnStart < entries.length) {
    var nextUser = turnStart + 1;
    while (nextUser < entries.length &&
        entries[nextUser].kind != TimelineKind.user) {
      nextUser++;
    }
    final turnEntries = entries.sublist(turnStart, nextUser);
    var finalAnswers = turnEntries
        .where(
          (entry) =>
              entry.kind == TimelineKind.agent &&
              entry.agentPhase == 'final_answer',
        )
        .toList(growable: false);
    if (finalAnswers.isEmpty) {
      final elapsedIndex = turnEntries.indexWhere(
        (entry) => entry.kind == TimelineKind.elapsed,
      );
      final hasProcessAfterElapsed =
          elapsedIndex >= 0 &&
          turnEntries
              .skip(elapsedIndex + 1)
              .any((entry) => !isTerminalTaskStatus(entry));
      if (hasProcessAfterElapsed) {
        final legacyFinalAnswer = turnEntries
            .take(elapsedIndex)
            .where((entry) => entry.kind == TimelineKind.agent)
            .lastOrNull;
        if (legacyFinalAnswer != null) {
          // Older persisted timelines did not retain phase. Only repair the
          // structurally impossible shape where process output follows the
          // elapsed boundary; ordinary unphased messages keep arrival order.
          finalAnswers = [legacyFinalAnswer];
        }
      }
    }
    if (finalAnswers.isEmpty) {
      ordered.addAll(turnEntries);
    } else {
      final finalAnswerIds = finalAnswers.map((entry) => entry.id).toSet();
      final elapsedEntries = turnEntries
          .where((entry) => entry.kind == TimelineKind.elapsed)
          .toList(growable: false);
      final terminalEntries = turnEntries
          .where(isTerminalTaskStatus)
          .toList(growable: false);
      ordered
        ..addAll(
          turnEntries.where(
            (entry) =>
                !finalAnswerIds.contains(entry.id) &&
                entry.kind != TimelineKind.elapsed &&
                !isTerminalTaskStatus(entry),
          ),
        )
        ..addAll(finalAnswers)
        ..addAll(elapsedEntries)
        ..addAll(terminalEntries);
    }
    turnStart = nextUser;
  }
  return ordered;
}

bool isTerminalTaskStatus(TimelineEntry entry) =>
    (entry.kind == TimelineKind.system &&
        (entry.title == '任务完成' ||
            entry.title == '任务已停止' ||
            entry.title == '任务已结束')) ||
    (entry.kind == TimelineKind.error && entry.title == '任务失败');

/// Adds uncompleted entries to the timeline, retaining compact tool groups.
void appendStandardTimelineItems(
  List<ConversationTimelineItem> items,
  List<IndexedTimelineEntry> entries,
) {
  var index = 0;
  while (index < entries.length) {
    final indexedEntry = entries[index];
    if (!isActivityEntry(indexedEntry.entry)) {
      items.add(
        ConversationTimelineItem.entry(
          indexedEntry.entry,
          indexedEntry.entryIndex,
        ),
      );
      index++;
      continue;
    }
    final activities = <TimelineEntry>[];
    final firstIndex = indexedEntry.entryIndex;
    while (index < entries.length && isActivityEntry(entries[index].entry)) {
      activities.add(entries[index].entry);
      index++;
    }
    items.add(ConversationTimelineItem.activities(activities, firstIndex));
  }
}

bool isActivityEntry(TimelineEntry entry) =>
    entry.kind == TimelineKind.tool ||
    entry.kind == TimelineKind.command ||
    isAutoApprovalActivity(entry);

bool isAutoApprovalActivity(TimelineEntry entry) =>
    entry.kind == TimelineKind.system && entry.title == '已自动批准本次操作';
