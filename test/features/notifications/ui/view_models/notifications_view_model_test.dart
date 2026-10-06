import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/notifications/domain/models/room_notification.dart';
import 'package:matrix_messenger/features/notifications/ui/view_models/notifications_view_model.dart';

import '../../../../../testing/fakes/repositories/fake_notification_repository.dart';
import '../../../../../testing/fakes/services/fake_system_notifications.dart';

void main() {
  late FakeNotificationRepository repository;
  late FakeSystemNotifications system;
  late NotificationsViewModel viewModel;

  RoomNotification message(String roomId) => RoomNotification(
    roomId: roomId,
    roomName: 'Equipe',
    senderName: 'Ana Ribeiro',
    body: 'oi',
    timestamp: DateTime(2026, 10, 6, 10),
  );

  Future<void> deliver(RoomNotification item) async {
    repository.notificationsController.add(item);
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    repository = FakeNotificationRepository();
    system = FakeSystemNotifications();
    viewModel = NotificationsViewModel(repository, system);
    await viewModel.init();
  });

  tearDown(() async {
    await viewModel.close();
    await repository.dispose();
  });

  test('omite a sala aberta com a janela em foco', () async {
    viewModel.setOpenRoom('!a:b.c');

    await deliver(message('!a:b.c'));

    expect(system.shown, isEmpty);
  });

  test('mostra com outra sala aberta, com título e corpo', () async {
    viewModel.setOpenRoom('!outra:b.c');

    await deliver(message('!a:b.c'));

    expect(system.shown, [(roomId: '!a:b.c', title: '#Equipe', body: 'Ana: oi')]);
  });

  test('mostra a sala aberta quando a janela está sem foco', () async {
    viewModel
      ..setOpenRoom('!a:b.c')
      ..setWindowFocused(false);

    await deliver(message('!a:b.c'));

    expect(system.shown, hasLength(1));
  });

  test('clique emite a sala e tapHandled limpa, permitindo repetir', () async {
    system.tap('!a:b.c');
    expect(viewModel.state.tappedRoomId, '!a:b.c');

    viewModel.tapHandled();
    expect(viewModel.state.tappedRoomId, isNull);

    system.tap('!a:b.c');
    expect(viewModel.state.tappedRoomId, '!a:b.c');
  });

  test('falha ao mostrar não interrompe as próximas', () async {
    system.showError = Exception('sem servidor de notificações');
    await deliver(message('!a:b.c'));

    system.showError = null;
    await deliver(message('!b:b.c'));

    expect(system.shown.map((item) => item.roomId), ['!b:b.c']);
  });

  test('close cancela as notificações e ignora o que chega depois', () async {
    await viewModel.close();

    await deliver(message('!a:b.c'));
    system.tap('!a:b.c');

    expect(system.cancelAllCalls, 1);
    expect(system.shown, isEmpty);
  });

  test('close durante o init não deixa a assinatura ativa', () async {
    final gate = Completer<void>();
    final gated = FakeSystemNotifications()..initGate = gate;
    final other = NotificationsViewModel(repository, gated);

    final initializing = other.init();
    final closing = other.close();
    gate.complete();
    await closing;
    await initializing;
    await deliver(message('!a:b.c'));

    expect(gated.shown, isEmpty);
  });
}
