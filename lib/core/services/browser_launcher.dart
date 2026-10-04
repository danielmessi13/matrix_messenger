import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

abstract interface class BrowserLauncher {
  Future<bool> open(Uri url);
}

class UrlLauncherBrowserLauncher implements BrowserLauncher {
  const UrlLauncherBrowserLauncher();

  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}
