import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/theme.dart';
import '../../widgets/auth_widgets.dart';
import '../home/home_screen.dart' show ago;
import 'capture_models.dart';
import 'location_pick.dart';
import 'scan_repository.dart';

/// Confirm location (design 41, 42, 45): the last location used in this unit is picked
/// already; any level can be changed. [onSubmit] gets the finished pick and returns a
/// message to show above the button when sending failed (null when it went through).
class LocationScreen extends StatefulWidget {
  const LocationScreen({
    super.key,
    required this.scans,
    required this.lastLocations,
    required this.buId,
    required this.unitName,
    required this.tenantName,
    required this.typeName,
    required this.photoCount,
    required this.onSubmit,
    this.thumbnail,
    this.clock = DateTime.now,
  });
  final ScanRepository scans;
  final LastLocationStore lastLocations;
  final String buId;
  final String unitName;
  final String tenantName;
  final String typeName;
  final int photoCount;
  final Future<String?> Function(LocationPick pick) onSubmit;
  final Widget? thumbnail;
  final DateTime Function() clock;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  LocationPick? _pick;
  LocationPick? _last;
  DateTime? _lastAt;
  String? _error;
  String? _sendError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final tree = await widget.scans.publishedLocations(widget.buId);
      final saved = await widget.lastLocations.read(widget.buId);
      final last = saved == null ? null : LocationPick.start(tree, remembered: saved.nodeIds);
      // Only a remembered location that is still complete counts as "last used".
      final usable = last != null && last.isComplete && last.nodeIds.length == saved!.nodeIds.length;
      if (!mounted) return;
      setState(() {
        _last = usable ? last : null;
        _lastAt = usable ? saved.usedAt : null;
        _pick = usable ? last : LocationPick.start(tree);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code == 'not-found' ? 'This unit has no published locations yet. Ask your BU Admin.' : e.message);
    }
  }

  /// Opens the chooser for [level]; after a pick, goes on down while the node has children.
  Future<void> _change(LocationLevel level) async {
    var pick = _pick!;
    LocationLevel? next = level;
    while (next != null && mounted) {
      final node = await Navigator.of(context).push<LocationNode>(MaterialPageRoute(
        builder: (_) => ChooseNodeScreen(pick: pick, level: next!, unitName: widget.unitName),
      ));
      if (node == null) break;
      pick = pick.choose(node);
      setState(() => _pick = pick);
      next = node.children.isEmpty ? null : pick.nextLevel;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _sendError = null;
    });
    try {
      final problem = await widget.onSubmit(_pick!);
      if (mounted) setState(() => _sendError = problem);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pick = _pick;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        title: Text(_last == null ? 'Choose location' : 'Confirm location',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(
              width: 44,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: widget.thumbnail ?? const ColoredBox(color: Color(0xFF1F1F23)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.typeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text('${widget.photoCount} photo${widget.photoCount == 1 ? '' : 's'} · ready to submit',
                    style: const TextStyle(fontSize: 11.5, color: Brand.hint)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    InfoBanner(text: _error!, error: true),
                    const SizedBox(height: 12),
                    PillButton(label: 'Try again', outlined: true, onPressed: _load),
                  ]),
                )
              : pick == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.all(16), children: _body(pick)),
        ),
        if (pick != null)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_sendError != null)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: InfoBanner(text: _sendError!, error: true)),
                PillButton(label: 'Submit scan', loading: _submitting, onPressed: pick.isComplete && !_submitting ? _submit : null),
                if (!pick.isComplete)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Choose down to the bin (and sub-bin if it has one) to submit',
                        style: TextStyle(fontSize: 11.5, color: Brand.hint)),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  List<Widget> _body(LocationPick pick) {
    final last = _last;
    final changed = last != null && last.nodeIds.join('/') != pick.nodeIds.join('/');
    return [
      if (last == null)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text(
            "This is your first scan in this unit, so there's no saved location yet. Choose where this equipment is — we'll remember it for next time.",
            style: TextStyle(fontSize: 12.5, height: 1.45, color: Brand.body),
          ),
        )
      else ...[
        _Label(changed ? 'Selected location' : 'Last used in ${widget.unitName}'),
        _LocationCard(
          pick: pick,
          tenant: widget.tenantName,
          note: changed ? 'You changed this just now' : 'Used for your last scan, ${ago(_lastAt!, widget.clock())}',
          selected: true,
          badge: changed ? 'New' : null,
        ),
        if (changed) ...[
          const SizedBox(height: 10),
          _LocationCard(
            pick: last,
            tenant: widget.tenantName,
            note: 'Tap to go back to this location',
            onTap: () => setState(() => _pick = last),
          ),
        ],
        const SizedBox(height: 14),
      ],
      _Label(last == null ? 'Where is this equipment?' : 'Or change location', trailing: 'Tap a level to change it'),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Icon(Icons.apartment, size: 14, color: Brand.muted),
          const SizedBox(width: 6),
          Text(widget.tenantName, style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.lineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final level in pick.tree.levels) _levelRow(pick, level),
        ]),
      ),
      const SizedBox(height: 14),
      const Text(
        "Levels follow your unit's location setup — optional levels can be left blank. Facility comes from your business unit.",
        style: TextStyle(fontSize: 11.5, height: 1.45, color: Brand.hint),
      ),
    ];
  }

  Widget _levelRow(LocationPick pick, LocationLevel level) {
    final node = pick.nodeAt(level);
    final options = pick.optionsAt(level);
    // The facility comes from the unit: fixed when the unit has only one.
    final fixed = level.order == pick.tree.levels.first.order && pick.tree.roots.length == 1;
    final canTap = !fixed && options.isNotEmpty;
    // Empty rows: "Choose" (grey until the level above is picked), or "Not used here" when
    // the picked branch skips this optional level or ends above it.
    final last = pick.chain.lastOrNull;
    final lastOrder = last == null ? 0 : pick.tree.levels.firstWhere((l) => l.levelId == last.levelId).order;
    final unused = node == null && !canTap && last != null && (level.order < lastOrder || last.children.isEmpty);
    final value = node?.name ?? (unused ? 'Not used here' : 'Choose');
    return InkWell(
      onTap: canTap ? () => _change(level) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: fixed ? Brand.surfaceAlt : null,
          border: const Border(bottom: BorderSide(color: Color(0xFFEFF1F3))),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(level.name, style: const TextStyle(fontSize: 11, color: Brand.hint)),
                if (level.isOptional) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(4)),
                    child: const Text('OPTIONAL',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Brand.muted)),
                  ),
                ],
              ]),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: unused ? FontWeight.w400 : FontWeight.w600,
                  color: fixed ? Brand.muted : (node != null ? Brand.ink : (canTap ? Brand.navy : Brand.hint)),
                ),
              ),
            ]),
          ),
          if (fixed)
            const Icon(Icons.lock_outline, size: 18, color: Brand.hint)
          else if (canTap)
            const Icon(Icons.chevron_right, size: 18, color: Brand.hint),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Brand.muted)),
          ),
          if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 11, color: Brand.hint)),
        ]),
      );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.pick, required this.tenant, required this.note, this.selected = false, this.badge, this.onTap});
  final LocationPick pick;
  final String tenant;
  final String note;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? Brand.navy : Brand.lineSoft, width: selected ? 2 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20, color: selected ? Brand.navy : Brand.hint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(pick.title,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Brand.navyDeep)),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: Brand.info, borderRadius: BorderRadius.circular(999)),
                      child: Text(badge!, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Brand.navy)),
                    ),
                ]),
                const SizedBox(height: 3),
                Text('$tenant › ${pick.context}', style: const TextStyle(fontSize: 12, height: 1.45, color: Brand.body)),
                const SizedBox(height: 4),
                Text(note, style: const TextStyle(fontSize: 11, color: Brand.hint)),
              ]),
            ),
          ]),
        ),
      );
}

