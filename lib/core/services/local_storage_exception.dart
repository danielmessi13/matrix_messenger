class LocalStorageException implements Exception {
  const LocalStorageException(this.details);

  final String details;

  @override
  String toString() => 'LocalStorageException: $details';
}
