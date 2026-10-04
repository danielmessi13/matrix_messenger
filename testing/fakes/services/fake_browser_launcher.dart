import 'package:matrix_messenger/core/services/browser_launcher.dart';

class FakeBrowserLauncher implements BrowserLauncher {
  FakeBrowserLauncher({this.result = true, this.error});

  bool result;

  Object? error;

  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    if (error case final error?) throw error;
    return result;
  }
}
