import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../domain/stock.dart';
import '../services/seastock_controller.dart';
import '../ui/seastock_widgets.dart';
import 'checkout_records_screen.dart';

enum _Kind { checkIns, checkOuts }

enum DatePreset { today, last7Days, last30Days, thisMonth, custom }

/// A range of whole days, both ends included.
class DateSpan {
  const DateSpan(this.preset, this.from, this.to);

  factory DateSpan.preset(DatePreset preset, {DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    return switch (preset) {
      DatePreset.today => DateSpan(preset, today, today),
      DatePreset.last7Days => DateSpan(
        preset,
        today.subtract(const Duration(days: 6)),
        today,
      ),
      DatePreset.thisMonth => DateSpan(
        preset,
        DateTime(today.year, today.month),
        today,
      ),
      _ => DateSpan(
        DatePreset.last30Days,
        today.subtract(const Duration(days: 29)),
        today,
      ),
    };
  }

  final DatePreset preset;
  final DateTime from;
  final DateTime to;

  static DateTime _day(DateTime at) {
    final local = at.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  bool contains(DateTime at) {
    final day = _day(at);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  String get label => switch (preset) {
    DatePreset.today => 'Today',
    DatePreset.last7Days => 'Last 7 days',
    DatePreset.last30Days => 'Last 30 days',
    DatePreset.thisMonth => 'This month',
    DatePreset.custom => 'Your dates',
  };

  String get dates => from == to
      ? ppgDate(from)
      : from.year == to.year
      ? '${ppgDate(from).replaceFirst(' ${from.year}', '')} – ${ppgDate(to)}'
      : '${ppgDate(from)} – ${ppgDate(to)}';
}

/// Check-ins (submitted delivery notes) and check-outs on the vessel, one tab
/// each, within a date range. Audits are not listed here.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  _Kind _kind = _Kind.checkIns;
  DateSpan _span = DateSpan.preset(DatePreset.last30Days);

  Future<void> _chooseDates() async {
    final picked = await showSeastockSheet<DateSpan>(
      context,
      _DatesSheet(current: _span),
    );
    if (picked != null && mounted) setState(() => _span = picked);
  }

  @override
  Widget build(BuildContext context) => Consumer<SeastockController>(
    builder: (context, ctrl, _) {
      final checkIns = ctrl.checkIns
          .where((record) => _span.contains(record.submittedAt))
          .toList();
      final checkOuts = ctrl.checkouts
          .where((record) => _span.contains(record.createdAt))
          .toList();
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PpgHeader(
              eyebrow: ctrl.vessel.name,
              title: 'Transactions',
              backTooltip: 'Back to Home',
              bottom: _tabs(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _datesButton(),
                  const SizedBox(height: PpgSpace.m),
                  ...(_kind == _Kind.checkIns
                      ? _checkIns(ctrl, checkIns)
                      : _checkOuts(ctrl, checkOuts)),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _tabs() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(PpgRadii.medium + 2),
    ),
    child: Row(
      children: [
        _tab(_Kind.checkIns, Icons.download_outlined, 'Check-ins'),
        const SizedBox(width: 4),
        _tab(_Kind.checkOuts, Icons.upload_outlined, 'Check-outs'),
      ],
    ),
  );

  Widget _tab(_Kind kind, IconData icon, String label) {
    final selected = _kind == kind;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(PpgRadii.small + 2),
          child: InkWell(
            key: ValueKey('tab-${kind.name}'),
            borderRadius: BorderRadius.circular(PpgRadii.small + 2),
            onTap: () => setState(() => _kind = kind),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? PpgColors.navy : Colors.white,
                  ),
                  const SizedBox(width: PpgSpace.s),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? PpgColors.navy : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _datesButton() => Semantics(
    button: true,
    label: 'Dates: ${_span.label}, ${_span.dates}. Change dates',
    excludeSemantics: true,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PpgRadii.large - 2),
        side: const BorderSide(color: PpgColors.control),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('transactions-dates'),
        onTap: _chooseDates,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, color: PpgColors.link),
              const SizedBox(width: PpgSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _span.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: PpgColors.textSecondary,
                      ),
                    ),
                    Text(
                      _span.dates,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'Change',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PpgColors.link,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _summary(String what, int total) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: PpgSectionLabel(what, trailing: '${ppgSigned(total)} PC in total'),
  );

  List<Widget> _byDay<T>(
    List<T> records,
    DateTime Function(T) at,
    Widget Function(T) row,
  ) {
    final days = <String, List<T>>{};
    for (final record in records) {
      days.putIfAbsent(seastockDay(at(record)), () => []).add(record);
    }
    return [
      for (final day in days.entries) ...[
        const SizedBox(height: PpgSpace.m),
        Text(
          day.key,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PpgColors.textMuted,
          ),
        ),
        const SizedBox(height: PpgSpace.s),
        PpgPanel(child: Column(children: ppgDivided(day.value.map(row)))),
      ],
    ];
  }

  List<Widget> _checkIns(SeastockController ctrl, List<CheckInRecord> list) {
    if (list.isEmpty) {
      return [
        PpgEmptyState(
          icon: Icons.download_outlined,
          title: 'No check-ins in these dates',
          message:
              'Submitted delivery notes on ${ctrl.vessel.name} are listed here.',
        ),
      ];
    }
    return [
      _summary(
        ppgPlural(list.length, 'check-in'),
        list.fold(0, (sum, record) => sum + record.total),
      ),
      ..._byDay<CheckInRecord>(
        list,
        (record) => record.submittedAt,
        (record) => PpgRow(
          key: ValueKey('checkin-${record.sessionId}'),
          title: record.deliveryNoteNumber == null
              ? 'Delivery note'
              : 'DN ${record.deliveryNoteNumber}',
          subtitle:
              '${ppgTime(record.submittedAt)} · ${ppgPlural(record.lines.length, 'article')}',
          trailing: Text(
            '${ppgSigned(record.total)} PC',
            style: PpgText.figures(size: 18),
          ),
          onTap: () => seastockPush<void>(
            context,
            ctrl,
            CheckInDetailScreen(record: record),
          ),
        ),
      ),
      const SizedBox(height: PpgSpace.l),
      PpgHint(
        'Submitted delivery notes on ${ctrl.vessel.name}, newest first. Records can\'t be edited.',
      ),
    ];
  }

  List<Widget> _checkOuts(SeastockController ctrl, List<CheckoutRecord> list) {
    if (list.isEmpty) {
      return [
        PpgEmptyState(
          icon: Icons.upload_outlined,
          title: 'No check-outs in these dates',
          message: 'Cans checked out of ${ctrl.vessel.name} are listed here.',
        ),
      ];
    }
    return [
      _summary(
        ppgPlural(list.length, 'check-out'),
        -list.fold(0, (sum, record) => sum + record.total),
      ),
      ..._byDay<CheckoutRecord>(
        list,
        (record) => record.createdAt,
        (record) => PpgRow(
          key: ValueKey('checkout-${record.id}'),
          title: 'Check-out ${record.reference}',
          subtitle: [
            ppgTime(record.createdAt),
            record.lines.length == 1
                ? '${record.lines.single.articleNumber} ×${record.lines.single.quantity}'
                : ppgPlural(record.lines.length, 'article'),
          ].join(' · '),
          trailing: Text(
            '${ppgSigned(-record.total)} PC',
            style: PpgText.figures(size: 18),
          ),
          onTap: () => seastockPush<void>(
            context,
            ctrl,
            CheckoutDetailScreen(record: record),
          ),
        ),
      ),
      const SizedBox(height: PpgSpace.l),
      PpgHint(
        'Check-outs from ${ctrl.vessel.name}, newest first. Records can\'t be edited.',
      ),
    ];
  }
}

class _DatesSheet extends StatelessWidget {
  const _DatesSheet({required this.current});

  final DateSpan current;

  Future<void> _custom(BuildContext context) async {
    final today = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(start: current.from, end: current.to),
      helpText: 'Show transactions from',
      saveText: 'Show',
    );
    if (picked != null && context.mounted) {
      Navigator.pop(
        context,
        DateSpan(DatePreset.custom, picked.start, picked.end),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Show transactions from',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: PpgSpace.m),
          Wrap(
            spacing: PpgSpace.s,
            runSpacing: PpgSpace.s,
            children: [
              for (final preset in [
                DatePreset.today,
                DatePreset.last7Days,
                DatePreset.last30Days,
                DatePreset.thisMonth,
              ])
                ChoiceChip(
                  key: ValueKey('dates-${preset.name}'),
                  label: Text(DateSpan.preset(preset).label),
                  selected: current.preset == preset,
                  onSelected: (_) =>
                      Navigator.pop(context, DateSpan.preset(preset)),
                ),
            ],
          ),
          const SizedBox(height: PpgSpace.l),
          OutlinedButton.icon(
            key: const ValueKey('dates-custom'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => _custom(context),
            icon: const Icon(Icons.date_range_outlined),
            label: Text(
              current.preset == DatePreset.custom
                  ? 'Your dates: ${current.dates}'
                  : 'Pick your own dates',
            ),
          ),
        ],
      ),
    ),
  );
}

/// One submitted delivery note, with what it added to the vessel.
class CheckInDetailScreen extends StatelessWidget {
  const CheckInDetailScreen({super.key, required this.record});

