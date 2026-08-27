// Shared declarations extracted from codex_app_server.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// JSON-RPC 载荷在协议边界内使用的可变映射别名。
/// Mutable map alias used for JSON-RPC payloads at the protocol boundary.
typedef JsonMap = Map<String, dynamic>;

/// CLI 探测的可展示结果；错误文本进入前已在协议层脱敏。
/// Displayable CLI-probe result whose error text has already been redacted.

/// App Server 发出的通知或需要客户端回复的 JSON-RPC 请求。
/// A notification or client-answerable JSON-RPC request emitted by App Server.

/// `codex app-server --listen stdio://` 的协议边界，负责隔离逐行 JSON-RPC，避免原始协议 Map 泄漏到 Flutter Widget。
/// Boundary around `codex app-server --listen stdio://`; it isolates newline-delimited JSON-RPC so raw protocol maps do not leak into Flutter widgets.
