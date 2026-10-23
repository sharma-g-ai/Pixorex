import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_navigation.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';

/// The saved receiving form. Done (and back) return to Delivery notes rather
/// than to the read-only count list behind it.
class PpgConfirmationScreen extends StatelessWidget {
  const PpgConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PpgSessionController>();
    final sub = ctrl.submission;
    final map = ctrl.submissionMap;
    final lines =
        [
          for (final raw in (map?['lines'] as List?) ?? const [])
            Map<String, dynamic>.from(raw as Map),
        ]..sort(
          (a, b) => ((a['source_page'] as int?) ?? 0).compareTo(
            (b['source_page'] as int?) ?? 0,
          ),
        );
    final differences = lines
        .where((line) => ((line['variance'] as num?) ?? 0) != 0)
        .toList();
    final matched = lines.length - differences.length;
    final practice = map != null && map['mode'] != 'CAMERA';

    return PpgThemed(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) ppgPopToHub(context);
        },
        child: Scaffold(
          body: sub == null
              ? Column(
                  children: [
                    const PpgHeader(title: 'Receipt'),
                    const Expanded(
                      child: PpgEmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No saved form',
                        message: 'This delivery note has not been submitted.',
                      ),
                    ),
                    PpgBottomBar(
                      children: [
                        FilledButton(
                          onPressed: () => ppgPopToHub(context),
                          child: const Text('Back to Delivery notes'),
                        ),
                      ],
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(
                      map?['delivery_note_number'] as String? ?? '—',
                      sub.submittedAt,
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          if (practice) ...[
                            const PpgBanner(
                              tone: PpgTone.info,
                              message:
                                  'Practice data: this form was made from sample pages, not a real delivery.',
                            ),
                            const SizedBox(height: PpgSpace.m),
                          ],
                          PpgPanel(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                _figure(
                                  'On DN',
                                  '${map?['document_quantity_total'] ?? '—'} PC',
                                ),
                                _figure(
                                  'Counted',
                                  '${map?['physical_quantity_total'] ?? '—'} PC',
                                ),
                                _figure('Items', '${lines.length}'),
                              ],
                            ),
                          ),
                          const SizedBox(height: PpgSpace.l),
                          PpgSectionLabel(
                            'Differences recorded · ${differences.length}',
                          ),
                          const SizedBox(height: PpgSpace.s),
                          if (differences.isEmpty)
                            const PpgHint(
                              'Every item matched the DN.',
                              center: false,
                            )
                          else
                            PpgPanel(
                              child: Column(
                                children: ppgDivided(
                                  differences.map(_differenceRow),
                                ),
                              ),
                            ),
                          if (matched > 0 && differences.isNotEmpty) ...[
                            const SizedBox(height: PpgSpace.m),
                            PpgPanel(
                              child: Theme(
                                data: Theme.of(
                                  context,
                                ).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  title: Text(
                                    '${ppgPlural(matched, 'item')} matched the DN',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                                  expandedAlignment: Alignment.centerLeft,
                                  children: [
                                    Text(
                                      lines
                                          .where(
                                            (l) =>
                                                ((l['variance'] as num?) ??
                                                    0) ==
                                                0,
                                          )
                                          .map((l) => '${l['article_number']}')
                                          .join(' · '),
                                      style: PpgText.mono(
                                        size: 13,
                                        weight: FontWeight.w500,
                                        color: PpgColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: PpgSpace.l),
                          Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontSize: 13,
                                color: PpgColors.textSecondary,
                              ),
                              children: [
                                const TextSpan(text: 'Reference '),
                                TextSpan(
                                  text: sub.submissionId.substring(0, 8),
                                  style: PpgText.mono(
                                    size: 13,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    PpgBottomBar(
                      children: [
                        FilledButton(
                          onPressed: () => ppgPopToHub(context),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header(String dn, DateTime submittedAt) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: PpgColors.navy,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: PpgColors.stepDone,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 30,
                    color: PpgColors.navy,
                  ),
                ),
                const SizedBox(height: PpgSpace.l),
                Semantics(
                  header: true,
                  child: const Text(
                    'Receiving form saved',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 15,
                      color: PpgColors.onNavyMuted,
                    ),
                    children: [
                      const TextSpan(text: 'DN '),
                      TextSpan(
                        text: dn,
                        style: PpgText.mono(
                          size: 15,
                          weight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(text: ' · ${ppgDateTime(submittedAt)}'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Saved on this device only. Inventory and ERP are not updated.',
                  style: TextStyle(fontSize: 14, color: PpgColors.onNavyMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _figure(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: PpgColors.textSecondary),
        ),
        Text(value, style: PpgText.figures(size: 22)),
      ],
    ),
  );

  Widget _differenceRow(Map<String, dynamic> line) {
    final variance = (line['variance'] as num?)?.toInt() ?? 0;
    final unit = line['unit'] ?? 'PC';
    final reason = line['variance_reason'] as String?;
    return PpgRow(
      title: '${line['article_number']}',
      monoTitle: true,
      subtitle:
          '${reason ?? 'No reason given'} · ${line['physical_quantity']} of ${line['document_quantity']} $unit',
      trailing: Text(
        '${ppgSigned(variance)} $unit',
        style: PpgText.figures(
          size: 15,
          color: variance < 0
              ? PpgTone.danger.foreground
              : PpgTone.info.foreground,
        ),
      ),
    );
  }
}
