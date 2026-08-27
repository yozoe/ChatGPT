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
  final items = <ConversationTimelineItem>[];
  final pendingTurnEntries = <IndexedTimelineEntry>[];

  void flushPendingTurnEntries() {
    if (pendingTurnEntries.isEmpty) return;
    appendStandardTimelineItems(items, pendingTurnEntries);
    pendingTurnEntries.clear();
  }

  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
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
      // App Server emits the final agent message before the turn duration.
      // Keep that last answer, approvals, and errors outside the disclosure:
      // collapsing elapsed details must never hide the user-visible outcome or
      // a decision/audit record.
      final finalAgentIndex = pendingTurnEntries.lastIndexWhere(
        (item) => item.entry.kind == TimelineKind.agent,
      );
      final processEntries = <IndexedTimelineEntry>[];
      final visibleEntries = <IndexedTimelineEntry>[];
      for (
        var pendingIndex = 0;
        pendingIndex < pendingTurnEntries.length;
        pendingIndex++
      ) {
        final item = pendingTurnEntries[pendingIndex];
        final staysVisible =
            pendingIndex == finalAgentIndex ||
            item.entry.kind == TimelineKind.approval ||
            item.entry.kind == TimelineKind.error;
        (staysVisible ? visibleEntries : processEntries).add(item);
      }
      // Keep audit records and the final answer at their original position
      // relative to the duration. Moving them after the disclosure would make
      // an approval or error that happened during the turn look post-completion.
      appendStandardTimelineItems(items, visibleEntries);
      if (processEntries.isEmpty) {
        items.add(ConversationTimelineItem.entry(entry, index));
      } else {
        items.add(
          ConversationTimelineItem.completedTurn(
            entry,
            processEntries.map((item) => item.entry).toList(growable: false),
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
