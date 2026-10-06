import 'package:matrix_messenger/core/services/image_file_picker.dart';

class FakeImageFilePicker implements ImageFilePicker {
  FakeImageFilePicker([this.path]);

  String? path;

  int calls = 0;

  @override
  Future<String?> pickImage() async {
    calls++;
    return path;
  }
}
