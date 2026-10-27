/// `GET /me` (contract 1.1), the parts the app uses.
class UnitRole {
  const UnitRole({
    required this.buId,
    required this.name,
    required this.role,
    this.isPrimary = false,
    this.assignedByName,
  });
  final String? buId;
  final String? name;
  final String role;
  final bool isPrimary;

  /// Who added this person to the unit (unit switcher, design 19).
  final String? assignedByName;

  bool get isTechnician => role == 'field_technician';

  factory UnitRole.fromJson(Map<String, dynamic> j) => UnitRole(
        buId: j['bu_id'] as String?,
        name: j['name'] as String?,
        role: j['role'] as String,
        isPrimary: j['is_primary'] as bool? ?? false,
        assignedByName: j['assigned_by_name'] as String?,
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
    this.phoneNumber,
    this.activeBuId,
    this.lastBuId,
  });

  final String userId;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String status;
  final String tenantName;
  final List<UnitRole> units;
  final String? activeBuId;
  final String? lastBuId;

  /// This app is for technicians only (ARCHITECTURE 2: Mobile app).
  bool get isTechnician => units.any((u) => u.isTechnician);

  /// One entry per unit; a unit is listed once even if the API sent it twice.
  List<UnitRole> get technicianUnits {
    final seen = <String?>{};
    return [for (final u in units) if (u.isTechnician && u.buId != null && seen.add(u.buId)) u];
  }

  /// The active unit, only when this person is a technician there.
  UnitRole? get activeUnit {
    for (final u in technicianUnits) {
      if (u.buId == activeBuId) return u;
    }
    return null;
  }

  /// Where a technician should be working when [activeUnit] is null: the API chooses the
  /// last unit used on any app, which for someone who is also a BU Admin can be a unit
  /// where they are only an admin. Last technician unit used, else primary, else the first.
  UnitRole? get preferredTechnicianUnit {
    final units = technicianUnits;
    if (units.isEmpty) return null;
    for (final u in units) {
      if (u.buId == lastBuId) return u;
    }
    for (final u in units) {
      if (u.isPrimary) return u;
    }
    return units.first;
  }

  /// "Jorge Martinez" -> "Jorge".
  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  /// "Jorge Martinez" -> "J. Martinez" (Home header, design 13).
  String get shortName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return fullName.trim();
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }

  /// "Jorge Martinez" -> "JM".
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return '$first$last'.toUpperCase();
  }

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String,
        email: j['email'] as String,
        phoneNumber: j['phone_number'] as String?,
        status: j['status'] as String,
        tenantName: j['tenant_name'] as String,
        activeBuId: j['active_bu_id'] as String?,
        lastBuId: j['last_bu_id'] as String?,
        units: (j['units'] as List)
            .map((e) => UnitRole.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
