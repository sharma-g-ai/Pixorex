import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/invite_link.dart';
import 'core/theme.dart';
import 'features/auth/activate_screen.dart';
import 'features/auth/activation_controller.dart';
import 'features/auth/invite_repository.dart';
import 'features/auth/session_controller.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/home/home_shell.dart';

/// Source of links that open the app (invite links). A seam so tests can fake it.
abstract class LinkSource {
  Future<Uri?> initialLink();
  Stream<Uri> get links;
}

class AppLinksSource implements LinkSource {
  final _links = AppLinks();
  @override
  Future<Uri?> initialLink() => _links.getInitialLink();
  @override
  Stream<Uri> get links => _links.uriLinkStream;
}

class PixorexApp extends StatefulWidget {
  const PixorexApp({super.key, required this.invites, required this.linkSource});
  final InviteRepository invites;
  final LinkSource linkSource;

  @override
  State<PixorexApp> createState() => _PixorexAppState();
}

class _PixorexAppState extends State<PixorexApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _sub;
  String? _openToken;
  late final SessionController _session;
  SessionStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = widget.linkSource.links.listen(_onLink);
    final session = _session = context.read<SessionController>();
    session.addListener(_onSession);
    final restored = session.restore();
    widget.linkSource.initialLink().then((u) async {
      await restored;
      // After Android restarts the app mid-sign-in it replays the invite link that launched
      // it; that invite is already used, so the resumed sign-in's home screen stays.
      if (u != null && !session.resumedSignIn) _onLink(u);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    _sub?.cancel();
    super.dispose();
  }

  /// Signed out while working (access removed, session ended): close any sheet or page
  /// left over the signed-in screens so the sign-in screen and its message show.
  void _onSession() {
    final status = _session.status;
    if (_lastStatus == SessionStatus.signedIn && status == SessionStatus.signedOut) {
      _navigator.currentState?.popUntil((r) => r.isFirst);
    }
    _lastStatus = status;
  }

  /// Back in the foreground: pick up unit or access changes made meanwhile (contract 1.19).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<SessionController>().refresh();
  }

  void _onLink(Uri uri) {
    final token = parseInviteToken(uri);
    if (token == null || token == _openToken) return;
    _openToken = token;
    // Wait a frame so a link that launched the app finds a mounted navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _navigator.currentState;
      if (nav == null) return;
      nav.push(MaterialPageRoute<void>(
        builder: (_) => ActivateScreen(
          controller: ActivationController(repository: widget.invites, token: token),
        ),
      )).whenComplete(() => _openToken = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixorex',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: _navigator,
      builder: (context, child) =>
          AnnotatedRegion<SystemUiOverlayStyle>(value: brandSystemBars, child: child!),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final status = context.select<SessionController, SessionStatus>((s) => s.status);
    return switch (status) {
      SessionStatus.restoring => const SplashScreen(),
      SessionStatus.signedIn => const HomeShell(),
      SessionStatus.signedOut || SessionStatus.signingIn => const SignInScreen(),
    };
  }
}
