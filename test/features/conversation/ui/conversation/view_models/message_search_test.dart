import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/message_search.dart';

class _Items extends Cubit<(List<TimelineItem>, bool)> {
  _Items(List<TimelineItem> items) : super((items, false));

  int loads = 0;

  List<TimelineItem> Function()? older;

  Future<void> loadOlder() async {
    loads++;
    final next = older?.call();
    if (next != null) {
      Future<void>.delayed(
        const Duration(milliseconds: 10),
        () => emit((next, true)),
      );
    }
  }
}

MessageItem _message(String id) => MessageItem(
  id: 'u$id',
  eventId: id,
  senderId: '@b:c',
  senderName: 'B',
  isOwn: false,
  timestamp: DateTime(2026, 10, 4),
  kind: MessageKind.text,
  body: id,
);

Future<String?> _search(_Items cubit, String eventId) => searchMessage(
  cubit,
  eventId: eventId,
  items: (s) => s.$1,
  reachedStart: (s) => s.$2,
  loadOlder: cubit.loadOlder,
);

void main() {
  test('acha na lista carregada sem paginar', () async {
    final cubit = _Items([_message('\$1')]);

    expect(await _search(cubit, '\$1'), 'u\$1');
    expect(cubit.loads, 0);
  });

  test('pagina até achar', () async {
    final cubit = _Items([_message('\$2')])
      ..older = () => [_message('\$1'), _message('\$2')];

    expect(await _search(cubit, '\$1'), 'u\$1');
    expect(cubit.loads, 1);
  });

  test('desiste no início da conversa', () async {
    final cubit = _Items([_message('\$2')])..older = () => [_message('\$2')];

    expect(await _search(cubit, '\$1'), isNull);
    expect(cubit.loads, 1);
  });

  test('desiste depois de searchPages páginas', () async {
    final cubit = _Items([_message('\$9')]);

    expect(await _search(cubit, '\$1'), isNull);
    expect(cubit.loads, searchPages);
  });
}
