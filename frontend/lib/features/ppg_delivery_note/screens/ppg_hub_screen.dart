import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../persistence/ppg_repository.dart';
import '../services/ppg_session_controller.dart';
import '../ui/ppg_format.dart';
import '../ui/ppg_navigation.dart';
import '../ui/ppg_tokens.dart';
import '../ui/ppg_widgets.dart';
import 'ppg_capture_screen.dart';
import 'ppg_confirmation_screen.dart';
import 'ppg_review_screen.dart';
import 'ppg_session_screen.dart';

class PpgHubScreen extends StatefulWidget {
  const PpgHubScreen({
    super.key,
    this.operatorEmail,
    this.controller,
    this.vesselId = ppgDefaultVesselId,
    this.vesselName,
  });

  final String? operatorEmail;

  /// Only this vessel's delivery notes are listed; new ones are started on it.
  final String vesselId;
  final String? vesselName;

  /// Injected in tests; the hub creates and owns one otherwise.
  final PpgSessionController? controller;

  @override
  State<PpgHubScreen> createState() => _PpgHubScreenState();
}

enum _Stage { document, count, submit }

class _PpgHubScreenState extends State<PpgHubScreen> {
  late final PpgSessionController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? PpgSessionController();
    _controller.vesselId = widget.vesselId;
    if (_ownsController) _controller.init();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  _Stage _stageOf(SessionProgress item) {
    final s = item.session;
    final allPagesChecked =
        item.pageCount > 0 &&
        item.checkedPageCount == item.pageCount &&
        (s.declaredPageCount == null || s.declaredPageCount == item.pageCount);
    if (item.itemCount > 0 && item.verifiedItemCount == item.itemCount) {
      return _Stage.submit;
    }
    if (item.hasPhysicalCounts || (allPagesChecked && item.itemCount > 0)) {
      return _Stage.count;
    }
    return _Stage.document;
  }

  Future<void> _startNewDelivery() async {
    final ctrl = _controller;
    ctrl.closeSession();
    final captureId = await ppgPush<String>(
      context,
      ctrl,
      PpgCaptureScreen(newDelivery: true, operatorEmail: widget.operatorEmail),
    );
    final sessionId = ctrl.session?.id;
    if (!mounted) return;
    if (captureId != null && sessionId != null) {
      await ppgPush<void>(
        context,
        ctrl,
        PpgSessionScreen(sessionId: sessionId, reviewCaptureId: captureId),
      );
    }
    await ctrl.refreshSessions();
  }

  Future<void> _open(SessionProgress item) async {
    final ctrl = _controller;
    final ok = await ppgRun(context, () => ctrl.loadSession(item.session.id));
    if (!ok || !mounted) return;
    if (item.session.isSubmitted) {
      await ppgPush<void>(context, ctrl, const PpgConfirmationScreen());
    } else if (ctrl.sourceReviewReady && ctrl.lines.isNotEmpty) {
      await ppgPush<void>(context, ctrl, const PpgReviewScreen());
    } else {
      await ppgPush<void>(
        context,
        ctrl,
        PpgSessionScreen(sessionId: item.session.id),
      );
    }
    await ctrl.refreshSessions();
  }

