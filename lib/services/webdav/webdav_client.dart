import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/utils/platform.dart';
import 'package:xml/xml.dart';

class WebDavException implements Exception {
  final String message;
  final int? statusCode;

  const WebDavException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class WebDavClient {
  final WebDavAccount account;
  final Dio _dio;

  WebDavClient(this.account, {Dio? dio}) : _dio = dio ?? Dio();

  Future<Uri> testConnection() async {
    final configuredRoot = account.endpointUri;
    late Uri connectedEndpoint;
    try {
      await _propfind(configuredRoot, depth: 0);
      connectedEndpoint = configuredRoot;
    } on WebDavException catch (error) {
      final isServerRoot = configuredRoot.pathSegments.every(
        (segment) => segment.isEmpty,
      );
      if (error.statusCode != 405 || !isServerRoot) rethrow;

      // AList/OpenList expose their web UI at `/` and WebDAV at `/dav/`.
      // Some music clients append this path automatically, so mirror that
      // compatibility behavior when the configured server root rejects
      // PROPFIND with Method Not Allowed.
      final discoveredRoot = configuredRoot.replace(path: '/dav/');
      await _propfind(discoveredRoot, depth: 0);
      connectedEndpoint = discoveredRoot;
    }

    final selectedRoot = account.resolveRoot(connectedEndpoint);
    if (selectedRoot != connectedEndpoint) {
      await _propfind(selectedRoot, depth: 0);
    }
    return connectedEndpoint;
  }

  Future<List<WebDavEntry>> list([Uri? directory]) async {
    final requestUri = directory ?? account.rootUri;
    final document = await _propfind(requestUri, depth: 1);
    final entries = <WebDavEntry>[];

    for (final response in document.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'response',
        )) {
      final href = _firstText(response, 'href');
      if (href == null || href.isEmpty) continue;

      final responseUri = _resolveHref(requestUri, href);
      if (!_isWithinAccountRoot(responseUri)) continue;
      if (_sameResource(requestUri, responseUri)) continue;

      final successfulProp = response.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'propstat')
          .where((element) =>
              (_firstText(element, 'status') ?? '').contains(' 200 '))
          .map((element) => element.descendants.whereType<XmlElement>().where(
                (child) => child.name.local == 'prop',
              ))
          .expand((elements) => elements)
          .firstOrNull;
      final properties = successfulProp ?? response;
      final isDirectory = properties.descendants
          .whereType<XmlElement>()
          .any((element) => element.name.local == 'collection');
      final displayName = _firstText(properties, 'displayname') ??
          _displayNameFromUri(responseUri);
      final contentLength = int.tryParse(
        _firstText(properties, 'getcontentlength') ?? '',
      );
      final lastModified = DateTime.tryParse(
        _firstText(properties, 'getlastmodified') ?? '',
      );

      entries.add(
        WebDavEntry(
          uri: responseUri,
          displayName: displayName,
          isDirectory: isDirectory,
          contentLength: contentLength,
          contentType: _firstText(properties, 'getcontenttype'),
          lastModified: lastModified,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return entries;
  }

  Future<List<WebDavEntry>> scanRecursively([Uri? directory]) async {
    final root = _asDirectoryUri(directory ?? account.rootUri);
    final pending = ListQueue<Uri>()..add(root);
    final visited = <String>{};
    final audioEntries = <WebDavEntry>[];
    // Windows can comfortably keep more WebDAV directory requests in flight;
    // retain the conservative value on mobile networks.
    final directoryConcurrency = kIsWindows ? 8 : 4;

    while (pending.isNotEmpty) {
      final batch = <Uri>[];
      while (pending.isNotEmpty && batch.length < directoryConcurrency) {
        final current = pending.removeFirst();
        final key = current.replace(query: null, fragment: null).toString();
        if (visited.add(key)) batch.add(current);
      }
      if (batch.isEmpty) continue;

      final listings = await Future.wait(batch.map(list));
      for (final entries in listings) {
        for (final entry in entries) {
          if (entry.isDirectory) {
            pending.add(_asDirectoryUri(entry.uri));
          } else if (entry.isSupportedAudio) {
            audioEntries.add(entry);
          }
        }
      }
    }

    audioEntries.sort(
      (a, b) => a.uri.toString().compareTo(b.uri.toString()),
    );
    return audioEntries;
  }

  Future<XmlDocument> _propfind(Uri uri, {required int depth}) async {
    try {
      final response = await _dio.request<String>(
        uri.toString(),
        data: _propfindBody,
        options: Options(
          method: 'PROPFIND',
          responseType: ResponseType.plain,
          headers: {
            ...account.authorizationHeaders,
            'Depth': '$depth',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          validateStatus: (_) => true,
          followRedirects: false,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw WebDavException(
          'WebDAV authentication failed.',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode != 207 &&
          (response.statusCode == null ||
              response.statusCode! < 200 ||
              response.statusCode! >= 300)) {
        throw WebDavException(
          'WebDAV server returned HTTP ${response.statusCode ?? 'unknown'}.',
          statusCode: response.statusCode,
        );
      }
      if (response.data == null || response.data!.trim().isEmpty) {
        throw const WebDavException(
            'WebDAV server returned an empty response.');
      }

      return XmlDocument.parse(response.data!);
    } on WebDavException {
      rethrow;
    } on DioException catch (error) {
      throw WebDavException(
        error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.sendTimeout
            ? 'WebDAV connection timed out.'
            : 'Unable to connect to the WebDAV server.',
        statusCode: error.response?.statusCode,
      );
    } on XmlParserException {
      throw const WebDavException('WebDAV server returned invalid XML.');
    }
  }

  void close() => _dio.close();

  static String? _firstText(XmlElement element, String localName) {
    return element.descendants
        .whereType<XmlElement>()
        .where((child) => child.name.local == localName)
        .map((child) => child.innerText.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
  }

  static Uri _resolveHref(Uri requestUri, String href) {
    final parsed = Uri.parse(href);
    return parsed.hasScheme ? parsed : requestUri.resolveUri(parsed);
  }

  static bool _sameResource(Uri a, Uri b) {
    String normalizePath(Uri uri) {
      final decoded = Uri.decodeComponent(uri.path);
      return decoded.length > 1 && decoded.endsWith('/')
          ? decoded.substring(0, decoded.length - 1)
          : decoded;
    }

    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        _effectivePort(a) == _effectivePort(b) &&
        normalizePath(a) == normalizePath(b);
  }

  bool _isWithinAccountRoot(Uri uri) {
    final root = account.rootUri;
    if (root.scheme.toLowerCase() != uri.scheme.toLowerCase() ||
        root.host.toLowerCase() != uri.host.toLowerCase() ||
        _effectivePort(root) != _effectivePort(uri)) {
      return false;
    }

    final rootSegments = root.pathSegments.where((part) => part.isNotEmpty);
    final entrySegments = uri.pathSegments.where((part) => part.isNotEmpty);
    final rootParts = rootSegments.toList(growable: false);
    final entryParts = entrySegments.toList(growable: false);
    if (entryParts.length < rootParts.length) return false;

    for (var index = 0; index < rootParts.length; index++) {
      if (rootParts[index] != entryParts[index]) return false;
    }
    return true;
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  static Uri _asDirectoryUri(Uri uri) {
    if (uri.path.endsWith('/')) return uri;
    return uri.replace(path: '${uri.path}/');
  }

  static String _displayNameFromUri(Uri uri) {
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    return segments.isEmpty ? uri.host : segments.last;
  }

  static const _propfindBody = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname />
    <d:resourcetype />
    <d:getcontentlength />
    <d:getcontenttype />
    <d:getlastmodified />
  </d:prop>
</d:propfind>''';
}
