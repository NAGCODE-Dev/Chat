import 'package:flutter_test/flutter_test.dart';

import 'package:chat_app/features/chat/models/chat_models.dart';

void main() {
  test('horário sem fuso do SQLite é interpretado como UTC', () {
    final parsed = parseBackendDate('2026-10-26 16:00:00');
    expect(parsed, DateTime.utc(2026, 10, 26, 16).toLocal());
  });

  test('horário com fuso explícito é respeitado', () {
    final parsed = parseBackendDate('2026-10-26T16:00:00-03:00');
    expect(parsed, DateTime.utc(2026, 10, 26, 19).toLocal());
  });
}
