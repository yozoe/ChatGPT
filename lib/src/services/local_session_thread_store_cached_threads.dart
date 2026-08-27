// Extracted class from local_session_thread_store.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'local_session_thread_store_support.dart';

class CachedThreads {
  /// 创建带有加载时间的缓存条目。
  /// Creates a cache entry with its load timestamp.
  const CachedThreads({required this.threads, required this.loadedAt});

  final List<CodexThread> threads;
  final DateTime loadedAt;
}
