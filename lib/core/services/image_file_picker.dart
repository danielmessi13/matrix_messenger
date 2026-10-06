import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

abstract interface class ImageFilePicker {
  Future<String?> pickImage();
}

class FileSelectorImageFilePicker implements ImageFilePicker {
  const FileSelectorImageFilePicker();

  static const _images = XTypeGroup(
    label: 'Imagens',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
  );

  @override
  Future<String?> pickImage() async {
    try {
      return (await openFile(acceptedTypeGroups: const [_images]))?.path;
    } on PlatformException {
      return null;
    }
  }
}
