import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_address.dart';

/// Installation-scoped binding. There is intentionally no reset/change API.
class ServerBinding {
  final SharedPreferences preferences;
  ServerBinding(this.preferences);
  bool get isLocked => preferences.containsKey('server_origin');
  ServerAddress? read() {
    if (!isLocked) return null;
    final value = preferences.get('server_origin');
    if (value is! String) {
      throw const FormatException('بيانات الاتصال غير صالحة.');
    }
    return ServerAddress.parse(value);
  }

  Future<void> bind(ServerAddress candidate) async {
    if (isLocked) {
      if (read().toString() != candidate.toString()) {
        throw StateError('Connection is already bound to this installation');
      }
      return;
    }
    if (!await preferences.setString('server_origin', candidate.toString())) {
      throw StateError('Could not persist connection');
    }
  }
}
