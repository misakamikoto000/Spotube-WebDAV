import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/webdav/webdav_audio_quality.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/server/active_track_sources.dart';
import 'package:spotube/provider/webdav/webdav_audio_quality_provider.dart';

enum TrackQualityLevel { standard, high, lossless, hiRes }

/// A lightweight audio-quality description that can be produced without
/// opening or downloading the audio file.
class TrackQualityInfo {
  final TrackQualityLevel level;
  final String format;
  final int? bitDepth;
  final double? sampleRate;
  final double? bitrate;

  const TrackQualityInfo({
    required this.level,
    this.format = '',
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
  });

  String get label => switch (level) {
        TrackQualityLevel.standard => 'SQ',
        TrackQualityLevel.high => 'HQ',
        TrackQualityLevel.lossless => 'LOSSLESS',
        TrackQualityLevel.hiRes => 'HI-RES',
      };

  String get description => switch (level) {
        TrackQualityLevel.standard => '标准音质',
        TrackQualityLevel.high => '高品质音频',
        TrackQualityLevel.lossless => '无损音质',
        TrackQualityLevel.hiRes => '高解析无损音频',
      };

  String get technicalDetails {
    final values = <String>[
      if (format.isNotEmpty) format.toUpperCase(),
      if (bitDepth != null) '$bitDepth-bit',
      if (sampleRate != null) '${_formatNumber(sampleRate! / 1000)} kHz',
      if (bitrate != null) '${_formatNumber(bitrate! / 1000)} kbps',
    ];
    return values.join(' · ');
  }

  String get tooltip => technicalDetails.isEmpty
      ? description
      : '$description · $technicalDetails';

  static TrackQualityInfo fromTrack(
    SpotubeTrackObject track, {
    SpotubeAudioSourceStreamObject? stream,
    SpotubeAudioSourceContainerPreset? preset,
    Object? quality,
    WebDavAudioQuality? detectedQuality,
  }) {
    if (stream != null) return fromStream(stream);
    if (detectedQuality != null) return fromDetectedQuality(detectedQuality);
    if (track case SpotubeLocalTrackObject(:final path)) {
      return fromLocalPath(path);
    }
    if (preset != null) return fromPreset(preset, quality);
    return const TrackQualityInfo(level: TrackQualityLevel.standard);
  }

  static TrackQualityInfo fromDetectedQuality(WebDavAudioQuality quality) {
    final isHiRes = quality.lossless &&
        ((quality.bitDepth ?? 0) >= 24 || (quality.sampleRate ?? 0) >= 88200);
    return TrackQualityInfo(
      level: isHiRes
          ? TrackQualityLevel.hiRes
          : quality.lossless
              ? TrackQualityLevel.lossless
              : (quality.bitrate ?? 0) >= 256000
                  ? TrackQualityLevel.high
                  : TrackQualityLevel.standard,
      format: quality.codec.isEmpty ? quality.container : quality.codec,
      bitDepth: quality.bitDepth,
      sampleRate: quality.sampleRate?.toDouble(),
      bitrate: quality.bitrate?.toDouble(),
    );
  }

  static TrackQualityInfo fromStream(SpotubeAudioSourceStreamObject stream) {
    final isHiRes = stream.type == SpotubeMediaCompressionType.lossless &&
        ((stream.bitDepth ?? 0) >= 24 || (stream.sampleRate ?? 0) >= 88200);
    final level = isHiRes
        ? TrackQualityLevel.hiRes
        : stream.type == SpotubeMediaCompressionType.lossless
            ? TrackQualityLevel.lossless
            : (stream.bitrate ?? 0) >= 256000
                ? TrackQualityLevel.high
                : TrackQualityLevel.standard;
    return TrackQualityInfo(
      level: level,
      format: stream.container,
      bitDepth: stream.bitDepth,
      sampleRate: stream.sampleRate,
      bitrate: stream.type == SpotubeMediaCompressionType.lossy
          ? stream.bitrate
          : null,
    );
  }

