import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'config/dependencies.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  LicenseRegistry.addLicense(() async* {
    for (final family in ['Newsreader', 'IBMPlexSans']) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/OFL-$family.txt'));
    }
  });
  runApp(
    MultiRepositoryProvider(
      providers: providers(),
      child: const MessengerApp(),
    ),
  );
}
