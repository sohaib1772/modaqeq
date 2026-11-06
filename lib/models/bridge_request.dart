import 'dart:convert';
import 'server_address.dart';

class BridgeRequest {
  final String id, type;
  final Map<String, dynamic> data;
  BridgeRequest._(this.id, this.type, this.data);
  factory BridgeRequest.parse(String raw, ServerAddress server) {
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('حجم طلب الطباعة كبير جداً.');
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['id'] is! String ||
        (data['id'] as String).isEmpty ||
        (data['id'] as String).length > 128 ||
        !['print_html', 'download'].contains(data['type'])) {
      throw const FormatException('طلب غير مدعوم.');
    }
    final target = data[data['type'] == 'download' ? 'url' : 'base_url'];
    if (target is! String || !server.contains(Uri.tryParse(target))) {
      throw const FormatException('الرابط خارج السيرفر المختار.');
    }
    if (data['type'] == 'print_html' && data['html'] is! String) {
      throw const FormatException('مستند الطباعة غير صالح.');
    }
    return BridgeRequest._(data['id'], data['type'], data);
  }
}
