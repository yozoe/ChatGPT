import 'dart:convert';
import 'dart:io';

import 'package:chatgpt/src/services/codex_ide_context_host_transport.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'codex-ide-context-transport-',
  );
  final updates = <Object?>[];
  final transport = CodexIdeContextHostTransport(
    discoveryDirectory: directory,
    onUpdate: updates.add,
  );
  try {
    await transport.start();
    final discovery =
        jsonDecode(
              await File(
                '${directory.path}/${CodexIdeContextHostTransport.discoveryFileName}',
              ).readAsString(),
            )
            as Map;
    final port = discovery['port'] as int;
    final token = discovery['token'] as String;

    final unauthorized = await _post(
      port: port,
      token: 'invalid-token',
      body: jsonEncode({
        'activeFile': {'path': '/blocked.dart'},
      }),
    );
    _expect(unauthorized.statusCode == HttpStatus.unauthorized);
    await unauthorized.drain();

    final accepted = await _post(
      port: port,
      token: token,
      body: jsonEncode({
        'activeFile': {'path': '/workspace/main.dart'},
      }),
    );
    _expect(accepted.statusCode == HttpStatus.ok);
    await accepted.drain();
    _expect(updates.length == 1);

    final malformed = await _post(port: port, token: token, body: '{malformed');
    _expect(malformed.statusCode == HttpStatus.badRequest);
    await malformed.drain();

    final oversized = await _post(
      port: port,
      token: token,
      body: List.filled(
        CodexIdeContextHostTransport.maxRequestBytes + 1,
        'x',
      ).join(),
    );
    _expect(oversized.statusCode == HttpStatus.requestEntityTooLarge);
    await oversized.drain();

    final disconnected = await _post(port: port, token: token, body: '{}');
    _expect(disconnected.statusCode == HttpStatus.ok);
    await disconnected.drain();
    _expect(updates.length == 2 && updates.last is Map);
  } finally {
    await transport.stop();
    _expect(
      !File(
        '${directory.path}/${CodexIdeContextHostTransport.discoveryFileName}',
      ).existsSync(),
    );
    await directory.delete(recursive: true);
  }
  stdout.writeln('IDE context host transport verification passed.');
}

Future<HttpClientResponse> _post({
  required int port,
  required String token,
  required String body,
}) async {
  final client = HttpClient();
  final request = await client.post('127.0.0.1', port, '/updateContext');
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.headers.contentType = ContentType.json;
  request.write(body);
  final response = await request.close();
  client.close();
  return response;
}

void _expect(bool condition) {
  if (!condition) throw StateError('IDE context transport verification failed');
}
