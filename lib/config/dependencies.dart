import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/services/browser_launcher.dart';
import '../core/services/matrix_service.dart';
import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/data/repositories/auth_repository_matrix.dart';
import '../features/conversation/data/repositories/conversation_repository.dart';
import '../features/conversation/data/repositories/conversation_repository_matrix.dart';
import '../features/recovery/data/repositories/recovery_repository.dart';
import '../features/recovery/data/repositories/recovery_repository_matrix.dart';
import '../features/rooms/data/repositories/room_repository.dart';
import '../features/rooms/data/repositories/room_repository_matrix.dart';

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
  RepositoryProvider<RoomRepository>(
    create: (context) => RoomRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<ConversationRepository>(
    create: (context) =>
        ConversationRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<RecoveryRepository>(
    create: (context) =>
        RecoveryRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<BrowserLauncher>(
    create: (_) => const UrlLauncherBrowserLauncher(),
  ),
];
