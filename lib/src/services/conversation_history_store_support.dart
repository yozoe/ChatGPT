// Shared declarations extracted from conversation_history_store.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'app_storage_scope.dart';
import 'codex_keychain_storage.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'app_storage_scope.dart';
import 'codex_keychain_storage.dart';

/// 单个工作区的可加密持久化视图；与 App Server 的原始会话数据分离。
/// Encryptable persisted view of one workspace, separate from App Server's source session.

/// 可移植的本地历史导出格式；只包含本应用的缓存，不代表可恢复 App Server 的原始 session。
/// A portable local-history export format; it includes only this app's cache and cannot restore an App Server session.

/// 将每个工作区的对话缓存加密保存到用户的 Application Support 目录，App Server 停止或暂时不可用时仍可显示历史。
/// Stores each workspace's encrypted conversation cache in Application Support so history remains visible while App Server is stopped or unavailable.
