import 'package:chatgpt/src/presentation/workspace/workspace_file_tabs_notifier.dart';
import 'package:chatgpt/src/services/agent_markdown_link.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears switched workspaces and rejects late file-open requests', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = workspaceFileTabsProvider((
      scope: Object(),
      initialWorkspacePath: '/workspace-a',
    ));
    final notifier = container.read(provider.notifier);
    final originalReference = WorkspaceFileReference(
      uri: Uri.file('/workspace-a/example.dart'),
    );

    final originalTab = notifier.open(
      originalReference,
      workspacePath: '/workspace-a',
    );
    expect(originalTab, workspaceFileTabId(originalReference.path));
    expect(container.read(provider).files, contains(originalTab));

    expect(notifier.synchronizeWorkspace('/workspace-b'), isTrue);
    expect(container.read(provider).files, isEmpty);
    expect(
      notifier.open(originalReference, workspacePath: '/workspace-a'),
      isNull,
    );
    expect(container.read(provider).files, isEmpty);
  });
}
