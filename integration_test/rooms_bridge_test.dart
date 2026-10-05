import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';
import 'package:matrix_messenger/src/rust/frb_generated.dart';

const _homeserver = String.fromEnvironment('MATRIX_HOMESERVER');
const _username = String.fromEnvironment('MATRIX_USERNAME');
const _password = String.fromEnvironment('MATRIX_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  test(
    'sync real entrega a lista de salas e chega a running',
    () async {
      final dataDir = await Directory.systemTemp.createTemp('rooms_it_');
      addTearDown(() => dataDir.delete(recursive: true));
      final client = await MatrixClient.login(
        homeserver: _homeserver,
        username: _username,
        password: _password,
        dataDir: dataDir.path,
      );
      addTearDown(client.dispose);

      final running = client.watchSyncStatus().firstWhere(
        (status) => status == SyncStatus.running,
      );
      final rooms = await client.watchRooms().first.timeout(
        const Duration(seconds: 60),
      );

      expect(rooms, isA<List<RoomSummary>>());
      await running.timeout(const Duration(seconds: 60));
      await client.logout();
    },
    skip: _homeserver.isEmpty ? 'requer --dart-define MATRIX_*' : false,
  );
}
