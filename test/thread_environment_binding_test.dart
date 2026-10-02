import 'package:chatgpt/src/domain/thread_environment_binding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('thread environment binding round trips', () {
    const binding = ThreadEnvironmentBinding(
      threadId: 'thread-1',
      kind: ThreadEnvironmentKind.managedWorktree,
      workingDirectory: '/tmp/worktree',
      worktreeId: 'wt-1',
    );
    final decoded = ThreadEnvironmentBinding.fromJson(binding.toJson());
    expect(decoded.threadId, 'thread-1');
    expect(decoded.kind, ThreadEnvironmentKind.managedWorktree);
    expect(decoded.workingDirectory, '/tmp/worktree');
    expect(decoded.worktreeId, 'wt-1');
  });
}
