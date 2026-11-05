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
import 'features/home/home_screen.dart';
import 'core/secure_store.dart';
import 'core/api_exception.dart';
import 'features/scan/location_pick.dart';
import 'features/scan/my_scans_screen.dart';
import 'features/scan/new_scan_flow.dart';
import 'features/scan/photo_source.dart';
import 'features/scan/rejection_screens.dart';
import 'features/scan/scan_models.dart' show MyScan;
import 'features/scan/scan_repository.dart';

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
  const PixorexApp({
    super.key,
    required this.invites,
    required this.linkSource,
    this.photoSource,
    this.store = const PlatformSecureStore(),
  });
  final InviteRepository invites;
  final LinkSource linkSource;

  /// The camera; tests pass a fake. Defaults to the phone's camera and gallery.
  final PhotoSource Function()? photoSource;

  /// Where small per-phone settings live (the last location per unit).
  final SecureStore store;

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
      home: _AuthGate(photoSource: widget.photoSource ?? DevicePhotoSource.new, store: widget.store),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.photoSource, required this.store});
  final PhotoSource Function() photoSource;
  final SecureStore store;

  @override
  Widget build(BuildContext context) {
    final status = context.select<SessionController, SessionStatus>((s) => s.status);
    return switch (status) {
      SessionStatus.restoring => const SplashScreen(),
      SessionStatus.signedIn => _signedIn(context),
      SessionStatus.signedOut || SessionStatus.signingIn => const SignInScreen(),
    };
  }

  Widget _signedIn(BuildContext context) {
    final session = context.read<SessionController>();
    final scans = ScanRepository(session.api);
    final unit = session.me == null ? null : activeUnit(session.me!);
    final buId = unit?.buId;
    if (buId == null) return HomeShell(scans: scans);
    final nav = Navigator.of(context);
    late final Future<bool> Function(MyScan old) retake;

    NewScanFlow flow({RetakeOf? retakeOf}) => NewScanFlow(
          scans: scans,
          lastLocations: LastLocationStore(store, userId: session.me!.userId),
          photoSource: photoSource,
          buId: buId,
          unitName: unit!.name ?? '',
          tenantName: session.me!.tenantName,
          retakeOf: retakeOf,
          onMyScans: retakeOf == null ? () => openMyScans(nav, scans, unit.name ?? '', retake) : null,
        );
    retake = retakeWith(nav, scans, flow, photoSource);

    return HomeShell(
      scans: scans,
      onNewScan: () => nav.push(MaterialPageRoute<void>(builder: (_) => flow())),
      onMyScans: ({String? tab}) => openMyScans(nav, scans, unit!.name ?? '', retake, tab: tab),
      onRetake: retake,
    );
  }
}

/// My Scans, with Retake replacing a scan by a new one.
Future<void> openMyScans(
  NavigatorState nav,
  ScanRepository scans,
  String unitName,
  Future<bool> Function(MyScan old) retake, {
  String? tab,
}) =>
    nav.push(MaterialPageRoute<void>(
      builder: (context) => MyScansScreen(scans: scans, unitName: unitName, initialTab: tab, onRetake: retake),
    ));

/// Retake [old] for its type and place: a rejected scan gets one photo and a confirm
/// (design 71-72), a failed one the full capture flow (design 65). True once sent.
Future<bool> Function(MyScan old) retakeWith(
  NavigatorState nav,
  ScanRepository scans,
  NewScanFlow Function({RetakeOf? retakeOf}) flow,
  PhotoSource Function() photoSource,
) =>
    (old) async {
          try {
            final scan = await scans.scan(old.scanId);
            final type = (await scans.equipmentTypes(scan.buId)).where((t) => t.typeId == scan.equipmentTypeId).firstOrNull;
            if (type == null) {
              throw ApiException(
                status: 409,
                code: 'type-not-published',
                title: '${scan.equipmentTypeName} is no longer set up for this unit. Ask your BU Admin.',
              );
            }
            if (scan.reviewStatus == 'rejected') {
              final sent = await nav.push<bool>(MaterialPageRoute(
                builder: (_) => RejectedRetakeScreen(scans: scans, old: scan, type: type, photoSource: photoSource),
              ));
              return sent == true;
            }
            final sent = await nav.push<bool>(MaterialPageRoute(
              builder: (_) => flow(
                retakeOf: RetakeOf(
                  scanId: scan.scanId,
                  name: scan.equipmentTypeName,
                  type: type,
                  locationNodeId: scan.locationNodeId,
                ),
              ),
            ));
            return sent == true;
          } on ApiException catch (e) {
            if (nav.mounted) ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(SnackBar(content: Text(e.message)));
            return false;
          }
        };