  static TrackQualityInfo fromPreset(
    SpotubeAudioSourceContainerPreset preset,
    Object? quality,
  ) {
    if (quality case SpotubeAudioLosslessContainerQuality()) {
      return TrackQualityInfo(
        level: quality.bitDepth >= 24 || quality.sampleRate >= 88200
            ? TrackQualityLevel.hiRes
            : TrackQualityLevel.lossless,
        format: preset.name,
        bitDepth: quality.bitDepth,
        sampleRate: quality.sampleRate.toDouble(),
      );
    }
    if (quality case SpotubeAudioLossyContainerQuality()) {
      return TrackQualityInfo(
        level: quality.bitrate >= 256000
            ? TrackQualityLevel.high
            : TrackQualityLevel.standard,
        format: preset.name,
        bitrate: quality.bitrate.toDouble(),
      );
    }
    return TrackQualityInfo(
      level: preset.type == SpotubeMediaCompressionType.lossless
          ? TrackQualityLevel.lossless
          : TrackQualityLevel.standard,
      format: preset.name,
    );
  }

  static TrackQualityInfo fromLocalPath(String rawPath) {
    String decodedPath;
    try {
      decodedPath = Uri.decodeFull(rawPath);
    } catch (_) {
      decodedPath = rawPath;
    }
    final source = decodedPath.toLowerCase();
    final uri = Uri.tryParse(decodedPath);
    final extension = path
        .extension(uri != null && uri.path.isNotEmpty ? uri.path : decodedPath)
        .replaceFirst('.', '')
        .toLowerCase();

    final bitDepth = _firstInt(
      RegExp(r'(?:^|[^\d])(16|20|24|32)[\s._-]*(?:bit|位)').firstMatch(source),
    );
    final sampleRate = _firstDouble(
      RegExp(
        r'\b(44\.1|48|88\.2|96|176\.4|192|352\.8|384)[\s._-]*khz\b',
      ).firstMatch(source),
    );
    final bitrateKbps = _firstDouble(
      RegExp(r'\b(128|192|256|320)[\s._-]*k(?:bps)?\b').firstMatch(source),
    );
    final explicitlyHiRes = RegExp(
      r'hi[\s._-]?res|high[\s._-]?resolution|高解析|高分辨率|母带|\bdsd(?:64|128|256|512)?\b|\bdxd\b',
    ).hasMatch(source);
    const hiResFormats = {'dsf', 'dff'};
    const losslessFormats = {
      'flac',
      'alac',
      'ape',
      'wav',
      'wave',
      'aif',
      'aiff',
      'wv',
      ...hiResFormats,
    };
    final explicitlyLossless = source.contains('lossless') ||
        source.contains('无损') ||
        source.contains('alac') ||
        source.contains('wavpack');

    final level = explicitlyHiRes ||
            hiResFormats.contains(extension) ||
            (bitDepth ?? 0) >= 24 ||
            (sampleRate ?? 0) >= 88.2
        ? TrackQualityLevel.hiRes
        : losslessFormats.contains(extension) || explicitlyLossless
            ? TrackQualityLevel.lossless
            : (bitrateKbps ?? 0) >= 256
                ? TrackQualityLevel.high
                : TrackQualityLevel.standard;

    return TrackQualityInfo(
      level: level,
      format: extension,
      bitDepth: bitDepth,
      sampleRate: sampleRate == null ? null : sampleRate * 1000,
      bitrate: bitrateKbps == null ? null : bitrateKbps * 1000,
    );
  }

  static int? _firstInt(RegExpMatch? match) =>
      match == null ? null : int.tryParse(match.group(1) ?? '');

  static double? _firstDouble(RegExpMatch? match) =>
      match == null ? null : double.tryParse(match.group(1) ?? '');

  static String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

class TrackQualityBadgeForTrack extends ConsumerWidget {
  final SpotubeTrackObject track;
  final SpotubeAudioSourceStreamObject? stream;
  final bool compact;

