import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chatgpt/src/services/codex_app_server.dart';

import 'app_controller_codex_controller.dart';
import 'app_controller_codex_controller_notifier.dart';

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

/// 会与另一 Codex 客户端争抢 writer 的任务操作。
/// Thread operations that can conflict with another Codex client's writer.
enum ThreadWriterConflictOperation { resume, archive }

JsonMap cloneJsonMap(JsonMap value) =>
    JsonMap.from(jsonDecode(jsonEncode(value)) as Map);

/// 将本地存储的审批模式转换为受支持的安全值。
/// Converts a locally stored approval mode into a supported safe value.
ApprovalMode approvalModeFromStorageValue(String? value) =>
    value == ApprovalMode.autoApprove.name
    ? ApprovalMode.autoApprove
    : ApprovalMode.manual;

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

/// 提供应用共享的 Codex 控制器，并在 ProviderScope 销毁时释放资源。
/// Provides the app-wide Codex controller and releases its resources when the ProviderScope is disposed.
final codexControllerProvider =
    NotifierProvider<CodexControllerNotifier, CodexController>(
      CodexControllerNotifier.new,
    );
