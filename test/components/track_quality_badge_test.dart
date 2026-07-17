import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/components/track_quality/track_quality_badge.dart';
import 'package:spotube/models/webdav/webdav_audio_quality.dart';

void main() {
  group('TrackQualityInfo.fromLocalPath', () {
    test('classifies a regular FLAC file as lossless', () {
      final quality = TrackQualityInfo.fromLocalPath(
        'https://music.example/dav/Album/Track.flac',
      );

      expect(quality.level, TrackQualityLevel.lossless);
      expect(quality.format, 'flac');
    });

    test('recognizes Hi-Res resolution markers in WebDAV paths', () {
      final quality = TrackQualityInfo.fromLocalPath(
        'https://music.example/dav/Hi-Res/Track%20%5B24bit-96kHz%5D.flac',
      );

      expect(quality.level, TrackQualityLevel.hiRes);
      expect(quality.bitDepth, 24);
      expect(quality.sampleRate, 96000);
    });

    test('recognizes Chinese master and lossless folder names', () {
      final master = TrackQualityInfo.fromLocalPath(
        'https://music.example/dav/%E6%AF%8D%E5%B8%A6/Track.m4a',
      );
      final lossless = TrackQualityInfo.fromLocalPath(
        'https://music.example/dav/%E6%97%A0%E6%8D%9F/Track.m4a',
      );

      expect(master.level, TrackQualityLevel.hiRes);
      expect(lossless.level, TrackQualityLevel.lossless);
    });

    test('distinguishes high bitrate and standard lossy files', () {
      final high = TrackQualityInfo.fromLocalPath(
        r'D:\Music\Artist - Track 320kbps.mp3',
      );
      final standard = TrackQualityInfo.fromLocalPath(
        r'D:\Music\Artist - Track.mp3',
      );

      expect(high.level, TrackQualityLevel.high);
      expect(standard.level, TrackQualityLevel.standard);
    });
  });

  group('TrackQualityInfo.fromDetectedQuality', () {
    test('uses real bit depth and sample rate for lossless files', () {
      final hiRes = TrackQualityInfo.fromDetectedQuality(
        const WebDavAudioQuality(
          container: 'flac',
          codec: 'FLAC',
          lossless: true,
          bitDepth: 24,
          sampleRate: 48000,
        ),
      );
      final cd = TrackQualityInfo.fromDetectedQuality(
        const WebDavAudioQuality(
          container: 'flac',
          codec: 'FLAC',
          lossless: true,
          bitDepth: 16,
          sampleRate: 44100,
        ),
      );

      expect(hiRes.level, TrackQualityLevel.hiRes);
      expect(cd.level, TrackQualityLevel.lossless);
    });

    test('uses actual lossy bitrate for HQ', () {
      final quality = TrackQualityInfo.fromDetectedQuality(
        const WebDavAudioQuality(
          container: 'mp3',
          codec: 'MP3',
          lossless: false,
          bitrate: 320000,
          sampleRate: 44100,
        ),
      );

      expect(quality.level, TrackQualityLevel.high);
      expect(quality.technicalDetails, contains('320 kbps'));
    });
  });
}
