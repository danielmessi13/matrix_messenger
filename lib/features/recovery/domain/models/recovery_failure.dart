enum RecoveryFailureType { invalidKey, network, unknown }

class RecoveryFailure implements Exception {
  const RecoveryFailure(this.type, [this.details]);

  final RecoveryFailureType type;

  final String? details;

  @override
  String toString() =>
      'RecoveryFailure($type${details == null ? '' : ': $details'})';
}
