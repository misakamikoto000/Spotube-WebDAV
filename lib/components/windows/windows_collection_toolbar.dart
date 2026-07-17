import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';

class WindowsCollectionToolbar extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? countLabel;
  final String searchPlaceholder;
  final ValueChanged<String> onSearchChanged;
  final Widget? trailing;

  const WindowsCollectionToolbar({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.searchPlaceholder,
    required this.onSearchChanged,
    this.countLabel,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 600;

    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 15 : 20,
        vertical: mobile ? 14 : 16,
      ),
      borderRadius: BorderRadius.circular(22),
      borderColor: const Color(0x2CFFFFFF),
      borderWidth: 1,
      fillColor: const Color(0xD20B0F19),
      surfaceOpacity: 0.68,
      surfaceBlur: 24,
      boxShadow: const [
        BoxShadow(
          color: Color(0x3D000000),
          blurRadius: 30,
          offset: Offset(0, 14),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 880;
          final heading = Row(
            mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF745CFF), Color(0xFF288FEF)],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x443E78FF), blurRadius: 16),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const Gap(13),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.h3.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (countLabel != null) ...[
                          const Gap(9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withAlpha(25),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: theme.colorScheme.primary.withAlpha(58),
                              ),
                            ),
                            child: Text(
                              countLabel!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Gap(2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.mutedForeground,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final search = SizedBox(
            height: 42,
            child: TextField(
              onChanged: onSearchChanged,
              features: const [
                InputFeature.leading(Icon(SpotubeIcons.search, size: 17)),
              ],
              placeholder: Text(searchPlaceholder),
            ),
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const Gap(14),
                search,
                if (trailing != null) ...[
                  const Gap(10),
                  Align(alignment: Alignment.centerRight, child: trailing!),
                ],
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: heading),
              const Gap(24),
              SizedBox(width: 310, child: search),
              if (trailing != null) ...[
                const Gap(10),
                trailing!,
              ],
            ],
          );
        },
      ),
    );
  }
}
