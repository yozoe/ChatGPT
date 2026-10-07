import 'package:flutter_test/flutter_test.dart';

import 'package:chatgpt/src/app_controller_runtime_exit_info.dart';

void main() {
  test('preserves the App Server exit code in the diagnostic message', () {
    final info = CodexRuntimeExitInfo.fromParams({'code': 17});

    expect(info.code, 17);
    expect(info.message, 'Codex runtime 已退出（code 17）。');
  });

  test('keeps the compatible null-code message when code is absent', () {
    final info = CodexRuntimeExitInfo.fromParams(const {});

    expect(info.message, 'Codex runtime 已退出（code null）。');
  });
}
