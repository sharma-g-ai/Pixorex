import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import 'invite_repository.dart';

enum ActivationStatus {
  loading,

  /// Invite is valid; the form is shown.
  ready,
  submitting,

  /// 409 invite-expired / invite-used / invite-cancelled: screen "Invite link expired".
  linkInvalid,

  /// The invite is for an administrator role; this app is for technicians.
  wrongRole,

  /// Could not read the invite (offline, server error). Retry is offered.
  loadFailed,

  /// Accepted. [ActivationController.signInHint] is ready for Keycloak.
  accepted,
}

class ActivationFormErrors {
  const ActivationFormErrors({this.name, this.phone});
  final String? name;
  final String? phone;
  bool get hasAny => name != null || phone != null;
}

class ActivationController extends ChangeNotifier {
  ActivationController({required InviteRepository repository, required this.token})
      : _repo = repository;

  final InviteRepository _repo;
  final String token;

  ActivationStatus _status = ActivationStatus.loading;
  InvitePreview? _preview;
  String? _message;
  String? _signInHint;
  String? _linkProblem;

  ActivationStatus get status => _status;
  InvitePreview? get preview => _preview;

  /// Error text for a failed accept or for the load-failed screen.
  String? get message => _message;

  /// `invite-expired`, `invite-used`, `invite-cancelled` or `invite-invalid`.
  String? get linkProblem => _linkProblem;

  /// login_hint for Keycloak: the phone for technicians (verify_phone), else the email.
  String? get signInHint => _signInHint;

  Future<void> load() async {
    _status = ActivationStatus.loading;
    _message = null;
    notifyListeners();
    try {
      final p = await _repo.preview(token);
      _preview = p;
      _status = p.isTechnician ? ActivationStatus.ready : ActivationStatus.wrongRole;
    } on ApiException catch (e) {
      if (e.status == 409 || e.status == 404) {
        _linkProblem = e.code;
        _status = ActivationStatus.linkInvalid;
      } else if (e.status == 400) {
        // A token the server cannot read is as good as an expired link.
        _linkProblem = 'invite-invalid';
        _status = ActivationStatus.linkInvalid;
      } else {
        _message = e.message;
        _status = ActivationStatus.loadFailed;
      }
    }
    notifyListeners();
  }

  /// Validates and submits. Returns field errors, or null when it went through
  /// (check [status] for the outcome).
  ///
  /// [phoneE164] is the number already formatted by `toE164`; null means incomplete.
  Future<ActivationFormErrors?> submit({required String fullName, required String? phoneE164}) async {
    final errors = ActivationFormErrors(
      name: fullName.trim().isEmpty ? 'Enter your full name' : null,
      phone: phoneE164 == null ? 'Enter a complete mobile number' : null,
    );
    if (errors.hasAny) return errors;

    _status = ActivationStatus.submitting;
    _message = null;
    notifyListeners();
    try {
      final accepted = await _repo.accept(
        token: token,
        fullName: fullName.trim(),
        phoneNumber: phoneE164!,
      );
      _signInHint = accepted.nextStep == NextStep.verifyPhone ? phoneE164 : _preview!.email;
      _status = ActivationStatus.accepted;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      if (e.status == 409) {
        _linkProblem = e.code;
        _status = ActivationStatus.linkInvalid;
        notifyListeners();
        return null;
      }
      _status = ActivationStatus.ready;
      _message = e.message;
      String? firstFor(String key) {
        for (final f in e.fieldErrors) {
          if (f.field.contains(key)) return f.message;
        }
        return null;
      }

      notifyListeners();
      return ActivationFormErrors(name: firstFor('name'), phone: firstFor('phone'));
    }
  }
}