  final CheckInRecord record;

  @override
  Widget build(BuildContext context) {
    final vessel = context.read<SeastockController>().vessel;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PpgHeader(
            eyebrow: 'Check-in · ${vessel.name}',
            title: record.deliveryNoteNumber == null
                ? 'Delivery note'
                : 'DN ${record.deliveryNoteNumber}',
            monoTitle: record.deliveryNoteNumber != null,
            subtitle:
                '${ppgDateTime(record.submittedAt)} · ${record.total} PC checked in',
            backTooltip: 'Back to Transactions',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                PpgSectionLabel('Articles · ${record.lines.length}'),
                const SizedBox(height: PpgSpace.s),
                PpgPanel(
                  child: Column(
                    children: ppgDivided(
                      record.lines.map(
                        (line) => PpgRow(
                          title: line.articleNumber,
                          monoTitle: true,
                          subtitle: line.product,
                          trailing: SeastockQuantity(line.quantity),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: PpgSpace.m),
                const PpgHint(
                  'Counted cans on the submitted delivery note. Check-ins can\'t be edited.',
                  center: false,
                ),
                if (record.operatorEmail != null) ...[
                  const SizedBox(height: PpgSpace.s),
                  PpgHint(
                    'Checked in by ${record.operatorEmail}.',
                    center: false,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
