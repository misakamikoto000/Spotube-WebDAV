import 'dart:math';

import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Shared immersive visual shell for Android and the wide Windows layout.
///
/// The background is intentionally drawn in Flutter so the app theme does
/// not depend on third-party artwork and remains cheap to render.
class WindowsStage extends StatelessWidget {
  final Widget child;

  const WindowsStage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final currentTheme = Theme.of(context);
    final accent = currentTheme.colorScheme.primary;
    final darkScheme = LegacyColorSchemes.darkSlate().copyWith(
      background: () => const Color(0xFF05070D),
      card: () => const Color(0xFF0D111C),
      popover: () => const Color(0xFF111625),
      secondary: () => const Color(0xFF171D2B),
      muted: () => const Color(0xFF121826),
      border: () => const Color(0xFF252D3E),
      input: () => const Color(0xFF20283A),
      primary: () => accent,
      ring: () => accent,
      sidebar: () => const Color(0xFF090D16),
      sidebarBorder: () => const Color(0xFF252D3E),
      sidebarPrimary: () => accent,
      sidebarRing: () => accent,
    );
    final stageTheme = currentTheme.copyWith(
      colorScheme: () => darkScheme,
      radius: () => 0.9,
      surfaceOpacity: () => 0.72,
      surfaceBlur: () => 24,
    );

    final materialTheme = material.ThemeData.dark().copyWith(
      scaffoldBackgroundColor: material.Colors.transparent,
      canvasColor: const Color(0xFF05070D),
      colorScheme: material.ColorScheme.dark(
        primary: accent,
        surface: const Color(0xFF0D111C),
      ),
    );

    return Theme(
      data: stageTheme,
      child: material.Theme(
        data: materialTheme,
        child: ColoredBox(
          color: const Color(0xFF05070D),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const RepaintBoundary(
                child: CustomPaint(painter: _NightSkyPainter()),
              ),
              const _AmbientGlow(
                alignment: Alignment.topRight,
                offset: Offset(140, -180),
                size: 680,
                colors: [Color(0x2D6846FF), Color(0x006846FF)],
              ),
              const _AmbientGlow(
                alignment: Alignment.bottomLeft,
                offset: Offset(-210, 160),
                size: 620,
                colors: [Color(0x2430B7FF), Color(0x0030B7FF)],
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  final Alignment alignment;
  final Offset offset;
  final double size;
  final List<Color> colors;

  const _AmbientGlow({
    required this.alignment,
    required this.offset,
    required this.size,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Transform.translate(
          offset: offset,
          child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: colors),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NightSkyPainter extends CustomPainter {
  const _NightSkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF070A12),
          Color(0xFF05070D),
          Color(0xFF090713),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final random = Random(2407);
    for (var index = 0; index < 86; index++) {
      final position = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 0.35 + random.nextDouble() * 1.15;
      final alpha = 36 + random.nextInt(92);
      final star = Paint()
        ..color = const Color(0xFFDDE7FF).withAlpha(alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(position, radius, star);
    }

    final horizon = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x003A7CFF),
          Color(0x183A7CFF),
          Color(0x006A48FF),
        ],
      ).createShader(Rect.fromLTWH(0, size.height * 0.62, size.width, 1));
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.62, size.width, 1),
      horizon,
    );
  }

  @override
  bool shouldRepaint(covariant _NightSkyPainter oldDelegate) => false;
}
