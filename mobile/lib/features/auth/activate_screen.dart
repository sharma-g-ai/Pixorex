import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/phone.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import 'activation_controller.dart';
import 'invite_expired_screen.dart';
import 'session_controller.dart';

/// Activate account from invite (design 03). Loads the invite (contract 1.6),
/// accepts it (1.7), then hands over to Keycloak, which texts the code.
class ActivateScreen extends StatefulWidget {
  const ActivateScreen({super.key, required this.controller});
  final ActivationController controller;

  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  Country _country = supportedCountries.first;
  ActivationFormErrors? _errors;
  bool _signInFailed = false;

  ActivationController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _c.load();
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _activate() async {
    FocusScope.of(context).unfocus();
    final session = context.read<SessionController>();
    final errors = await _c.submit(
      fullName: _name.text,
      phoneE164: toE164(_country, _phone.text),
    );
    if (!mounted) return;
    setState(() => _errors = errors);
    if (_c.status == ActivationStatus.accepted) await _continueToSignIn(session);
  }

  /// Keycloak texts the code and shows its own verify screen.
  Future<void> _continueToSignIn(SessionController session) async {
    setState(() => _signInFailed = false);
    final ok = await session.signIn(loginHint: _c.signInHint);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      setState(() => _signInFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_c.status) {
      case ActivationStatus.linkInvalid:
        return InviteExpiredScreen(problem: _c.linkProblem ?? 'invite-expired');
      case ActivationStatus.loading:
        return const _Frame(child: Center(child: CircularProgressIndicator()));
      case ActivationStatus.loadFailed:
        return _Frame(
          child: _Message(
            title: "Couldn't open your invite",
            body: _c.message ?? 'Please try again.',
            action: PillButton(label: 'Try again', onPressed: _c.load),
          ),
        );
      case ActivationStatus.wrongRole:
        return _Frame(
          child: _Message(
            title: 'This app is for field technicians',
            body: 'Your invite is for an administrator account. Open the invite on a computer to use the web dashboard.',
            action: PillButton(
              label: 'Back to sign in',
              outlined: true,
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ),
        );
      case ActivationStatus.ready:
      case ActivationStatus.submitting:
      case ActivationStatus.accepted:
        return _form(context);
    }
  }

  Widget _form(BuildContext context) {
    final preview = _c.preview!;
    final session = context.watch<SessionController>();
    final accepted = _c.status == ActivationStatus.accepted;
    final working = _c.status == ActivationStatus.submitting || session.status == SessionStatus.signingIn;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          const BrandHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Activate your account', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    "You've been added to Pixorex as a Field Technician. Check your details, then activate.",
                    style: TextStyle(fontSize: 13.5, color: Brand.muted, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  FieldBlock(
                    label: 'Full name',
                    error: _errors?.name,
                    child: AppTextField(
                      controller: _name,
                      enabled: !accepted && !working,
                      error: _errors?.name,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() => _errors = null),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FieldBlock(label: 'Work email', child: LockedField(value: preview.email)),
                  const SizedBox(height: 12),
                  FieldBlock(
                    label: 'Mobile number',
                    error: _errors?.phone,
                    help: "We'll text a code to this number to verify it. Later you can sign in with this number or your email.",
                    child: PhoneField(
                      controller: _phone,
                      country: _country,
                      enabled: !accepted && !working,
                      error: _errors?.phone,
                      onCountryChanged: (c) => setState(() => _country = c),
                      onChanged: (_) => setState(() => _errors = null),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Your business units', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final unit in preview.units)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Brand.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Brand.lineSoft),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(unit.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          Text('Assigned by ${preview.invitedByName}', style: const TextStyle(fontSize: 11, color: Brand.hint)),
                        ],
                      ),
                    ),
                  if (_c.message != null && !accepted) ...[
                    const SizedBox(height: 4),
                    InfoBanner(text: _c.message!, icon: Icons.error_outline, error: true),
                  ],
                  if (_signInFailed) ...[
                    const SizedBox(height: 4),
                    InfoBanner(
                      text: session.error ??
                          'Your account is activated. Finish verifying your number to sign in.',
                      icon: session.error != null ? Icons.error_outline : Icons.check_circle_outline,
                      error: session.error != null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 8, 26, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PillButton(
                    label: accepted ? 'Verify and sign in' : 'Activate account',
                    loading: working,
                    onPressed: accepted ? () => _continueToSignIn(context.read<SessionController>()) : _activate,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This invite link expires 24 hours after it was sent',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Brand.hint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Column(children: [const BrandHeader(), Expanded(child: child)]));
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body, required this.action});
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Brand.body, height: 1.55)),
          const SizedBox(height: 24),
          action,
        ],
      ),
    );
  }
}
