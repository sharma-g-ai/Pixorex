/// `GET /me` (contract 1.1), only the parts the sign-in flow needs.
class UnitRole {
  const UnitRole({required this.buId, required this.name, required this.role});
  final String? buId;
  final String? name;
  final String role;

  factory UnitRole.fromJson(Map<String, dynamic> j) => UnitRole(
        buId: j['bu_id'] as String?,
        name: j['name'] as String?,
        role: j['role'] as String,
      );
}

class Me {
  const Me({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.status,
    required this.tenantName,
    required this.units,
    this.activeBuId,
  });

  final String userId;
  final String fullName;
  final String email;
  final String status;
  final String tenantName;
  final List<UnitRole> units;
  final String? activeBuId;

  /// This app is for technicians only (ARCHITECTURE 2: Mobile app).
  bool get isTechnician => units.any((u) => u.role == 'field_technician');

  Iterable<UnitRole> get technicianUnits => units.where((u) => u.role == 'field_technician');

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String,
        email: j['email'] as String,
        status: j['status'] as String,
        tenantName: j['tenant_name'] as String,
        activeBuId: j['active_bu_id'] as String?,
        units: (j['units'] as List)
            .map((e) => UnitRole.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
