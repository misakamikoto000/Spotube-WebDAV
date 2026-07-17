import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/utils/platform.dart';

class StatsItemFrame extends StatelessWidget {
  final Widget child;

  const StatsItemFrame({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final windowsStage = useImmersiveUi(context);
    if (!windowsStage) return child;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x18FFFFFF)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      ),
    );
  }
}
