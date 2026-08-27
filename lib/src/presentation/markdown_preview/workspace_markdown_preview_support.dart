// Shared declarations extracted from workspace_markdown_preview.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:chatgpt/src/presentation/markdown_preview/workspace_markdown_preview_workspace_markdown_preview.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';

const maximumMarkdownBytes = 8 * 1024 * 1024;
const sourceLineExtent = 24.0;
const maximumRenderedSourceLineCharacters = 4096;
const truncatedSourceLineMessage = '… 此行过长，已截断显示';

enum MarkdownViewMode { preview, source }

/// Opens a project-local Markdown document without leaving the workbench.
Future<void> showWorkspaceMarkdownPreview(
  BuildContext context, {
  required WorkspaceFileReference reference,
  required String workspacePath,
}) async {
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭 Markdown 预览',
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, animation, secondaryAnimation) =>
        WorkspaceMarkdownPreview(
          reference: reference,
          workspacePath: workspacePath,
        ),
  );
}

MarkdownStyleSheet markdownStyle(ThemeData theme, YeknomPalette palette) {
  final body = theme.textTheme.bodyMedium?.copyWith(
    color: palette.trace,
    fontSize: 13,
    height: 1.55,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    pPadding: const EdgeInsets.only(bottom: 4),
    h1: body?.copyWith(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 12),
    h2: body?.copyWith(fontSize: 16, height: 1.3, fontWeight: FontWeight.w600),
    h2Padding: const EdgeInsets.only(top: 16, bottom: 8),
    h3: body?.copyWith(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600),
    h3Padding: const EdgeInsets.only(top: 12, bottom: 6),
    blockSpacing: 10,
    listIndent: 24,
    listBullet: body,
    a: body?.copyWith(
      color: palette.active,
      decoration: TextDecoration.underline,
      decorationColor: palette.active.withValues(alpha: 0.6),
    ),
    code: body?.copyWith(
      color: palette.trace,
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.5,
      backgroundColor: palette.field,
    ),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: palette.field,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: palette.border),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    blockquoteDecoration: BoxDecoration(
      color: palette.raised,
      border: Border(left: BorderSide(color: palette.active, width: 3)),
    ),
    tableBorder: TableBorder.all(color: palette.border),
    tableHead: body?.copyWith(fontWeight: FontWeight.w700),
    tableBody: body,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: palette.border)),
    ),
  );
}