  Future<void> _confirmDelete(SessionProgress item) async {
    final delete = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) =>
          PpgThemed(child: _DeleteDraftSheet(item: item)),
    );
    if (delete != true || !mounted) return;
    final ok = await ppgRun(
      context,
      () => _controller.deleteDraft(item.session.id),
    );
    if (ok && mounted) showPpgMessage(context, 'Draft deleted');
  }

  Future<void> _loadReferenceFixture() async {
    final ctrl = _controller;
    await ctrl.loadFixtureSession();
    final id = ctrl.session?.id;
    if (id == null || !mounted) return;
    await ppgPush<void>(context, ctrl, PpgSessionScreen(sessionId: id));
    await ctrl.refreshSessions();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: PpgThemed(
        child: Consumer<PpgSessionController>(
          builder: (context, ctrl, _) => Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PpgHeader(
                  eyebrow: widget.vesselName == null
                      ? 'Check in'
                      : 'Check in · ${widget.vesselName}',
                  title: 'Delivery notes',
                  subtitle: 'Saved on this device',
                  backTooltip: 'Back to Home',
                  showBack: Navigator.of(context).canPop(),
                  actions: [
                    if (kDebugMode && ctrl.ready)
                      PopupMenuButton<String>(
                        tooltip: 'Developer tools',
                        iconColor: Colors.white,
                        onSelected: (value) {
                          if (value == 'fixture') _loadReferenceFixture();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'fixture',
                            child: Text('Load reference fixture'),
                          ),
                        ],
                      ),
                  ],
                ),
                Expanded(child: _body(ctrl)),
              ],
            ),
            bottomNavigationBar: PpgBottomBar(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: ctrl.ready ? _startNewDelivery : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Scan a new delivery note'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(PpgSessionController ctrl) {
    if (!ctrl.ready) {
      if (ctrl.error == null) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading'),
        );
      }
      return PpgEmptyState(
        icon: Icons.error_outline,
        title: 'Delivery notes could not be opened',
        message: ctrl.error!,
        action: FilledButton(onPressed: ctrl.init, child: const Text('Retry')),
      );
    }
    final notes = ctrl.progress
        .where((p) => p.session.vesselId == widget.vesselId)
        .toList();
    if (notes.isEmpty) {
      return PpgEmptyState(
        icon: Icons.description_outlined,
        title: widget.vesselName == null
            ? 'No delivery notes yet'
            : 'No delivery notes on ${widget.vesselName}',
        message:
            'Tap Scan a new delivery note and photograph the first page of the paper DN.',
      );
    }
    final open = notes.where((p) => !p.session.isSubmitted).toList();
    final submitted = notes.where((p) => p.session.isSubmitted).toList();
    return RefreshIndicator(
      onRefresh: ctrl.refreshSessions,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          if (open.isNotEmpty) ...[
            PpgSectionLabel('In progress · ${open.length}'),
            const SizedBox(height: PpgSpace.m),
            for (final item in open) ...[
              item.session.deliveryNoteNumber == null
                  ? _unidentifiedDraft(item)
                  : _openCard(item),
              const SizedBox(height: PpgSpace.m),
            ],
          ],
          if (submitted.isNotEmpty) ...[
            if (open.isNotEmpty) const SizedBox(height: PpgSpace.m),
            PpgSectionLabel('Submitted · ${submitted.length}'),
            const SizedBox(height: PpgSpace.m),
            PpgPanel(
              child: Column(children: ppgDivided(submitted.map(_submittedRow))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stageBadge(_Stage stage) => switch (stage) {
    _Stage.document => const PpgStatusBadge(
      label: '1 · Document',
      tone: PpgTone.info,
    ),
    _Stage.count => const PpgStatusBadge(
      label: '2 · Count',
      tone: PpgTone.info,
    ),
    _Stage.submit => const PpgStatusBadge(
      label: '3 · Ready to submit',
      tone: PpgTone.success,
    ),
  };

  Widget _deleteButton(SessionProgress item) => IconButton(
    tooltip: 'Delete this draft',
    color: PpgColors.textMuted,
    onPressed: () => _confirmDelete(item),
    icon: const Icon(Icons.delete_outline),
  );

  Widget _openCard(SessionProgress item) {
    final s = item.session;
    final stage = _stageOf(item);
    final pages = s.declaredPageCount ?? item.pageCount;
    final (progressText, figure, fraction) = switch (stage) {
      _Stage.document => (
        '${item.checkedPageCount} of $pages pages checked',
        '${item.documentTotal} PC on DN',
        pages == 0 ? 0.0 : item.checkedPageCount / pages,
      ),
      _ => (
        '${item.verifiedItemCount} of ${item.itemCount} items verified',
        '${item.countedTotal} / ${item.documentTotal} PC',
        item.documentTotal == 0
            ? 0.0
            : (item.countedTotal / item.documentTotal).clamp(0.0, 1.0),
      ),
    };
    final nextAction = switch (stage) {
      _Stage.document => 'Continue checking pages',
      _Stage.count => 'Continue counting',
      _Stage.submit => 'Review and submit',
    };
    return Semantics(
      container: true,
      child: PpgPanel(
        child: InkWell(
          onTap: () => _open(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Delivery note',
                              style: TextStyle(
                                fontSize: 12,
                                color: PpgColors.textMuted,
                              ),
                            ),
                            Text(
                              s.deliveryNoteNumber!,
                              style: PpgText.mono(size: 20),
                            ),
                            Text(
                              'Updated ${ppgRelative(s.updatedAt)} · ${ppgPlural(pages, 'page')}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: PpgColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _stageBadge(stage),
                    ],
                  ),
                ),
                const SizedBox(height: PpgSpace.m),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          progressText,
                          style: const TextStyle(
                            fontSize: 13,
                            color: PpgColors.textSecondary,
                          ),
                        ),
                      ),
                      Text(figure, style: PpgText.figures(size: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      backgroundColor: PpgColors.divider,
                      color: PpgColors.blue,
                      semanticsLabel: progressText,
                    ),
                  ),
                ),
                const SizedBox(height: PpgSpace.s),
                const Divider(height: 1, color: PpgColors.divider),
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          nextAction,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: PpgColors.link,
                          ),
                        ),
                      ),
                    ),
                    if (!item.hasPhysicalCounts) _deleteButton(item),
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.chevron_right, color: PpgColors.link),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _unidentifiedDraft(SessionProgress item) {
    return PpgPanel(
      child: InkWell(
        onTap: () => _open(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery number not read yet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${item.pageCount == 0 ? 'No pages saved' : '${ppgPlural(item.pageCount, 'page')} saved'} · started ${ppgRelative(item.session.createdAt)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: PpgColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const PpgStatusBadge(
                      label: '1 · Document',
                      tone: PpgTone.info,
                      compact: true,
                    ),
                  ],
                ),
              ),
              if (!item.hasPhysicalCounts) _deleteButton(item),
              const Icon(Icons.chevron_right, color: PpgColors.link),
            ],
          ),
        ),
      ),
    );
  }

  Widget _submittedRow(SessionProgress item) {
    final when = item.submittedAt ?? item.session.updatedAt;
    return PpgRow(
      title: item.session.deliveryNoteNumber ?? 'Delivery note',
      monoTitle: true,
      subtitle:
          'Submitted ${ppgDate(when)} · ${ppgPlural(item.itemCount, 'item')} · ${item.documentTotal} PC on DN',
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: PpgTone.success.background,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check, color: PpgTone.success.foreground),
      ),
      trailing: const Text(
        'View',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: PpgColors.link,
        ),
      ),
      showChevron: false,
      onTap: () => _open(item),
    );
  }
}

