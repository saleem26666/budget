import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

bool get isMobilePlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

bool get supportsDeviceCamera => isMobilePlatform;

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
