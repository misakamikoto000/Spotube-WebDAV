import 'package:auto_route/auto_route.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/root/sidebar/sidebar_footer.dart';

class WindowsDesktopSidebar extends StatelessWidget {
  final Widget child;

  const WindowsDesktopSidebar({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final router = context.watchRouter;
    final primaryTiles = getSidebarTileList(context.l10n);
    final libraryTiles = getSidebarLibraryTileList(context.l10n);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 0, 126),
          child: SizedBox(
            width: 222,
            child: SurfaceCard(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              borderRadius: BorderRadius.circular(22),
              borderColor: const Color(0x2FFFFFFF),
              borderWidth: 1,
              fillColor: const Color(0xE60A0D16),
              surfaceOpacity: 0.76,
              surfaceBlur: 28,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x5A000000),
                  blurRadius: 34,
                  offset: Offset(0, 18),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Brand(),
                  const Gap(24),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SectionLabel(context.l10n.browse),
                          const Gap(8),
                          for (final tile in primaryTiles)
                            _WindowsNavigationTile(
                              tile: tile,
                              selected: router.currentPath
                                  .startsWith(tile.pathPrefix),
                              onPressed: () => context.navigateTo(tile.route),
                            ),
                          const Gap(20),
                          _SectionLabel(context.l10n.library),
                          const Gap(8),
                          for (final tile in libraryTiles)
                            _WindowsNavigationTile(
                              tile: tile,
                              selected: router.currentPath
                                  .startsWith(tile.pathPrefix),
                              onPressed: () => context.navigateTo(tile.route),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  const Gap(4),
                  const _LocalFirstStatus(),
                  const Gap(8),
                  const SidebarFooter(),
                ],
              ),
            ),
          ),
        ),
        const Gap(14),
        Expanded(child: child),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF735CFF), Color(0xFF1EB8FF)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x553E78FF),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 23),
        ),
        const Gap(11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Spotube',
                style: TextStyle(
                  fontFamily: 'Cookie',
                  fontSize: 27,
                  height: 0.95,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'DESKTOP STAGE',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.mutedForeground,
                  fontSize: 9,
                  letterSpacing: 1.7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.mutedForeground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.35,
        ),
      ),
    );
  }
}

class _WindowsNavigationTile extends StatefulWidget {
  final SideBarTiles tile;
  final bool selected;
  final VoidCallback onPressed;

  const _WindowsNavigationTile({
    required this.tile,
    required this.selected,
    required this.onPressed,
  });

  @override
  State<_WindowsNavigationTile> createState() => _WindowsNavigationTileState();
}

class _WindowsNavigationTileState extends State<_WindowsNavigationTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.tile.title,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? null
                    : hovered
                        ? const Color(0x151E8CFF)
                        : Colors.transparent,
                gradient: selected
                    ? LinearGradient(
                        colors: [
                          colorScheme.primary.withAlpha(72),
                          const Color(0x222CB5FF),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? colorScheme.primary.withAlpha(105)
                      : hovered
                          ? const Color(0x22FFFFFF)
                          : Colors.transparent,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: colorScheme.primary.withAlpha(36),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.tile.icon,
                    size: 19,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.mutedForeground,
                  ),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      widget.tile.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? colorScheme.foreground
                            : colorScheme.mutedForeground,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    width: selected ? 5 : 0,
                    height: selected ? 5 : 0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: colorScheme.primary,
                                blurRadius: 7,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalFirstStatus extends StatelessWidget {
  const _LocalFirstStatus();

  @override
  Widget build(BuildContext context) {
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF48D597),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x8848D597), blurRadius: 8),
              ],
            ),
          ),
          const Gap(8),
          Expanded(
            child: Text(
              isChinese ? '本地曲库已就绪' : 'Local library ready',
              style: TextStyle(
                color: Theme.of(context).colorScheme.mutedForeground,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
