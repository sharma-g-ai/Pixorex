import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../ppg_delivery_note/ui/ppg_format.dart';
import '../../ppg_delivery_note/ui/ppg_tokens.dart';
import '../../ppg_delivery_note/ui/ppg_widgets.dart';
import '../domain/article_colours.dart';
import '../domain/stock.dart';
import '../services/seastock_controller.dart';

/// Route name of the check-out scanner.
const seastockCheckoutRouteName = '/seastock/check-out';

/// Route name of the audit count list, so later steps can return to it.
const seastockAuditRouteName = '/seastock/audit';

/// A route to a Seastock screen with the shared controller in scope.
MaterialPageRoute<T> seastockRoute<T>(
  SeastockController controller,
  Widget screen, {
  String? name,
}) => MaterialPageRoute<T>(
  settings: RouteSettings(name: name),
  builder: (_) => ChangeNotifierProvider.value(
    value: controller,
    child: PpgThemed(child: screen),
  ),
);

Future<T?> seastockPush<T>(
  BuildContext context,
  SeastockController controller,
  Widget screen, {
  String? name,
}) => Navigator.of(
  context,
).push<T>(seastockRoute<T>(controller, screen, name: name));

/// "20 PC" with the unit in lighter type.
class SeastockQuantity extends StatelessWidget {
  const SeastockQuantity(this.value, {super.key, this.size = 18, this.color});

