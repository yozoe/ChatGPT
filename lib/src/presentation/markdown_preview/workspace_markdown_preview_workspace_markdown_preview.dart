// Extracted class from workspace_markdown_preview.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_support.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_workspace_markdown_preview_state.dart';

class WorkspaceMarkdownPreview extends StatefulWidget {
  const WorkspaceMarkdownPreview({
    required this.reference,
    required this.workspacePath,
    super.key,
  });

  final WorkspaceFileReference reference;
  final String workspacePath;

  @override
  State<WorkspaceMarkdownPreview> createState() =>
      WorkspaceMarkdownPreviewState();
}
