import 'package:flutter/services.dart';

class Country {
  const Country(this.dialCode, this.nationalLength);
  final String dialCode;
  final int nationalLength;
}

const supportedCountries = [Country('+1', 10), Country('+91', 10)];

/// Returns the E.164 number (e.g. `+12165550148`), or null when [input] is not a
/// complete national number for [country].
String? toE164(Country country, String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length != country.nationalLength) return null;
  return '${country.dialCode}$digits';
}

/// "+12165550148" -> "+1 ••• ••• 0148" (never show a whole number on screen).
String maskPhone(String e164) {
  if (e164.length < 5) return e164;
  final cc = supportedCountries.firstWhere(
    (c) => e164.startsWith(c.dialCode),
    orElse: () => const Country('+', 0),
  );
  return '${cc.dialCode} ••• ••• ${e164.substring(e164.length - 4)}';
}

/// Formats as the user types: `2165550148` -> `(216) 555-0148`.
class NationalPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 10 ? digits.substring(0, 10) : digits;
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 0) b.write('(');
      if (i == 3) b.write(') ');
      if (i == 6) b.write('-');
      b.write(d[i]);
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
bool isValidEmail(String v) => _emailPattern.hasMatch(v.trim());