  final int value;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: PpgText.figures(size: size, color: color ?? PpgColors.navy),
      children: [
        TextSpan(text: '$value'),
        TextSpan(
          text: ' PC',
          style: TextStyle(
            fontSize: size * 0.72,
            fontWeight: FontWeight.w400,
            color: PpgColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

/// Bottom sheet to switch the vessel all stock, check-ins and check-outs use.
class SeastockVesselSheet extends StatelessWidget {
  const SeastockVesselSheet({super.key, required this.controller});

  final SeastockController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: FutureBuilder<Map<String, StockSnapshot>>(
        future: controller.stockByVessel(),
        builder: (context, snapshot) {
          final stock = snapshot.data;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose vessel',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const Text(
                'Stock, check-ins and check-outs are kept per vessel.',
                style: TextStyle(fontSize: 14, color: PpgColors.textSecondary),
              ),
              const SizedBox(height: PpgSpace.m),
              PpgPanel(
                child: Column(
                  children: ppgDivided([
                    for (final vessel in controller.vessels)
                      PpgRow(
                        key: ValueKey('vessel-${vessel.id}'),
                        title: vessel.name,
                        subtitle: stock == null
                            ? ' '
                            : stock[vessel.id]!.total == 0
                            ? 'No stock yet'
                            : '${stock[vessel.id]!.total} PC · ${ppgPlural(stock[vessel.id]!.articlesOnBoard, 'article')}',
                        highlight: vessel.id == controller.vessel.id
                            ? const Color(0xFFF5F9FF)
                            : null,
                        showChevron: false,
                        trailing: vessel.id == controller.vessel.id
                            ? const Icon(Icons.check, color: PpgColors.link)
                            : null,
                        semanticLabel:
                            '${vessel.name}${vessel.id == controller.vessel.id ? ', selected' : ''}',
                        onTap: () => Navigator.pop(context, vessel),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: PpgSpace.m),
              const PpgHint(
                'Vessels are set up by your team. Ask them to add a new one.',
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Sets how many cans of one article go on the check-out: adding several
/// from the scanner, or changing a line on the review list.
class SeastockQuantitySheet extends StatefulWidget {
  const SeastockQuantitySheet({
    super.key,
    required this.controller,
    required this.articleNumber,
    this.editing = false,
  });

  final SeastockController controller;
  final String articleNumber;

  /// Changing an existing line: zero removes it.
  final bool editing;

  @override
  State<SeastockQuantitySheet> createState() => _SeastockQuantitySheetState();
}

class _SeastockQuantitySheetState extends State<SeastockQuantitySheet> {
  late final TextEditingController _text;
  late int _value;

  SeastockController get _ctrl => widget.controller;
  int get _onBoard => _ctrl.stock.onBoard(widget.articleNumber);
  int get _max =>
      widget.editing ? _onBoard : _ctrl.available(widget.articleNumber);
  int get _min => widget.editing ? 0 : 1;
  int get _already =>
      widget.editing ? 0 : _ctrl.basket[widget.articleNumber] ?? 0;

  @override
  void initState() {
    super.initState();
    _value = widget.editing
        ? _ctrl.basket[widget.articleNumber] ?? 0
        : _max.clamp(_min, 2);
    _text = TextEditingController(text: '$_value');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set(int value) {
    setState(() {
      _value = value.clamp(_min, _max);
      _text.text = '$_value';
    });
  }

  @override
  Widget build(BuildContext context) {
    final after = _onBoard - _already - _value;
    final product = _ctrl.productOf(widget.articleNumber);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.editing ? 'Change quantity' : 'Check out several cans',
              style: const TextStyle(
                fontSize: 13,
                color: PpgColors.textSecondary,
              ),
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
            Row(
              children: [
                _stepButton(
                  icon: Icons.remove,
                  tooltip: 'One less',
                  onPressed: _value > _min ? () => _set(_value - 1) : null,
                ),
                const SizedBox(width: PpgSpace.m),
                Expanded(
                  child: TextField(
                    key: const ValueKey('seastock-quantity-field'),
                    controller: _text,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: PpgText.figures(size: 30),
                    decoration: const InputDecoration(
                      suffixText: 'PC',
                      labelText: 'Cans to check out',
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                    onChanged: (raw) {
                      final parsed = int.tryParse(raw);
                      if (parsed != null) {
                        setState(() => _value = parsed.clamp(_min, _max));
                      }
                    },
                    onEditingComplete: () => _set(_value),
                  ),
                ),
                const SizedBox(width: PpgSpace.m),
                _stepButton(
                  icon: Icons.add,
                  tooltip: 'One more',
                  filled: true,
                  onPressed: _value < _max ? () => _set(_value + 1) : null,
                ),
              ],
            ),
            const SizedBox(height: PpgSpace.m),
            Wrap(
              spacing: PpgSpace.s,
              children: [
                ActionChip(
                  label: const Text('+5'),
                  onPressed: () => _set(_value + 5),
                ),
                ActionChip(
                  label: const Text('+10'),
                  onPressed: () => _set(_value + 10),
                ),
                ActionChip(
                  label: Text('All $_max'),
                  onPressed: () => _set(_max),
                ),
              ],
            ),
            const SizedBox(height: PpgSpace.m),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: PpgColors.ground,
                borderRadius: BorderRadius.circular(PpgRadii.medium),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'On board after check-out',
                      style: TextStyle(color: PpgColors.textSecondary),
                    ),
                  ),
                  Text(
                    '$_onBoard → $after PC',
                    style: PpgText.figures(size: 16, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PpgSpace.m),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.pop(context, _value),
              child: Text(
                widget.editing
                    ? (_value == 0
                          ? 'Remove from check-out'
                          : 'Save $_value PC')
                    : 'Add $_value PC to check-out',
              ),
            ),
            const SizedBox(height: PpgSpace.s),
            PpgHint(
              _already > 0
                  ? 'Up to $_max more PC. $_already already on this check-out.'
                  : 'Up to $_max PC, what is on board.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final style = IconButton.styleFrom(
      fixedSize: const Size.square(PpgSizes.counter),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PpgRadii.large),
      ),
    );
    return filled
        ? IconButton.filled(
            tooltip: tooltip,
            style: style,
            onPressed: onPressed,
            icon: Icon(icon),
          )
        : IconButton.outlined(
            tooltip: tooltip,
            style: style,
            onPressed: onPressed,
            icon: Icon(icon),
          );
  }
}

/// Picks an article on board by hand, for when a label can't be scanned.
class SeastockArticlePicker extends StatefulWidget {
  const SeastockArticlePicker({super.key, required this.controller});

  final SeastockController controller;

  @override
  State<SeastockArticlePicker> createState() => _SeastockArticlePickerState();
}

class _SeastockArticlePickerState extends State<SeastockArticlePicker> {
  String _query = '';

  Widget _row(StockItem item) {
    final left = widget.controller.available(item.articleNumber);
    return Opacity(
      opacity: left > 0 ? 1 : 0.5,
      child: PpgRow(
        key: ValueKey('pick-${item.articleNumber}'),
        title: item.articleNumber,
        monoTitle: true,
        subtitle: [
          ?item.product,
          if (left <= 0) 'all on this check-out',
        ].join(' · '),
        showChevron: false,
        trailing: SeastockQuantity(item.onBoard),
        onTap: left > 0
            ? () => Navigator.pop(context, item.articleNumber)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = widget.controller.stock.items
        .where((item) => item.onBoard > 0)
        .where(
          (item) =>
              q.isEmpty ||
              item.articleNumber.contains(q) ||
              (item.product?.toLowerCase().contains(q) ?? false),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose the article',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Use the Article no. printed on the can.',
              style: TextStyle(fontSize: 14, color: PpgColors.textSecondary),
            ),
            const SizedBox(height: PpgSpace.m),
            TextField(
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Article no. or product',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: PpgSpace.m),
            Flexible(
              child: items.isEmpty
                  ? const PpgHint('No article on board matches.')
                  : SingleChildScrollView(
                      child: PpgPanel(
                        child: Column(
                          children: ppgDivided([
                            for (final item in items) _row(item),
                          ]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The paint's colour from the master list; hatched for a product with no
/// colour (a hardener), outlined with "?" when the list has no entry yet.
class SeastockColourChip extends StatelessWidget {
  const SeastockColourChip({
    super.key,
    required this.articleNumber,
    this.product,
    this.size = 36,
  });

  final String articleNumber;
  final String? product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = articleColour(articleNumber, product);
    final (label, decoration, child) = switch (colour) {
      PaintColour(:final color) => (
        'Paint colour',
        BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(PpgRadii.small + 2),
          border: Border.all(color: PpgColors.navy.withValues(alpha: 0.18)),
        ),
        null,
      ),
      NoColour() => (
        'No colour',
        BoxDecoration(
          borderRadius: BorderRadius.circular(PpgRadii.small + 2),
          border: Border.all(color: PpgColors.control),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment(-0.6, -0.6),
            colors: [
              Colors.white,
              Colors.white,
              PpgColors.divider,
              PpgColors.divider,
            ],
            stops: [0, 0.5, 0.5, 1],
            tileMode: TileMode.repeated,
          ),
        ),
        null,
      ),
      UnknownColour() => (
        'Colour not on the master list',
        BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(PpgRadii.small + 2),
          border: Border.all(color: PpgColors.control),
        ),
        const Text(
          '?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PpgColors.textMuted,
          ),
        ),
      ),
    };
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        image: true,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: decoration,
          child: child,
        ),
      ),
    );
  }
}

/// A large − / number / + counter. Tapping the number lets the operator type
/// one. Buttons are disabled at [min] and [max].
class SeastockCounter extends StatelessWidget {
  const SeastockCounter({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.trailingLabel,
  });

  final int value;
  final String label;
  final String? trailingLabel;
  final int min;
  final int? max;
  final ValueChanged<int>? onChanged;

  Future<void> _type(BuildContext context) async {
    final typed = await showSeastockNumberDialog(
      context,
      title: label,
      initial: value,
      max: max,
    );
    if (typed != null && typed != value) {
      onChanged?.call(typed.clamp(min, max ?? typed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLess = onChanged != null && value > min;
    final canMore = onChanged != null && (max == null || value < max!);
    final style = IconButton.styleFrom(
      fixedSize: const Size(72, PpgSizes.counter),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PpgRadii.large - 2),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PpgColors.textSecondary,
                ),
              ),
            ),
            if (trailingLabel != null)
              Text(
                trailingLabel!,
                style: const TextStyle(
                  fontSize: 13,
                  color: PpgColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton.outlined(
              key: const ValueKey('counter-minus'),
              tooltip: 'One less',
              style: style,
              onPressed: canLess ? () => onChanged!(value - 1) : null,
              icon: const Icon(Icons.remove, size: 26),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                button: true,
                label: '$value. $label. Tap to type a number',
                excludeSemantics: true,
                child: Material(
                  color: const Color(0xFFF8FAFC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PpgRadii.large - 2),
                    side: const BorderSide(color: PpgColors.control),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('counter-value'),
                    onTap: onChanged == null ? null : () => _type(context),
                    child: SizedBox(
                      height: PpgSizes.counter,
                      child: Center(
                        child: Text('$value', style: PpgText.figures(size: 34)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              key: const ValueKey('counter-plus'),
              tooltip: 'One more',
              style: style,
              onPressed: canMore ? () => onChanged!(value + 1) : null,
              icon: const Icon(Icons.add, size: 26),
            ),
          ],
        ),
      ],
    );
  }
}

/// Asks for a whole number, at most [max] when given.
Future<int?> showSeastockNumberDialog(
  BuildContext context, {
  required String title,
  required int initial,
  int? max,
}) => showDialog<int>(
  context: context,
  builder: (_) => PpgThemed(
    child: _NumberDialog(title: title, initial: initial, max: max),
  ),
);

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.initial, this.max});

  final String title;
  final int initial;
  final int? max;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _text = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_text.text);
    if (parsed == null) return;
    final max = widget.max;
    Navigator.pop(context, max == null ? parsed : parsed.clamp(0, max));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('counter-field'),
      controller: _text,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: PpgText.figures(size: 26),
      decoration: InputDecoration(
        suffixText: 'PC',
        helperText: widget.max == null ? null : 'Up to ${widget.max} PC',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

/// "Today" or "8 Oct 2026", for grouping records by day.
String seastockDay(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return 'Today';
  }
  return ppgDate(local);
}

Future<T?> showSeastockSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => PpgThemed(child: child),
    );
