import 'package:shadcn_flutter/shadcn_flutter.dart';

class WindowsPageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const WindowsPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final compact = MediaQuery.sizeOf(context).width < 600;

    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: 17,
      ),
      borderRadius: BorderRadius.circular(22),
      borderColor: const Color(0x30FFFFFF),
      borderWidth: 1,
      fillColor: const Color(0xD00A0E18),
      surfaceOpacity: 0.7,
      surfaceBlur: 26,
      boxShadow: const [
        BoxShadow(
          color: Color(0x36000000),
          blurRadius: 28,
          offset: Offset(0, 13),
        ),
      ],
      child: Row(
        children: [
          Container(
            width: compact ? 42 : 46,
            height: compact ? 42 : 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF745CFF), Color(0xFF288FEF)],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x443E78FF), blurRadius: 18),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
          const Gap(13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.h3.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
          if (trailing != null) ...[
            Gap(compact ? 8 : 16),
            trailing!,
          ],
        ],
      ),
    );
  }
}
