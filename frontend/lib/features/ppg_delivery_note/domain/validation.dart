/// Validation helpers for PPG article / quantity fields.
class PpgValidation {
  static final RegExp articlePattern = RegExp(r'^[0-9]{1,32}$');

  static bool isValidArticle(String value) => articlePattern.hasMatch(value);

  static bool isValidQuantity(int? value) => value != null && value >= 0;

  static String? validatePhysicalInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Quantity is required';
    if (trimmed.contains('.') || trimmed.contains(',')) {
      return 'Fractions are not supported';
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 0) return 'Negative quantities are not allowed';
    return null;
  }

  static int variance(int physical, int document) => physical - document;

  static bool requiresVarianceReason(int physical, int document) =>
      physical != document;
}
