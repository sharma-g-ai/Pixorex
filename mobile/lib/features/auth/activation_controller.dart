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
  const ActivationFormErrors({this.name});
  final String? name;
  bool get hasAny => name != null;
}

const _deadLinkCodes = {'invite-expired', 'invite-used', 'invite-cancelled'};

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

  /// login_hint for Keycloak: the invited email (everyone signs in by email).
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
  Future<ActivationFormErrors?> submit({required String fullName}) async {
    final errors = ActivationFormErrors(name: fullName.trim().isEmpty ? 'Enter your full name' : null);
    if (errors.hasAny) return errors;

    _status = ActivationStatus.submitting;
    _message = null;
    notifyListeners();
    try {
      await _repo.accept(token: token, fullName: fullName.trim());
      _signInHint = _preview!.email;
      _status = ActivationStatus.accepted;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      // Only a dead link replaces the form. Other 409s (email-in-use, unit-has-bu-admin;
      // contract 1.7) need the admin, so the form stays with the server's message.
      if (e.status == 409 && _deadLinkCodes.contains(e.code)) {
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
      return ActivationFormErrors(name: firstFor('name'));
    }
  }
}
