// Extracted App Server history verification helper.
import 'dart:io';

class Options {
  const Options({required this.workingDirectory, this.threadId});

  final String workingDirectory;
  final String? threadId;

  static Options parse(List<String> arguments) {
    String? cwd;
    String? threadId;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--cwd':
          cwd = _argumentValue(arguments, ++index);
        case '--thread-id':
          threadId = _argumentValue(arguments, ++index);
        default:
          throw ArgumentError(
            'Usage: dart run tool/verify_app_server_history.dart '
            '[--cwd <directory>] [--thread-id <id>]',
          );
      }
    }
    return Options(
      workingDirectory: cwd ?? Directory.current.path,
      threadId: threadId,
    );
  }

  /// 读取紧随命令行选项后的参数值，缺失时抛出格式错误。
  /// Reads the value following a command-line option or throws on absence.
  static String _argumentValue(List<String> arguments, int index) {
    if (index >= arguments.length || arguments[index].startsWith('--')) {
      throw ArgumentError(
        'Usage: dart run tool/verify_app_server_history.dart '
        '[--cwd <directory>] [--thread-id <id>]',
      );
    }
    return arguments[index];
  }
}
