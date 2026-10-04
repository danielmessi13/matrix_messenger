import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';

void main() {
  test('ok guarda o valor', () {
    const Result<int> result = Result.ok(42);

    expect(switch (result) {
      Ok(:final value) => value,
      Error() => null,
    }, 42);
  });

  test('error guarda a exceção', () {
    final exception = Exception('falhou');
    final Result<int> result = Result.error(exception);

    expect(switch (result) {
      Ok() => null,
      Error(:final error) => error,
    }, same(exception));
  });
}
