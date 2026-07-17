import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_parser.dart';

void main() {
  test('reads 24-bit 96 kHz FLAC STREAMINFO without audio data', () {
    final quality = WebDavAudioQualityParser.parse(
      header: _flacHeader(
        sampleRate: 96000,
        bitDepth: 24,
        channels: 2,
        seconds: 180,
      ),
      extension: '.flac',
      fileSize: 100000000,
    );

    expect(quality, isNotNull);
    expect(quality!.lossless, isTrue);
    expect(quality.codec, 'FLAC');
    expect(quality.bitDepth, 24);
    expect(quality.sampleRate, 96000);
    expect(quality.channels, 2);
    expect(quality.bitrate, closeTo(4444444, 2));
  });

  test('keeps CD-quality FLAC at 16-bit 44.1 kHz', () {
    final quality = WebDavAudioQualityParser.parse(
      header: _flacHeader(
        sampleRate: 44100,
        bitDepth: 16,
        channels: 2,
        seconds: 200,
      ),
      extension: 'flac',
      fileSize: 30000000,
    );

    expect(quality!.bitDepth, 16);
    expect(quality.sampleRate, 44100);
  });

  test('reads PCM WAVE bit depth, sample rate and exact bitrate', () {
    final bytes = Uint8List(44);
    _ascii(bytes, 0, 'RIFF');
    _u32le(bytes, 4, 36);
    _ascii(bytes, 8, 'WAVE');
    _ascii(bytes, 12, 'fmt ');
    _u32le(bytes, 16, 16);
    _u16le(bytes, 20, 1);
    _u16le(bytes, 22, 2);
    _u32le(bytes, 24, 96000);
    _u32le(bytes, 28, 576000);
    _u16le(bytes, 32, 6);
    _u16le(bytes, 34, 24);

    final quality = WebDavAudioQualityParser.parse(
      header: bytes,
      extension: 'wav',
    );

    expect(quality!.codec, 'PCM');
    expect(quality.bitDepth, 24);
    expect(quality.sampleRate, 96000);
    expect(quality.bitrate, 4608000);
  });

  test('reads DSF as one-bit high sample-rate DSD', () {
    final bytes = Uint8List(80);
    _ascii(bytes, 0, 'DSD ');
    _ascii(bytes, 28, 'fmt ');
    _u32le(bytes, 52, 2);
    _u32le(bytes, 56, 2822400);
    _u32le(bytes, 60, 1);

    final quality = WebDavAudioQualityParser.parse(
      header: bytes,
      extension: 'dsf',
    );

    expect(quality!.codec, 'DSD');
    expect(quality.bitDepth, 1);
    expect(quality.sampleRate, 2822400);
    expect(quality.channels, 2);
  });

  test('reads MPEG-1 Layer III 320 kbps frame headers', () {
    final bytes = Uint8List(32);
    final header = 0xffe00000 | (3 << 19) | (1 << 17) | (1 << 16) | (14 << 12);
    _u32be(bytes, 0, header);

    final quality = WebDavAudioQualityParser.parse(
      header: bytes,
      extension: 'mp3',
    );

    expect(quality!.lossless, isFalse);
    expect(quality.bitrate, 320000);
    expect(quality.sampleRate, 44100);
  });

  test('reads an ALAC sample entry from an M4A header', () {
    final bytes = Uint8List(160);
    _u32be(bytes, 0, 36);
    _ascii(bytes, 4, 'alac');
    _u16be(bytes, 24, 2);
    _u16be(bytes, 26, 24);
    _u32be(bytes, 40, 36);
    _ascii(bytes, 44, 'alac');
    bytes[57] = 24;
    bytes[61] = 2;
    _u32be(bytes, 68, 4000000);
    _u32be(bytes, 72, 96000);
    _u32be(bytes, 92, 32);
    _ascii(bytes, 96, 'mdhd');
    _u32be(bytes, 112, 1000);
    _u32be(bytes, 116, 180000);

    final quality = WebDavAudioQualityParser.parse(
      header: bytes,
      extension: 'm4a',
      fileSize: 90000000,
    );

    expect(quality!.codec, 'ALAC');
    expect(quality.lossless, isTrue);
    expect(quality.bitDepth, 24);
    expect(quality.sampleRate, 96000);
    expect(quality.bitrate, 4000000);
  });
}

Uint8List _flacHeader({
  required int sampleRate,
  required int bitDepth,
  required int channels,
  required int seconds,
}) {
  final bytes = Uint8List(42);
  _ascii(bytes, 0, 'fLaC');
  bytes[4] = 0x80;
  bytes[7] = 34;
  final totalSamples = sampleRate * seconds;
  final packed = (sampleRate << 44) |
      ((channels - 1) << 41) |
      ((bitDepth - 1) << 36) |
      totalSamples;
  for (var index = 0; index < 8; index++) {
    bytes[18 + index] = (packed >> ((7 - index) * 8)) & 0xff;
  }
  return bytes;
}

void _ascii(Uint8List bytes, int offset, String value) {
  bytes.setRange(offset, offset + value.length, value.codeUnits);
}

void _u16le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _u16be(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

void _u32le(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 4; index++) {
    bytes[offset + index] = (value >> (index * 8)) & 0xff;
  }
}

void _u32be(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 4; index++) {
    bytes[offset + index] = (value >> ((3 - index) * 8)) & 0xff;
  }
}
