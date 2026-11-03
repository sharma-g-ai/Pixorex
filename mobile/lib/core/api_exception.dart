/// An error from the API (RFC 9457 problem+json) or from the network.
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.title,
    this.detail,
    this.fieldErrors = const [],
    this.fields = const [],
    this.correlationId,
  });

  /// HTTP status; 0 when the request never reached the server.
  final int status;

  /// Last segment of the problem `type`, e.g. `invite-expired`.
  final String code;
  final String title;
  final String? detail;
  final List<FieldError> fieldErrors;

  /// Labels some 409s carry, e.g. `required-fields-empty` (docs/mobile-api.md section 3).
  final List<String> fields;
  final String? correlationId;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  /// A sentence that is safe to show the user.
  String get message => detail?.isNotEmpty == true ? detail! : title;

  factory ApiException.network() => ApiException(
        status: 0,
        code: 'network',
        title: 'No connection',
        detail: "Can't reach Pixorex. Check your connection and try again.",
      );

  factory ApiException.fromProblem(int status, Map<String, dynamic> json) {
    final type = (json['type'] as String?) ?? '';
    final errors = json['errors'];
    final fields = json['fields'];
    return ApiException(
      status: status,
      code: type.isEmpty ? 'unknown' : type.split('/').last,
      title: (json['title'] as String?) ?? 'Something went wrong',
      detail: json['detail'] as String?,
      correlationId: json['correlation_id'] as String?,
      fieldErrors: errors is List
          ? errors
              .whereType<Map<String, dynamic>>()
              .map((e) => FieldError(
                    e['field']?.toString() ?? '',
                    e['message']?.toString() ?? '',
                  ))
              .toList()
          : const [],
      fields: fields is List ? fields.map((f) => f.toString()).toList() : const [],
    );
  }

  @override
  String toString() => 'ApiException($status $code: $title)';
}

class FieldError {
  const FieldError(this.field, this.message);
  final String field;
  final String message;
}
