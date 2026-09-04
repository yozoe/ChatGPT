// Extracted class from app_controller.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
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
import 'app_controller_support.dart';

/// 保留 App Server 原始配置值的推理强度选择，兼容未来新增等级。
/// Reasoning-effort selection that preserves raw App Server values for forward compatibility.
class ReasoningEffort {
  const ReasoningEffort._(this.configValue);

  static const defaultValue = ReasoningEffort._(null);
  static const minimal = ReasoningEffort._('minimal');
  static const low = ReasoningEffort._('low');
  static const medium = ReasoningEffort._('medium');
  static const high = ReasoningEffort._('high');
  static const xhigh = ReasoningEffort._('xhigh');

  /// 要发送给 App Server 的原始配置值；`null` 表示使用模型默认值。
  /// Raw configuration value sent to App Server; `null` uses the model default.
  final String? configValue;

  /// 返回稳定的菜单 Key 名称，同时保留 App Server 的未知值。
  /// Returns a stable menu-key name while preserving unknown App Server values.
  String get name => configValue ?? 'defaultValue';

  /// 返回用于界面的推理强度标签，未知值直接展示原始名称。
  /// Returns a UI label, displaying an unknown effort by its original name.
  String get label => switch (configValue) {
    null => '默认',
    'minimal' => '最小',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    'max' => '最高',
    final value => value,
  };

  /// 将保存或服务器返回的配置值转换为不会丢失未知值的对象。
  /// Converts a persisted or server-provided value without dropping unknown values.
  static ReasoningEffort fromConfigValue(String? value) {
    final normalized = value?.trim();
    return switch (normalized) {
      null || '' => defaultValue,
      'minimal' => minimal,
      'low' => low,
      'medium' => medium,
      'high' => high,
      'xhigh' => xhigh,
      final value => ReasoningEffort._(value),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReasoningEffort && other.configValue == configValue;

  @override
  int get hashCode => configValue.hashCode;
}
