import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'presentation/codex_workspace.dart';

void runCodexDesk() {
  runApp(const CodexDeskApp());
}

class CodexDeskApp extends StatelessWidget {
  const CodexDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B1017);
    const surface = Color(0xFF111925);
    const outline = Color(0xFF263448);
    const accent = Color(0xFF68E0B8);

    return MaterialApp(
      title: 'Codex Desk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          surface: surface,
          outline: outline,
        ),
        dividerColor: outline,
        useMaterial3: true,
      ),
      home: CodexWorkspace(controller: CodexController()),
    );
  }
}
