import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../domain/stock.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';
import 'audit_scanner_screen.dart';

/// Audit page: what an audit is, this vessel's audit reports, and the way in
/// to a new count (or back to an unfinished one).
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  Future<void> _open(BuildContext context, SeastockController ctrl) async {
    if (ctrl.audit == null) {
      final ok = await ppgRun(context, ctrl.startAudit);
      if (!ok || !context.mounted) return;
    }
    await seastockPush<void>(
      context,
      ctrl,
      const AuditCountScreen(),
      name: seastockAuditRouteName,
    );
  }

  @override
  Widget build(BuildContext context) => Consumer<SeastockController>(
    builder: (context, ctrl, _) {
      final inProgress = ctrl.audit != null;
      final canStart = inProgress || ctrl.auditList.isNotEmpty;
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PpgHeader(
              eyebrow: ctrl.vessel.name,
              title: 'Audit',
              backTooltip: 'Back to Home',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  if (inProgress) ...[
                    PpgBanner(
                      tone: PpgTone.info,
                      title: 'Audit in progress',
                      message:
                          '${ctrl.auditCountedArticles} of ${ctrl.auditList.length} articles counted. Your count is kept on this phone.',
                    ),
                    const SizedBox(height: PpgSpace.l),
                  ],
                  const _Steps(),
                  const SizedBox(height: PpgSpace.l),
                  const PpgSectionLabel('Audit reports'),
                  const SizedBox(height: PpgSpace.s),
                  if (ctrl.audits.isEmpty)
                    const PpgHint('No audits yet on this vessel.')
                  else
                    PpgPanel(
                      child: Column(
                        children: ppgDivided(
                          ctrl.audits.map(
                            (report) => PpgRow(
                              key: ValueKey('audit-${report.id}'),
                              title:
                                  '${ppgRelative(report.createdAt)} · ${report.reference}',
                              subtitle:
                                  '${_statusLabel(report.status)} · ${ppgPlural(report.differences.length, 'difference')}',
                              trailing: _StatusDot(status: report.status),
                              onTap: () => seastockPush<void>(
                                context,
                                ctrl,
                                AuditReportScreen(record: report),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: PpgBottomBar(
          children: [
            FilledButton.icon(
              key: const ValueKey('audit-start'),
              style: FilledButton.styleFrom(
                backgroundColor: PpgColors.navy,
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: canStart ? () => _open(context, ctrl) : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(inProgress ? 'Resume audit' : 'Start audit'),
            ),
            if (!canStart)
              PpgHint('Nothing on ${ctrl.vessel.name} to audit yet.'),
          ],
        ),
      );
    },
  );
}

String _statusLabel(AuditStatus status) => switch (status) {
  AuditStatus.waiting => 'Waiting for approval',
  AuditStatus.approved => 'Approved',
  AuditStatus.rejected => 'Rejected',
};

PpgTone _statusTone(AuditStatus status) => switch (status) {
  AuditStatus.waiting => PpgTone.warning,
  AuditStatus.approved => PpgTone.success,
  AuditStatus.rejected => PpgTone.danger,
};

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final AuditStatus status;

  @override
  Widget build(BuildContext context) => Icon(
    switch (status) {
      AuditStatus.waiting => Icons.schedule,
      AuditStatus.approved => Icons.check_circle_outline,
      AuditStatus.rejected => Icons.cancel_outlined,
    },
    color: _statusTone(status).foreground,
    semanticLabel: _statusLabel(status),
  );
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) => PpgPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Count what is really on board',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: PpgSpace.m),
        for (final (n, title, text) in const [
          (
            1,
            'Count every article',
            'Scan each can or type how many you see. You won\'t see the expected numbers yet, so the count stays honest.',
          ),
          (
            2,
            'Compare with inventory',
            'See where your count and the inventory differ. Recount if something looks wrong.',
          ),
          (
            3,
            'Send to the vessel manager',
            'Your count becomes a report. Stock changes only when the manager approves it.',
          ),
        ]) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: PpgColors.navy,
                foregroundColor: Colors.white,
                child: Text(
                  '$n',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: PpgSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 13,
                        color: PpgColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (n < 3) const SizedBox(height: PpgSpace.m),
        ],
      ],
    ),
  );
}

/// The blind count: every article on the inventory with only what has been
/// counted, never what is expected.
class AuditCountScreen extends StatelessWidget {
  const AuditCountScreen({super.key});

  Future<void> _countByHand(
    BuildContext context,
    SeastockController ctrl,
    String article,
  ) async {
    final count = await showSeastockSheet<int>(
      context,
      AuditCountSheet(controller: ctrl, articleNumber: article),
    );
    if (count == null || !context.mounted) return;
    await ppgRun(context, () => ctrl.setAuditCount(article, count));
  }

  Future<void> _discard(BuildContext context, SeastockController ctrl) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PpgThemed(
        child: AlertDialog(
          title: const Text('Discard this audit?'),
          content: const Text(
            'Everything counted so far is removed. Nothing is sent and stock does not change.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep counting'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PpgColors.destructive,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ),
    );
    if (discard != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await ctrl.discardAudit();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) => Consumer<SeastockController>(
    builder: (context, ctrl, _) {
      final counts = ctrl.audit ?? const <String, int>{};
      final list = ctrl.auditList;
      final todo = [
        for (final item in list)
          if (!counts.containsKey(item.articleNumber)) item,
      ];
      final done = [
        for (final item in list)
          if (counts.containsKey(item.articleNumber)) item,
      ];
      final found = ctrl.auditFound;
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PpgHeader(
              eyebrow: 'Audit · ${ctrl.vessel.name}',
              title: 'Count list',
              backTooltip: 'Leave audit. Your count is kept',
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'More',
                  iconColor: Colors.white,
                  onSelected: (_) => _discard(context, ctrl),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'discard',
                      child: Text('Discard this audit'),
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (todo.isNotEmpty) ...[
                    const PpgSectionLabel('Not counted yet'),
                    const SizedBox(height: PpgSpace.s),
                    PpgPanel(
                      child: Column(
                        children: ppgDivided(
                          todo.map(
                            (item) => PpgRow(
                              key: ValueKey('audit-todo-${item.articleNumber}'),
                              title: item.articleNumber,
                              monoTitle: true,
                              subtitle: item.product,
                              showChevron: false,
                              trailing: OutlinedButton(
                                key: ValueKey(
                                  'audit-count-${item.articleNumber}',
                                ),
                                onPressed: () => _countByHand(
                                  context,
                                  ctrl,
                                  item.articleNumber,
                                ),
                                child: const Text('Count'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: PpgSpace.l),
                  ],
                  if (done.isNotEmpty) ...[
                    const PpgSectionLabel('Counted'),
                    const SizedBox(height: PpgSpace.s),
                    PpgPanel(
                      child: Column(
                        children: ppgDivided(
                          done.map(
                            (item) => _countedRow(
                              context,
                              ctrl,
                              item.articleNumber,
                              item.product,
                              counts[item.articleNumber]!,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: PpgSpace.l),
                  ],
                  if (found.isNotEmpty) ...[
                    const PpgSectionLabel('Found, not in inventory'),
                    const SizedBox(height: PpgSpace.s),
                    PpgPanel(
                      tone: PpgTone.warning,
                      child: Column(
                        children: ppgDivided(
                          found.map(
                            (article) => _countedRow(
                              context,
                              ctrl,
                              article,
                              'Scanned, but not on the inventory',
                              counts[article]!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _footer(context, ctrl, done.length, list.length),
      );
    },
  );

  Widget _countedRow(
    BuildContext context,
    SeastockController ctrl,
    String article,
    String? subtitle,
    int count,
  ) => PpgRow(
    key: ValueKey('audit-done-$article'),
    leading: Icon(Icons.check, color: PpgTone.success.foreground),
    title: article,
    monoTitle: true,
    subtitle: subtitle,
    trailing: Text.rich(
      TextSpan(
        style: PpgText.figures(size: 18),
        children: [
          TextSpan(text: '$count'),
          const TextSpan(
            text: ' counted',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: PpgColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
    showChevron: false,
    semanticLabel: '$article, counted $count. Change',
    onTap: () => _countByHand(context, ctrl, article),
  );

  Widget _footer(
    BuildContext context,
    SeastockController ctrl,
    int counted,
    int total,
  ) => Material(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: PpgColors.line),
          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          children: [
                            TextSpan(
                              text: '$counted of $total articles counted',
                            ),
                            if (total > counted)
                              TextSpan(
                                text: ' · ${total - counted} to go',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w400,
                                  color: PpgColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : counted / total,
                          minHeight: 6,
                          backgroundColor: PpgColors.divider,
                          color: const Color(0xFFF97316),
                          semanticsLabel: 'Articles counted',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: PpgSpace.s),
                TextButton.icon(
                  key: const ValueKey('audit-finish'),
                  iconAlignment: IconAlignment.end,
                  onPressed: (ctrl.audit?.isEmpty ?? true)
                      ? null
                      : () => seastockPush<void>(
                          context,
                          ctrl,
                          const AuditTallyScreen(),
                        ),
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Finish counting'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: FilledButton.icon(
              key: const ValueKey('audit-scan'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () =>
                  seastockPush<void>(context, ctrl, const AuditScannerScreen()),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan a can'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Counts one article by hand. Returns the count to save.
class AuditCountSheet extends StatefulWidget {
  const AuditCountSheet({
    super.key,
    required this.controller,
    required this.articleNumber,
  });

  final SeastockController controller;
  final String articleNumber;

  @override
  State<AuditCountSheet> createState() => _AuditCountSheetState();
}

class _AuditCountSheetState extends State<AuditCountSheet> {
  late int _value = widget.controller.audit?[widget.articleNumber] ?? 0;

  @override
  Widget build(BuildContext context) {
    final product = widget.controller.productOf(widget.articleNumber);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Count this article',
              style: TextStyle(fontSize: 13, color: PpgColors.textSecondary),
            ),
            Text(widget.articleNumber, style: PpgText.mono(size: 22)),
            if (product != null)
              Text(
                product,
                style: const TextStyle(
                  fontSize: 14,
                  color: PpgColors.textSecondary,
                ),
              ),
            const SizedBox(height: PpgSpace.l),
            SeastockCounter(
              label: 'Counted on board',
              value: _value,
              onChanged: (value) => setState(() => _value = value),
            ),
            const SizedBox(height: PpgSpace.l),
            FilledButton(
              key: const ValueKey('audit-count-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.pop(context, _value),
              child: Text('Save $_value counted'),
            ),
            const SizedBox(height: PpgSpace.s),
            const PpgHint('None on board? Save 0. That counts too.'),
          ],
        ),
      ),
    );
  }
}

/// The lines a report would have if sent now, from the controller's count.
List<AuditLine> _previewLines(SeastockController ctrl) {
  final counts = ctrl.audit ?? const <String, int>{};
  return [
    for (final item in ctrl.auditList)
      AuditLine(
        articleNumber: item.articleNumber,
        product: item.product,
        counted: counts[item.articleNumber],
        expected: item.onBoard,
      ),
    for (final article in ctrl.auditFound)
      AuditLine(
        articleNumber: article,
        product: ctrl.productOf(article),
        counted: counts[article],
        expected: 0,
      ),
  ];
}

/// Expected figures appear only here. Sending turns the count into a report
/// for the vessel manager; stock does not change.
class AuditTallyScreen extends StatefulWidget {
  const AuditTallyScreen({super.key});

  @override
  State<AuditTallyScreen> createState() => _AuditTallyScreenState();
}

class _AuditTallyScreenState extends State<AuditTallyScreen> {
  bool _sending = false;

  Future<void> _send(SeastockController ctrl) async {
    setState(() => _sending = true);
    AuditRecord? record;
    final ok = await ppgRun(context, () async {
      record = await ctrl.sendAudit();
    }, failurePrefix: 'Not sent.');
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok || record == null) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    navigator.push<void>(
      seastockRoute<void>(
        ctrl,
        AuditReportScreen(record: record!, justSent: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Consumer<SeastockController>(
    builder: (context, ctrl, _) {
      final lines = _previewLines(ctrl);
      final report = AuditRecord(
        id: '',
        vesselId: ctrl.vessel.id,
        reference: '',
        deviceId: '',
        createdAt: DateTime.now(),
        lines: lines,
      );
      return PopScope(
        canPop: !_sending,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PpgHeader(
                eyebrow: 'Audit · ${ctrl.vessel.name}',
                title: 'Compare with inventory',
                backTooltip: 'Back to the count list',
                bottom: _Figures(report: report),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    ..._reportLines(report),
                    const SizedBox(height: PpgSpace.m),
                    PpgHint(
                      'Sending makes this a report for the vessel manager. Stock stays at ${ctrl.stock.total} PC until they approve it; then it becomes ${ctrl.stock.total + report.netDifference} PC. Something looks wrong? Count again first.',
                      center: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: PpgBottomBar(
            children: [
              Row(
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      side: const BorderSide(color: PpgColors.blue, width: 1.5),
                    ),
                    onPressed: _sending ? null : () => Navigator.pop(context),
                    child: const Text('Count again'),
                  ),
                  const SizedBox(width: PpgSpace.m),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('audit-send'),
                      style: FilledButton.styleFrom(
                        backgroundColor: PpgColors.navy,
                        minimumSize: const Size.fromHeight(56),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _sending ? null : () => _send(ctrl),
                      icon: const Icon(Icons.send_outlined),
                      label: Text(_sending ? 'Sending…' : 'Send to manager'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Figures extends StatelessWidget {
  const _Figures({required this.report});

  final AuditRecord report;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _figure('Match', '${report.matches.length}'),
      const SizedBox(width: PpgSpace.s),
      _figure('Differ', '${report.differences.length}', highlight: true),
      const SizedBox(width: PpgSpace.s),
      _figure('Net difference', '${ppgSigned(report.netDifference)} PC'),
    ],
  );

  Widget _figure(
    String label,
    String value, {
    bool highlight = false,
  }) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0x2EFDBA74)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PpgRadii.medium),
        border: highlight ? Border.all(color: const Color(0x80FDBA74)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: highlight
                  ? const Color(0xFFFED7AA)
                  : PpgColors.onNavyMuted,
            ),
          ),
          Text(value, style: PpgText.figures(size: 20, color: Colors.white)),
        ],
      ),
    ),
  );
}

/// Differences first, then articles not counted, then a single line for the
/// matches.
List<Widget> _reportLines(AuditRecord report) {
  final differences = report.differences;
  final notCounted = report.notCounted;
  final matches = report.matches;
  return [
    if (differences.isNotEmpty) ...[
      PpgSectionLabel('Differences · ${differences.length}'),
      const SizedBox(height: PpgSpace.s),
      PpgPanel(
        child: Column(
          children: ppgDivided(
            differences.map(
              (line) => PpgRow(
                key: ValueKey('audit-diff-${line.articleNumber}'),
                title: line.articleNumber,
                monoTitle: true,
                subtitle: [
                  if (line.isFound) 'Not in inventory' else ?line.product,
                  'inventory ${line.expected} → counted ${line.counted}',
                ].join(' · '),
                showChevron: false,
                trailing: PpgStatusBadge(
                  label: ppgSigned(line.difference),
                  tone: line.difference < 0 ? PpgTone.warning : PpgTone.info,
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: PpgSpace.m),
    ],
    if (notCounted.isNotEmpty) ...[
      PpgSectionLabel('Not counted · ${notCounted.length}'),
      const SizedBox(height: PpgSpace.s),
      PpgPanel(
        child: Column(
          children: ppgDivided(
            notCounted.map(
              (line) => PpgRow(
                title: line.articleNumber,
                monoTitle: true,
                subtitle: [
                  ?line.product,
                  'stays at ${line.expected}',
                ].join(' · '),
                showChevron: false,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: PpgSpace.m),
    ],
    if (matches.isNotEmpty)
      PpgPanel(
        child: Theme(
          data: ThemeData(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(Icons.check, color: PpgTone.success.foreground),
            title: Text(
              '${ppgPlural(matches.length, 'article')} match · ${matches.fold(0, (sum, line) => sum + line.expected)} PC',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            children: [
              for (final line in matches)
                ListTile(
                  dense: true,
                  title: Text(line.articleNumber, style: PpgText.mono()),
                  subtitle: line.product == null ? null : Text(line.product!),
                  trailing: Text(
                    '${line.counted}',
                    style: PpgText.figures(size: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
  ];
}

/// One audit report: just sent, or opened from the Audit page.
class AuditReportScreen extends StatelessWidget {
  const AuditReportScreen({
    super.key,
    required this.record,
    this.justSent = false,
  });

  final AuditRecord record;
  final bool justSent;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SeastockController>();
    final status = switch (record.status) {
      AuditStatus.waiting => (
        'Inventory not changed yet',
        'Stays at ${ctrl.stock.total} PC until the vessel manager approves this report on the dashboard.',
      ),
      AuditStatus.approved => (
        'Approved by the vessel manager',
        'Stock was set to this count${record.decidedAt == null ? '' : ' on ${ppgDateTime(record.decidedAt!)}'}.',
      ),
      AuditStatus.rejected => (
        'Rejected by the vessel manager',
        'Stock did not change. Start a new audit to count again.',
      ),
    };
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        PpgBanner(
          tone: _statusTone(record.status),
          title: status.$1,
          message: status.$2,
        ),
        const SizedBox(height: PpgSpace.l),
        ..._reportLines(record),
        const SizedBox(height: PpgSpace.m),
        const PpgHint(
          'Reports can\'t be edited. If the manager rejects one, start a new audit.',
          center: false,
        ),
      ],
    );
    if (!justSent) {
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PpgHeader(
              eyebrow: 'Audit report · ${ctrl.vessel.name}',
              title: record.reference,
              monoTitle: true,
              subtitle:
                  '${ppgDateTime(record.createdAt)} · ${_statusLabel(record.status)}',
              backTooltip: 'Back to Audit',
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).popUntil((r) => r.isFirst);
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: PpgColors.navy,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0xFFDBEAFE),
                        foregroundColor: Color(0xFF1E3A8A),
                        child: Icon(Icons.send_outlined, size: 28),
                      ),
                      const SizedBox(height: PpgSpace.m),
                      const Text(
                        'Sent to the vessel manager',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: PpgSpace.xs),
                      Text(
                        'Audit report ${record.reference} · ${ctrl.vessel.name} · ${ppgDateTime(record.createdAt)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: PpgColors.onNavyMuted,
                        ),
                      ),
                      const SizedBox(height: PpgSpace.m),
                      PpgStatusBadge(
                        label: _statusLabel(record.status),
                        tone: _statusTone(record.status),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: content),
          ],
        ),
        bottomNavigationBar: PpgBottomBar(
          children: [
            FilledButton(
              key: const ValueKey('audit-done'),
              style: FilledButton.styleFrom(
                backgroundColor: PpgColors.navy,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.popUntil((route) => route.isFirst);
                navigator.push<void>(
                  seastockRoute<void>(ctrl, const AuditScreen()),
                );
              },
              child: const Text('See audit reports'),
            ),
          ],
        ),
      ),
    );
  }
}
