// Sem == próprio: clicar de novo na mesma thread é um pedido novo.
class ThreadRequest {
  ThreadRequest({required this.roomId, required this.rootEventId});

  final String roomId;

  final String rootEventId;
}
