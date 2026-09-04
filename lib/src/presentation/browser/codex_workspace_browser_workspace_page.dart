import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_url_normalizer.dart';
import 'package:flutter/material.dart';

/// macOS 内置浏览器工作区，承载原生 WebView、多标签与导航控件。
/// A macOS browser workspace with native WebViews, tabs, and navigation controls.
class BrowserWorkspacePage extends StatefulWidget {
  const BrowserWorkspacePage({
    required this.onOpenConversation,
    this.initialUrl,
    this.navigationRevision = 0,
    this.isVisible = true,
    this.urlSafetyChecker = isBrowserWebUriSafe,
    super.key,
  });

  final VoidCallback onOpenConversation;
  final String? initialUrl;
  final int navigationRevision;
  final bool isVisible;
  final Future<bool> Function(Uri uri) urlSafetyChecker;

  @override
  State<BrowserWorkspacePage> createState() => BrowserWorkspacePageState();
}
