final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Everyone signs in with their email (phone sign-in was removed on 19 Nov 2026).
bool isValidEmail(String v) => _emailPattern.hasMatch(v.trim());
