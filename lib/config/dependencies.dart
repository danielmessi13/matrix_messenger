import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/services/browser_launcher.dart';
import '../core/services/image_file_picker.dart';
import '../core/services/matrix_service.dart';
import '../core/services/system_notifications.dart';
import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/data/repositories/auth_repository_matrix.dart';
import '../features/conversation/data/repositories/conversation_repository.dart';
import '../features/conversation/data/repositories/conversation_repository_matrix.dart';
import '../features/conversation/data/repositories/media_repository.dart';
import '../features/conversation/data/repositories/media_repository_matrix.dart';
import '../features/notifications/data/repositories/notification_repository.dart';
import '../features/notifications/data/repositories/notification_repository_matrix.dart';
import '../features/recovery/data/repositories/recovery_repository.dart';
import '../features/recovery/data/repositories/recovery_repository_matrix.dart';
import '../features/rooms/data/repositories/room_repository.dart';
import '../features/rooms/data/repositories/room_repository_matrix.dart';
import '../features/threads/data/repositories/recent_threads_repository.dart';
import '../features/threads/data/repositories/recent_threads_repository_matrix.dart';

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
  RepositoryProvider<RecentThreadsRepository>(
    create: (context) =>
        RecentThreadsRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<ConversationRepository>(
    create: (context) =>
        ConversationRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<MediaRepository>(
    create: (context) => MediaRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<RecoveryRepository>(
    create: (context) =>
        RecoveryRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<NotificationRepository>(
    create: (context) =>
        NotificationRepositoryMatrix(context.read<MatrixService>()),
  ),
  RepositoryProvider<BrowserLauncher>(
    create: (_) => const UrlLauncherBrowserLauncher(),
  ),
  RepositoryProvider<SystemNotifications>(
    create: (_) => LocalSystemNotifications(),
  ),
  RepositoryProvider<ImageFilePicker>(
    create: (_) => const FileSelectorImageFilePicker(),
  ),
];
