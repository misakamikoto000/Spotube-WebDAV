import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final kIsDesktop = kIsLinux || kIsWindows || kIsMacOS;

final kIsMobile = kIsAndroid || kIsIOS;

final kIsFlatpak = kIsWeb ? false : Platform.environment["FLATPAK_ID"] != null;

final kIsMacOS = kIsWeb ? false : Platform.isMacOS;
final kIsLinux = kIsWeb ? false : Platform.isLinux;
final kIsAndroid = kIsWeb ? false : Platform.isAndroid;
final kIsIOS = kIsWeb ? false : Platform.isIOS;
final kIsWindows = kIsWeb ? false : Platform.isWindows;

/// The shared dark glass visual language used by Android and wide Windows.
bool useImmersiveUi(BuildContext context) =>
    kIsAndroid || (kIsWindows && MediaQuery.sizeOf(context).width >= 1024);

bool useImmersiveDesktopUi(BuildContext context) =>
    kIsWindows && MediaQuery.sizeOf(context).width >= 1024;
