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

/// App Server 模型目录中可供新任务选择的只读条目。
/// A read-only model-catalog entry that can be selected for new App Server threads.
class CodexModelOption {
  const CodexModelOption({
    required this.id,
    required this.displayName,
    required this.description,
    required this.isDefault,
  });

  final String id;
  final String displayName;
  final String description;
  final bool isDefault;
}
