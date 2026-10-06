import 'dart:typed_data';

enum ImageStatus { loading, ready, failed }

final class ImageState {
  const ImageState({this.status = ImageStatus.loading, this.bytes});

  final ImageStatus status;

  final Uint8List? bytes;

  @override
  bool operator ==(Object other) =>
      other is ImageState &&
      other.status == status &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(status, identityHashCode(bytes));
}
