// Extracted class from app.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'codex_hover_popup.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';
import 'theme_preferences_controller.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'app_support.dart';
import 'app_codex_desk_app_view_state.dart';

class CodexDeskAppView extends ConsumerStatefulWidget {
  const CodexDeskAppView({super.key});

  @override
  ConsumerState<CodexDeskAppView> createState() => CodexDeskAppViewState();
}
