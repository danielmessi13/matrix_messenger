import 'package:equatable/equatable.dart';

import '../../../auth/domain/models/user_session.dart';

final class HomeState extends Equatable {
  const HomeState({required this.session});

  final UserSession session;

  @override
  List<Object?> get props => [session];
}
