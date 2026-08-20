import 'package:flutter/material.dart';
import 'package:yeknom_ui_kit/yeknom_workbench.dart';

import 'app_controller.dart';
import 'presentation/codex_workspace.dart';

/// 挂载 Codex Desk 的根 Widget。
/// Mounts the Codex Desk root widget.
void runCodexDesk() {
  runApp(const CodexDeskApp());
}

class CodexDeskApp extends StatelessWidget {
  const CodexDeskApp({super.key});

  /// 构建应用主题和初始工作区。
  /// Builds the application theme and initial workspace.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codex Desk',
      debugShowCheckedModeBanner: false,
      theme: YeknomWorkbenchTheme.dark(preset: YeknomColorPreset.midnight),
      home: CodexWorkspace(controller: CodexController()),
    );
  }
}
