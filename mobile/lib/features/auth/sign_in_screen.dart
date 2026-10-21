import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/phone.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import 'session_controller.dart';

/// Sign in (designs 06 and 07). The app only collects where to send the code;
/// Keycloak sends it and shows the code entry, resend and lock screens
/// in the system browser.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  Country _country = supportedCountries.first;
  int _tab = 0; // 0 phone, 1 email
  String? _fieldError;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final session = context.read<SessionController>();
    session.clearError();
    final String? hint;
    if (_tab == 0) {
      hint = toE164(_country, _phone.text);
      if (hint == null) {
        setState(() => _fieldError = 'Enter your full mobile number');
        return;
      }
    } else {
      final email = _email.text.trim();
      if (!isValidEmail(email)) {
        setState(() => _fieldError = 'Enter a valid email address');
        return;
      }
      hint = email;
    }
    setState(() => _fieldError = null);
    FocusScope.of(context).unfocus();
    await session.signIn(loginHint: hint);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final busy = session.status == SessionStatus.signingIn;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          const BrandHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 28, 26, 16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sign in', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Get a one-time code by text message or email.',
                    style: TextStyle(fontSize: 13.5, color: Brand.muted),
                  ),
                  const SizedBox(height: 16),
                  SegmentedTabs(
                    labels: const ['Phone number', 'Email'],
                    selected: _tab,
                    onChanged: busy
                        ? (_) {}
                        : (i) => setState(() {
                              _tab = i;
                              _fieldError = null;
                            }),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == 0)
                    FieldBlock(
                      label: 'Mobile number',
                      error: _fieldError,
                      child: PhoneField(
                        controller: _phone,
                        country: _country,
                        enabled: !busy,
                        error: _fieldError,
                        onCountryChanged: (c) => setState(() => _country = c),
                        onChanged: (_) => setState(() => _fieldError = null),
                      ),
                    )
                  else
                    FieldBlock(
                      label: 'Work email',
                      error: _fieldError,
                      child: AppTextField(
                        controller: _email,
                        enabled: !busy,
                        error: _fieldError,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _fieldError = null),
                        onSubmitted: (_) => _sendCode(),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const InfoBanner(
                    text:
                        "You'll open in the business unit you used last. If you work in more than one unit, switch any time from Profile.",
                    richBold: 'Profile',
                  ),
                  if (session.error != null) ...[
                    const SizedBox(height: 12),
                    InfoBanner(text: session.error!, icon: Icons.error_outline, error: true),
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
                  PillButton(label: 'Send code', loading: busy, onPressed: _sendCode),
                  const SizedBox(height: 12),
                  const Text(
                    'No account yet? Open the invite email from your administrator.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: Brand.hint, height: 1.45),
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