class _DeleteDraftSheet extends StatelessWidget {
  const _DeleteDraftSheet({required this.item});

  final SessionProgress item;

  @override
  Widget build(BuildContext context) {
    final dn = item.session.deliveryNoteNumber;
    final effect = item.pageCount == 0
        ? 'Nothing has been saved for it yet.'
        : 'Deleting removes the saved ${item.pageCount == 1 ? 'page photo' : 'page photos'} from this device. It can\'t be undone.';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: PpgTone.danger.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: PpgTone.danger.foreground,
                ),
              ),
            ),
            const SizedBox(height: PpgSpace.l),
            Text(
              'Delete this draft?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '${dn == null ? 'The delivery number hasn\'t been read yet. ' : ''}'
              '$effect',
              style: const TextStyle(
                fontSize: 15,
                color: PpgColors.textSecondary,
              ),
            ),
            const SizedBox(height: PpgSpace.l),
            Container(
              padding: const EdgeInsets.all(PpgSpace.m),
              decoration: BoxDecoration(
                color: PpgColors.ground,
                borderRadius: BorderRadius.circular(PpgRadii.medium),
              ),
              child: Column(
                children: [
                  if (dn != null) _fact('Delivery note', dn, mono: true),
                  _fact(
                    'Pages saved',
                    item.pageCount == 0
                        ? 'None'
                        : ppgPlural(item.pageCount, 'photo'),
                  ),
                  _fact('Items counted', 'None'),
                  _fact('Started', ppgDateTime(item.session.createdAt)),
                ],
              ),
            ),
            const SizedBox(height: PpgSpace.l),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PpgColors.destructive,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete draft'),
            ),
            const SizedBox(height: PpgSpace.s),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            const SizedBox(height: PpgSpace.m),
            const PpgHint(
              'Once any item has been counted, a draft can\'t be deleted. It can only be finished and submitted.',
              center: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: PpgColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: mono
              ? PpgText.mono(size: 14)
              : const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
