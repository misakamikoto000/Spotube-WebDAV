import 'dart:math' as math;
import 'dart:typed_data';

import 'package:spotube/models/webdav/webdav_audio_quality.dart';

abstract final class WebDavAudioQualityParser {
  static WebDavAudioQuality? parse({
    required Uint8List header,
    required String extension,
    int? fileSize,
    Uint8List? tail,
  }) {
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    return switch (normalized) {
      'flac' => _parseFlac(header, fileSize),
      'wav' || 'wave' => _parseWave(header),
      'aif' || 'aiff' => _parseAiff(header),
      'dsf' => _parseDsf(header),
      'dff' => _parseDff(header),
      'wv' => _parseWavPack(header, fileSize),
      'ape' => _parseApe(header, fileSize),
      'mp3' => _parseMp3(header),
      'aac' => _parseAdts(header),
      'm4a' || 'mp4' || 'alac' => _parseMp4(
          header,
          tail: tail,
          fileSize: fileSize,
          extension: normalized,
        ),
      'ogg' || 'opus' => _parseOgg(
          header,
          tail: tail,
          fileSize: fileSize,
        ),
      _ => null,
    };
  }

  /// Returns the first MPEG frame offset declared by an ID3v2 header. The
  /// caller can issue a second tiny range request when embedded artwork makes
  /// the tag larger than the initial probe window.
  static int? id3AudioOffset(Uint8List bytes) {
    if (bytes.length < 10 || !_matchesAscii(bytes, 0, 'ID3')) return null;
    final size = ((bytes[6] & 0x7f) << 21) |
        ((bytes[7] & 0x7f) << 14) |
        ((bytes[8] & 0x7f) << 7) |
        (bytes[9] & 0x7f);
    final hasFooter = bytes[5] & 0x10 != 0;
    return 10 + size + (hasFooter ? 10 : 0);
  }

  static WebDavAudioQuality? _parseFlac(Uint8List bytes, int? fileSize) {
    final marker = _indexOfAscii(bytes, 'fLaC');
    if (marker < 0) return null;
    var offset = marker + 4;
    while (offset + 4 <= bytes.length) {
      final blockType = bytes[offset] & 0x7f;
      final blockLength = (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final data = offset + 4;
      if (data + blockLength > bytes.length) return null;
      if (blockType == 0 && blockLength >= 34) {
        final packed = data + 10;
        final sampleRate = (bytes[packed] << 12) |
            (bytes[packed + 1] << 4) |
            (bytes[packed + 2] >> 4);
        final channels = ((bytes[packed + 2] & 0x0e) >> 1) + 1;
        final bitDepth =
            (((bytes[packed + 2] & 0x01) << 4) | (bytes[packed + 3] >> 4)) + 1;
        final totalSamples = ((bytes[packed + 3] & 0x0f) << 32) |
            (bytes[packed + 4] << 24) |
            (bytes[packed + 5] << 16) |
            (bytes[packed + 6] << 8) |
            bytes[packed + 7];
        return WebDavAudioQuality(
          container: 'flac',
          codec: 'FLAC',
          lossless: true,
          bitDepth: bitDepth,
          sampleRate: sampleRate,
          channels: channels,
          bitrate: _averageBitrate(
            fileSize,
            sampleRate == 0 ? null : totalSamples / sampleRate,
          ),
        );
      }
      offset = data + blockLength;
      if (bytes[offset - blockLength - 4] & 0x80 != 0) break;
    }
    return null;
  }

  static WebDavAudioQuality? _parseWave(Uint8List bytes) {
    if (bytes.length < 12 ||
        !_matchesAscii(bytes, 0, 'RIFF') ||
        !_matchesAscii(bytes, 8, 'WAVE')) {
      return null;
    }
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final size = _u32le(bytes, offset + 4);
      final data = offset + 8;
      if (_matchesAscii(bytes, offset, 'fmt ') &&
          size >= 16 &&
          data + 16 <= bytes.length) {
        final formatCode = _u16le(bytes, data);
        final channels = _u16le(bytes, data + 2);
        final sampleRate = _u32le(bytes, data + 4);
        final byteRate = _u32le(bytes, data + 8);
        final bitDepth = _u16le(bytes, data + 14);
        return WebDavAudioQuality(
          container: 'wav',
          codec: switch (formatCode) {
            1 => 'PCM',
            3 => 'IEEE Float',
            0xfffe => 'WAVE Extensible',
            _ => 'WAVE',
          },
          lossless: true,
          bitDepth: bitDepth == 0 ? null : bitDepth,
          sampleRate: sampleRate == 0 ? null : sampleRate,
          channels: channels == 0 ? null : channels,
          bitrate: byteRate == 0 ? null : byteRate * 8,
        );
      }
      final next = data + size + (size.isOdd ? 1 : 0);
      if (next <= offset || next > bytes.length) break;
      offset = next;
    }
    return null;
  }

