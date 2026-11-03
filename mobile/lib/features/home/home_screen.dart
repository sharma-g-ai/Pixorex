import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../auth/me.dart';
import '../auth/session_controller.dart';
import '../scan/scan_models.dart';
import '../scan/scan_repository.dart';
import '../scan/scan_status.dart';

/// Signed-in shell: Home (design 13/14) and Profile (design 15, sign-out part).
/// My Scans and the offline Queue tab come with their own tasks.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.scans, this.onNewScan});
  final ScanRepository scans;

  /// Opens New scan (design 30); the green button is hidden until it is wired.
  final VoidCallback? onNewScan;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().me;
    return Scaffold(
      backgroundColor: Brand.surface,
      body: Column(children: [
        Container(
          height: 56 + MediaQuery.paddingOf(context).top,
          padding: EdgeInsets.only(left: 18, top: MediaQuery.paddingOf(context).top),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(gradient: Brand.headerGradient),
          child: Image.asset('assets/pixorex_wordmark_white.png', height: 22, semanticLabel: 'Pixorex'),
        ),
        if (me != null) _UserStrip(me),
        Expanded(child: _tab == 0 ? HomeTab(scans: widget.scans, onNewScan: widget.onNewScan) : _Profile(me)),
      ]),
      floatingActionButton: _tab == 0 && widget.onNewScan != null
          ? FloatingActionButton(
              tooltip: 'New scan',
              backgroundColor: const Color(0xFF3C9F40),
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              onPressed: widget.onNewScan,
              child: const Icon(Icons.photo_camera_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        height: 64,
        // Design 14: no pill behind the active tab, navy label and icon instead.
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 10.5,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
              color: s.contains(WidgetState.selected) ? Brand.navy : Brand.hint,
            )),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined, color: Brand.hint),
              selectedIcon: Icon(Icons.home_outlined, color: Brand.navy),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.person_outline, color: Brand.hint),
              selectedIcon: Icon(Icons.person_outline, color: Brand.navy),
              label: 'Profile'),
        ],
      ),
    );
  }
}

String initials(String name) =>
    name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

/// The unit the API resolves calls to (`active_bu_id`), else the first technician unit.
UnitRole? activeUnit(Me me) =>
    me.technicianUnits.where((u) => u.buId == me.activeBuId).firstOrNull ?? me.technicianUnits.firstOrNull;

String unitName(Me me) => activeUnit(me)?.name ?? '';

class _UserStrip extends StatelessWidget {
  const _UserStrip(this.me);
  final Me me;

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: Brand.navy,
            child: Text(initials(me.fullName),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.fullName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text('Field Technician · ${unitName(me)}', style: const TextStyle(fontSize: 11, color: Brand.hint)),
            ]),
          ),
        ]),
      );
}

