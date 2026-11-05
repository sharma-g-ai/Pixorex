/// Plain-language formatting for operators: no exception class names, raw
/// timestamps or enum names reach the screen.
library;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "8 Oct 2026"
String ppgDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// "7:26 PM"
String ppgTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// "8 Oct 2026, 7:26 PM"
String ppgDateTime(DateTime value) => '${ppgDate(value)}, ${ppgTime(value)}';

/// "Just now", "10 min ago", "Today, 7:12 PM", "Yesterday", "8 Oct 2026".
String ppgRelative(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final diff = current.difference(local);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return 'today, ${ppgTime(local)}';
  if (today.difference(day).inDays == 1) return 'yesterday, ${ppgTime(local)}';
  return ppgDate(local);
}

/// "+12" or "−12" with a true minus sign, so it reads apart from a hyphen.
String ppgSigned(int value) => value > 0
    ? '+$value'
    : value < 0
    ? '−${-value}'
    : '0';

String ppgPlural(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

/// Turns a thrown controller error into a sentence an operator can act on.
String ppgErrorMessage(Object error) {
  final text = switch (error) {
    StateError(:final message) => message,
    ArgumentError(:final message) => '$message',
    _ => error.toString(),
  };
  return text
      .replaceFirst(
        RegExp(r'^(Exception|Bad state|Invalid argument\(s\)): '),
        '',
      )
      .trim();
}
