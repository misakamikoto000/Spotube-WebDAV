import 'dart:ui';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/components/image/universal_image.dart';

class WindowsDetailBackdrop extends StatelessWidget {
  final String image;
  final Widget child;

  const WindowsDetailBackdrop({
    super.key,
    required this.image,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
            child: Transform.scale(
              scale: 1.14,
              child: Opacity(
                opacity: 0.18,
                child: UniversalImage(path: image, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xE805070D),
                  primary.withAlpha(30),
                  const Color(0xF505070D),
                ],
                stops: const [0.08, 0.48, 1],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
