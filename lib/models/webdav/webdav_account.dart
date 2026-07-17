import 'dart:convert';

import 'package:spotube/models/database/database.dart';

class WebDavAccount {
  final String id;
  final String name;
  final String url;
  final String rootPath;
  final String username;
  final String password;

  const WebDavAccount({
    required this.id,
    required this.name,
    required this.url,
    this.rootPath = '',
    required this.username,
    required this.password,
  });

  Uri get endpointUri => normalizeUri(url);

  Uri get rootUri => resolveRoot(endpointUri);

  String get rootDisplayPath {
    final normalizedPath = normalizeRootPath(rootPath);
    return normalizedPath.isEmpty ? '/' : '/$normalizedPath/';
  }

  Map<String, String> get authorizationHeaders {
    if (username.isEmpty && password.isEmpty) return const {};

    final credentials = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $credentials'};
  }

  static Uri normalizeUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('A valid HTTP(S) WebDAV URL is required.');
    }

    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path, fragment: null);
  }

  static String normalizeRootPath(String value) {
    final segments = value
        .trim()
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.any((segment) => segment == '.' || segment == '..')) {
      throw const FormatException('The WebDAV folder path is invalid.');
    }
    return segments.join('/');
  }

  Uri resolveRoot(Uri endpoint) {
    final normalizedPath = normalizeRootPath(rootPath);
    if (normalizedPath.isEmpty) return normalizeUri(endpoint.toString());

    final relativeFolder = Uri(
      pathSegments: [...normalizedPath.split('/'), ''],
    );
    return endpoint.resolveUri(relativeFolder);
  }

  String rootPathFor(Uri directory) {
    final endpoint = endpointUri;
    if (endpoint.scheme.toLowerCase() != directory.scheme.toLowerCase() ||
        endpoint.host.toLowerCase() != directory.host.toLowerCase() ||
        _effectivePort(endpoint) != _effectivePort(directory)) {
      throw const FormatException(
        'The selected folder is outside the WebDAV endpoint.',
      );
    }

    final endpointParts = endpoint.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final directoryParts = directory.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (directoryParts.length < endpointParts.length) {
      throw const FormatException(
        'The selected folder is outside the WebDAV endpoint.',
      );
    }
    for (var index = 0; index < endpointParts.length; index++) {
      if (endpointParts[index] != directoryParts[index]) {
        throw const FormatException(
          'The selected folder is outside the WebDAV endpoint.',
        );
      }
    }

    return normalizeRootPath(
      directoryParts.skip(endpointParts.length).join('/'),
    );
  }

  bool contains(Uri uri) {
    final root = rootUri;
    if (root.scheme.toLowerCase() != uri.scheme.toLowerCase() ||
        root.host.toLowerCase() != uri.host.toLowerCase() ||
        _effectivePort(root) != _effectivePort(uri) ||
        uri.userInfo.isNotEmpty) {
      return false;
    }

    final rootParts = root.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final uriParts = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (uriParts.length < rootParts.length) return false;
    for (var index = 0; index < rootParts.length; index++) {
      if (rootParts[index] != uriParts[index]) return false;
    }
    return true;
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  WebDavAccount copyWith({
    String? id,
    String? name,
    String? url,
    String? rootPath,
    String? username,
    String? password,
  }) {
    return WebDavAccount(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      rootPath: rootPath ?? this.rootPath,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toStorageJson() {
    return {
      'id': id,
      'name': name,
      'url': endpointUri.toString(),
      'rootPath': normalizeRootPath(rootPath),
      'username': username,
      'password': DecryptedText(password).encrypt(),
    };
  }

  factory WebDavAccount.fromStorageJson(Map<String, dynamic> json) {
    return WebDavAccount(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      rootPath: json['rootPath'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: DecryptedText.decrypted(json['password'] as String).value,
    );
  }
}
