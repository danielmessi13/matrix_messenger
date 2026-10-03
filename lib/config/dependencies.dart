import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/services/matrix_service.dart';
import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/data/repositories/auth_repository_matrix.dart';

List<RepositoryProvider<Object>> providers({
  Future<String> Function()? dataDir,
}) => [
  RepositoryProvider<MatrixService>(
    create: (_) => MatrixService(dataDir: dataDir),
  ),
  RepositoryProvider<AuthRepository>(
    create: (context) => AuthRepositoryMatrix(context.read<MatrixService>()),
    dispose: (repository) => repository.dispose(),
  ),
];
