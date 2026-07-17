import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/string.dart';
import 'package:spotube/utils/platform.dart';

class PlaybuttonCard extends StatelessWidget {
  final void Function()? onTap;
  final void Function()? onPlaybuttonPressed;
  final void Function()? onAddToQueuePressed;
  final String? description;

  final String? imageUrl;
  final Widget? image;
  final bool isPlaying;
  final bool isLoading;
  final String title;
  final bool isOwner;

  const PlaybuttonCard({
    required this.isPlaying,
    required this.isLoading,
    required this.title,
    this.description,
    this.onPlaybuttonPressed,
    this.onAddToQueuePressed,
    this.onTap,
    this.isOwner = false,
    this.imageUrl,
    this.image,
    super.key,
  }) : assert(
          imageUrl != null || image != null,
          "imageUrl and image can't be null at the same time",
        );

  @override
  Widget build(BuildContext context) {
    final unescapeHtml = description?.unescapeHtml().cleanHtml() ?? "";
    final scale = context.theme.scaling;
    final windowsStage = useImmersiveUi(context);
    final imageSize = (windowsStage ? 164 : 150) * scale;
    final cardWidth = (windowsStage ? 176 : 150) * scale;

    final card = SizedBox(
      width: cardWidth,
      child: CardImage(
        hoverScale: windowsStage ? 1.025 : null,
        gap: windowsStage ? 10 : null,
        image: Stack(
          children: [
            if (imageUrl != null)
              Container(
                width: imageSize,
                height: imageSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(windowsStage ? 16 : 6),
                  border: windowsStage
                      ? Border.all(color: const Color(0x2FFFFFFF))
                      : null,
                  boxShadow: windowsStage
                      ? const [
                          BoxShadow(
                            color: Color(0x59000000),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ]
                      : null,
                  image: DecorationImage(
                    image: UniversalImage.imageProvider(
                      imageUrl!,
                      height: 200 * scale,
                      width: 200 * scale,
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              SizedBox(
                width: imageSize,
                height: imageSize,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(windowsStage ? 16 : 6),
                  child: image!,
                ),
              ),
            StatedWidget.builder(
              builder: (context, states) {
                return Positioned(
                  right: 8,
                  bottom: 8,
                  child: Column(
                    children: [
                      AnimatedScale(
                        curve: Curves.easeOutBack,
                        duration: const Duration(milliseconds: 300),
                        scale: (states.contains(WidgetState.hovered) ||
                                    kIsMobile) &&
                                !isLoading
                            ? 1
                            : 0.7,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: (states.contains(WidgetState.hovered) ||
                                      kIsMobile) &&
                                  !isLoading
                              ? 1
                              : 0,
                          child: IconButton.secondary(
                            icon: const Icon(SpotubeIcons.queueAdd),
                            onPressed: onAddToQueuePressed,
                            size: ButtonSize.small,
                          ),
                        ),
                      ),
                      const Gap(5),
                      AnimatedScale(
                        curve: Curves.easeOutBack,
                        duration: const Duration(milliseconds: 150),
                        scale: states.contains(WidgetState.hovered) ||
                                kIsMobile ||
                                isPlaying ||
                                isLoading
                            ? 1
                            : 0.7,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: states.contains(WidgetState.hovered) ||
                                  kIsMobile ||
                                  isPlaying ||
                                  isLoading
                              ? 1
                              : 0,
                          child: IconButton.secondary(
                            icon: switch ((isLoading, isPlaying)) {
                              (true, _) => const CircularProgressIndicator(
                                  size: 15,
                                ),
                              (false, false) => const Icon(SpotubeIcons.play),
                              (false, true) => const Icon(SpotubeIcons.pause)
                            },
                            enabled: !isLoading,
                            onPressed: onPlaybuttonPressed,
                            size: ButtonSize.small,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (isOwner)
              const Positioned(
                right: 5,
                top: 5,
                child: SecondaryBadge(
                  style: ButtonStyle.secondaryIcon(
                    shape: ButtonShape.circle,
                    size: ButtonSize.small,
                  ),
                  child: Icon(SpotubeIcons.user),
                ),
              ),
          ],
        ),
        title: Tooltip(
          tooltip: TooltipContainer(child: Text(title)).call,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        subtitle: Text(
          unescapeHtml.isEmpty ? "\n" : unescapeHtml,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: onTap,
      ),
    );

    return windowsStage ? _WindowsCardFrame(child: card) : card;
  }
}

class _WindowsCardFrame extends StatefulWidget {
  final Widget child;

  const _WindowsCardFrame({required this.child});

  @override
  State<_WindowsCardFrame> createState() => _WindowsCardFrameState();
}

class _WindowsCardFrameState extends State<_WindowsCardFrame> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: hovered ? const Color(0x191D75FF) : const Color(0x10FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hovered ? primary.withAlpha(82) : const Color(0x1FFFFFFF),
          ),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: primary.withAlpha(30),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: hovered ? 1.015 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}
