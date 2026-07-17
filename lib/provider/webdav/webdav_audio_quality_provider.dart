import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/webdav/webdav_audio_quality.dart';
import 'package:spotube/services/webdav/webdav_audio_quality_store.dart';

final webDavAudioQualityProvider =
    StateProvider<Map<String, WebDavAudioQuality>>(
  (ref) => WebDavAudioQualityStore.qualitiesByPath,
);