/// Choose one node of [level] (design 43, 44). Pops with the chosen node.
class ChooseNodeScreen extends StatefulWidget {
  const ChooseNodeScreen({super.key, required this.pick, required this.level, required this.unitName});
  final LocationPick pick;
  final LocationLevel level;
  final String unitName;

  @override
  State<ChooseNodeScreen> createState() => _ChooseNodeScreenState();
}

class _ChooseNodeScreenState extends State<ChooseNodeScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final levels = widget.pick.tree.levels;
    final name = widget.level.name;
    final plural = '${name.toLowerCase()}s';
    // Picks between the facility (shown on the unit) and this level, as chips.
    int orderOf(LocationNode n) => levels.firstWhere((l) => l.levelId == n.levelId).order;
    final above = widget.pick.chain
        .where((n) => orderOf(n) > levels.first.order && orderOf(n) < widget.level.order)
        .toList();
    final within = above.isEmpty ? widget.unitName : above.last.name;
    final current = widget.pick.nodeAt(widget.level);
    final all = widget.pick.optionsAt(widget.level);
    final shown = all.where((n) => n.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        title: Text('Choose ${name.toLowerCase()}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in above) _Chip(n.name),
              _Chip('$name ?', faint: true),
            ]),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search $plural in $within',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Brand.surface,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(
              'STEP ${levels.indexOf(widget.level) + 1} OF ${levels.length} · ${all.length} ${all.length == 1 ? name.toLowerCase() : plural} in $within'
                  .toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Brand.muted),
            ),
            const SizedBox(height: 8),
            for (final n in shown)
              _NodeTile(node: n, current: n.nodeId == current?.nodeId, levels: levels, level: widget.level),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No $plural match "$_q".', textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
              ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(10)),
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12, height: 1.45, color: Brand.body), children: [
                TextSpan(text: 'Only $plural your admin set up for '),
                TextSpan(text: widget.unitName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' are listed.'),
              ])),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({required this.node, required this.current, required this.levels, required this.level});
  final LocationNode node;
  final bool current;
  final List<LocationLevel> levels;
  final LocationLevel level;

  @override
  Widget build(BuildContext context) {
    final kids = node.children;
    // "3 sub-bins", "No sub-bins" (design 43); nothing under the last level.
    final kidLevel = kids.isEmpty
        ? levels.where((l) => l.order > level.order).firstOrNull
        : levels.where((l) => l.levelId == kids.first.levelId).firstOrNull;
    final kidName = kidLevel?.name.toLowerCase();
    final count = kidName == null
        ? null
        : kids.isEmpty
            ? 'No ${kidName}s'
            : '${kids.length} ${kids.length == 1 ? kidName : '${kidName}s'}';
    final subtitle = [if (current) 'Current', ?count].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: current ? Brand.navy : Brand.lineSoft, width: current ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.pop(context, node),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(node.name, style: TextStyle(fontSize: 14.5, fontWeight: current ? FontWeight.w700 : FontWeight.w600)),
                  if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(fontSize: 11, color: Brand.hint)),
                ]),
              ),
              Icon(current ? Icons.check : Icons.chevron_right, size: 18, color: current ? Brand.navy : Brand.hint),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.faint = false});
  final String text;
  final bool faint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: faint ? Colors.white : Brand.info,
          borderRadius: BorderRadius.circular(999),
          border: faint ? Border.all(color: Brand.line) : null,
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: faint ? Brand.hint : Brand.navyDeep)),
      );
}
