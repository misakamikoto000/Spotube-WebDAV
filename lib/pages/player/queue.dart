import 'package:auto_route/annotations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/modules/player/player_queue.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/utils/platform.dart';

@RoutePage()
class PlayerQueuePage extends HookConsumerWidget {
  const PlayerQueuePage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(
      audioPlayerProvider,
    );
    final playlistNotifier = ref.read(audioPlayerProvider.notifier);
    final windowsStage = useImmersiveUi(context);
    final queue = PlayerQueue.fromAudioPlayerNotifier(
      floating: false,
      playlist: playlist,
      notifier: playlistNotifier,
    );
    return Scaffold(
      backgroundColor: windowsStage ? Colors.transparent : null,
      child: SafeArea(
        bottom: false,
        child: windowsStage
            ? Padding(
                padding: EdgeInsets.fromLTRB(
                  kIsAndroid ? 8 : 12,
                  12,
                  kIsAndroid ? 8 : 24,
                  MediaQuery.paddingOf(context).bottom + 16,
                ),
                child: SurfaceCard(
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(26),
                  borderColor: const Color(0x32FFFFFF),
                  borderWidth: 1,
                  fillColor: const Color(0xD10A0D16),
                  surfaceOpacity: 0.7,
                  surfaceBlur: 28,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: queue,
                  ),
                ),
              )
            : queue,
      ),
    );
  }
}
