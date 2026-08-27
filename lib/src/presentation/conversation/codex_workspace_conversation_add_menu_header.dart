// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_header_state.dart';

class AddMenuHeader extends PopupMenuEntry<AddMenuAction> {
  const AddMenuHeader({required this.label, required this.palette});

  final String label;
  final YeknomPalette palette;

  @override
  double get height => 34;

  @override
  bool represents(AddMenuAction? value) => false;

  @override
  State<AddMenuHeader> createState() => AddMenuHeaderState();
}