  const TrackQualityBadgeForTrack({
    super.key,
    required this.track,
    this.stream,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SpotubeAudioSourceContainerPreset? preset;
    Object? quality;
    WebDavAudioQuality? detectedQuality;
    if (track
        case SpotubeLocalTrackObject(
          :final path,
          :final webDavAccountId,
        )) {
      if (webDavAccountId != null) {
        detectedQuality = ref.watch(
          webDavAudioQualityProvider.select((qualities) => qualities[path]),
        );
      }
    }
    if (track is! SpotubeLocalTrackObject && stream == null) {
      final presets = ref.watch(audioSourcePresetsProvider);
      final presetIndex = presets.selectedStreamingContainerIndex;
      if (presetIndex >= 0 && presetIndex < presets.presets.length) {
        preset = presets.presets[presetIndex];
        final qualityIndex = presets.selectedStreamingQualityIndex;
        if (qualityIndex >= 0 && qualityIndex < preset.qualities.length) {
          quality = preset.qualities[qualityIndex];
        }
      }
    }
    return TrackQualityBadge(
      info: TrackQualityInfo.fromTrack(
        track,
        stream: stream,
        preset: preset,
        quality: quality,
        detectedQuality: detectedQuality,
      ),
      compact: compact,
    );
  }
}

/// Uses the actual selected stream when it is already available for playback.
class ActiveTrackQualityBadge extends ConsumerWidget {
  final SpotubeTrackObject track;
  final bool compact;

  const ActiveTrackQualityBadge({
    super.key,
    required this.track,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SpotubeAudioSourceStreamObject? stream;
    if (track is! SpotubeLocalTrackObject) {
      final activeSources = ref.watch(activeTrackSourcesProvider).asData?.value;
      final source = activeSources?.source;
      if (source != null) {
        final presets = ref.watch(audioSourcePresetsProvider);
        final presetIndex = presets.selectedStreamingContainerIndex;
        if (presetIndex >= 0 && presetIndex < presets.presets.length) {
          final preset = presets.presets[presetIndex];
          final qualityIndex = presets.selectedStreamingQualityIndex;
          if (qualityIndex >= 0 && qualityIndex < preset.qualities.length) {
            stream = source.getStreamOfQuality(preset, qualityIndex);
          }
        }
      }
    }
    return TrackQualityBadgeForTrack(
      track: track,
      stream: stream,
      compact: compact,
    );
  }
}

class TrackQualityBadge extends StatelessWidget {
  final TrackQualityInfo info;
  final bool compact;

  const TrackQualityBadge({
    super.key,
    required this.info,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = switch (info.level) {
      TrackQualityLevel.standard => (
          const Color(0xFFA7AFC0),
          const Color(0xFF727B91)
        ),
      TrackQualityLevel.high => (
          const Color(0xFF76B7FF),
          const Color(0xFF8A78FF)
        ),
      TrackQualityLevel.lossless => (
          const Color(0xFF5EF2D3),
          const Color(0xFF35B8FF)
        ),
      TrackQualityLevel.hiRes => (
          const Color(0xFFFFDE7A),
          const Color(0xFFFF75D1)
        ),
    };
    final height = compact ? 20.0 : 24.0;

    return Tooltip(
      tooltip: TooltipContainer(child: Text(info.tooltip)).call,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [palette.$1.withAlpha(42), palette.$2.withAlpha(24)],
          ),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: palette.$1.withAlpha(135)),
          boxShadow: info.level == TrackQualityLevel.hiRes
              ? [
                  BoxShadow(
                    color: palette.$2.withAlpha(30),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _QualityWaveGlyph(
              color: palette.$1,
              hiRes: info.level == TrackQualityLevel.hiRes,
            ),
            const SizedBox(width: 4),
            Text(
              info.label,
              style: TextStyle(
                color: Color.lerp(palette.$1, const Color(0xFFFFFFFF), 0.2),
                fontSize: compact ? 9 : 10,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: info.label.length > 4 ? 0.45 : 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityWaveGlyph extends StatelessWidget {
  final Color color;
  final bool hiRes;

  const _QualityWaveGlyph({required this.color, required this.hiRes});

  @override
  Widget build(BuildContext context) {
    final heights =
        hiRes ? const [4.0, 10.0, 7.0, 11.0] : const [4.0, 8.0, 6.0];
    return SizedBox(
      width: hiRes ? 13 : 10,
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final barHeight in heights)
            Container(
              width: 2,
              height: barHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