  static WebDavAudioQuality? _parseAiff(Uint8List bytes) {
    if (bytes.length < 12 ||
        !_matchesAscii(bytes, 0, 'FORM') ||
        !(_matchesAscii(bytes, 8, 'AIFF') || _matchesAscii(bytes, 8, 'AIFC'))) {
      return null;
    }
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final size = _u32be(bytes, offset + 4);
      final data = offset + 8;
      if (_matchesAscii(bytes, offset, 'COMM') &&
          size >= 18 &&
          data + 18 <= bytes.length) {
        final channels = _u16be(bytes, data);
        final bitDepth = _u16be(bytes, data + 6);
        final sampleRate = _extended80(bytes, data + 8).round();
        return WebDavAudioQuality(
          container: 'aiff',
          codec: _matchesAscii(bytes, 8, 'AIFC') ? 'AIFC' : 'PCM',
          lossless: true,
          bitDepth: bitDepth,
          sampleRate: sampleRate,
          channels: channels,
          bitrate: sampleRate * channels * bitDepth,
        );
      }
      final next = data + size + (size.isOdd ? 1 : 0);
      if (next <= offset || next > bytes.length) break;
      offset = next;
    }
    return null;
  }

  static WebDavAudioQuality? _parseDsf(Uint8List bytes) {
    if (bytes.length < 72 || !_matchesAscii(bytes, 0, 'DSD ')) return null;
    final fmt = _indexOfAscii(bytes, 'fmt ', start: 24);
    if (fmt < 0 || fmt + 44 > bytes.length) return null;
    final channels = _u32le(bytes, fmt + 24);
    final sampleRate = _u32le(bytes, fmt + 28);
    return WebDavAudioQuality(
      container: 'dsf',
      codec: 'DSD',
      lossless: true,
      bitDepth: 1,
      sampleRate: sampleRate,
      channels: channels,
      bitrate: sampleRate == 0 || channels == 0 ? null : sampleRate * channels,
    );
  }

  static WebDavAudioQuality? _parseDff(Uint8List bytes) {
    if (bytes.length < 20 ||
        !_matchesAscii(bytes, 0, 'FRM8') ||
        !_matchesAscii(bytes, 12, 'DSD ')) {
      return null;
    }
    final fs = _indexOfAscii(bytes, 'FS  ', start: 16);
    if (fs < 0 || fs + 16 > bytes.length) return null;
    final sampleRate = _u32be(bytes, fs + 12);
    final channelChunk = _indexOfAscii(bytes, 'CHNL', start: 16);
    final channels = channelChunk >= 0 && channelChunk + 14 <= bytes.length
        ? _u16be(bytes, channelChunk + 12)
        : null;
    return WebDavAudioQuality(
      container: 'dff',
      codec: 'DSD',
      lossless: true,
      bitDepth: 1,
      sampleRate: sampleRate,
      channels: channels,
      bitrate: channels == null ? null : sampleRate * channels,
    );
  }

  static WebDavAudioQuality? _parseWavPack(
    Uint8List bytes,
    int? fileSize,
  ) {
    final marker = _indexOfAscii(bytes, 'wvpk');
    if (marker < 0 || marker + 32 > bytes.length) return null;
    final totalSamples = _u32le(bytes, marker + 12);
    final flags = _u32le(bytes, marker + 24);
    const rates = [
      6000,
      8000,
      9600,
      11025,
      12000,
      16000,
      22050,
      24000,
      32000,
      44100,
      48000,
      64000,
      88200,
      96000,
      192000,
      0,
    ];
    final sampleRate = rates[(flags >> 23) & 0x0f];
    final storedBytes = (flags & 0x03) + 1;
    final shift = (flags >> 13) & 0x1f;
    final bitDepth = storedBytes * 8 - shift;
    final channels = flags & 0x04 != 0 ? 1 : 2;
    final duration = totalSamples == 0xffffffff || sampleRate == 0
        ? null
        : totalSamples / sampleRate;
    return WebDavAudioQuality(
      container: 'wv',
      codec: 'WavPack',
      lossless: true,
      bitDepth: bitDepth,
      sampleRate: sampleRate == 0 ? null : sampleRate,
      channels: channels,
      bitrate: _averageBitrate(fileSize, duration),
    );
  }

  static WebDavAudioQuality? _parseApe(Uint8List bytes, int? fileSize) {
    final marker = _indexOfAscii(bytes, 'MAC ');
    if (marker < 0 || marker + 52 > bytes.length) return null;
    final version = _u16le(bytes, marker + 4);
    if (version < 3980) return null;
    final descriptorBytes = _u32le(bytes, marker + 8);
    final header = marker + descriptorBytes;
    if (descriptorBytes < 52 || header + 24 > bytes.length) return null;
    final blocksPerFrame = _u32le(bytes, header + 4);
    final finalFrameBlocks = _u32le(bytes, header + 8);
    final totalFrames = _u32le(bytes, header + 12);
    final bitDepth = _u16le(bytes, header + 16);
    final channels = _u16le(bytes, header + 18);
    final sampleRate = _u32le(bytes, header + 20);
    final totalSamples = totalFrames == 0
        ? 0
        : (totalFrames - 1) * blocksPerFrame + finalFrameBlocks;
    return WebDavAudioQuality(
      container: 'ape',
      codec: "Monkey's Audio",
      lossless: true,
      bitDepth: bitDepth,
      sampleRate: sampleRate,
      channels: channels,
      bitrate: _averageBitrate(
        fileSize,
        sampleRate == 0 ? null : totalSamples / sampleRate,
      ),
    );
  }

  static WebDavAudioQuality? _parseMp3(Uint8List bytes) {
    final declaredOffset = id3AudioOffset(bytes);
    final start = declaredOffset != null && declaredOffset < bytes.length
        ? declaredOffset
        : 0;
    for (var offset = start; offset + 4 <= bytes.length; offset++) {
      final header = _u32be(bytes, offset);
      if (header & 0xffe00000 != 0xffe00000) continue;
      final version = (header >> 19) & 0x03;
      final layer = (header >> 17) & 0x03;
      final bitrateIndex = (header >> 12) & 0x0f;
      final sampleIndex = (header >> 10) & 0x03;
      if (version == 1 ||
          layer == 0 ||
          bitrateIndex == 0 ||
          bitrateIndex == 15 ||
          sampleIndex == 3) {
        continue;
      }
      final bitrate = _mpegBitrate(version, layer, bitrateIndex);
      final baseRate = const [44100, 48000, 32000][sampleIndex];
      final sampleRate = switch (version) {
        3 => baseRate,
        2 => baseRate ~/ 2,
        _ => baseRate ~/ 4,
      };
      final channelMode = (header >> 6) & 0x03;
      return WebDavAudioQuality(
        container: 'mp3',
        codec: 'MP3',
        lossless: false,
        sampleRate: sampleRate,
        bitrate: bitrate * 1000,
        channels: channelMode == 3 ? 1 : 2,
      );
    }
    return null;
  }

  static WebDavAudioQuality? _parseAdts(Uint8List bytes) {
    const sampleRates = [
      96000,
      88200,
      64000,
      48000,
      44100,
      32000,
      24000,
      22050,
      16000,
      12000,
      11025,
      8000,
      7350,
    ];
    for (var offset = 0; offset + 7 <= bytes.length; offset++) {
      if (bytes[offset] != 0xff || bytes[offset + 1] & 0xf6 != 0xf0) continue;
      final sampleIndex = (bytes[offset + 2] >> 2) & 0x0f;
      if (sampleIndex >= sampleRates.length) continue;
      final sampleRate = sampleRates[sampleIndex];
      final channels =
          ((bytes[offset + 2] & 0x01) << 2) | ((bytes[offset + 3] >> 6) & 0x03);
      final frameLength = ((bytes[offset + 3] & 0x03) << 11) |
          (bytes[offset + 4] << 3) |
          (bytes[offset + 5] >> 5);
      final bitrate = frameLength <= 7
          ? null
          : (frameLength * 8 * sampleRate / 1024).round();
      return WebDavAudioQuality(
        container: 'aac',
        codec: 'AAC',
        lossless: false,
        sampleRate: sampleRate,
        bitrate: bitrate,
        channels: channels == 0 ? null : channels,
      );
    }
    return null;
  }

  static WebDavAudioQuality? _parseMp4(
    Uint8List header, {
    required Uint8List? tail,
    required int? fileSize,
    required String extension,
  }) {
    for (final bytes in [header, if (tail != null) tail]) {
      var type = 'alac';
      var sampleEntry = _indexOfAscii(bytes, type);
      if (sampleEntry < 0) {
        type = 'mp4a';
        sampleEntry = _indexOfAscii(bytes, type);
      }
      if (sampleEntry < 4 || sampleEntry + 32 > bytes.length) continue;
      var channels = _u16be(bytes, sampleEntry + 20);
      var bitDepth = _u16be(bytes, sampleEntry + 22);
      var sampleRate = _u32be(bytes, sampleEntry + 28) >> 16;
      int? declaredBitrate;
      if (type == 'alac') {
        final config = _indexOfAscii(
          bytes,
          'alac',
          start: sampleEntry + 4,
        );
        if (config >= 0 && config + 32 <= bytes.length) {
          bitDepth = bytes[config + 13];
          channels = bytes[config + 17];
          declaredBitrate = _u32be(bytes, config + 24);
          sampleRate = _u32be(bytes, config + 28);
        }
      }
      final duration = _mp4Duration(bytes) ??
          (tail == null || identical(bytes, tail) ? null : _mp4Duration(tail));
      final lossless = type == 'alac' || extension == 'alac';
      return WebDavAudioQuality(
        container: extension == 'alac' ? 'm4a' : extension,
        codec: lossless ? 'ALAC' : 'AAC',
        lossless: lossless,
        bitDepth: lossless && bitDepth > 0 ? bitDepth : null,
        sampleRate: sampleRate == 0 ? null : sampleRate,
        channels: channels == 0 ? null : channels,
        bitrate: declaredBitrate == null || declaredBitrate == 0
            ? _averageBitrate(fileSize, duration)
            : declaredBitrate,
      );
    }
    return null;
  }

  static WebDavAudioQuality? _parseOgg(
    Uint8List header, {
    required Uint8List? tail,
    required int? fileSize,
  }) {
    final opus = _indexOfAscii(header, 'OpusHead');
    int? sampleRate;
    int? channels;
    int? nominalBitrate;
    String codec;
    if (opus >= 0 && opus + 19 <= header.length) {
      codec = 'Opus';
      channels = header[opus + 9];
      sampleRate = 48000;
    } else {
      final vorbis = _indexOfAscii(header, '\u0001vorbis');
      if (vorbis < 0 || vorbis + 24 > header.length) return null;
      codec = 'Vorbis';
      channels = header[vorbis + 11];
      sampleRate = _u32le(header, vorbis + 12);
      final rawNominal = _u32le(header, vorbis + 20);
      nominalBitrate = rawNominal == 0xffffffff ? null : rawNominal;
    }
    final granule = tail == null ? null : _lastOggGranule(tail);
    final duration =
        granule == null || sampleRate == 0 ? null : granule / sampleRate;
    return WebDavAudioQuality(
      container: 'ogg',
      codec: codec,
      lossless: false,
      sampleRate: sampleRate,
      channels: channels,
      bitrate: nominalBitrate ?? _averageBitrate(fileSize, duration),
    );
  }

  static double? _mp4Duration(Uint8List bytes) {
    final mdhd = _indexOfAscii(bytes, 'mdhd');
    if (mdhd < 4 || mdhd + 32 > bytes.length) return null;
    final version = bytes[mdhd + 4];
    if (version == 1) {
      if (mdhd + 36 > bytes.length) return null;
      final timescale = _u32be(bytes, mdhd + 24);
      final duration = _u64be(bytes, mdhd + 28);
      return timescale == 0 ? null : duration / timescale;
    }
    final timescale = _u32be(bytes, mdhd + 16);
    final duration = _u32be(bytes, mdhd + 20);
    return timescale == 0 ? null : duration / timescale;
  }

  static int? _lastOggGranule(Uint8List bytes) {
    for (var offset = bytes.length - 27; offset >= 0; offset--) {
      if (_matchesAscii(bytes, offset, 'OggS')) {
        return _u64le(bytes, offset + 6);
      }
    }
    return null;
  }

  static int _mpegBitrate(int version, int layer, int index) {
    const mpeg1Layer1 = [
      0,
      32,
      64,
      96,
      128,
      160,
      192,
      224,
      256,
      288,
      320,
      352,
      384,
      416,
      448,
      0,
    ];
    const mpeg1Layer2 = [
      0,
      32,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320,
      384,
      0,
    ];
    const mpeg1Layer3 = [
      0,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320,
      0,
    ];
    const mpeg2Layer1 = [
      0,
      32,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
      176,
      192,
      224,
      256,
      0,
    ];
    const mpeg2Other = [
      0,
      8,
      16,
      24,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
      0,
    ];
    if (version == 3) {
      return switch (layer) {
        3 => mpeg1Layer1[index],
        2 => mpeg1Layer2[index],
        _ => mpeg1Layer3[index],
      };
    }
    return layer == 3 ? mpeg2Layer1[index] : mpeg2Other[index];
  }

  static int? _averageBitrate(int? fileSize, double? seconds) {
    if (fileSize == null || seconds == null || seconds <= 0) return null;
    return (fileSize * 8 / seconds).round();
  }

  static double _extended80(Uint8List bytes, int offset) {
    if (offset + 10 > bytes.length) return 0;
    final signAndExponent = _u16be(bytes, offset);
    final sign = signAndExponent & 0x8000 == 0 ? 1 : -1;
    final exponent = signAndExponent & 0x7fff;
    final mantissa = _u64be(bytes, offset + 2);
    if (exponent == 0 && mantissa == 0) return 0;
    return sign *
        (mantissa / 0x8000000000000000) *
        math.pow(2, exponent - 16383).toDouble();
  }

  static int _indexOfAscii(
    Uint8List bytes,
    String value, {
    int start = 0,
  }) {
    final signature = value.codeUnits;
    for (var offset = start;
        offset <= bytes.length - signature.length;
        offset++) {
      var matches = true;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[offset + index] != signature[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return offset;
    }
    return -1;
  }

  static bool _matchesAscii(Uint8List bytes, int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (bytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  static int _u16le(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _u16be(Uint8List bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static int _u32le(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static int _u32be(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static int _u64le(Uint8List bytes, int offset) {
    var value = 0;
    for (var index = 7; index >= 0; index--) {
      value = (value << 8) | bytes[offset + index];
    }
    return value;
  }

  static int _u64be(Uint8List bytes, int offset) {
    var value = 0;
    for (var index = 0; index < 8; index++) {
      value = (value << 8) | bytes[offset + index];
    }
    return value;
  }
}
