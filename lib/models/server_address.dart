class ServerAddress {
  final Uri origin;
  const ServerAddress._(this.origin);
  factory ServerAddress.parse(String input) {
    final text = input.trim();
    if (text.isEmpty || RegExp(r'[\s\\]').hasMatch(text)) {
      throw const FormatException(
        'أدخل عنوان الاتصال الذي زوّدك به مسؤول النظام.',
      );
    }
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
        'عنوان الاتصال غير صحيح. راجع العنوان مع مسؤول النظام.',
      );
    }
    return ServerAddress._(Uri.parse(uri.origin));
  }
  bool contains(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.origin == origin.origin;
  Uri resolve(String path) => origin.resolve(path);
  @override
  String toString() => origin.origin;
}
