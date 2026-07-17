import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:spotube/models/webdav/webdav_account.dart';
import 'package:spotube/models/webdav/webdav_audio_quality.dart';
import 'package:spotube/models/webdav/webdav_entry.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_parser.dart';
import 'package:spotube/services/webdav/webdav_stream_proxy.dart';

class WebDavAudioQualityProbe {
  static const headerWindow = 128 * 1024;
  static const tailWindow = 256 * 1024;

  final WebDavAccount account;
  final WebDavStreamProxy _proxy;

  WebDavAudioQualityProbe(
    this.account, {
    WebDavStreamProxy? proxy,
  }) : _proxy = proxy ?? WebDavStreamProxy();

  Future<WebDavAudioQuality?> probe(WebDavEntry entry) async {
    final extension = path.extension(entry.displayName).toLowerCase();
    final header = await _readRange(
      entry.uri,
      start: 0,
      length: headerWindow,
    );
    if (header == null || header.isEmpty) return null;

    Uint8List effectiveHeader = header;
    final audioOffset = WebDavAudioQualityParser.id3AudioOffset(header);
    if (audioOffset != null && audioOffset >= header.length) {
      effectiveHeader = await _readRange(
            entry.uri,
            start: audioOffset,
            length: 16 * 1024,
          ) ??
          header;
    }

    Uint8List? tail;
    final needsTail =
        const {'.m4a', '.mp4', '.alac', '.ogg', '.opus'}.contains(extension);
    final fileSize = entry.contentLength;
    if (needsTail && fileSize != null && fileSize > headerWindow) {
      final start = fileSize > tailWindow ? fileSize - tailWindow : 0;
      tail = await _readRange(
        entry.uri,
        start: start,
        length: fileSize - start,
      );
    }

    return WebDavAudioQualityParser.parse(
      header: effectiveHeader,
      extension: extension,
      fileSize: fileSize,
      tail: tail,
    );
  }

  Future<Uint8List?> _readRange(
    Uri uri, {
    required int start,
    required int length,
  }) async {
    if (length <= 0) return Uint8List(0);
    final response = await _proxy.open(
      account: account,
      remoteUri: uri,
      method: 'GET',
      range: 'bytes=$start-${start + length - 1}',
    );
    final body = response.body;
    if ((response.statusCode != 200 && response.statusCode != 206) ||
        body == null) {
      await body?.drain<void>();
      return null;
    }

    final builder = BytesBuilder(copy: false);
    var remaining = length;
    await for (final chunk in body) {
      if (remaining <= 0) break;
      if (chunk.length <= remaining) {
        builder.add(chunk);
        remaining -= chunk.length;
      } else {
        builder.add(chunk.sublist(0, remaining));
        remaining = 0;
        break;
      }
    }
    return builder.takeBytes();
  }

  void close() => _proxy.close();
}
