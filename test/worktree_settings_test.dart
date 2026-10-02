import 'package:chatgpt/src/domain/worktree_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worktree settings round trip and invalid retention fallback', () {
    const settings = WorktreeSettings(
      rootPath: '/tmp/codex-worktrees',
      fetchBeforeCreate: true,
      autoCleanup: false,
      retentionLimit: 7,
    );
    final decoded = WorktreeSettings.fromJson(settings.toJson());
    expect(decoded.toJson(), settings.toJson());
    expect(
      WorktreeSettings.fromJson(const {
        'rootPath': '/tmp/worktrees',
        'retentionLimit': 0,
      }).retentionLimit,
      15,
    );
  });
}
