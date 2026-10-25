import 'package:flutter_test/flutter_test.dart';

import 'package:chat_app/core/clock_format.dart';

void main() {
  test('formata a hora em 24 horas', () {
    expect(formatClockTime(DateTime(2026, 10, 24, 7, 5)), '07:05');
    expect(formatClockTime(DateTime(2026, 10, 24, 23, 59)), '23:59');
  });

  test('formata a hora em 12 horas', () {
    expect(
      formatClockTime(DateTime(2026, 10, 24, 0, 7), use24Hour: false),
      '12:07 AM',
    );
    expect(
      formatClockTime(DateTime(2026, 10, 24, 13, 5), use24Hour: false),
      '1:05 PM',
    );
  });

  test('formata a data por extenso em português', () {
    expect(
      formatPortugueseDate(DateTime(2026, 10, 24)),
      'Sábado, 24 de outubro de 2026',
    );
    expect(
      formatPortugueseDate(DateTime(2026, 3, 2)),
      'Segunda-feira, 2 de março de 2026',
    );
  });
}
