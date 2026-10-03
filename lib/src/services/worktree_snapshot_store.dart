import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chatgpt/src/domain/local_worktree_record.dart';
import 'package:chatgpt/src/domain/worktree_snapshot.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey, Sha256;

/// Captures and persists encrypted managed-worktree content snapshots.
class WorktreeSnapshotStore {
  WorktreeSnapshotStore({RuntimeConfigurationStore? store})
    : _store = store ?? RuntimeConfigurationStore();

  final RuntimeConfigurationStore _store;

  Future<WorktreeSnapshot> capture({
    required LocalWorktreeRecord record,
  }) async {
    final patch = await _run(record.worktreePath, const [
      'diff',
      '--binary',
      'HEAD',
    ]);
    if (patch.exitCode != 0) {
      throw StateError('无法读取工作树的 tracked 改动。');
    }
    final files = <String, String>{};
    final untracked = await _run(record.worktreePath, const [
      'ls-files',
      '--others',
      '--exclude-standard',
      '-z',
    ]);
    if (untracked.exitCode != 0) {
      throw StateError('无法读取工作树的 untracked 文件。');
    }
    for (final path in untracked.stdout.split('\u0000')) {
      if (path.isEmpty) continue;
      await _captureFile(
        root: Directory(record.worktreePath),
        relative: path,
        files: files,
      );
    }
    for (final relative in await _includedPaths(record)) {
      await _captureFile(
        root: Directory(record.worktreePath),
        relative: relative,
        files: files,
      );
    }
    return WorktreeSnapshot(
      snapshotId: _newSnapshotId(),
      baseCommit: record.baseCommit,
      trackedPatch: patch.stdout.toString(),
      files: files,
    );
  }

  Future<({String snapshotId, String digest})> save({
    required String rootPath,
    required WorktreeSnapshot snapshot,
  }) async {
    final root = Directory(rootPath);
    if (!root.isAbsolute) throw StateError('快照根目录必须是绝对路径。');
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}.codex-snapshots',
    );
    await directory.create(recursive: true);
    final encoded = await _encrypt(snapshot);
    final bytes = utf8.encode(encoded);
    final digest = base64UrlEncode((await Sha256().hash(bytes)).bytes);
    final destination = _snapshotFile(directory, snapshot.snapshotId);
    final temporary = File(
      '${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return (snapshotId: snapshot.snapshotId, digest: digest);
  }

  Future<WorktreeSnapshot> read({
    required String rootPath,
    required String snapshotId,
    required String digest,
  }) async {
    final directory = Directory(
      '${Directory(rootPath).path}${Platform.pathSeparator}.codex-snapshots',
    );
    final file = _snapshotFile(directory, snapshotId);
    if (!await file.exists()) throw StateError('工作树保护快照不存在。');
    final bytes = await file.readAsBytes();
    final actual = base64UrlEncode((await Sha256().hash(bytes)).bytes);
    if (actual != digest) throw StateError('工作树保护快照完整性校验失败。');
    final snapshot = await _decrypt(utf8.decode(bytes));
    if (snapshot.snapshotId != snapshotId) {
      throw StateError('工作树保护快照身份校验失败。');
    }
    return snapshot;
  }

  Future<void> delete({
    required String rootPath,
    required String snapshotId,
  }) async {
    final directory = Directory(
      '${Directory(rootPath).path}${Platform.pathSeparator}.codex-snapshots',
    );
    try {
      await _snapshotFile(directory, snapshotId).delete();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) {
        rethrow;
      }
    }
  }

  Future<List<String>> _includedPaths(LocalWorktreeRecord record) async {
    final paths = <String>{};
    final include = File(
      '${record.sourceRepository}${Platform.pathSeparator}.worktreeinclude',
    );
    if (await include.exists()) {
      for (final line in await include.readAsLines()) {
        final value = line.trim();
        if (value.isEmpty || value.startsWith('#') || value.startsWith('/')) {
          continue;
        }
        paths.add(value.replaceAll('\\', '/'));
      }
    }
    final override = File(
      '${record.sourceRepository}${Platform.pathSeparator}AGENTS.override.md',
    );
    if (await override.exists()) paths.add('AGENTS.override.md');
    return paths.toList(growable: false);
  }

  Future<void> _captureFile({
    required Directory root,
    required String relative,
    required Map<String, String> files,
  }) async {
    final normalized = relative.replaceAll('\\', '/');
    final entity = _safeChild(root, normalized);
    if (entity == null) throw StateError('快照包含越界路径：$relative');
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.link) {
      throw StateError('快照不接受符号链接：$relative');
    }
    if (type == FileSystemEntityType.directory) {
      await for (final child in Directory(
        entity.path,
      ).list(followLinks: false)) {
        final childRelative = child.path.substring(root.path.length + 1);
        await _captureFile(root: root, relative: childRelative, files: files);
      }
      return;
    }
    files[normalized] = base64Encode(await File(entity.path).readAsBytes());
  }

  FileSystemEntity? _safeChild(Directory root, String relative) {
    if (relative.isEmpty || relative.split('/').contains('..')) return null;
    final candidate = File(
      '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
    );
    final prefix = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';
    if (!candidate.absolute.path.startsWith(prefix)) return null;
    return candidate;
  }

  File _snapshotFile(Directory directory, String snapshotId) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(snapshotId)) {
      throw StateError('快照标识无效。');
    }
    return File('${directory.path}${Platform.pathSeparator}$snapshotId.json');
  }

  Future<String> _encrypt(WorktreeSnapshot snapshot) async {
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(snapshot.toJson())),
      secretKey: SecretKey(await _readOrCreateKey()),
    );
    return jsonEncode({
      'version': 1,
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    });
  }

  Future<WorktreeSnapshot> _decrypt(String encoded) async {
    final envelope = jsonDecode(encoded);
    if (envelope is! Map ||
        envelope['nonce'] is! String ||
        envelope['mac'] is! String ||
        envelope['ciphertext'] is! String) {
      throw const FormatException('工作树保护快照格式无效。');
    }
    final box = SecretBox(
      base64Decode(envelope['ciphertext'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    final clear = await AesGcm.with256bits().decrypt(
      box,
      secretKey: SecretKey(await _readOrCreateKey()),
    );
    final payload = jsonDecode(utf8.decode(clear));
    if (payload is! Map) throw const FormatException('工作树保护快照内容无效。');
    return WorktreeSnapshot.fromJson(payload);
  }

  Future<List<int>> _readOrCreateKey() async {
    final stored = await _store.readWorktreeSnapshotEncryptionKey();
    if (stored != null && stored.isNotEmpty) return base64Decode(stored);
    final generated = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    );
    await _store.saveWorktreeSnapshotEncryptionKey(base64Encode(generated));
    return generated;
  }

  String _newSnapshotId() => base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  Future<ProcessResult> _run(String cwd, List<String> args) =>
      Process.run('git', args, workingDirectory: cwd);
}
