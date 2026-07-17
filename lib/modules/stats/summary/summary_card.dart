import 'package:auto_size_text/auto_size_text.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/formatters.dart';
import 'package:spotube/utils/platform.dart';

class SummaryCard extends StatelessWidget {
  final String title;
  final String unit;
  final String description;
  final VoidCallback? onTap;

  final ColorShades color;

  SummaryCard({
    super.key,
    required double title,
    required this.unit,
    required this.description,
    required this.color,
    this.onTap,
  }) : title = compactNumberFormatter.format(title);

  const SummaryCard.unformatted({
    super.key,
    required this.title,
    required this.unit,
    required this.description,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData(:typography, :brightness) = Theme.of(context);
    final windowsStage = useImmersiveUi(context);

    final descriptionNewLines = description.split("").where((s) => s == "\n");

    final button = Button.ghost(
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AutoSizeText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: typography.h2.copyWith(
                      color: windowsStage ? color.shade400 : color.shade900,
                    ),
                  ),
                  TextSpan(
                    text: " $unit",
                    style: typography.semiBold.copyWith(
                      color: windowsStage
                          ? context.theme.colorScheme.foreground
                          : color.shade900,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
            ),
            const Gap(5),
            AutoSizeText(
              description,
              maxLines: description.contains("\n")
                  ? descriptionNewLines.length + 1
                  : 1,
              minFontSize: 9,
              style: typography.small.copyWith(
                color: windowsStage
                    ? context.theme.colorScheme.mutedForeground
                    : color.shade900,
              ),
            ),
          ],
        ),
      ),
    );

    if (windowsStage) {
      return SurfaceCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(18),
        borderColor: color.withAlpha(96),
        borderWidth: 1,
        fillColor: const Color(0xB00B101B),
        surfaceOpacity: 0.55,
        surfaceBlur: 14,
        boxShadow: [
          BoxShadow(color: color.withAlpha(25), blurRadius: 18),
        ],
        child: button,
      );
    }

    return Card(
      fillColor: brightness == Brightness.dark ? color.shade100 : color.shade50,
      filled: true,
      borderColor: color,
      padding: EdgeInsets.zero,
      borderRadius: context.theme.borderRadiusLg,
      child: button,
    );
  }
}
