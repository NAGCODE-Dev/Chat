/// Formatação do relógio de hibernação em português.
library;

const List<String> _weekdays = [
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
  'Domingo',
];

const List<String> _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// Formata a hora com dois dígitos, em 24 h ou 12 h.
String formatClockTime(DateTime time, {bool use24Hour = true}) {
  if (use24Hour) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
}

/// Formata a data por extenso, com o dia da semana.
String formatPortugueseDate(DateTime date) {
  final weekday = _weekdays[date.weekday - 1];
  final month = _months[date.month - 1];
  return '$weekday, ${date.day} de $month de ${date.year}';
}
