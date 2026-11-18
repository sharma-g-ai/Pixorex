import 'package:flutter_test/flutter_test.dart';
import 'package:pixorex_mobile/core/india_time.dart';
import 'package:pixorex_mobile/features/home/home_screen.dart';
import 'package:pixorex_mobile/features/scan/scan_details_screen.dart';

// Every day and time on the phone is Indian time (IST, UTC+5:30), whatever the phone's own zone.

void main() {
  group('Indian day', () {
    test('GIVEN 18:29 UTC THEN it is still the same Indian day (23:59)', () {
      expect(istDay(DateTime.utc(2026, 11, 17, 18, 29)), '2026-11-17');
    });

    test('GIVEN 18:30 UTC THEN it is already the next Indian day (00:00)', () {
      expect(istDay(DateTime.utc(2026, 11, 17, 18, 30)), '2026-11-18');
    });

    test('GIVEN a month end THEN the day rolls into the next month in India', () {
      expect(istDay(DateTime.utc(2026, 11, 30, 19, 0)), '2026-12-01');
    });

    test('GIVEN a local-zone time THEN the same instant gives the same Indian day', () {
      final instant = DateTime.utc(2026, 11, 17, 20, 0);
      expect(istDay(instant), istDay(instant.toLocal()));
    });
  });

  group('Times shown on the phone', () {
    test('eventTime writes the Indian clock, not the phone\'s', () {
      expect(eventTime(DateTime.utc(2026, 11, 4, 9, 45, 42)), '4 Nov 15:15:42');
      expect(eventTime(DateTime.utc(2026, 11, 17, 19, 0, 0)), '18 Nov 00:30:00');
    });

    test('the home date is the Indian day and weekday', () {
      // Tue 17 Nov 20:00 UTC is already Wed 18 Nov 01:30 in India.
      expect(dayLabel(DateTime.utc(2026, 11, 17, 20, 0)), 'Wed 18 Nov');
      expect(dayLabel(DateTime.utc(2026, 11, 17, 12, 0)), 'Tue 17 Nov');
    });
  });
}
