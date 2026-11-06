import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modaqeq_maktabali/services/server_binding.dart';
import 'package:modaqeq_maktabali/models/server_address.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('first successful binding survives a new store instance', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ServerBinding(prefs);
    expect(store.isLocked, false);
    await store.bind(ServerAddress.parse('portal.example.com'));
    final restored = ServerBinding(prefs);
    expect(restored.isLocked, true);
    expect(restored.read().toString(), 'https://portal.example.com');
  });
  test('cannot replace saved server; same origin is idempotent', () async {
    final store = ServerBinding(await SharedPreferences.getInstance());
    final first = ServerAddress.parse('first.example.com');
    await store.bind(first);
    await store.bind(first);
    await expectLater(
      store.bind(ServerAddress.parse('second.example.com')),
      throwsStateError,
    );
    expect(store.read().toString(), first.toString());
  });
  test(
    'corrupt saved address fails closed and cannot bind another server',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_origin', 'corrupt/address');
      final store = ServerBinding(prefs);
      expect(store.isLocked, true);
      expect(store.read, throwsFormatException);
      await expectLater(
        store.bind(ServerAddress.parse('second.example.com')),
        throwsFormatException,
      );
      expect(prefs.getString('server_origin'), 'corrupt/address');
    },
  );
}
