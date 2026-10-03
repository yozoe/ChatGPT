import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_download.dart';
import 'package:chatgpt/src/services/browser_history_store.dart';
import 'package:chatgpt/src/services/browser_download_store.dart';
import 'package:chatgpt/src/services/browser_session_store.dart';
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
    this.historyStore,
    this.downloadStore,
    this.sessionStore,
    this.downloadDirectory,
    this.askBeforeDownload = true,
    this.restoreTabs = false,
    this.clearWebsiteData,
    this.clearCache,
    this.clearNavigationHistory,
    this.restoreTabNavigation,
    this.downloadSaver,
    super.key,
  });

  final VoidCallback onOpenConversation;
  final String? initialUrl;
  final int navigationRevision;
  final bool isVisible;
  final Future<bool> Function(Uri uri) urlSafetyChecker;
  final BrowserHistoryStore? historyStore;
  final BrowserDownloadStore? downloadStore;
  final BrowserSessionStore? sessionStore;
  final String? downloadDirectory;
  final bool askBeforeDownload;
  final bool restoreTabs;
  final Future<void> Function()? clearWebsiteData;
  final Future<void> Function()? clearCache;
  final Future<void> Function()? clearNavigationHistory;
  final Future<void> Function(int tabId, Uri uri)? restoreTabNavigation;
  final BrowserDownloadSaver? downloadSaver;

  @override
  State<BrowserWorkspacePage> createState() => BrowserWorkspacePageState();
}
