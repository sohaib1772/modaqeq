import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import '../models/server_address.dart';
import 'portal_transport.dart';
import 'print_layout.dart';

/// Produces a network-free, script-free snapshot. Authenticated resources are
/// fetched through the native cookie store before entering the print WebView.
class PrintDocument {
  final PortalTransport transport;
  final ServerAddress server;
  final CancelToken cancellation;
  int total = 0;
  int count = 0;
  final Map<Uri, String> cache = {};
  PrintDocument(this.transport, this.server) : cancellation = transport.token;
  Future<List<int>> fetch(Uri uri, {int limit = 8 * 1024 * 1024}) async {
    if (cancellation.isCancelled) {
      throw cancellation.cancelError!;
    }
    if (!server.contains(uri)) {
      throw const FormatException('مصدر الطباعة خارج السيرفر.');
    }
    if (++count > 80) throw const FormatException('موارد الطباعة كثيرة جداً.');
    final bytes = await transport.bytes(server, uri, limit: limit);
    if (cancellation.isCancelled) {
      throw cancellation.cancelError!;
    }
    total += bytes.length;
    if (total > 24 * 1024 * 1024) {
      throw const FormatException('مستند الطباعة كبير جداً.');
    }
    return bytes;
  }

  Future<String> resource(String value, Uri base) async {
    if (value.startsWith('data:image/') || value.startsWith('data:font/')) {
      return value;
    }
    final uri = base.resolve(value);
    if (!server.contains(uri)) {
      throw const FormatException('مصدر الطباعة خارج السيرفر.');
    }
    if (cache.containsKey(uri)) return cache[uri]!;
    final bytes = await fetch(uri);
    final path = uri.path.toLowerCase();
    final mime = path.endsWith('.png')
        ? 'image/png'
        : path.endsWith('.jpg') || path.endsWith('.jpeg')
        ? 'image/jpeg'
        : path.endsWith('.woff2')
        ? 'font/woff2'
        : path.endsWith('.woff')
        ? 'font/woff'
        : path.endsWith('.ttf')
        ? 'font/ttf'
        : 'application/octet-stream';
    return cache[uri] = 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<String> css(String text, Uri base) async {
    text = text.replaceAll(RegExp(r'@import[^;]*;', caseSensitive: false), '');
    if (RegExp(
      r'expression\s*\(|javascript:|behavior\s*:',
      caseSensitive: false,
    ).hasMatch(text)) {
      return '';
    }
    final matches = RegExp(
      r'''url\(\s*["']?([^\)"']+)["']?\s*\)''',
      caseSensitive: false,
    ).allMatches(text).toList();
    for (final match in matches.reversed) {
      final data = await resource(match[1]!.trim(), base);
      text = text.replaceRange(match.start, match.end, 'url("$data")');
    }
    return text;
  }

  Future<String> prepare(String source) async =>
      (await prepareDocument(source)).html;

  Future<PreparedPrintDocument> prepareDocument(String source) async {
    final doc = html.parse(source);
    PrintLayout.extractInvoicePages(doc);
    PrintLayout.removeInterface(doc);
    final landscape = PrintLayout.landscape(doc);
    doc
        .querySelectorAll(
          'script,iframe,frame,frameset,object,embed,base,meta,form,button,input,textarea,select,audio,video,source,svg,math',
        )
        .forEach((e) => e.remove());
    for (final link in doc.querySelectorAll('link').toList()) {
      if (link.attributes['rel'] == 'stylesheet') {
        final uri = server.resolve(link.attributes['href'] ?? '');
        final bytes = await fetch(uri, limit: 1024 * 1024);
        link.replaceWith(
          Element.tag('style')..text = await css(utf8.decode(bytes), uri),
        );
      } else {
        link.remove();
      }
    }
    for (final element in doc.querySelectorAll('*')) {
      element.attributes.removeWhere(
        (key, value) => ![
          'style',
          'class',
          'id',
          'dir',
          'lang',
          'colspan',
          'rowspan',
          'width',
          'height',
          'src',
          'alt',
          'hidden',
        ].contains(key),
      );
      if (element.localName == 'img') {
        element.attributes['src'] = await resource(
          element.attributes['src'] ?? '',
          server.origin,
        );
      } else {
        element.attributes.remove('src');
      }
      if (element.attributes.containsKey('style')) {
        element.attributes['style'] = await css(
          element.attributes['style']!,
          server.origin,
        );
      }
      if (element.localName == 'style') {
        element.text = await css(element.text, server.origin);
      }
    }
    PrintLayout.apply(doc, landscape: landscape);
    doc.head!.nodes.insert(
      0,
      Element.tag('meta')
        ..attributes.addAll({
          'http-equiv': 'Content-Security-Policy',
          'content':
              "default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
        }),
    );
    return PreparedPrintDocument(
      '<!doctype html>${doc.documentElement!.outerHtml}',
      landscape: landscape,
    );
  }
}
