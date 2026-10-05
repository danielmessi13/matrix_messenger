import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

void useDesktopSize(WidgetTester tester, [Size size = const Size(1440, 900)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
