// Shared declarations extracted from pending_elicitation.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';

/// MCP 服务器向用户请求补充信息的形式。
/// The form of additional information requested by an MCP server.
enum ElicitationMode { form, url }

/// A safe, scalar field that can be rendered by the host form.

/// An MCP elicitation that is safe for this client to present to a user.
/// 不受支持或格式损坏的 schema 会被拒绝，而不会呈现为不完整的表单。
