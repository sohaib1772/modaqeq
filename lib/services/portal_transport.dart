import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/server_address.dart';

class PortalTransport {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
      followRedirects: false,
    ),
  );
  CancelToken token = CancelToken();
  String? basicAuthorization;
  String? authorizationOrigin;
  void authorize(ServerAddress server, String value) {
    authorizationOrigin = server.toString();
    basicAuthorization = value;
  }

  void cancel() {
    token.cancel();
    token = CancelToken();
    basicAuthorization = null;
  }

  Future<Response<ResponseBody>> get(
    ServerAddress server,
    Uri uri, {
    int redirects = 0,
    CancelToken? requestToken,
  }) async {
    requestToken ??= token;
    if (requestToken.isCancelled) {
      throw requestToken.cancelError!;
    }
    if (!server.contains(uri) || redirects > 5) {
      throw const FormatException('تم رفض رابط أو تحويل خارج السيرفر.');
    }
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(uri.toString()),
    );
    final response = await dio.get<ResponseBody>(
      uri.toString(),
      cancelToken: requestToken,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        headers: {
          if (cookies.isNotEmpty)
            'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; '),
          if (basicAuthorization != null &&
              authorizationOrigin == server.toString())
            'Authorization': basicAuthorization!,
        },
      ),
    );
    if (requestToken.isCancelled) {
      throw requestToken.cancelError!;
    }
    for (final value in response.headers['set-cookie'] ?? <String>[]) {
      final cookie = io.Cookie.fromSetCookieValue(value);
      await CookieManager.instance().setCookie(
        url: WebUri(uri.toString()),
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path ?? '/',
        isSecure: cookie.secure,
        isHttpOnly: cookie.httpOnly,
        expiresDate: cookie.maxAge != null
            ? DateTime.now()
                  .add(Duration(seconds: cookie.maxAge!))
                  .millisecondsSinceEpoch
            : cookie.expires?.millisecondsSinceEpoch,
      );
    }
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      await response.data!.stream.drain<void>();
      final location = response.headers.value('location');
      if (location == null) throw const FormatException('تحويل غير صالح.');
      return get(
        server,
        uri.resolve(location),
        redirects: redirects + 1,
        requestToken: requestToken,
      );
    }
    if (response.statusCode != 200) {
      await response.data!.stream.drain<void>();
      throw io.HttpException('HTTP ${response.statusCode}');
    }
    return response;
  }

  Future<List<int>> bytes(
    ServerAddress server,
    Uri uri, {
    int limit = 8 * 1024 * 1024,
  }) async {
    final response = await get(server, uri);
    final result = <int>[];
    await for (final chunk in response.data!.stream) {
      if (result.length + chunk.length > limit) {
        throw const FormatException('تجاوز الملف الحجم المسموح.');
      }
      result.addAll(chunk);
    }
    return result;
  }
}
