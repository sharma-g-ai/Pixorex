/// Every day, time and "today" in the app is Indian time (IST), whatever the phone's own zone is
/// (decision of 18 Nov 2026), so the phone, the dashboard and the exports agree.
///
/// India has no daylight saving, so IST is a fixed UTC+5:30.
const Duration istOffset = Duration(hours: 5, minutes: 30);

/// The Indian wall clock for an instant: the returned time's year, month, day, hour... read as
/// they do in India. (It is flagged UTC only because Dart has no other zone to carry it in;
/// never compare it with a real instant.)
DateTime toIst(DateTime instant) => instant.toUtc().add(istOffset);

/// The Indian day of an instant as YYYY-MM-DD, the format the API's from/to take.
String istDay(DateTime instant) {
  final d = toIst(instant);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
