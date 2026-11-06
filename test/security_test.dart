import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:almizan_mobile/models/server_address.dart';
import 'package:almizan_mobile/models/bridge_request.dart';
import 'package:almizan_mobile/services/portal_transport.dart';
import 'package:almizan_mobile/services/print_document.dart';

class FixtureTransport extends PortalTransport {
  final fetched = <Uri>[];
  @override
  Future<List<int>> bytes(
    ServerAddress server,
    Uri uri, {
    int limit = 8 * 1024 * 1024,
  }) async {
    if (!server.contains(uri)) throw const FormatException('external');
    fetched.add(uri);
    return uri.path.endsWith('.css')
        ? utf8.encode('body { color: black; }')
        : [1, 2, 3];
  }
}

void main() {
  final server = ServerAddress.parse('portal.example.com:8443');
  test('HTTPS address normalization, IP and IPv6', () {
    expect(server.toString(), 'https://portal.example.com:8443');
    expect(
      ServerAddress.parse('192.168.1.20').toString(),
      'https://192.168.1.20',
    );
    expect(ServerAddress.parse('[::1]:8443').origin.host, '::1');
  });
  test('reject credentials, paths, insecure schemes, query and fragments', () {
    for (final value in [
      '',
      'http://example.com',
      'https://user:secret@example.com',
      'example.com/login',
      'example.com?x=1',
      'example.com#x',
      'example.com\\evil',
      'https://example.com:65536',
    ]) {
      expect(
        () => ServerAddress.parse(value),
        throwsFormatException,
        reason: value,
      );
    }
  });
  test('origin compares scheme, host and port exactly', () {
    for (final value in [
      'http://portal.example.com:8443',
      'https://portal.example.com',
      'https://portal.example.com.evil:8443',
      'https://evil.com',
    ]) {
      expect(server.contains(Uri.parse(value)), isFalse);
    }
    expect(server.contains(server.resolve('/login')), isTrue);
  });
  test('bridge refuses unknown versions, commands and external URLs', () {
    final good = {
      'version': 1,
      'id': 'a',
      'type': 'download',
      'url': server.resolve('/backup').toString(),
    };
    expect(BridgeRequest.parse(jsonEncode(good), server).id, 'a');
    for (final bad in [
      {...good, 'version': 2},
      {...good, 'id': ''},
      {...good, 'type': 'shell'},
      {...good, 'url': 'https://evil.com/file'},
      {...good, 'url': 'javascript:alert(1)'},
    ]) {
      expect(
        () => BridgeRequest.parse(jsonEncode(bad), server),
        throwsFormatException,
      );
    }
    expect(
      () => BridgeRequest.parse('x' * (2 * 1024 * 1024 + 1), server),
      throwsFormatException,
    );
  });
  test(
    'print snapshot removes active content and embeds session resources',
    () async {
      final transport = FixtureTransport();
      final output = await PrintDocument(transport, server).prepare('''
      <html><head><script>alert(1)</script><base href="https://evil.com">
      <link rel="stylesheet" href="/style.css"></head><body onload="bad()">
      <iframe src="https://evil.com"></iframe><img src="/photo.png" onerror="bad()">
      <a href="javascript:bad()">فاتورة</a></body></html>''');
      expect(output, isNot(contains('<script')));
      expect(output, isNot(contains('<iframe')));
      expect(output, isNot(contains('onerror')));
      expect(output, isNot(contains('javascript:')));
      expect(output, contains('data:image/png;base64,'));
      expect(output, contains('Content-Security-Policy'));
      expect(transport.fetched.length, 2);
    },
  );
  test('printing cannot fetch external resources', () async {
    final transport = FixtureTransport();
    await expectLater(
      PrintDocument(
        transport,
        server,
      ).prepare('<img src="https://evil.com/x.png">'),
      throwsFormatException,
    );
    expect(transport.fetched, isEmpty);
  });
}
