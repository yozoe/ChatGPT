/// Shared framework and domain dependencies for the Codex workspace modules.
library;

export 'dart:async' hide AsyncError;
export 'dart:convert';
export 'dart:io';

export 'package:desktop_drop/desktop_drop.dart';
export 'package:file_selector/file_selector.dart';
export 'package:flutter/foundation.dart';
export 'package:flutter/material.dart';
export 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
export 'package:flutter/rendering.dart';
export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter/services.dart';
export 'package:url_launcher/url_launcher.dart';

export 'package:chatgpt/src/app_controller.dart';
export 'package:chatgpt/src/codex_hover_popup.dart';
export 'package:chatgpt/src/domain/codex_file_change.dart';
export 'package:chatgpt/src/domain/codex_hook.dart';
export 'package:chatgpt/src/domain/codex_marketplace.dart';
export 'package:chatgpt/src/domain/codex_mcp_server.dart';
export 'package:chatgpt/src/domain/codex_plugin.dart';
export 'package:chatgpt/src/domain/codex_skill.dart';
export 'package:chatgpt/src/domain/codex_thread.dart';
export 'package:chatgpt/src/domain/git_project_status.dart';
export 'package:chatgpt/src/domain/pending_approval.dart';
export 'package:chatgpt/src/domain/pending_elicitation.dart';
export 'package:chatgpt/src/domain/scheduled_task.dart';
export 'package:chatgpt/src/domain/task_plan.dart';
export 'package:chatgpt/src/domain/timeline_entry.dart';
export 'package:chatgpt/src/domain/workspace_configuration.dart';
export 'package:chatgpt/src/services/agent_markdown_link.dart';
export 'package:chatgpt/src/services/clipboard_file_reader.dart';
export 'package:chatgpt/src/services/codex_app_server.dart';
export 'package:chatgpt/src/theme/yeknom_workbench.dart';
export 'package:chatgpt/src/presentation/code_review/code_review_panel.dart';
export 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview.dart';
