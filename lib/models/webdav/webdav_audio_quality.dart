import 'package:spotube/models/webdav/webdav_entry.dart';

class WebDavAudioQuality {
  final String container;
  final String codec;
  final bool lossless;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final int? channels;

  const WebDavAudioQuality({
    required this.container,
    required this.codec,
    required this.lossless,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.channels,
  });

  factory WebDavAudioQuality.fromJson(Map<String, dynamic> json) =>
      WebDavAudioQuality(
        container: json['container'] as String? ?? '',
        codec: json['codec'] as String? ?? '',
        lossless: json['lossless'] as bool? ?? false,
        bitDepth: (json['bitDepth'] as num?)?.toInt(),
        sampleRate: (json['sampleRate'] as num?)?.toInt(),
        bitrate: (json['bitrate'] as num?)?.toInt(),
        channels: (json['channels'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'container': container,
        'codec': codec,
        'lossless': lossless,
        if (bitDepth != null) 'bitDepth': bitDepth,
        if (sampleRate != null) 'sampleRate': sampleRate,
        if (bitrate != null) 'bitrate': bitrate,
        if (channels != null) 'channels': channels,
      };
}

class WebDavAudioQualityCacheEntry {
  final String accountId;
  final String path;
  final int? contentLength;
  final int? lastModifiedMs;
  final DateTime probedAt;
  final WebDavAudioQuality? quality;

  const WebDavAudioQualityCacheEntry({
    required this.accountId,
    required this.path,
    required this.probedAt,
    this.contentLength,
    this.lastModifiedMs,
    this.quality,
  });

  factory WebDavAudioQualityCacheEntry.fromJson(Map<String, dynamic> json) {
    final quality = json['quality'];
    return WebDavAudioQualityCacheEntry(
      accountId: json['accountId'] as String? ?? '',
      path: json['path'] as String? ?? '',
      contentLength: (json['contentLength'] as num?)?.toInt(),
      lastModifiedMs: (json['lastModifiedMs'] as num?)?.toInt(),
      probedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['probedAtMs'] as num?)?.toInt() ?? 0,
      ),
      quality: quality is Map
          ? WebDavAudioQuality.fromJson(
              quality.cast<String, dynamic>(),
            )
          : null,
    );
  }

  factory WebDavAudioQualityCacheEntry.fromProbe({
    required String accountId,
    required WebDavEntry entry,
    required WebDavAudioQuality? quality,
  }) =>
      WebDavAudioQualityCacheEntry(
        accountId: accountId,
        path: entry.uri.toString(),
        contentLength: entry.contentLength,
        lastModifiedMs: entry.lastModified?.millisecondsSinceEpoch,
        probedAt: DateTime.now(),
        quality: quality,
      );

  bool matches(WebDavEntry entry) {
    if (path != entry.uri.toString()) return false;
    if (contentLength != null &&
        entry.contentLength != null &&
        contentLength != entry.contentLength) {
      return false;
    }
    final modified = entry.lastModified?.millisecondsSinceEpoch;
    if (lastModifiedMs != null &&
        modified != null &&
        lastModifiedMs != modified) {
      return false;
    }
    // Retry failed/unsupported probes periodically so a transient WebDAV
    // download error does not become a permanent SQ/LOSSLESS fallback.
    if (quality == null &&
        DateTime.now().difference(probedAt) > const Duration(days: 7)) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'path': path,
        if (contentLength != null) 'contentLength': contentLength,
        if (lastModifiedMs != null) 'lastModifiedMs': lastModifiedMs,
        'probedAtMs': probedAt.millisecondsSinceEpoch,
        if (quality != null) 'quality': quality!.toJson(),
      };
}
