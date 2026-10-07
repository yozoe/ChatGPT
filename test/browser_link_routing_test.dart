import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_url_normalizer.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';
import 'package:chatgpt/src/presentation/workspace/browser_link_open_scope.dart';

void main() {
  test('browser URL normalizer accepts web URLs and rejects other schemes', () {
    expect(
      normalizeBrowserUrl('example.com'),
      Uri.parse('https://example.com'),
    );
    expect(normalizeBrowserUrl('http://localhost:3000/path'), isNull);
    expect(normalizeBrowserUrl('file:///tmp/example.txt'), isNull);
    expect(normalizeBrowserUrl('mailto:user@example.com'), isNull);
    expect(normalizeBrowserUrl('tel:+123456789'), isNull);
    expect(normalizeBrowserUrl('javascript:alert(1)'), isNull);
    expect(normalizeBrowserUrl('https://example.com/a b'), isNull);
    expect(isBrowserWebUri(Uri.parse('https://example.com')), isTrue);
    expect(isBrowserWebUri(Uri.parse('mailto:user@example.com')), isFalse);
  });

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
