import 'package:flutter/material.dart' show ListTileTheme, ListTileThemeData;
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Theme, ThemeData;
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/utils/platform.dart';

class SectionCardWithHeading extends StatelessWidget {
  final String heading;
  final List<Widget> children;
  const SectionCardWithHeading({
    super.key,
    required this.heading,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final windowsStage = useImmersiveUi(context);
    final headingWidget = Text(
      heading,
      style: context.theme.typography.large.copyWith(
        color: context.theme.colorScheme.foreground,
        fontWeight: windowsStage ? FontWeight.w700 : null,
      ),
    );
    final sectionChildren = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ).gap(8.0);

    final content = windowsStage
        ? Padding(
            padding: EdgeInsets.symmetric(
              horizontal: kIsAndroid ? 0 : 12,
              vertical: 5,
            ),
            child: SurfaceCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(20),
              borderColor: const Color(0x24FFFFFF),
              borderWidth: 1,
              fillColor: const Color(0xA80B0F19),
              surfaceOpacity: 0.52,
              surfaceBlur: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  headingWidget,
                  const Gap(12),
                  sectionChildren,
                ],
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: headingWidget,
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: sectionChildren,
              ),
            ],
          );

    return ListTileTheme(
      data: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: context.theme.borderRadiusLg,
          side: BorderSide(
            color: context.theme.colorScheme.border,
            width: .5,
          ),
        ),
        textColor: context.theme.colorScheme.foreground,
        iconColor: context.theme.colorScheme.foreground,
        selectedColor: context.theme.colorScheme.accent,
        subtitleTextStyle: context.theme.typography.xSmall,
      ),
      child: content,
    );
  }
}
