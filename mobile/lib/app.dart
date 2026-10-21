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
import 'features/auth/signed_in_placeholder.dart';
import 'features/auth/splash_screen.dart';

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

class _PixorexAppState extends State<PixorexApp> {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _sub;
  String? _openToken;

  @override
  void initState() {
    super.initState();
    _sub = widget.linkSource.links.listen(_onLink);
    widget.linkSource.initialLink().then((u) {
      if (u != null) _onLink(u);
    });
    context.read<SessionController>().restore();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
      SessionStatus.signedIn => const SignedInPlaceholder(),
      SessionStatus.signedOut || SessionStatus.signingIn => const SignInScreen(),
    };
  }
}
