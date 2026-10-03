enum AuthFailureType {
  invalidHomeserver,
  homeserverUnreachable,
  invalidCredentials,
  userDeactivated,
  rateLimited,
  storage,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.type, [this.details]);

  final AuthFailureType type;

  final String? details;

  @override
  String toString() =>
      'AuthFailure($type${details == null ? '' : ': $details'})';
}
