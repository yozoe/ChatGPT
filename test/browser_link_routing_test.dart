import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/workspace/browser_link_open_scope.dart';

void main() {
  testWidgets(
    'routes user-activated HTTP Markdown links to the browser scope',
    (tester) async {
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: BrowserLinkOpenScope(
            onOpenBrowserLink: (uri) async {
              opened = uri;
              return true;
            },
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  openAgentMarkdownDestination(
                    context,
                    href: 'https://example.com/docs',
                    workspacePath: null,
                  ),
                ),
                child: const Text('link'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('link'));
      await tester.pump();

      expect(opened, Uri.parse('https://example.com/docs'));
    },
  );
}
