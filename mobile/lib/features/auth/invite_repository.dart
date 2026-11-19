import '../../core/api_client.dart';

class InviteUnit {
  const InviteUnit({required this.buId, required this.name});
  final String buId;
  final String name;
}

/// `POST /invites/preview` (contract 1.6).
class InvitePreview {
  const InvitePreview({
    required this.role,
    required this.email,
    required this.units,
    required this.invitedByName,
    required this.expiresAt,
  });

  final String role;
  final String email;
  final List<InviteUnit> units;
  final String invitedByName;
  final DateTime expiresAt;

  bool get isTechnician => role == 'field_technician';

  factory InvitePreview.fromJson(Map<String, dynamic> j) => InvitePreview(
        role: j['role'] as String,
        email: j['email'] as String,
        invitedByName: j['invited_by_name'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        units: (j['units'] as List)
            .map((u) => InviteUnit(
                  buId: (u as Map<String, dynamic>)['bu_id'] as String,
                  name: u['name'] as String,
                ))
            .toList(),
      );
}

/// `POST /invites/accept` (contract 1.7). The next step is always the email code.
class InviteAccepted {
  const InviteAccepted({required this.userId});
  final String userId;
}

class InviteRepository {
  InviteRepository(this._api);
  final ApiClient _api;

  Future<InvitePreview> preview(String token) async {
    final json = await _api.post('/invites/preview', body: {'token': token}, authenticated: false);
    return InvitePreview.fromJson(json);
  }

  /// The name only: everyone signs in by email (phone numbers removed on 19 Nov 2026).
  Future<InviteAccepted> accept({required String token, required String fullName}) async {
    final json = await _api.post(
      '/invites/accept',
      body: {'token': token, 'full_name': fullName},
      authenticated: false,
    );
    return InviteAccepted(userId: json['user_id'] as String);
  }
}
