// Shared declarations extracted from clipboard_file_reader.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'package:flutter/services.dart';
import 'package:flutter/services.dart';

/// 主机剪贴板公开给 Flutter 的文件系统项；临时项由原生层负责受限清理。
/// A filesystem item exposed by the host clipboard; native code owns constrained temporary cleanup.

/// 通过受限 MethodChannel 读取主机剪贴板文件，不读取普通文本内容。
/// Reads host clipboard files through a constrained MethodChannel without reading normal text.
