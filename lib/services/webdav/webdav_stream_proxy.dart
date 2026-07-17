import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:spotube/models/webdav/webdav_account.dart';

class WebDavProxyResponse {
  final int statusCode;
  final Map<String, List<String>> headers;
  final Stream<List<int>>? body;

  const WebDavProxyResponse({
    required this.statusCode,
    required this.headers,
    this.body,
  });
}

class WebDavStreamProxy {
  final Dio _dio;

  WebDavStreamProxy({Dio? dio}) : _dio = dio ?? Dio();

  static String encodeRemoteUri(Uri uri) {
    return base64UrlEncode(utf8.encode(uri.toString())).replaceAll('=', '');
  }

  static Uri decodeRemoteUri(String value) {
    final padding = (4 - value.length % 4) % 4;
    final decoded = utf8.decode(
      base64Url.decode(value.padRight(value.length + padding, '=')),
    );
    return Uri.parse(decoded);
  }

  Future<WebDavProxyResponse> open({
    required WebDavAccount account,
    required Uri remoteUri,
    required String method,
    String? range,
    String? ifRange,
  }) async {
    if (!account.contains(remoteUri)) {
      throw const FormatException(
        'The requested WebDAV file is outside the library folder.',
      );
    }

    var currentUri = remoteUri;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final response = await _dio.request<ResponseBody>(
        currentUri.toString(),
        options: Options(
          method: method,
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            // AList redirects `/dav/` downloads to a signed `/d/` URL on the
            // same server. Preserve Basic Auth for that same-origin redirect;
            // common HTTP clients strip it and AList answers with sign error.
            if (_sameOrigin(account.endpointUri, currentUri))
              ...account.authorizationHeaders,
            if (range != null) 'Range': range,
            if (ifRange != null) 'If-Range': ifRange,
            // Baidu Netdisk signs direct download URLs for this exact user
            // agent. AList knows about the required header internally, but a
            // WebDAV 302 response cannot carry it to the client. Without it,
            // Baidu PCS rejects an otherwise valid URL with error 31362.
            if (userAgentForUri(currentUri) case final userAgent?)
              'User-Agent': userAgent,
            'Accept-Encoding': 'identity',
          },
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      final statusCode = response.statusCode ?? 502;
      final location = response.headers.value('location');
      if (statusCode >= 300 &&
          statusCode < 400 &&
          location != null &&
          redirectCount < 5) {
        await response.data?.stream.drain<void>();
        currentUri = currentUri.resolve(location);
        continue;
      }

      return WebDavProxyResponse(
        statusCode: statusCode,
        headers: _playbackHeaders(response.headers, currentUri),
        body: method == 'HEAD' ? null : response.data?.stream,
      );
    }

    throw StateError('Too many WebDAV download redirects.');
  }

  void close() => _dio.close();

  static Map<String, List<String>> _playbackHeaders(
    Headers source,
    Uri remoteUri,
  ) {
    const forwarded = {
      'accept-ranges',
      'cache-control',
      'content-length',
      'content-range',
      'content-type',
      'etag',
      'last-modified',
    };
    final headers = <String, List<String>>{
      for (final entry in source.map.entries)
        if (forwarded.contains(entry.key.toLowerCase())) entry.key: entry.value,
    };
    final location = source.value('location');
    if (location != null) {
      headers['location'] = [
        Uri.tryParse(location)?.hasScheme == true
            ? location
            : remoteUri.resolve(location).toString(),
      ];
    }
    return headers;
  }

  static bool _sameOrigin(Uri a, Uri b) {
    int effectivePort(Uri uri) {
      if (uri.hasPort) return uri.port;
      return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
    }

    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        effectivePort(a) == effectivePort(b);
  }

  static String? userAgentForUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final isBaiduPcs = host == 'baidupcs.com' ||
        host.endsWith('.baidupcs.com') ||
        host == 'pcs.baidu.com' ||
        host.endsWith('.pcs.baidu.com');
    return isBaiduPcs ? 'pan.baidu.com' : null;
  }
}
