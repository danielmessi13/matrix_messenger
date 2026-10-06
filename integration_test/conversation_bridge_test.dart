import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix_messenger/src/rust/api/client.dart';
import 'package:matrix_messenger/src/rust/api/timeline.dart';
import 'package:matrix_messenger/src/rust/frb_generated.dart';

const _homeserver = String.fromEnvironment('MATRIX_HOMESERVER');
const _username = String.fromEnvironment('MATRIX_USERNAME');
const _password = String.fromEnvironment('MATRIX_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  test(
    'abre a primeira sala, envia e vê a mensagem como enviada',
    () async {
      final dataDir = await Directory.systemTemp.createTemp('conversation_it_');
      addTearDown(() => dataDir.delete(recursive: true));
      final client = await MatrixClient.login(
        homeserver: _homeserver,
        username: _username,
        password: _password,
        dataDir: dataDir.path,
        keepSignedIn: true,
      );
      addTearDown(client.dispose);
      final rooms = await client
          .watchRooms()
          .firstWhere(
            (rooms) => rooms.any((room) => !room.isInvite),
          )
          .timeout(const Duration(seconds: 60));
      final room = rooms.firstWhere((room) => !room.isInvite);
      final timeline = await client.openTimeline(roomId: room.id);
      addTearDown(timeline.dispose);
      final body =
          'teste de integração ${DateTime.now().millisecondsSinceEpoch}';

      final sent = timeline.watch().firstWhere(
        (snapshot) => snapshot.items.any(
          (entry) =>
              entry.message?.body == body &&
              entry.message?.sendState == SendState.sent,
        ),
      );
      await timeline.sendMarkdown(body: body);

      await sent.timeout(const Duration(seconds: 60));
      await client.logout();
    },
    skip: _homeserver.isEmpty ? 'requer --dart-define MATRIX_*' : false,
  );
}
