// Shared declarations extracted from app_controller.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/domain/pending_elicitation.dart';
import 'package:chatgpt/src/domain/runtime_log_entry.dart';
import 'package:chatgpt/src/domain/scheduled_task.dart';
import 'package:chatgpt/src/domain/subagent_thread_view.dart';
import 'package:chatgpt/src/domain/task_plan.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/clipboard_file_reader.dart';
import 'package:chatgpt/src/services/codex_plugin_store.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:chatgpt/src/services/local_session_thread_store.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'app_controller_codex_controller_notifier.dart';
import 'app_controller_codex_controller.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/domain/pending_approval.dart';
import 'package:chatgpt/src/domain/pending_elicitation.dart';
import 'package:chatgpt/src/domain/runtime_log_entry.dart';
import 'package:chatgpt/src/domain/scheduled_task.dart';
import 'package:chatgpt/src/domain/subagent_thread_view.dart';
import 'package:chatgpt/src/domain/task_plan.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/clipboard_file_reader.dart';
import 'package:chatgpt/src/services/codex_plugin_store.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:chatgpt/src/services/local_session_thread_store.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';

/// App Server 连接与当前前台任务共同决定的工作台运行状态。
/// Workbench runtime state derived from the App Server connection and focused turn.
enum RuntimeStatus { stopped, starting, ready, running, failed }

/// 当前运行时凭据来源的已解析状态；不暴露任何凭据内容。
/// Resolved runtime credential source without exposing credential values.
enum AuthStatus { checking, signedOut, chatgpt, apiKey, external }

/// App Server 请求额外权限时采用的本地决策策略。
/// Local decision policy for App Server approval requests.
enum ApprovalMode { manual, autoApprove }

enum TurnCompletionOutcome { succeeded, stopped, failed, unknown }

/// Result of one archive submission, including tasks that were deliberately
/// left untouched because their state changed before the request was sent.
///
/// 单次归档提交结果，同时保留因状态变化而未发送请求的任务及原因。
@immutable
/// App Server 明确报告、但尚未完成的当前 turn 活动。
/// A transient activity that App Server has explicitly reported for the
/// focused turn. It is intentionally not persisted: completed work belongs in
/// the timeline, while this only describes what is happening right now.
@immutable
/// 会与另一 Codex 客户端争抢 writer 的任务操作。
/// Thread operations that can conflict with another Codex client's writer.
enum ThreadWriterConflictOperation { resume, archive }

/// A recoverable operation rejected because another Codex client still owns
/// the thread writer. The workspace is retained so a stale retry can never
/// run after the user moves to another project.

/// 保存“先取消归档、再打开任务”的可重试上下文。
/// Retry context for unarchiving a task before opening it.

/// In-memory view state for a previously opened task.
/// 已打开任务的内存视图缓存。

/// Read-only local task list for a workspace that is not currently connected.
/// 由本地历史恢复的非当前项目只读任务列表。
@immutable
/// 非当前项目的只读任务清单，来自本地加密历史而非活动运行时。
/// Read-only task list for an inactive workspace, sourced from local history.
/// A direction change submitted from the composer but not yet sent to the
/// active App Server turn. It is deliberately transient and never written to
/// the conversation history until `turn/steer` succeeds.
/// 在输入框提交、但尚未发送至当前 App Server turn 的调整方向。它仅存在于
/// 当前界面；在 `turn/steer` 成功前不会写入对话历史。
@immutable
/// Composer 已提交但尚未发送给 App Server 的临时方向调整。
/// A composer direction change retained locally until it can be sent to App Server.
/// Exact inputs for a turn that can be submitted again after a task failure.
/// 可在任务失败后原样再次提交的 turn 输入；仅保留在当前应用进程内。
@immutable
@immutable
JsonMap cloneJsonMap(JsonMap value) =>
    JsonMap.from(jsonDecode(jsonEncode(value)) as Map);

/// 将本地存储的审批模式转换为受支持的安全值。
/// Converts a locally stored approval mode into a supported safe value.
ApprovalMode approvalModeFromStorageValue(String? value) =>
    value == ApprovalMode.autoApprove.name
    ? ApprovalMode.autoApprove
    : ApprovalMode.manual;

/// App Server 公布的推理强度；保留未知字符串以兼容未来新增的模型能力。
/// A reasoning effort advertised by App Server; unknown strings are preserved for future model capabilities.
@immutable
/// 保留 App Server 原始配置值的推理强度选择，兼容未来新增等级。
/// Reasoning-effort selection that preserves raw App Server values for forward compatibility.
/// 将审批策略映射为稳定的界面标签。
/// Maps approval policies to stable UI labels.
extension ApprovalModeLabel on ApprovalMode {
  /// 返回用于界面的本地化审批模式标签。
  /// Returns the localized approval-mode label for the UI.
  String get label => switch (this) {
    ApprovalMode.manual => '请求批准',
    ApprovalMode.autoApprove => '帮我批准',
  };
}

/// App Server 模型目录中可供新任务选择的只读条目。
/// A read-only model-catalog entry that can be selected for new App Server threads.

/// 提供应用共享的 Codex 控制器，并在 ProviderScope 销毁时释放资源。
/// Provides the app-wide Codex controller and releases its resources when the ProviderScope is disposed.
final codexControllerProvider =
    NotifierProvider<CodexControllerNotifier, CodexController>(
      CodexControllerNotifier.new,
    );

/// 将既有控制器的状态变更桥接为 Riverpod 状态更新。
/// Bridges existing controller changes into Riverpod state updates.

/// 应用的协调层：维护运行时、工作区、任务历史与实时 App Server 事件。
/// Application coordinator for runtime, workspaces, task history, and live App Server events.
