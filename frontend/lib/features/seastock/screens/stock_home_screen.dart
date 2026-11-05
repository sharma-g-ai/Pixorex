import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../branding/app_brand.dart';
import '../../ppg_delivery_note/screens/ppg_hub_screen.dart';
import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_navigation.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../domain/stock.dart';
import '../domain/vessels.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';
import 'audit_screens.dart';
import 'checkout_records_screen.dart';
import 'inventory_screen.dart';
import 'transactions_screen.dart';

/// Seastock Home: stock on board for one vessel, the three stock records
/// (Inventory, Transactions, Audit), and the two daily jobs at the bottom:
/// Check in (delivery notes) and Check out (scan cans).
class StockHomeScreen extends StatefulWidget {
  const StockHomeScreen({super.key, this.operatorEmail, this.controller});

  final String? operatorEmail;

  /// Injected in tests; the screen creates and owns one otherwise.
  final SeastockController? controller;

  @override
  State<StockHomeScreen> createState() => _StockHomeScreenState();
}

class _StockHomeScreenState extends State<StockHomeScreen> {
  late final SeastockController _ctrl;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _ctrl = widget.controller ?? SeastockController();
    _ctrl.operatorEmail = widget.operatorEmail;
    if (_owns) _ctrl.init();
  }

  @override
  void didUpdateWidget(StockHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ctrl.operatorEmail = widget.operatorEmail;
  }

  @override
  void dispose() {
    if (_owns) _ctrl.dispose();
    super.dispose();
  }

  Future<void> _chooseVessel() async {
    final picked = await showSeastockSheet<Vessel>(
      context,
      SeastockVesselSheet(controller: _ctrl),
    );
    if (picked == null || !mounted) return;
    await ppgRun(context, () => _ctrl.selectVessel(picked));
  }

  Future<void> _checkIn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: ppgHubRouteName),
        builder: (_) => PpgHubScreen(
          operatorEmail: widget.operatorEmail,
          vesselId: _ctrl.vessel.id,
          vesselName: _ctrl.vessel.name,
        ),
      ),
    );
    // A submitted delivery note adds stock.
    if (mounted) await _ctrl.refresh();
  }

  Future<void> _checkOut() => startCheckout(context, _ctrl);

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _ctrl,
    child: PpgThemed(
      child: Consumer<SeastockController>(
        builder: (context, ctrl, _) => Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(ctrl),
              Expanded(child: _body(ctrl)),
            ],
          ),
          bottomNavigationBar: PpgBottomBar(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _bigButton(
                      key: const ValueKey('seastock-check-in'),
                      icon: Icons.download_outlined,
                      label: 'Check in',
                      sublabel: 'Delivery note',
                      color: PpgColors.navy,
                      onPressed: ctrl.ready ? _checkIn : null,
                    ),
                  ),
                  const SizedBox(width: PpgSpace.m),
                  Expanded(
                    child: _bigButton(
                      key: const ValueKey('seastock-check-out'),
                      icon: Icons.upload_outlined,
                      label: 'Check out',
                      sublabel: ctrl.stock.total == 0
                          ? 'Nothing on board'
                          : 'Scan cans',
                      color: PpgColors.blue,
                      onPressed: ctrl.ready && ctrl.stock.total > 0
                          ? _checkOut
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header(SeastockController ctrl) =>
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Material(
          color: PpgColors.navy,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                children: [
                  Semantics(
                    label: AppBrand.name,
                    image: true,
                    child: Image.asset(
                      AppBrand.wordmarkOnDark,
                      width: 150,
                      height: 42,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: 'Vessel: ${ctrl.vessel.name}. Change vessel',
                    excludeSemantics: true,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(PpgRadii.medium),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('seastock-vessel'),
                        onTap: ctrl.ready ? _chooseVessel : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 44,
                            maxWidth: 180,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.directions_boat_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: PpgSpace.s),
                                Flexible(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Vessel',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: PpgColors.onNavyMuted,
                                        ),
                                      ),
                                      Text(
                                        ctrl.vessel.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: PpgSpace.xs),
                                const Icon(
                                  Icons.expand_more,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _body(SeastockController ctrl) {
    if (!ctrl.ready) {
      if (ctrl.error == null) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading stock'),
        );
      }
      return PpgEmptyState(
        icon: Icons.error_outline,
        title: 'Stock could not be opened',
        message: ctrl.error!,
        action: FilledButton(onPressed: ctrl.init, child: const Text('Retry')),
      );
    }
    return RefreshIndicator(
      onRefresh: ctrl.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _summary(ctrl.stock),
          const SizedBox(height: PpgSpace.l),
          const PpgSectionLabel('Stock records'),
          const SizedBox(height: PpgSpace.s),
          PpgPanel(
            child: Column(
              children: ppgDivided([
                _recordRow(
                  key: const ValueKey('seastock-inventory'),
                  icon: Icons.inventory_2_outlined,
                  iconTone: PpgTone.info,
                  title: 'Inventory',
                  subtitle: 'Every article and how many are on board',
                  onTap: () => seastockPush<void>(
                    context,
                    ctrl,
                    const InventoryScreen(),
                  ),
                ),
                _recordRow(
                  key: const ValueKey('seastock-transactions'),
                  icon: Icons.swap_vert,
                  iconTone: PpgTone.info,
                  title: 'Transactions',
                  subtitle: _latestTransaction(ctrl),
                  onTap: () => seastockPush<void>(
                    context,
                    ctrl,
                    const TransactionsScreen(),
                  ),
                ),
                _recordRow(
                  key: const ValueKey('seastock-audit'),
                  icon: Icons.fact_check_outlined,
                  iconTone: PpgTone.warning,
                  title: 'Audit',
                  subtitle: _auditStatus(ctrl),
                  onTap: () =>
                      seastockPush<void>(context, ctrl, const AuditScreen()),
                ),
              ]),
            ),
          ),
          if (ctrl.stock.items.isEmpty) ...[
            const SizedBox(height: PpgSpace.l),
            PpgHint(
              'No stock on ${ctrl.vessel.name} yet. Check in a delivery note to add stock.',
            ),
          ],
        ],
      ),
    );
  }

  static String _latestTransaction(SeastockController ctrl) {
    final checkIn = ctrl.checkIns.firstOrNull;
    final checkout = ctrl.checkouts.firstOrNull;
    if (checkIn != null &&
        (checkout == null || checkIn.submittedAt.isAfter(checkout.createdAt))) {
      final dn = checkIn.deliveryNoteNumber;
      return 'Latest: check-in${dn == null ? '' : ' DN $dn'}, ${ppgRelative(checkIn.submittedAt)}';
    }
    if (checkout != null) {
      return 'Latest: check-out ${checkout.reference}, ${ppgRelative(checkout.createdAt)}';
    }
    return 'Check-ins and check-outs';
  }

  static String _auditStatus(SeastockController ctrl) {
    if (ctrl.audit != null) return 'Audit in progress · tap to resume';
    final waiting = ctrl.waitingAudits;
    if (waiting > 0) {
      return '${ppgPlural(waiting, 'report')} waiting for approval';
    }
    final last = ctrl.audits.firstOrNull;
    if (last != null) return 'Last audited ${ppgRelative(last.createdAt)}';
    return 'Count what is on board';
  }

  Widget _recordRow({
    required Key key,
    required IconData icon,
    required PpgTone iconTone,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => PpgRow(
    key: key,
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconTone == PpgTone.info
            ? const Color(0xFFE8EEF8)
            : iconTone.background,
        borderRadius: BorderRadius.circular(PpgRadii.medium),
      ),
      child: Icon(
        icon,
        size: 22,
        color: iconTone == PpgTone.info ? PpgColors.navy : iconTone.foreground,
      ),
    ),
    title: title,
    subtitle: subtitle,
    onTap: onTap,
  );

  Widget _summary(StockSnapshot stock) => PpgPanel(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
    child: Semantics(
      label:
          'Stock on board: ${stock.total} PC, ${ppgPlural(stock.articlesOnBoard, 'article')}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('STOCK ON BOARD', style: PpgText.sectionLabel),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    style: PpgText.figures(size: 50, color: PpgColors.navy),
                    children: [
                      TextSpan(text: '${stock.total}'),
                      const TextSpan(
                        text: ' PC',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: PpgColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  ppgPlural(stock.articlesOnBoard, 'article'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  stock.lastChange == null
                      ? 'Nothing checked in'
                      : 'Updated ${ppgRelative(stock.lastChange!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PpgColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _bigButton({
    required Key key,
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback? onPressed,
  }) => FilledButton(
    key: key,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      minimumSize: const Size.fromHeight(64),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