class HomeData {
  const HomeData({required this.needsAction, required this.today, required this.latest});
  final List<MyScan> needsAction;
  final List<MyScan> today;
  final List<MyScan> latest;
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.scans, this.onNewScan, this.clock = DateTime.now});
  final ScanRepository scans;
  final VoidCallback? onNewScan;
  final DateTime Function() clock;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  HomeData? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        widget.scans.myScans(tab: 'needs_action', limit: 100),
        widget.scans.myScans(from: widget.clock(), limit: 100),
        widget.scans.myScans(limit: 4),
      ]);
      if (!mounted) return;
      setState(() {
        _data = HomeData(needsAction: r[0].items, today: r[1].items, latest: r[2].items);
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TypeError {
      // A reply that doesn't match the contract: say so instead of a red screen.
      if (mounted) setState(() => _error = "Couldn't load your scans. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              InfoBanner(text: _error!, error: true),
              const SizedBox(height: 12),
              PillButton(label: 'Try again', outlined: true, onPressed: _load),
            ]));
    }
    final me = context.read<SessionController>().me;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
        children: data.latest.isEmpty
            ? _firstTime(me?.fullName.split(' ').first ?? '')
            : _returning(data),
      ),
    );
  }

  List<Widget> _firstTime(String firstName) => [
        Text('Welcome, $firstName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text("You haven't scanned anything yet. Here's how a scan works:",
            style: TextStyle(fontSize: 13, color: Brand.body)),
        const SizedBox(height: 12),
        for (final (i, (title, text)) in _steps.indexed) _Step(i + 1, title, text),
        if (widget.onNewScan != null) ...[
          const SizedBox(height: 16),
          PillButton(label: 'Start your first scan', onPressed: widget.onNewScan),
        ],
      ];

  static const _steps = [
    ('Pick the equipment type', 'Choose what you\'re scanning — only types set up for your unit are listed.'),
    ('Photograph the nameplate', 'Fill the frame and hold steady. Add a second photo for worn text.'),
    ('Confirm the location', 'Pick the shop, bin and sub-bin, then submit. We remember it for next time.'),
    ('Check it in My Scans', 'Text is read in the background. Review anything flagged before it goes to a reviewer.'),
  ];

  List<Widget> _returning(HomeData d) {
    final needs = d.needsAction;
    final review = needs.where((s) => s.reviewStatus == 'draft' && s.processingStatus == 'ready_to_review').length;
    final rejected = needs.where((s) => s.reviewStatus == 'rejected').length;
    final failed = needs.length - review - rejected;
    final now = widget.clock();
    return [
      if (needs.isNotEmpty)
        _ActionCard(
          count: needs.length,
          title: '${needs.length} scan${needs.length == 1 ? '' : 's'} need${needs.length == 1 ? 's' : ''} your action',
          detail: [
            if (review > 0) '$review to review',
            if (rejected > 0) '$rejected rejected',
            if (failed > 0) '$failed failed',
          ].join(' · '),
        ),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        const Expanded(child: Text('Today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        Text(dayLabel(now), style: const TextStyle(fontSize: 11.5, color: Brand.hint)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _Stat('${d.today.length}', 'Scanned', Brand.ink),
        const SizedBox(width: 8),
        _Stat('${d.today.where((s) => const {'waiting_for_approval', 'approved', 'rejected'}.contains(s.reviewStatus)).length}',
            'Submitted', Brand.navy),
        const SizedBox(width: 8),
        _Stat('${d.today.where((s) => s.reviewStatus == 'approved').length}', 'Approved', const Color(0xFF2C7A30)),
      ]),
      const SizedBox(height: 16),
      const Text('LATEST SCANS',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Brand.muted)),
      const SizedBox(height: 10),
      for (final s in d.latest) ScanRow(s, now: now),
    ];
  }
}

/// "Thu 1 Oct", as on design 14.
String dayLabel(DateTime d) =>
    '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} ${d.day} '
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

/// "4 min ago", "1 hr ago", "3 days ago".
String ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} hr ago';
  return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
}

class ScanRow extends StatelessWidget {
  const ScanRow(this.scan, {super.key, required this.now});
  final MyScan scan;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final look = ScanStatusLook.of(scan.processingStatus, scan.reviewStatus);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: look.needsAction
            ? Border.all(color: Brand.warn, width: 1.5)
            : Border.all(color: Brand.lineSoft),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: const Color(0xFF1F1F23), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.qr_code_scanner, size: 18, color: Colors.white54),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(scan.equipmentTypeName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            Text('${scan.place} · ${ago(scan.updatedAt, now)}', style: const TextStyle(fontSize: 11, color: Brand.hint)),
          ]),
        ),
        ScanStatusPill(look),
      ]),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.count, required this.title, required this.detail});
  final int count;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Brand.warnBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF0C68A), width: 1.5),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: Brand.warn,
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF8B3E0C))),
              Text(detail, style: const TextStyle(fontSize: 11, color: Color(0xFF8B3E0C))),
            ]),
          ),
        ]),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Brand.lineSoft),
          ),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: const TextStyle(fontSize: 10.5, color: Brand.muted)),
          ]),
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step(this.no, this.title, this.text);
  final int no;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: Brand.info,
            child: Text('$no', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.navy)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text(text, style: const TextStyle(fontSize: 12, color: Brand.body)),
            ]),
          ),
        ]),
      );
}

/// Design 15, the parts that work today: who you are, your unit, sign out.
class _Profile extends StatelessWidget {
  const _Profile(this.me);
  final Me? me;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        Text(me?.fullName ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        Text(me?.email ?? '', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
        const SizedBox(height: 16),
        const Text('SIGNED IN TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.muted)),
        Text(me == null ? '' : unitName(me!), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        PillButton(label: 'Sign out', outlined: true, onPressed: () => context.read<SessionController>().signOut()),
      ]);
}
