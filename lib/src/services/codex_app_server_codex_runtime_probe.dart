// Extracted class from codex_app_server.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'codex_app_server_support.dart';

class CodexRuntimeProbe {
  const CodexRuntimeProbe({
    required this.isAvailable,
    this.executablePath,
    this.version,
    this.discovery,
    this.error,
  });

  final bool isAvailable;
  final String? executablePath;
  final String? version;
  final String? discovery;
  final String? error;
}
