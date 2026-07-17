import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/hooks/configurators/use_check_yt_dlp_installed.dart';
import 'package:spotube/modules/root/bottom_player.dart';
import 'package:spotube/modules/root/sidebar/sidebar.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/root/windows/windows_stage.dart';
import 'package:spotube/hooks/configurators/use_endless_playback.dart';
import 'package:spotube/modules/root/use_global_subscriptions.dart';
import 'package:spotube/provider/glance/glance.dart';
import 'package:spotube/utils/platform.dart';

@RoutePage()
class RootAppPage extends HookConsumerWidget {
  const RootAppPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final backgroundColor = Theme.of(context).colorScheme.background;
    final brightness = Theme.of(context).brightness;
    final windowsStage = useImmersiveDesktopUi(context);
    final immersiveStage = useImmersiveUi(context);
    final systemBackgroundColor =
        immersiveStage ? const Color(0xFF05070D) : backgroundColor;

    ref.listen(glanceProvider, (_, __) {});

    useGlobalSubscriptions(ref);
    useEndlessPlayback(ref);
    useCheckYtDlpInstalled(ref);

    useEffect(() {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: systemBackgroundColor,
          statusBarIconBrightness:
              immersiveStage || brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
          systemNavigationBarColor: systemBackgroundColor,
          systemNavigationBarIconBrightness:
              immersiveStage || brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: false,
        ),
      );
      return null;
    }, [systemBackgroundColor, brightness, immersiveStage]);

    final scaffold = MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: SafeArea(
        top: false,
        child: Scaffold(
          backgroundColor: immersiveStage ? Colors.transparent : null,
          footers: const [
            BottomPlayer(),
            SpotubeNavigationBar(),
          ],
          floatingFooter: true,
          child: Sidebar(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: MediaQuery.paddingOf(context).copyWith(
                  bottom: (windowsStage
                          ? 126
                          : kIsAndroid
                              ? 108
                              : 100) *
                      context.theme.scaling,
                ),
              ),
              child: const AutoRouter(),
            ),
          ),
        ),
      ),
    );

    return immersiveStage ? WindowsStage(child: scaffold) : scaffold;
  }
}
